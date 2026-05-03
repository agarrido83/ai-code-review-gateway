data "aws_caller_identity" "current" {}

# ─── Task Execution Role (PoC — mantenido) ───────────────────────────────────
# ECS usa este role para: pull de imagen, escribir logs en CloudWatch
# e inyectar secrets de Secrets Manager como env vars.

resource "aws_iam_role" "poc_task_execution_role" {
  name = "poc-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "poc_ecs_execution_managed" {
  role       = aws_iam_role.poc_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "poc_task_execution_secrets" {
  name = "poc-read-secrets"
  role = aws_iam_role.poc_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:poc-*"
    }]
  })
}

# ─── Task Role (PoC — mantenido) ─────────────────────────────────────────────
# El contenedor LiteLLM usa este role en runtime para invocar Bedrock y leer config de S3.

resource "aws_iam_role" "poc_task_role" {
  name = "poc-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.tags
}

# Bedrock: invocar inference profiles EU
# Cross-region profiles requieren permiso sobre el profile ARN + los foundation models
# subyacentes en cada region del pool EU (eu-west-1, eu-west-2, eu-central-1)
resource "aws_iam_role_policy" "poc_task_bedrock" {
  name = "poc-bedrock-invoke"
  role = aws_iam_role.poc_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Marketplace: necesario para que el task role pueda suscribirse a modelos
        # distribuidos via AWS Marketplace la primera vez que se invocan
        Effect   = "Allow"
        Action   = ["aws-marketplace:ViewSubscriptions", "aws-marketplace:Subscribe", "aws-marketplace:Unsubscribe"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Claude Sonnet 4.5 y 4.6 — inference profiles EU (con y sin account ID)
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.anthropic.claude-sonnet-4-6",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-6",
          # Claude — foundation models en cualquier region del pool EU
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6",
          # Llama 3.2 3B — inference profile EU (con y sin account ID)
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.meta.llama3-2-3b-instruct-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.meta.llama3-2-3b-instruct-v1:0",
          "arn:aws:bedrock:*::foundation-model/meta.llama3-2-3b-instruct-v1:0",
          # Mistral Pixtral Large — inference profile EU
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.mistral.pixtral-large-2502-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.mistral.pixtral-large-2502-v1:0",
          "arn:aws:bedrock:*::foundation-model/mistral.pixtral-large-2502-v1:0",
          # Amazon Nova Pro — inference profile EU
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.amazon.nova-pro-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.amazon.nova-pro-v1:0",
          "arn:aws:bedrock:*::foundation-model/amazon.nova-pro-v1:0",
          # Amazon Nova 2 Lite
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.amazon.nova-2-lite-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.amazon.nova-2-lite-v1:0",
          "arn:aws:bedrock:*::foundation-model/amazon.nova-2-lite-v1:0"
        ]
      }
    ]
  })
}

# S3: leer config.yaml del bucket de configuracion de LiteLLM
resource "aws_iam_role_policy" "poc_task_s3" {
  name = "poc-s3-config"
  role = aws_iam_role.poc_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::poc-litellm-config-${data.aws_caller_identity.current.account_id}/config.yaml"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::poc-litellm-config-${data.aws_caller_identity.current.account_id}"
      }
    ]
  })
}

# ECS Exec: permite entrar al contenedor en ejecucion para diagnosticar
resource "aws_iam_role_policy" "poc_task_ecs_exec" {
  name = "poc-ecs-exec"
  role = aws_iam_role.poc_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# ─── EKS Cluster Role ────────────────────────────────────────────────────────
# El control plane de EKS asume este role para gestionar recursos AWS en nombre del cluster

resource "aws_iam_role" "capstone_eks_cluster_role" {
  name = "capstone-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = local.capstone_tags
}

resource "aws_iam_role_policy_attachment" "capstone_eks_cluster_policy" {
  role       = aws_iam_role.capstone_eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── EKS Node Group Role ─────────────────────────────────────────────────────
# Los nodos EC2 del Node Group asumen este role.
# Los pods acceden a Bedrock via el instance profile del nodo (simplificacion valida
# para capstone; en produccion se usaria IRSA - IAM Roles for Service Accounts).

resource "aws_iam_role" "capstone_eks_node_role" {
  name = "capstone-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.capstone_tags
}

resource "aws_iam_role_policy_attachment" "capstone_eks_node_policy" {
  role       = aws_iam_role.capstone_eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "capstone_eks_cni_policy" {
  role       = aws_iam_role.capstone_eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "capstone_ecr_readonly" {
  role       = aws_iam_role.capstone_eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Bedrock: los pods de LiteLLM invocan Bedrock via el instance profile del nodo.
# Mismos ARNs que poc_task_bedrock (inference profiles EU + foundation models subyacentes).
resource "aws_iam_role_policy" "capstone_node_bedrock" {
  name = "capstone-bedrock-invoke"
  role = aws_iam_role.capstone_eks_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aws-marketplace:ViewSubscriptions", "aws-marketplace:Subscribe", "aws-marketplace:Unsubscribe"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.anthropic.claude-sonnet-4-6",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-6",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.meta.llama3-2-3b-instruct-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.meta.llama3-2-3b-instruct-v1:0",
          "arn:aws:bedrock:*::foundation-model/meta.llama3-2-3b-instruct-v1:0",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.mistral.pixtral-large-2502-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.mistral.pixtral-large-2502-v1:0",
          "arn:aws:bedrock:*::foundation-model/mistral.pixtral-large-2502-v1:0",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.amazon.nova-pro-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.amazon.nova-pro-v1:0",
          "arn:aws:bedrock:*::foundation-model/amazon.nova-pro-v1:0",
          "arn:aws:bedrock:eu-west-1::inference-profile/eu.amazon.nova-2-lite-v1:0",
          "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.amazon.nova-2-lite-v1:0",
          "arn:aws:bedrock:*::foundation-model/amazon.nova-2-lite-v1:0"
        ]
      }
    ]
  })
}
