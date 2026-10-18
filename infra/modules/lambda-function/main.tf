# One Lambda, any of our runtimes: its IAM role (least privilege: logs, VPC networking and
# the statements the caller passes), its log group, a published version and a `live` alias.
# Callers (API Gateway, event source mappings, schedules) always target the alias, which is
# what SnapStart requires.

locals {
  runtimes = {
    go     = { runtime = "provided.al2023", handler = "bootstrap" }
    python = { runtime = "python3.13", handler = var.handler }
    java   = { runtime = "java21", handler = var.handler }
  }
  runtime = local.runtimes[var.runtime_kind]
  in_vpc  = length(var.subnet_ids) > 0
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "base" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
  statement {
    # X-Ray does not support resource-level permissions for these actions.
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = local.in_vpc ? [1] : []
    content {
      # ENI management for VPC Lambdas; these actions do not support resource scoping.
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "base" {
  name   = "base"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.base.json
}

resource "aws_iam_role_policy" "extra" {
  count  = var.policy_json == null ? 0 : 1
  name   = "service"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

resource "aws_lambda_function" "this" {
  function_name    = var.name
  role             = aws_iam_role.this.arn
  runtime          = local.runtime.runtime
  handler          = local.runtime.handler
  architectures    = ["arm64"]
  filename         = var.artifact_path
  source_code_hash = filebase64sha256(var.artifact_path)
  memory_size      = var.memory_size
  timeout          = var.timeout
  publish          = true

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = var.environment
  }

  dynamic "vpc_config" {
    for_each = local.in_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  dynamic "snap_start" {
    for_each = var.snapstart ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  depends_on = [aws_iam_role_policy.base]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

check "snapstart_runtime" {
  assert {
    condition     = !var.snapstart || var.runtime_kind != "go"
    error_message = "SnapStart is not available for provided.al2023 (Go); Go cold starts are fast enough without it."
  }
}
