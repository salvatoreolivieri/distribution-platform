# Queues and triggers:
#   staging bucket --(S3 event)--> upload-events --> upload-handler
#   upload-handler / watchdog --> tasks --> task worker
#   tasks --(after max_receive_count receives)--> tasks-dlq --> dlq-handler
#   EventBridge Scheduler --> watchdog
# The tasks queue's maxReceiveCount is the retry budget.

resource "aws_sqs_queue" "upload_events_dlq" {
  name                      = "${var.name}-upload-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "upload_events" {
  name                       = "${var.name}-upload-events"
  visibility_timeout_seconds = var.upload_handler_timeout * 6
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.upload_events_dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "upload_events" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.upload_events.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.staging_bucket_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "upload_events" {
  queue_url = aws_sqs_queue.upload_events.id
  policy    = data.aws_iam_policy_document.upload_events.json
}

resource "aws_sqs_queue" "tasks_dlq" {
  name                      = "${var.name}-tasks-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "tasks" {
  name                       = "${var.name}-tasks"
  visibility_timeout_seconds = var.worker_timeout * 6
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tasks_dlq.arn
    maxReceiveCount     = var.retry_budget
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "tasks_dlq" {
  queue_url = aws_sqs_queue.tasks_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.tasks.arn]
  })
}

# ---- triggers (function ARNs are the `live` aliases)

resource "aws_lambda_event_source_mapping" "upload_handler" {
  event_source_arn        = aws_sqs_queue.upload_events.arn
  function_name           = var.upload_handler_arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn        = aws_sqs_queue.tasks.arn
  function_name           = var.worker_arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config {
    maximum_concurrency = var.worker_max_concurrency
  }
}

resource "aws_lambda_event_source_mapping" "dlq_handler" {
  event_source_arn        = aws_sqs_queue.tasks_dlq.arn
  function_name           = var.dlq_handler_arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name}-watchdog-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = var.watchdog_arn
    }]
  })
}

resource "aws_scheduler_schedule" "watchdog" {
  name                = "${var.name}-watchdog"
  schedule_expression = var.watchdog_schedule
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = var.watchdog_arn
    role_arn = aws_iam_role.scheduler.arn
    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}
