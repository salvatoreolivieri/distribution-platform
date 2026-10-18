# HTTP API Gateway in front of the auth, platform and DocBridge Lambdas.
#
# Routes are grouped, and each group points at a backend through var.route_backends, so moving
# a group to another implementation (for example DocBridge from Go to Java) is a one-line
# change in envs/. The JWT authorizer trusts our own issuer: the auth service publishes
# /.well-known/openid-configuration and /.well-known/jwks.json on this same API.

locals {
  issuer = aws_apigatewayv2_api.this.api_endpoint

  route_groups = {
    auth = {
      authorization = "NONE"
      scopes        = []
      routes = [
        "POST /v1/auth/login",
        "POST /v1/auth/refresh",
        "POST /v1/auth/logout",
        "POST /v1/auth/token",
        "GET /.well-known/jwks.json",
        "GET /.well-known/openid-configuration",
      ]
    }
    auth_me = {
      authorization = "JWT"
      scopes        = []
      routes        = ["GET /v1/auth/me"]
    }
    browse = {
      authorization = "JWT"
      scopes        = []
      routes        = ["GET /v1/binders", "GET /v1/binders/{binderId}/tree"]
    }
    documents = {
      authorization = "JWT"
      scopes        = []
      routes        = ["GET /v1/documents/{documentId}", "GET /v1/documents/{documentId}/download"]
    }
    ingest = {
      authorization = "JWT"
      scopes        = ["documents:ingest"]
      routes        = ["ANY /internal/v1/{proxy+}"]
    }
    destinations = {
      authorization = "JWT"
      scopes        = []
      routes        = ["GET /v1/destinations"]
    }
    jobs = {
      authorization = "JWT"
      scopes        = []
      routes = [
        "POST /v1/jobs",
        "GET /v1/jobs",
        "GET /v1/jobs/{jobId}",
        "POST /v1/jobs/{jobId}/files/{fileId}/upload-target",
        "POST /v1/jobs/{jobId}/files/{fileId}/upload-failed",
      ]
    }
    files = {
      authorization = "JWT"
      scopes        = []
      routes        = ["GET /v1/files/{fileId}/download-url"]
    }
  }

  routes = merge([
    for group, g in local.route_groups : {
      for r in g.routes : r => {
        backend       = var.route_backends[group]
        authorization = g.authorization
        scopes        = g.scopes
      }
    }
  ]...)
}

resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "docbridge-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    issuer   = local.issuer
    audience = [var.jwt_audience]
  }
}

resource "aws_apigatewayv2_integration" "backend" {
  for_each               = var.backends
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "this" {
  for_each             = local.routes
  api_id               = aws_apigatewayv2_api.this.id
  route_key            = each.key
  target               = "integrations/${aws_apigatewayv2_integration.backend[each.value.backend].id}"
  authorization_type   = each.value.authorization
  authorizer_id        = each.value.authorization == "JWT" ? aws_apigatewayv2_authorizer.jwt.id : null
  authorization_scopes = length(each.value.scopes) > 0 ? each.value.scopes : null
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      routeKey    = "$context.routeKey"
      status      = "$context.status"
      latencyMs   = "$context.responseLatency"
      integration = "$context.integration.status"
      authError   = "$context.authorizer.error"
      sub         = "$context.authorizer.claims.sub"
    })
  }
}

resource "aws_lambda_permission" "backend" {
  for_each      = var.backends
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  qualifier     = each.value.alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
