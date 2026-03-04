# ECR Repository para la imagen Docker
resource "aws_ecr_repository" "app" {
  provider = aws.primary
  name     = "${var.project_name}-app"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "${var.project_name}-app-repo"
  }
}

# Lifecycle policy - mantener solo últimas 5 imágenes
resource "aws_ecr_lifecycle_policy" "app" {
  provider   = aws.primary
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
