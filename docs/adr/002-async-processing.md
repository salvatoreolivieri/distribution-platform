# ADR-002: Async processing

**Status:** accepted.

## Decision required

How do we process a job's tasks asynchronously and independently of each other?

## Context

Each file-to-destination pair becomes an independent task. Tasks can be processed asynchronously,
retried independently and scaled on queue depth. A failed task must not block the other tasks of
the same job.

## Alternatives evaluated

### 1. Synchronous job processing (no queue)

The API receives the job and performs every file-to-destination upload inline, holding the HTTP
request open until all are done.

- \+ Easy.
- \+ Stronger "all or nothing" feel for the client: the job is done when the response returns.
- − Poor scalability and long-running requests; large jobs hit timeouts.

### 2. SQS to decouple task submission from processing (chosen)

One SQS message per file-to-destination pair; workers consume the queue and upload asynchronously.

- \+ Each task is isolated; one failed upload does not block the others.
- \+ Horizontal scaling by matching workers to queue depth.
- − Extra operational overhead: queues, workers, monitoring.
- − Needs careful idempotency and visibility-timeout design to avoid duplicates.

### 3. Event-driven processing (SNS + SQS, or EventBridge)

The API publishes a `JobCreated` event; consumers fan out into queues and process uploads.

- \+ Flexible for future integrations: other services can subscribe.
- \+ Decouples job creation from processing and from future consumers (audit, notifications,
  analytics).
- − More complex than one SQS queue for this scope.
- − More moving parts to operate (topics, rules, several queues).
- − Overengineered for now.

## Decision

Option 2. SQS-based task processing gives per-task isolation, scalable asynchronous processing and
robust retry and DLQ patterns, at much lower complexity than a fully event-driven architecture. A
synchronous model would be simpler but does not meet the scalability and reliability needs of large
multi-destination jobs.
