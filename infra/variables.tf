variable "aws_region" {
  description = "Region AWS donde se despliega la PoC"
  type        = string
  default     = "eu-west-1"
}

# Opcional: si no se especifica, se genera aleatoriamente (ver secrets.tf)
variable "litellm_master_key" {
  description = "Master key para la API admin de LiteLLM (se genera aleatoria si se deja null)"
  type        = string
  default     = null
  sensitive   = true
}

# Opcional: si no se especifica, se genera aleatoriamente (ver secrets.tf)
variable "db_password" {
  description = "Contrasena de Aurora PostgreSQL (se genera aleatoria si se deja null)"
  type        = string
  default     = null
  sensitive   = true
}

variable "eks_node_type" {
  description = "Tipo de instancia para los nodos del Node Group"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_count" {
  description = "Numero de nodos deseados en el Node Group"
  type        = number
  default     = 2
}
