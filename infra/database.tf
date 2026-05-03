resource "random_password" "poc_db_password" {
  length  = 24
  special = false # Aurora no admite todos los caracteres especiales en el master password
}

locals {
  db_password = var.db_password != null ? var.db_password : random_password.poc_db_password.result
}

# Aurora requiere un subnet group con >= 2 AZs aunque el cluster use solo una
resource "aws_db_subnet_group" "poc_aurora" {
  name = "poc-aurora-subnet-group"
  subnet_ids = [
    aws_subnet.poc_subnet_public_a.id,
    aws_subnet.poc_subnet_public_b.id,
  ]

  tags = local.tags
}

resource "aws_rds_cluster" "poc_aurora" {
  cluster_identifier = "poc-aurora"
  engine             = "aurora-postgresql"
  # Verificar version disponible con: aws rds describe-db-engine-versions --engine aurora-postgresql --region eu-west-1
  engine_version = "16.4"
  # Serverless v2 usa engine_mode = "provisioned" — "serverless" es la v1 (deprecated)
  engine_mode = "provisioned"

  database_name   = "litellm"
  master_username = "litellm"
  master_password = local.db_password

  db_subnet_group_name   = aws_db_subnet_group.poc_aurora.name
  vpc_security_group_ids = [aws_security_group.poc_sg_aurora.id]

  serverlessv2_scaling_configuration {
    min_capacity = 0.5 # Siempre activo (~0.03 EUR/h) - Serverless v2 no escala a 0
    max_capacity = 2.0 # Cap para evitar escalados inesperados durante la PoC
  }

  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1 # Minimo obligatorio en Aurora; no necesitamos los backups para la PoC

  tags = local.tags
}

resource "aws_rds_cluster_instance" "poc_aurora_instance" {
  identifier         = "poc-aurora-instance"
  cluster_identifier = aws_rds_cluster.poc_aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.poc_aurora.engine
  engine_version     = aws_rds_cluster.poc_aurora.engine_version

  tags = local.tags
}

# Credenciales completas como JSON (para referencia / conexiones manuales)
resource "aws_secretsmanager_secret" "poc_db_credentials" {
  name                    = "poc-db-credentials"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "poc_db_credentials" {
  secret_id = aws_secretsmanager_secret.poc_db_credentials.id

  secret_string = jsonencode({
    username = "litellm"
    password = local.db_password
    host     = aws_rds_cluster.poc_aurora.endpoint
    port     = 5432
    dbname   = "litellm"
  })
}

# DATABASE_URL como cadena plana — ECS la inyecta directamente sin extraccion JSON
# connect_timeout=10: si Aurora no responde en 10s Prisma falla rapido y LiteLLM loggea el error
resource "aws_secretsmanager_secret" "poc_db_url" {
  name                    = "poc-db-url"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "poc_db_url" {
  secret_id     = aws_secretsmanager_secret.poc_db_url.id
  # TEST: postgres (BD por defecto) + sslmode=disable para aislar si el problema es SSL.
  # sslaccept=accept_invalid_certs es un param de LiteLLM, no de Prisma — Prisma entiende sslmode.
  secret_string = "postgresql://litellm:${local.db_password}@${aws_rds_cluster.poc_aurora.endpoint}:5432/postgres?sslmode=disable&connect_timeout=10"
}
