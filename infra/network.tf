locals {
  tags = {
    Project     = "laberit-ai-gateway-poc"
    Environment = "poc"
    ManagedBy   = "terraform"
    Owner       = "antonio"
  }
}

resource "aws_vpc" "poc_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = "poc-vpc" })
}

resource "aws_internet_gateway" "poc_igw" {
  vpc_id = aws_vpc.poc_vpc.id

  tags = merge(local.tags, { Name = "poc-igw" })
}

# Subnet principal: Fargate corre aqui, con IP publica directa (sin ALB ni NAT Gateway para minimizar coste de PoC)
resource "aws_subnet" "poc_subnet_public_a" {
  vpc_id                  = aws_vpc.poc_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                     = "poc-subnet-public-a"
    "kubernetes.io/role/elb" = "1" # Requerido por el cloud controller de EKS para crear NLBs en esta subnet
  })
}

# Segunda subnet: requerida por Aurora (>= 2 AZs) y por el Node Group de EKS
resource "aws_subnet" "poc_subnet_public_b" {
  vpc_id                  = aws_vpc.poc_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                     = "poc-subnet-public-b"
    "kubernetes.io/role/elb" = "1" # Requerido por el cloud controller de EKS para crear NLBs en esta subnet
  })
}

resource "aws_route_table" "poc_rt_public" {
  vpc_id = aws_vpc.poc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.poc_igw.id
  }

  tags = merge(local.tags, { Name = "poc-rt-public" })
}

resource "aws_route_table_association" "poc_rta_a" {
  subnet_id      = aws_subnet.poc_subnet_public_a.id
  route_table_id = aws_route_table.poc_rt_public.id
}

resource "aws_route_table_association" "poc_rta_b" {
  subnet_id      = aws_subnet.poc_subnet_public_b.id
  route_table_id = aws_route_table.poc_rt_public.id
}

# SG para el task de Fargate: acepta trafico en 4000 (LiteLLM) desde cualquier IP
# Sin ALB porque cada hora de ALB cuenta y queremos minimizar coste de PoC
resource "aws_security_group" "poc_sg_fargate" {
  name        = "poc-sg-fargate"
  description = "LiteLLM Fargate task"
  vpc_id      = aws_vpc.poc_vpc.id

  ingress {
    description = "LiteLLM API - IP publica directa, sin ALB (solo valido para PoC)"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total: necesaria para Bedrock (HTTPS publico), S3, Secrets Manager, ECR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "poc-sg-fargate" })
}

# SG para Aurora: solo acepta conexiones Postgres desde el SG de Fargate
resource "aws_security_group" "poc_sg_aurora" {
  name        = "poc-sg-aurora"
  description = "Aurora PostgreSQL - acceso solo desde Fargate"
  vpc_id      = aws_vpc.poc_vpc.id

  ingress {
    description     = "PostgreSQL solo desde el task LiteLLM"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.poc_sg_fargate.id]
  }

  tags = merge(local.tags, { Name = "poc-sg-aurora" })
}
