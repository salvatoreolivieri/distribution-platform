output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "alias_name" {
  value = aws_lambda_alias.live.name
}

output "alias_arn" {
  value = aws_lambda_alias.live.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the live alias, for API Gateway integrations."
  value       = aws_lambda_alias.live.invoke_arn
}

output "role_name" {
  value = aws_iam_role.this.name
}
