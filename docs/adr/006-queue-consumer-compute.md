# ADR-006: Compute for the queue consumers

**Status:** accepted.

## Decision required

What compute runs the queue consumers: Lambda, an ECS service, or EC2?

## Context

Workers consume SQS messages in three roles: fan-out on the upload-events queue (verify the staged
object, promote the file, batch-send task messages), delivery on the tasks queue (deliver to the
platform, update status, push the WebSocket update), and the watchdog (deadlines, job completion,
re-arm). Separate WebSocket lifecycle handlers cover `$connect`, `$disconnect` and `subscribe`.
Load: 90,000 tasks/day, bursty (2,000-task spikes), 2 MB average, 1 GB maximum. Status writes go to
PostgreSQL.

## Alternatives evaluated

### 1. Lambda with SQS event source mappings (chosen)

- \+ Scales to zero between bursts; no idle cost at 90k/day.
- \+ Per-message concurrency scaling with no autoscaling configuration.
- \+ Retry and DLQ semantics native to the SQS integration.
- \+ Fan-out and delivery are separate functions, sized separately.
- − 15-minute hard cap; the 1 GB worst case must stream within it (it does, with margin).
- − Concurrent invocations exhaust Postgres connections: RDS Proxy becomes required.
- − No resident process: no in-memory batching; cold starts.

### 2. ECS Fargate worker service long-polling SQS

- \+ No execution time cap; persistent connection pools, no proxy needed.
- \+ Same container model as the API services.
- \+ A resident process allows in-memory coalescing.
- − Always-on cost for a bursty workload that is idle most of the day.
- − Queue-depth autoscaling must be built and tuned by hand.

### 3. EC2 auto-scaling group of consumers

- \+ Cheapest per compute-hour at sustained high load.
- − Slowest scaling; instances to patch and manage.
- − Sustained high load is not this workload.

## Decision

Option 1: Lambda. The workload is per-message independent, which is exactly Lambda's shape.
Accepted consequences, written into the design: RDS Proxy in front of PostgreSQL, and the delivery
function sized for the 1 GB worst case (Lambda memory also sets network throughput).

In the implementation the roles are the `upload-handler` (fan-out), the task worker (delivery),
the `watchdog` (on an EventBridge schedule), the `dlq-handler`, and one `ws` function for every
WebSocket route.
