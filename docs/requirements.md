# Requirements

Source: DocBridge PAS-002. The problem and the user flows are in [blueprint.md](blueprint.md).

## Functional requirements

| # | Requirement | Detail |
|---|---|---|
| FR-1 | Destination discovery | An authenticated user can browse the destinations available to them: teams, binders and nested folders. The list reflects the user's real permissions; they see and upload only to what they are authorized to access. |
| FR-2 | File selection and destination mapping | A user selects multiple files in one session and assigns each file to one or more destinations. One file can go to many destinations; one destination can receive many files. |
| FR-3 | Job submission | Submitting creates a job that represents the whole batch. The system acknowledges submission immediately; the user does not wait for uploads to finish. Users can see their active and past jobs. |
| FR-4 | Asynchronous processing | Each file-to-destination pair is a task; a job is one or more tasks. Tasks are processed asynchronously and independently: one task failing must not block or cancel the others. Processing is decoupled from submission. |
| FR-5 | Status tracking | Each task has a lifecycle: `pending`, `in_progress`, `completed`, `failed`. The job's status is an aggregate derived from its tasks. Users can query a job and see every task's status, and statuses update automatically as work progresses. |
| FR-6 | File delivery | Each task uploads a file to the client's document platform through its API. The file must arrive intact (integrity verified). Delivery failures are handled gracefully and surfaced on the task with enough detail to understand what went wrong. |
| FR-7 | Authentication and authorization | Every operation runs on behalf of an authenticated user. The system manages users and credentials itself, including login and token issuance. Authorization is resource-based: access is determined by the teams a user belongs to, and users see and act only on resources of those teams. |
| FR-8 | File retrieval | A user can download any file of a job submitted by a member of their teams. Downloads must not flow through application servers. |

Task status meanings (FR-5):

- **pending**: the task exists and its message is waiting in the queue. No worker has touched it.
- **in_progress**: a worker took the message and is executing. The queue no longer holds it; the worker owns it.

## Non-functional requirements

### Scale

| Dimension | Target |
|---|---|
| Active users | 2,000 registered; up to 200 concurrent during business hours |
| Files per batch | Up to 100 per job |
| Destinations per batch | Up to 20 per job |
| Tasks per job (files × destinations) | Up to 2,000 in one operation |
| Daily deliveries | 90,000 tasks/day |
| Average file size | 2 MB |
| Maximum file size | 1 GB |
| Supported file types | PDF, DOCX, XLSX, PNG, JPG (no executables) |

### Availability

99.9% uptime: less than 9 hours of unplanned downtime per year.

### Performance

- Job submission acknowledged in under **500 ms at p99**, whatever the number of files or destinations.
- The destination browser (teams, binders, folders) loads in under **1 second** for a user with access to up to 50 teams.
- The UI stays responsive during file selection and upload; it never freezes or blocks the user.

### Reliability

- No uploaded file is silently lost. Delivery failure rate stays at or below **0.1%** under normal conditions, and every failure is recorded and shown to the user with enough detail to understand it.
- Transient delivery failures (for example, the destination API is temporarily unavailable) are retried automatically, **at least 3 times** before a task is marked failed.
- Partial failure is expected: if some tasks of a job fail, the rest still complete.
- A failed task does not affect any other task of the same job.

### Security

- All files are encrypted at rest, with keys managed by the cloud key management service. The system implements no cryptography of its own.
- File integrity is verifiable end to end: any corruption between upload and delivery is detected.
- Files are never accessible to anyone other than the submitting user's authorized team members, at any point in the pipeline.
- No credentials, API keys or secrets in source code. Secrets are injected at runtime through environment variables or a secrets manager.
- Every API endpoint requires authentication; unauthenticated requests are rejected.
- Compliance: staged files are kept for 30 days after job completion, then deleted.

### Operability

- Deployment to the cloud is automated; no manual steps beyond the initial credentials setup.
- All configuration (database URLs, AWS credentials, service endpoints, feature flags) comes from environment variables or a secrets manager.
- The application services (API, auth, workers, document platform) run locally with docker compose against emulated or dev cloud resources.

## Scope (feature level)

- User registration, login and token-based sessions
- Destination browsing filtered by real team membership
- Multi-file selection with direct-to-staging upload and per-file progress
- File-to-destination mapping and one-action batch submission with instant acknowledgment
- Asynchronous, independent per-task delivery with automatic retries
- Job and task status tracking down to individual failure reasons
- Team-scoped file download, direct from staging
- Encrypted staging with 30-day post-completion retention

**External dependencies:** none. The auth service and the document platform are built as part of this release.

## Success metrics

| Metric | Target | How we measure |
|---|---|---|
| Job submission latency | p99 < 500 ms regardless of batch size | Submission API response time (`tests/load`) |
| No silent file loss | 0 undetected failures | Every failed task appears in the status view; DLQ depth stays at 0 in normal operation |
| Delivery failure rate | ≤ 0.1% under normal conditions | Failed tasks / total tasks over a rolling window |
| Destination browser load time | < 1 s for users with ≤ 50 teams | Time to interactive on first browse |
| Partial failure isolation | A failed task does not block its siblings | Integration test: kill one delivery, assert the others complete |
| End-to-end pipeline | A full batch completes locally and in the cloud | Smoke test: N files × M destinations → all tasks completed |
