# Reliability, security and testing

## Failure modes

| Dependency down | Effect | Recovery |
|---|---|---|
| Document platform | Deliveries fail and are retried through the visibility timeout, to the DLQ after the retry budget; browsing and submission validation return 502 | The backlog drains when the platform returns; the DLQ handler marks stragglers failed (visible, not silent) |
| Auth service | Logins fail; workers keep delivering with cached service tokens until they expire, then the retry path applies | Smallest, most stable service; Lambda replaces failed execution environments |
| PostgreSQL | User-facing requests fail; SQS buffers messages (14-day retention) | Messages replay on recovery; idempotency makes replay safe |
| S3 / KMS | Uploads and deliveries fail transiently | The standard retry path; nothing acknowledged is lost |
| S3 event lost or delayed | Tasks sit pending; the watchdog HEADs the object at the deadline and promotes it | A latency problem, not a correctness problem |
| User closes the tab mid-upload | Remaining files miss the deadline; their tasks fail `FILE_NOT_UPLOADED` with file name and destination | Files already uploaded deliver normally |
| WebSocket push path | The dashboard stalls | Non-fatal by design; refetch on reconnect; deliveries unaffected |
| One AZ | Lambda, API Gateway, SQS and S3 are multi-AZ managed services; RDS Multi-AZ in prod | Meets 99.9% without extra machinery |

The PAS rows for the auth service and one AZ referred to ECS; they are corrected here for
[ADR-010](../adr/010-compute-api-gateway-and-lambda.md), as the PAS "Stack" decision asked.

## Delivery semantics

- **Retry budget:** the `tasks` queue's `maxReceiveCount` owns it (at least 3, per the requirements;
  5 in `infra/`). `attempt_count` is for display and fencing only.
- **Lease (decision 5):** claim with
  `WHERE status = 'pending' OR (status = 'in_progress' AND lease_expires_at < now())`; the lease is
  sized by file size and capped below the Lambda timeout. Completion is fenced with
  `AND attempt_count = :claimedAttempt`, so a worker whose lease expired cannot overwrite a newer
  attempt.
- **Idempotent ingest:** the platform's `PUT` on `sourceTaskId` makes a redelivered task a replay,
  never a duplicate document.
- **Classification:** 429, 5xx and timeouts are transient (back to pending, retried); 409, 422, 404
  and 403 from ingest are permanent (failed, with the reason).

## Security controls

- Encryption at rest: SSE-KMS with customer-managed keys on the staging and documents buckets;
  RDS storage encrypted; secrets in Secrets Manager.
- Integrity: client SHA-256 → S3 checksum on write (per part for multipart) → full SHA-256 at
  ingest.
- Least privilege: one IAM role per Lambda; one Postgres role per service; service tokens scoped
  (`documents:ingest`).
- No existence leaks: 404, not 403, on every job and file resource the caller cannot see.
- Presigned URLs: one object, short expiry, issued only after an authorization check.

## Testing strategy

- **Unit** (every CI run): token issuance and validation, presigned policy construction, task claim
  logic, aggregate status derivation, transient-versus-permanent failure classification.
- **Integration** (docker compose + LocalStack): submit → fan-out → deliver locally; double delivery
  of the same task message; the DLQ path marks tasks failed; upload-event promotion; a duplicate
  `ObjectCreated` promotes once; a checksum mismatch leaves the file unpromoted. The grants test
  (`just test-integration`) proves table ownership.
- **Shared scenarios:** `tests/shared-scenarios/task-transitions.json`, run by every implementation
  that changes task status.
- **Contract conformance:** `tests/api-conformance`, black-box against every API implementation.
- **E2E** (deployed dev): the M5 list, gated before any prod apply.
- **Load:** `tests/load`, `POST /jobs` p99 under 500 ms with 100 files and about 2,000 tasks.
