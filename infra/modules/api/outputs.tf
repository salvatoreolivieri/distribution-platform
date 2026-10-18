output "api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "jwt_issuer" {
  description = "Issuer the auth service must put in iss; equal to the API endpoint."
  value       = local.issuer
}

output "jwks_url" {
  value = "${local.issuer}/.well-known/jwks.json"
}
