
# ============================================================
# ECR REPOSITORY
# Stores Docker images for Wishifai
# ============================================================

resource "aws_ecr_repository" "wishifai" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}


# ============================================================
# S3 BUCKET
# Existing bucket containing uploaded Wishifai images
# ============================================================

resource "aws_s3_bucket" "uploads" {
  bucket = "wishifai-uploads"

  lifecycle {
    prevent_destroy = true
  }
}


# ============================================================
# S3 VERSIONING
# Protects against accidental overwrites and deletions
# ============================================================

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}


# ============================================================
# S3 PUBLIC ACCESS BLOCK
# Prevents public access to uploaded images
# ============================================================

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}


# ============================================================
# ECS TASK EXECUTION ROLE
# Allows ECS to pull images from ECR and publish logs
# ============================================================

resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ============================================================
# ECS EXPRESS INFRASTRUCTURE ROLE
# Allows ECS to manage Express Gateway infrastructure
# ============================================================

resource "aws_iam_role" "ecs_infrastructure" {
  name = "${var.project_name}-ecs-infrastructure-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}


# ============================================================
# ECS TASK ROLE
# Permissions used by the Wishifai Spring Boot application
# ============================================================

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# ============================================================
# APPLICATION PERMISSIONS
# S3, Rekognition and Bedrock
# ============================================================

resource "aws_iam_role_policy" "ecs_task_permissions" {
  name = "${var.project_name}-aws-services-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid      = "UploadImagesToS3"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Sid      = "AnalyzeImagesWithRekognition"
        Effect   = "Allow"
        Action   = ["rekognition:DetectLabels"]
        Resource = "*"
      },
      {
        Sid      = "GenerateSuggestionsWithBedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      }
    ]
  })
}


# ============================================================
# CLOUDWATCH LOG GROUP
# Stores Wishifai application logs
# ============================================================

resource "aws_cloudwatch_log_group" "wishifai" {
  name              = "/ecs/wishifai"
  retention_in_days = 30
}


# ============================================================
# ECS EXPRESS GATEWAY SERVICE
# Deploys Wishifai using AWS ECS Express Mode
# ============================================================

resource "aws_ecs_express_gateway_service" "wishifai" {
  service_name            = "wishifai"
  execution_role_arn      = aws_iam_role.ecs_execution.arn
  infrastructure_role_arn = aws_iam_role.ecs_infrastructure.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  health_check_path = "/api/health"

  cpu    = "1024"
  memory = "2048"

  primary_container {
    image          = "${aws_ecr_repository.wishifai.repository_url}:54d3fee"
    container_port = 8080

    environment {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment {
      name  = "S3_BUCKET"
      value = "wishifai-uploads"
    }

    environment {
      name  = "BEDROCK_MODEL_ID"
      value = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
    }

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.wishifai.name
      log_stream_prefix = "wishifai"
    }
  }

  wait_for_steady_state = true

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution,
    aws_iam_role_policy_attachment.ecs_infrastructure,
    aws_iam_role_policy.ecs_task_permissions
  ]
}
