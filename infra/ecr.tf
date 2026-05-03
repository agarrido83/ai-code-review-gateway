resource "aws_ecr_repository" "code_review_api" {
  name = "code-review-api"

  # MUTABLE: permite sobreescribir el tag :latest en cada build (simplicidad de capstone)
  # En producción se usaría IMMUTABLE con el SHA del commit como tag
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Escaneo de CVEs gratuito en ECR Basic; sin coste adicional
  }

  tags = local.capstone_tags
}

# Retener solo las últimas 5 imágenes para no acumular capas en la cuenta personal
resource "aws_ecr_lifecycle_policy" "code_review_api" {
  repository = aws_ecr_repository.code_review_api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
