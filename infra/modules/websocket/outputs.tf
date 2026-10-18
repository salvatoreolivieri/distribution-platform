output "url" {
  value = "${aws_apigatewayv2_api.this.api_endpoint}/${var.stage_name}"
}

output "management_endpoint" {
  description = "Endpoint the ws Lambda posts to (connections API)."
  value       = "https://${aws_apigatewayv2_api.this.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${var.stage_name}"
}

output "connections_arn" {
  description = "Resource for execute-api:ManageConnections."
  value       = "${aws_apigatewayv2_api.this.execution_arn}/${var.stage_name}/POST/@connections/*"
}
