# Milestones

The implementation plan, and the place where its progress is recorded. Every agent and every
person working on the repo keeps this file current; see [How to update this file](#how-to-update-this-file).

Source: DocBridge PAS-002 ("Milestones", "Decisions", "Break Down"). Requirements:
[requirements.md](requirements.md). Design: [architecture/](architecture/README.md).

## Status

| Milestone | Flow | Estimate | Demoable at the end | Status |
|---|---|---|---|---|
| [M0](#m0-foundations) | Foundations (no flow) | 3 days | Infra live, pipelines green, `just up` runs the whole stack locally, grants test proves table ownership | In progress: code done; dev deploy pending |
| [M1](#m1-auth--browse-destinations) | Flow 1: Browse destinations | 7 days | Log in, browse the team/binder/folder tree in the browser | Not started |
| [M2](#m2-distribute-files) | Flow 2: Distribute files | 10 days | Submit an upload job, then follow details and statuses for every file | Not started |
| [M3](#m3-live-updates--download) | Flow 3: Live updates + download | 5.5 days | The job page updates by itself; a teammate downloads a file, an outsider gets 404 | Not started |
| [M4](#m4-track-jobs--manage-files) | Flow 4–5: Track jobs + manage files | 6 days | Active and past jobs, a full log of what was sent, search → rename → delete | Not started |
| [M5](#m5-hardening--e2e-verification) | Hardening + E2E verification | 2.5 days | Success metrics proven on the deployed system | Not started |
| **Total** | | **34 days** | | |

Estimates follow the per-milestone breakdown below. The PAS summary table has different figures
for M2–M5 (9, 7, 5, 2 days; 33 in total); that mismatch is an open point.

Status values: `Not started`, `In progress`, `Blocked: <reason>`, `Done`. A milestone is `Done`
only when its demo works and every box under it is ticked or explicitly moved to another milestone.

## How to update this file

- **Before starting** an item, set its milestone to `In progress` and append `(in progress)` to the
  item. Working in parallel? Put your session or branch name in it, so two agents do not take the
  same item: `(in progress: m1-auth-service)`.
- **When an item is finished and verified** (see the checks in [CLAUDE.md](../CLAUDE.md)), tick it
  and add a short note under it if anything differs from the plan: a link to the PR, a changed
  route, a follow-up. Tick it in the same commit as the work.
- **When the plan changes**, edit the item and say why in the commit message. Do not delete
  unfinished items: move them to another milestone and say where they went.
- **When a decision is taken**, add it to [Decisions after the design](#decisions-after-the-design),
  or write an ADR in [adr/](adr/README.md) if alternatives were weighed.
- **When code and design disagree**, add a row to [Divergences](#divergences-between-the-pas-and-m0)
  rather than silently picking one.
- **Blocked**: mark the milestone `Blocked: <reason>` and say what would unblock it.

## Decisions after the design

These replace "Gaps in the design to settle before M1/M2" in the PAS.

| # | Topic | Decision |
|---|---|---|
| A1 | Build vs integrate | Everything is built in-house: auth service, document platform, DocBridge. No external or managed identity service ([ADR-013](adr/013-own-token-issuer.md)). |
| A2 | Table ownership | One DB, one writer per table; writes to another service's tables go through its HTTP API. Enforced with one Postgres role per service with write grants only on its own tables ([ADR-014](adr/014-table-ownership.md)). **Auth:** users, refresh_tokens, service_clients. **Platform:** teams, team_members, binders, folders, documents. **DocBridge:** jobs, files, tasks, status_events, ws_connections. |
| 1 | Refresh tokens + logout | `refresh_tokens(id, user_id, family_id, token_hash, expires_at, used_at, revoked_at, created_at)`. Rotation on every refresh; presenting an already-used token revokes the whole family. `POST /auth/logout` revokes the family and returns 204. Access tokens stay valid up to 15 min after logout (no `jti` denylist). The refresh token is an `httpOnly; Secure; SameSite=Strict` cookie scoped to `/api/v1/auth`. |
| 2 | Platform ingest | Pull-based. `PUT /internal/v1/documents/{sourceTaskId}`, service JWT with scope `documents:ingest`. Body `{onBehalfOfUserId, teamId, binderId, folderId?, name, contentType, sizeBytes, sha256, sourceUrl}`; `sourceUrl` is a presigned GET valid for ~15 min. Idempotent through the `PUT` on `sourceTaskId`. 201 created; 200 replay with the same payload; 409 replay with a different payload (permanent); 422 `CHECKSUM_MISMATCH` (permanent); 404 `DESTINATION_NOT_FOUND` (permanent); 403 `ACCESS_REVOKED` when membership changed or DocBridge was disabled after submission (permanent); 429, 5xx, timeout: transient. Bytes never pass through the worker; the platform verifies the full SHA-256 while copying into its documents bucket. |
| 3 | Split `files` | `files` is the staging object only, one per upload, status `pending \| uploaded \| rejected \| expired`. Placement columns, `source_task_id` and `ingested` dropped. New platform-owned `documents(id, team_id, binder_id, folder_id, name, size, content_type, sha256, storage_key, source_task_id UNIQUE, created_by, created_at, deleted_at)`; `tasks.platform_document_id` links them. Search, rename and delete move to the Platform API (`GET/PATCH/DELETE /api/v1/documents…`). DocBridge keeps `/files/:id/multipart` and `/files/:id/download-url` (staging, while retained). |
| 4 | Multipart checksums | `CreateMultipartUpload` with `ChecksumAlgorithm=SHA256` and a SHA-256 per part, verified by S3 on arrival. Fixed part size in the contract; the hash worker computes the full hash and the part hashes in one pass. `POST /files/:id/multipart` takes `parts: [{partNumber, sha256}]` (unsigned `x-amz-*` headers are rejected on presigned URLs). The platform checks the full-object SHA-256 at ingest. For multipart, a mismatch surfaces as `CHECKSUM_MISMATCH` on the tasks, and the upload handler checks size only. |
| 5 | Task lease | Add `tasks.lease_expires_at`. Claim: `WHERE status='pending' OR (status='in_progress' AND lease_expires_at < now())`, lease sized by file size and capped below the Lambda timeout. Completion fenced with `AND attempt_count = :claimedAttempt`. SQS redelivery handles recovery; the watchdog is a backstop for lost messages. SQS `maxReceiveCount` owns the retry budget; `attempt_count` is for display and fencing. |
| 6 | Idempotency key | Partial UNIQUE `(submitted_by_user_id, idempotency_key)` plus `jobs.request_hash`. Same key with a different payload returns 422 `IDEMPOTENCY_KEY_REUSED`. Concurrent duplicates: `INSERT … ON CONFLICT DO NOTHING`, then `SELECT`. A replay re-presigns uploads only for files still pending. |
| — | Small items | `expiresIn` everywhere. Paginated envelope everywhere, no exceptions. One WebSocket subscription per connection; `subscribe` replaces the current job; add `unsubscribe`. Log view: `GET /jobs/:id/events?taskId=&page=&limit=` (paginated status_events). Add `'upload'` to the status_events actor CHECK. |
| — | Stack | Go services and Lambdas, Python task worker ([ADR-012](adr/012-python-task-worker.md); the PAS said Java), React web, Terraform, API Gateway + Lambda ([ADR-010](adr/010-compute-api-gateway-and-lambda.md)). Auth and platform are two more Go binaries. ECS rows in the failure-modes table corrected in [reliability-security-testing.md](architecture/reliability-security-testing.md). |

### Open points

- **Maximum file size.** It sets the multipart threshold, part size, Lambda timeouts and the lease
  formula. Needed before M2.
- **Summary table vs breakdown.** M3's label vs its demo, and the estimates (see [Status](#status)).
  Fix while revising M1–M5.
- **One schema or one schema per owner.** See ADR-014 and divergence D6 below. Settle in M1.0.

## Divergences between the PAS and M0

M0 was built from the Technical Design before the decisions above were folded in, so its contracts
and schema differ from the PAS in places. M1.0 settles them: for each row, either change the code
to match the PAS, or update the PAS-derived docs and record why. Remove a row once it is settled.

| # | Area | PAS says | M0 has |
|---|---|---|---|
| D1 | Response envelope | `{success, status, data, errors: [{code, message, field?}], message}`; offset pagination `{page, limit, total, totalPages}` | `{data, meta}` on success, `{error: {code, message, details}}` on failure; cursor pagination (`contracts/openapi/common.yaml`, `internal/envelope`, `web/src/api/client.ts`) |
| D2 | Route prefix | `/api/v1/...` | `/v1/...` (contracts, Go routers, `infra/modules/api` route groups, Vite proxy) |
| D3 | Platform browse | `GET /teams?docbridgeEnabled=true`, `/teams/:id/binders`, `/binders/:id/contents`, `/folders/:id/contents`; documents search/rename/delete | `GET /v1/binders`, `/v1/binders/{id}/tree`, `/v1/documents/{id}`, `/v1/documents/{id}/download` |
| D4 | Platform ingest | `PUT /internal/v1/documents/{sourceTaskId}` with `sourceUrl`, `onBehalfOfUserId`, `teamId` (decision 2) | `POST /internal/v1/binders/{binderId}/documents` with `stagingKey` and `idempotencyKey`; failure injection keys per-binder rules on the `{binderId}` path value |
| D5 | DocBridge routes | `POST /jobs` with `files` + `mappings[{fileIndex, destinations}]`; `/files/:id/multipart`; `POST /files/:id/download-url`; `/jobs/:id/tasks`; `/jobs/:id/events` | `POST /v1/jobs` with destinations inline per file; `/upload-target`; `/upload-failed`; `GET /v1/files/{id}/download-url`; `GET /v1/destinations`; no tasks or events endpoints |
| D6 | Schemas and ownership | One schema; teams and team_members owned by the platform; no `access_grants` (access comes from team membership) | One schema per owner (`auth`, `platform`, `docbridge`); teams and team_members in `auth`; `platform.access_grants` with user/team grants per binder or folder; binders have `region` and no `team_id` |
| D7 | Tables and columns | `status_events` (actors `api`, `delivery`, `watchdog`, `dlq`, `upload`), `ws_connections`, `refresh_tokens` with `family_id`/`used_at`, `documents` per decision 3, `jobs` without a status column (aggregate derived) but with `task_count`, `next_check_at`, `idempotency_key`, `request_hash`; `tasks.attempt_count`, `failure_reason`, `job_id`, `team_id` | `task_events` (actors `api`, `upload_handler`, `worker`, `dlq_handler`, `watchdog`, `user`); no `ws_connections`; `refresh_tokens` without families; `jobs.status`; `tasks.attempts`, `error_code`, no `job_id`/`team_id`; `users.display_name` |
| D8 | Statuses | Task: `pending, in_progress, completed, failed`. File: `pending, uploaded, rejected, expired` | Task adds `skipped`. File: `pending_upload, uploaded, upload_failed, expired`. Same in `tests/shared-scenarios/task-transitions.json` |
| D9 | Auth routes | `register` exists; no `me` | No `register`; has `GET /v1/auth/me` |
| D10 | Password hashing | argon2id | Seed hashes with bcrypt (`pgcrypto` `crypt`/`gen_salt('bf')`); the auth service must be able to verify seed users |
| D11 | Retry budget | "DLQ after 3" (failure modes); at least 3 attempts (requirements) | `maxReceiveCount = 5` (`infra`, LocalStack); satisfies the requirement |

## M0: Foundations

**Status:** In progress. Code done; dev deploy pending. 3 days.

### Monorepo (0.5d)

- [x] `contracts/openapi/`: `common.yaml` (envelope, pagination, errors), `auth.yaml`,
  `platform.yaml` (browse, documents, `/internal/v1/*` ingest), `docbridge.yaml`;
  `contracts/events/` unchanged.
- [x] `services/backend/cmd/`: auth, platform, api, upload-handler (was task-creator), dlq-handler,
  watchdog (was sweeper), ws (every WebSocket route).
- [x] `internal/`: shared jwtverify, envelope, platform/ (config, logging, AWS clients); per-service
  auth/, platformsvc/, DocBridge packages; store/ split by owner.
- [x] `services/task-worker/` scaffolded with an empty handler. Python with import-linter instead of
  Gradle and ArchUnit ([ADR-012](adr/012-python-task-worker.md)).
- [x] Web types from openapi-typescript (no `packages/shared`).

### Infrastructure as code (1.5d)

- [x] network: VPC, private subnets, VPC endpoints (S3, SQS, KMS, Secrets Manager), NAT (single in
  dev), flow logs.
- [x] database: RDS Postgres + RDS Proxy (IAM auth); extensions citext, pgcrypto, pg_trgm; roles
  auth_svc, platform_svc, docbridge_svc, worker_svc, each with its own secret.
- [x] storage: staging bucket (CMK, CORS for POST and multipart, lifecycle) and platform-owned
  documents bucket.
- [x] auth: ES256 KMS key (kid = key version); worker client secret in Secrets Manager.
- [x] api: HTTP API, route groups per backend, JWT authorizer on our JWKS, `/internal/v1/*` requires
  `documents:ingest`.
- [x] WebSocket API → ws Lambda.
- [x] processing: upload-events, tasks, tasks-dlq (`maxReceiveCount` = retry budget), EventBridge
  schedule → watchdog.
- [x] Generic lambda-function module (Go/Python/Java, SnapStart), one IAM role per Lambda.
- [ ] Make the state bucket name configurable instead of hard-coded in both `backend.tf` files.
- [ ] Split the GitHub OIDC role: read-only for PR plans, admin only for deploys from `main`.
- [ ] Bootstrap the AWS account (`infra/bootstrap`) and set the `AWS_DEPLOY_ROLE_ARN` repository
  variable.
- [ ] First `terraform plan` and `apply` of `infra/envs/dev`; fix what the real account reports.
- [ ] Apply migrations and role passwords on RDS (CI cannot reach the private subnets; for example a
  migrate Lambda). Not needed for the M0 demo; needed before M1 runs in dev.

### Local environment (0.5d)

- [x] docker compose: Postgres, LocalStack (S3, SQS, KMS), auth, api, two platform containers (eu,
  us) with their own failure-injection configs.
- [x] dbmate migrations from `000_roles.sql`, seed script.
- [x] `just up | down | seed | migrate | gen | build | test | lint | test-integration | tf-check | tf-plan`.

### CI/CD (0.5d)

- [x] One workflow per area: web, backend, task-worker, contracts, infra, deploy-dev.
- [x] Drift check: `contracts` fails when generated code is out of date.
- [x] Grants integration test: every role's write against a table it does not own fails.
- [x] Deploy to dev on merge (skipped until `AWS_DEPLOY_ROLE_ARN` is set).
- [x] Pipelines green on GitHub (`047eb7b`); `infra` runs on its first PR.

**Demo:** infra deployed to dev, all pipelines green, `just up` starts the whole stack locally, the
grants test proves the ownership rule. Done so far: everything except the dev deploy.

## M1: Auth + browse destinations

**Status:** Not started. 7 days. Pending revision in the PAS.

### Align contracts and schema with the PAS (M1.0)

- [ ] Settle divergences D1–D11 (see [Divergences](#divergences-between-the-pas-and-m0)): update
  the contracts, migrations, seed, Go routers, envelope, web client, API Gateway route groups and
  shared scenarios, or record why the PAS docs change instead.
- [ ] Decide one schema vs one schema per owner; update ADR-014 and the grants test.

### Migrations (0.5d)

- [ ] users (citext email), teams, team_members, binders, folders, refresh-token store.
- [ ] Index on `folders(binder_id, parent_folder_id)`.
- [ ] Seed: teams in several regions, some with `docbridge_enabled = false`, users in overlapping
  teams, nested folders.

### Auth service (2d)

- [ ] register: argon2id password hashing, unique email.
- [ ] login.
- [ ] refresh: rotates the token and detects reuse (family revocation).
- [ ] token: client credentials issuing a service JWT with `scope` and `token_use: "service"`.
- [ ] `jwks.json` with a `kid`, so keys can rotate; `openid-configuration`.
- [ ] Rate limiting on login and register.

### JWT middleware (0.5d)

- [x] Verifies tokens against the JWKS with a cache; tells user tokens from service tokens; maps
  errors to the envelope (401/403); shared by every service (`internal/jwtverify`, done in M0).
- [ ] Adjust to the envelope chosen in M1.0 if it changes.

### Document platform browse API (1.5d)

- [ ] `GET /teams?docbridgeEnabled=true`.
- [ ] `GET /teams/:id/binders`, 403 to non-members.
- [ ] `GET /binders/:id/contents` and `GET /folders/:id/contents`, one level at a time.
- [ ] Membership resolved through folder → binder → team.

### Frontend (2d)

- [ ] Login and register pages.
- [ ] Token handling with silent refresh.
- [ ] Destination tree that loads each level when expanded.
- [ ] Loading and error states.

### Tests (0.5d)

- [ ] Access matrix: members, non-members, teams with DocBridge disabled.

**Demo:** two users in different teams log in and see different teams. A non-member gets 403 on a
binder.

## M2: Distribute files

**Status:** Not started. 10 days. Pending revision in the PAS. Needs the maximum file size (open
point).

### Migrations (0.5d)

- [ ] jobs, files, tasks, status_events with their CHECK constraints.
- [ ] Partial UNIQUE on `(submitted_by_user_id, idempotency_key)`.
- [ ] Indexes: `tasks(job_id, status)`, `jobs(next_check_at) WHERE completed_at IS NULL`,
  `status_events(job_id, occurred_at)`.

### POST /jobs (1.5d)

- [ ] Validation: at most 100 files, `fileIndex` in range, no duplicate destinations; each folder
  belongs to its binder, each binder to its team, and the team has DocBridge enabled; allowed sizes
  and content types; membership check on every destination team.
- [ ] `Idempotency-Key`: a replay returns 200 with the existing job (decision 6).
- [ ] One transaction inserts the job, files, tasks (pending, region copied from the team) and the
  job-created status event.
- [ ] Upload instructions in the order of `files`: presigned POST with `content-length-range`,
  `Content-Type` and `x-amz-checksum-sha256` for small files; a multipart plan above the threshold.
- [ ] Under 500 ms: presigning is local crypto, inserts are batched.

### POST /files/:id/multipart (0.5d)

- [ ] No body: start the multipart upload. With a body: re-sign the listed parts and return fresh
  `completeUrl`/`abortUrl` (decision 4).
- [ ] Submitter only.

### Client upload (2d)

- [ ] Streaming SHA-256 with hash-wasm (Web Crypto needs the whole file in memory).
- [ ] Form POST for small files, parallel parts for multipart.
- [ ] Retries with backoff; re-signing of expired parts.
- [ ] Progress bar per file.

### Upload handler (0.75d)

- [ ] S3 event → SQS → conditional `pending → uploaded`.
- [ ] Check the arrived size and checksum against the declared ones; on a mismatch set
  `verification_error` and fail the file's tasks.
- [ ] Otherwise send the file's tasks with `SendMessageBatch`.
- [ ] Write a status event.

### Delivery worker + platform ingest (2d)

- [ ] Claim with a conditional `pending → in_progress` and `attempt_count++`, lease per decision 5.
- [ ] Cached service JWT.
- [ ] Ingest per decision 2: idempotent on `source_task_id`, checksum verified by the platform,
  placement by `binder_id`/`folder_id`.
- [ ] Error classification: transient back to pending with backoff, permanent to failed with a
  `failure_reason`.
- [ ] Store `platform_document_id`; set `jobs.completed_at` when the last task resolves.
- [ ] Shared scenarios run by the Go and Python implementations.

### Watchdog + DLQ handler (0.75d)

- [ ] Watchdog scans jobs where `next_check_at <= now()`: re-sends stale `in_progress` tasks; marks
  files past `staging_deadline_at` expired and fails their tasks; re-arms `next_check_at`; HEADs
  pending files at the deadline (ADR-009 backstop).
- [ ] DLQ handler marks tasks failed with actor `dlq`.

### GET /jobs/:id + GET /jobs/:id/tasks (0.5d)

- [ ] Counts and aggregate status.
- [ ] Paginated tasks with a status filter.
- [ ] Visible to the submitter or a member of any destination team; everyone else gets 404.

### Frontend (1.5d)

- [ ] File selection, each file mapped to its destinations through the tree.
- [ ] Submit.
- [ ] Job detail page with manual refresh and a paginated task table.

**Demo:** submit 3 files, one large enough to go multipart. One destination fails because its
platform is configured to fail (`local/faults/`). One file is uploaded with bytes that don't match
its declared checksum and is rejected with `verification_error`. The other tasks complete; the job
ends partially failed, with the reasons shown.

## M3: Live updates + download

**Status:** Not started. 5.5 days. Pending revision in the PAS.

### WebSocket push (2.5d)

- [ ] `$connect` validates the JWT from the query string (short-lived token).
- [ ] `$disconnect` removes the connection.
- [ ] `subscribe` sets `ws_connections.job_id` after the same visibility check as `GET /jobs/:id`;
  `unsubscribe` clears it.
- [ ] Publisher on every status change: look up subscribed connections, `PostToConnection`, delete
  connections that return 410 Gone.

### Frontend live updates (1d)

- [ ] The job page updates task status and counts by itself.
- [ ] After a reconnect, reload with `GET /jobs/:id` to catch missed events.
- [ ] The job is marked complete when everything finishes.

### Download (1d)

- [ ] `POST /files/:id/download-url` returns a presigned GET valid for 120 seconds.
- [ ] Allowed for the submitter or a member of one of the file's destination teams; everyone else
  gets 404.
- [ ] Content disposition `attachment`, except `inline` for safe content types.

### Frontend (0.5d)

- [ ] View and download buttons; View hidden for types that can't be shown inline.

### Tests (0.5d)

- [ ] Download permissions; file bytes never pass through the application servers; WebSocket
  subscription authorization.

**Demo:** the job page updates by itself while tasks run. A teammate downloads the file; an outsider
gets 404.

## M4: Track jobs + manage files

**Status:** Not started. 6 days. Pending revision in the PAS.

### GET /jobs (1d)

- [ ] page/limit pagination in the standard envelope.
- [ ] One aggregate query with `count(*) FILTER (...)` returning the counts and `aggregateStatus`.

### Teammate visibility (0.5d)

- [ ] One shared visibility predicate for every job and file endpoint.
- [ ] Indexes: `tasks(team_id, job_id)`, `team_members(user_id)`.

### Log view (1d)

- [ ] Built on status_events: per task, the timeline, attempts, `failure_reason`, actor and
  `platform_document_id` (`GET /jobs/:id/events`).

### File management (1.5d)

- [ ] Search: trigram index on name, path built with a recursive CTE over folders, limited to what
  the caller can see (Platform API, decision 3).
- [ ] Rename.
- [ ] Delete, with clear rules on who may do it and what happens in S3 and on the platform.

### Frontend (1.5d)

- [ ] Job list with filters.
- [ ] Log view, linked from the job detail page.
- [ ] File search with rename and delete.

### Tests (0.5d)

- [ ] Visibility, log view, search, rename and delete.

**Demo:** active and past jobs; a full log of what was sent, when, by whom and with what result; a
search → rename → delete flow.

## M5: Hardening + E2E verification

**Status:** Not started. 2.5 days. Pending revision in the PAS.

### Load test (0.5d)

- [ ] `POST /jobs` stays under 500 ms at p99 with 100 files and about 2,000 tasks (`tests/load`).

### Resilience tests (0.75d)

- [ ] Duplicate S3 and SQS messages.
- [ ] A worker killed mid-delivery: the watchdog re-sends the task, and `source_task_id` prevents a
  duplicate document.
- [ ] An expired upload.
- [ ] A checksum mismatch.
- [ ] The platform down: tasks retry, then go to the DLQ.
- [ ] Stale WebSocket connections.

### Security (0.25d)

- [ ] JWKS key rotation.
- [ ] Refresh-token reuse detection.
- [ ] Service-token scope enforcement.
- [ ] 404 rather than 403 on every job and file resource.

### Retention + observability (0.5d)

- [ ] Clean up jobs 30 days after `completed_at`.
- [ ] Alarms: DLQ depth, age of the oldest queued message, watchdog re-send rate.
- [ ] Structured logs carrying `jobId`, `taskId` and `fileId`.

### E2E on the deployed system (0.5d)

- [ ] Playwright: register/login → browse → submit (including multipart) → live updates → download
  → search/rename (`tests/e2e`).

**Demo:** the [success metrics](requirements.md#success-metrics) demonstrated on the deployed
system.

## After M5

- [ ] Java implementation of the DocBridge API (`services/api-java`), passing `tests/api-conformance`
  and `tests/e2e`; route groups moved one at a time in `infra/modules/api`.
