locals {
  capstone_tags = {
    Project     = "ai-code-review-gateway"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "antonio"
  }
}

# Extrae el ARN "base" del caller: sin sufijo de sesión, válido para IAM users y roles asumidos.
# Necesario para aws_eks_access_entry, que rechaza ARNs con formato assumed-role/rol/sesion.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_cloudwatch_log_group" "capstone_eks" {
  name              = "/aws/eks/capstone-cluster/cluster"
  retention_in_days = 1 # Mínimo para reducir coste; el capstone no necesita logs históricos

  tags = local.capstone_tags
}

resource "aws_eks_cluster" "capstone" {
  name     = "capstone-cluster"
  role_arn = aws_iam_role.capstone_eks_cluster_role.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = [
      aws_subnet.poc_subnet_public_a.id,
      aws_subnet.poc_subnet_public_b.id,
    ]
    # Sin endpoint privado: acceso al kube-apiserver solo desde internet (suficiente para demo)
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Solo api + audit: evitar scheduler/controllerManager logs que disparan el coste de CloudWatch
  enabled_cluster_log_types = ["api", "audit"]

  # API mode: gestión de acceso con access entries, sin editar aws-auth ConfigMap a mano
  access_config {
    authentication_mode = "API"
  }

  depends_on = [
    aws_iam_role_policy_attachment.capstone_eks_cluster_policy,
    aws_cloudwatch_log_group.capstone_eks,
  ]

  tags = local.capstone_tags
}

# 2 x t3.medium: mínimo viable para EKS con todos los pods (LiteLLM + FastAPI + Prometheus + Grafana).
# Nodos en subnets públicas con IP pública directa: sin NAT Gateway para minimizar coste del capstone.
# En producción: subnets privadas + NAT Gateway + multi-AZ.
resource "aws_eks_node_group" "capstone" {
  cluster_name    = aws_eks_cluster.capstone.name
  node_group_name = "capstone-nodes"
  node_role_arn   = aws_iam_role.capstone_eks_node_role.arn

  subnet_ids = [
    aws_subnet.poc_subnet_public_a.id,
    aws_subnet.poc_subnet_public_b.id,
  ]

  instance_types = [var.eks_node_type]

  scaling_config {
    desired_size = var.eks_node_count
    max_size     = var.eks_node_count + 1
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.capstone_eks_node_policy,
    aws_iam_role_policy_attachment.capstone_eks_cni_policy,
    aws_iam_role_policy_attachment.capstone_ecr_readonly,
  ]

  tags = local.capstone_tags
}

# Permite acceso PostgreSQL desde cualquier recurso de la VPC (nodos EKS incluidos).
# network.tf no se modifica; Aurora necesita aceptar conexiones desde los pods de LiteLLM.
resource "aws_security_group_rule" "capstone_aurora_from_vpc" {
  description       = "PostgreSQL desde la VPC (nodos EKS)"
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.poc_vpc.cidr_block]
  security_group_id = aws_security_group.poc_sg_aurora.id
}

# Access entry: otorga al IAM identity que corre Terraform acceso admin al cluster vía kubectl.
resource "aws_eks_access_entry" "capstone_admin" {
  cluster_name  = aws_eks_cluster.capstone.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn

  tags = local.capstone_tags
}

resource "aws_eks_access_policy_association" "capstone_admin" {
  cluster_name  = aws_eks_cluster.capstone.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
