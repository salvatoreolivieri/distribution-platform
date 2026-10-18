output "upload_events_queue_arn" {
  value = aws_sqs_queue.upload_events.arn
}

output "upload_events_queue_url" {
  value = aws_sqs_queue.upload_events.url
}

output "tasks_queue_arn" {
  value = aws_sqs_queue.tasks.arn
}

output "tasks_queue_url" {
  value = aws_sqs_queue.tasks.url
}

output "tasks_dlq_arn" {
  value = aws_sqs_queue.tasks_dlq.arn
}

output "tasks_dlq_url" {
  value = aws_sqs_queue.tasks_dlq.url
}
