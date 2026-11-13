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
# EXISTING IAM ROLES REQUIRED BY THE EXAM
# These roles are managed outside this Terraform configuration.
# ============================================================

data "aws_iam_role" "ecs_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_iam_role" "ecs_infrastructure" {
  name = "ecsInfrastructureRoleForExpressServices"
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
# ECS TASK ROLE - CANDIDATE 21
# Permissions used by the Wishifai Spring Boot application
# ============================================================

resource "aws_iam_role" "ecs_task_21" {
  name = "${var.project_name}-task-role-${var.candidate_number}"

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

resource "aws_iam_role_policy" "ecs_task_permissions_21" {
  name = "${var.project_name}-aws-services-policy-${var.candidate_number}"
  role = aws_iam_role.ecs_task_21.id

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
  execution_role_arn      = data.aws_iam_role.ecs_execution.arn
  infrastructure_role_arn = data.aws_iam_role.ecs_infrastructure.arn
  task_role_arn           = aws_iam_role.ecs_task_21.arn

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
    aws_iam_role_policy.ecs_task_permissions_21
  ]
}


# ============================================================
# CLOUDWATCH ALARM
# Monitors Bedrock response parsing failures
# ============================================================

resource "aws_cloudwatch_metric_alarm" "bedrock_parse_failures" {
  alarm_name        = "${var.project_name}-bedrock-parse-failures"
  alarm_description = "Triggers when Wishifai encounters Bedrock response parsing failures"

  namespace   = "wishifai"
  metric_name = "wishifai.bedrock.parse.failures.count"

  statistic = "Sum"
  period    = 60

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1

  evaluation_periods  = 1
  datapoints_to_alarm = 1

  treat_missing_data = "notBreaching"

  tags = {
    Name        = "Wishifai Bedrock Parse Failures"
    Environment = var.environment
  }
}


# ============================================================
# CLOUDWATCH DASHBOARD
# Centralized application observability
# ============================================================

resource "aws_cloudwatch_dashboard" "wishifai" {
  dashboard_name = "Wishifai-Observability"

  dashboard_body = jsonencode({
    widgets = [

      # ------------------------------------------------------
      # HTTP REQUESTS - SUCCESSFUL IMAGE ANALYSIS
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "Successful Image Analysis Requests"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Sum"

          metrics = [
            [
              "wishifai",
              "http.server.requests.count",
              "exception", "none",
              "method", "POST",
              "error", "none",
              "uri", "/api/analyze",
              "outcome", "SUCCESS",
              "status", "200"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # HTTP RESPONSE TIME - IMAGE ANALYSIS
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "Image Analysis Response Time"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Average"

          metrics = [
            [
              "wishifai",
              "http.server.requests.avg",
              "exception", "none",
              "method", "POST",
              "error", "none",
              "uri", "/api/analyze",
              "outcome", "SUCCESS",
              "status", "200"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # JVM HEAP MEMORY - G1 EDEN SPACE
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          title  = "JVM Heap Memory - G1 Eden Space"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Average"

          metrics = [
            [
              "wishifai",
              "jvm.memory.used.value",
              "area", "heap",
              "id", "G1 Eden Space"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # PROCESS CPU
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          title  = "Process CPU Usage"
          region = var.aws_region
          period = 300
          view   = "timeSeries"
          stat   = "Average"

          metrics = [
            [
              "wishifai",
              "process.cpu.usage.value"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # IMAGES ANALYZED
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6

        properties = {
          title  = "Images Analyzed"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Sum"

          metrics = [
            [
              "wishifai",
              "wishifai.images.analyzed.count"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # GIFTS GENERATED
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6

        properties = {
          title  = "Gifts Generated"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Sum"

          metrics = [
            [
              "wishifai",
              "wishifai.gifts.generated.count"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # BEDROCK PARSE FAILURES
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6

        properties = {
          title  = "Bedrock Parse Failures"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Sum"

          metrics = [
            [
              "wishifai",
              "wishifai.bedrock.parse.failures.count"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # BEDROCK RESPONSE TIME
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6

        properties = {
          title  = "Bedrock Response Time (Milliseconds)"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Average"

          metrics = [
            [
              "wishifai",
              "wishifai.bedrock.duration.avg"
            ]
          ]
        }
      },

      # ------------------------------------------------------
      # REKOGNITION RESPONSE TIME
      # ------------------------------------------------------

      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6

        properties = {
          title  = "Rekognition Response Time (Milliseconds)"
          region = var.aws_region
          period = 3600
          view   = "timeSeries"
          stat   = "Average"

          metrics = [
            [
              "wishifai",
              "wishifai.rekognition.duration.avg"
            ]
          ]
        }
      }
    ]
  })
}