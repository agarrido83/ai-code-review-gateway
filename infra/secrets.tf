resource "random_password" "poc_litellm_master_key" {
  length  = 32
  special = false # Evitar caracteres que puedan romper headers HTTP o el YAML de config
}

locals {
  # LiteLLM >= reciente requiere que el master key empiece con "sk-"
  _raw_key           = var.litellm_master_key != null ? var.litellm_master_key : random_password.poc_litellm_master_key.result
  litellm_master_key = startswith(local._raw_key, "sk-") ? local._raw_key : "sk-${local._raw_key}"
}

resource "aws_secretsmanager_secret" "poc_litellm_master_key" {
  name = "poc-litellm-master-key"

  # recovery_window_in_days = 0: borrado inmediato en terraform destroy
  # Sin esto, el secret queda en "pendiente de borrado" 7-30 dias y bloquea un re-deploy con el mismo nombre
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "poc_litellm_master_key" {
  secret_id     = aws_secretsmanager_secret.poc_litellm_master_key.id
  secret_string = local.litellm_master_key
}

# ─── S3: config.yaml de LiteLLM ─────────────────────────────────────────────
# El task de Fargate descarga este archivo al arrancar (via boto3 en el comando de inicio)
# y lo pasa a LiteLLM con --config. Mas limpio que embeber la config en la Task Definition.

resource "aws_s3_bucket" "poc_litellm_config" {
  bucket = "poc-litellm-config-${data.aws_caller_identity.current.account_id}"

  # force_destroy permite terraform destroy aunque el bucket no este vacio
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "poc_litellm_config" {
  bucket = aws_s3_bucket.poc_litellm_config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sube litellm/config.yaml automaticamente en cada terraform apply
# etag: Terraform detecta cambios en el fichero local y re-sube solo cuando cambia
resource "aws_s3_object" "poc_litellm_config_yaml" {
  bucket = aws_s3_bucket.poc_litellm_config.id
  key    = "config.yaml"
  source = "${path.module}/../litellm/config.yaml"
  etag   = filemd5("${path.module}/../litellm/config.yaml")

  tags = local.tags
}
