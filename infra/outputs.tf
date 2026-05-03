output "litellm_master_key" {
  description = "Master key de LiteLLM - usar como Authorization: Bearer <key> o para configurar OpenCode"
  value       = local.litellm_master_key
  sensitive   = true
}

output "aurora_endpoint" {
  description = "Endpoint del cluster Aurora (solo accesible desde dentro de la VPC)"
  value       = aws_rds_cluster.poc_aurora.endpoint
}

output "config_bucket" {
  description = "Bucket S3 con el config.yaml de LiteLLM"
  value       = aws_s3_bucket.poc_litellm_config.bucket
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR para docker push/pull de la imagen code-review-api"
  value       = aws_ecr_repository.code_review_api.repository_url
}

output "eks_cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.capstone.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint del kube-apiserver (referencia; kubectl lo usa internamente tras update-kubeconfig)"
  value       = aws_eks_cluster.capstone.endpoint
}

output "kubectl_config_command" {
  description = "Ejecutar tras terraform apply para que kubectl apunte al cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.capstone.name}"
}

# La URL del LoadBalancer es dinámica: la asigna AWS cuando Kubernetes crea el Service.
# No se puede obtener en terraform apply sin un ALB con DNS fijo.
output "get_api_url" {
  description = "Comando para obtener el hostname del NLB una vez que los pods estén RUNNING"
  value       = "kubectl get svc api-service -n ai-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
