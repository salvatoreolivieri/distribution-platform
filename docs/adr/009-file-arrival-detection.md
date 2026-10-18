# ADR-009: Detecting that a file has arrived

**Status:** accepted.

## Decision required

What tells the system that a file's bytes have arrived, and what enqueues that file's tasks?

## Context

Task rows are created before their file's bytes exist, and bytes go from the browser straight to
the staging bucket ([ADR-005](005-file-uploads.md)), so no request the API handles sees an upload
complete. Something must decide that a file has arrived and that its tasks may be enqueued. The
signal must be trustworthy: the point of not proxying bytes is that the client's account of what
happened is not evidence. A watchdog that wakes periodically and arbitrates job completion exists
anyway, so a backstop exists whichever mechanism is chosen.

## Alternatives evaluated

### 1. The client calls an endpoint per file once its upload succeeds

- \+ No storage-side wiring.
- \+ Lowest latency: the client knows first.
- − The claim is unverified, the pattern ADR-005 avoids.
- − A tab closed between the last byte and the call leaves an arrived file marked as never arrived.
- − The server would have to check storage anyway, so the call buys nothing.

### 2. The watchdog polls

On each wake it HEADs every file still `pending`, promotes those that exist and enqueues their tasks.

- \+ No new queue, no bucket notification, one fewer moving part.
- \+ Reuses machinery that exists anyway for deadlines.
- \+ Self-healing: there is no event to lose.
- − Delivery starts on the next wake, not when the upload finishes; a batch uploaded in 20 seconds can
  sit idle for minutes.
- − One HEAD per pending file per wake; a 100-file job polls 100 objects every cycle.
- − Shortening the cycle multiplies that cost across every in-flight job.

### 3. S3 `ObjectCreated` notification to a dedicated queue, consumed by the fan-out worker (chosen)

The worker verifies the object against the declared row, promotes the file and batch-sends its task
messages.

- \+ Deliveries start about a second after the last byte lands.
- \+ The signal comes from storage, the only party that actually knows.
- \+ Retry, visibility timeout and DLQ apply to promotion exactly as to delivery, so a failed
  promotion is recoverable and never silent.
- \+ Work is proportional to files that arrive, not files being waited on.
- − A third queue and DLQ to provision and watch.
- − Bucket notification configuration is one more thing that can be misconfigured.
- − Events can be delayed or lost, so a backstop is still needed.

### 4. S3 `ObjectCreated` notification straight to the fan-out Lambda, no queue

- \+ Same latency as option 3 with one fewer resource.
- − Async Lambda invocation has its own retry model instead of the visibility-timeout and
  `maxReceiveCount` semantics used everywhere else, so failure handling stops being uniform.
- − No queue depth to observe; the promotion backlog becomes invisible.
- − Bursty arrivals hit the function directly with no buffer.

## Decision

Option 3: an S3 `ObjectCreated` notification to a dedicated `upload-events` queue, consumed by the
fan-out worker (the `upload-handler`).

- For each event the worker loads the `files` row by object key, compares the actual size and
  checksum with what the client declared, and promotes the row with a conditional
  `UPDATE ... WHERE status = 'pending'`; a duplicate event promotes once. It then batch-sends one
  task message per destination for that file (at most 20).
- A mismatch leaves the row unpromoted and records the reason; the watchdog fails those tasks at the
  deadline rather than delivering bytes nobody vouched for.
- Option 2 stays as the backstop: the watchdog HEADs any file still `pending` at its deadline.
  Object present means the event was lost, so promote and enqueue; object absent means the upload
  never happened, so fail that file's tasks. A lost notification is a latency problem, not a
  correctness problem.
- Fan-out is per file, not per job: a job whose files arrive at different times starts delivering
  as soon as the first lands.
- Reconsider when a second independent consumer of upload events appears; then a topic in front of
  the queue is worth its hop.
