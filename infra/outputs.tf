output "wishifai_url" {
  description = "Public URL of the Wishifai ECS Express service"
  value       = aws_ecs_express_gateway_service.wishifai.ingress_paths[0].endpoint
}

output "ecs_service_arn" {
  description = "ARN of the Wishifai ECS Express service"
  value       = aws_ecs_express_gateway_service.wishifai.service_arn
}

output "task_role_arn" {
  description = "IAM task role for candidate 21"
  value       = aws_iam_role.ecs_task_21.arn
}