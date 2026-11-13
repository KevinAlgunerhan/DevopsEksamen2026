
variable "aws_region" {
  description = "AWS region where Wishifai infrastructure will be deployed"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "wishifai"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "exam-2026"
}

variable "container_port" {
  description = "Port exposed by the Spring Boot application"
  type        = number
  default     = 8080
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "candidate_number" {
  description = "Exam candidate number"
  type        = string
  default     = "21"
}
