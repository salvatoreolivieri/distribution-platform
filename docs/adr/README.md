# Architecture decision records

One file per decision, numbered in the order taken. ADR-001 to ADR-009 come from DocBridge PAS-002;
ADR-010 onwards were recorded while building. A record is never rewritten once accepted: a new
record supersedes it, and the old one says so in its status line.

| ADR | Decision | Status |
|---|---|---|
| [001](001-route-traffic.md) | API Gateway HTTP API as the public edge, JWT authorizer | Accepted; internal ALB superseded by 010 |
| [002](002-async-processing.md) | SQS decouples task submission from processing | Accepted |
| [003](003-deployment-and-configuration.md) | Automated deployments; configuration and secrets injected at runtime | Accepted |
| [004](004-status-updates.md) | Live updates through the API Gateway WebSocket API | Accepted |
| [005](005-file-uploads.md) | Presigned POST uploads and presigned GET downloads | Accepted |
| [006](006-queue-consumer-compute.md) | Queue consumers on Lambda, RDS Proxy in front of Postgres | Accepted |
| [007](007-backend-compute.md) | Backend as a modular monolith on EKS | Superseded by 010 |
| [008](008-worker-authentication.md) | Workers authenticate with service tokens from the auth service | Accepted |
| [009](009-file-arrival-detection.md) | S3 ObjectCreated → upload-events queue → fan-out worker; watchdog as backstop | Accepted |
| [010](010-compute-api-gateway-and-lambda.md) | Every backend service is a Go Lambda behind API Gateway | Accepted |
| [011](011-one-language-per-service.md) | One language per service, sharing only contracts | Accepted |
| [012](012-python-task-worker.md) | The task worker is written in Python | Accepted |
| [013](013-own-token-issuer.md) | Our own token issuer, signing with KMS | Accepted |
| [014](014-table-ownership.md) | Table ownership enforced by database roles | Accepted, one open point |

Smaller decisions taken after the design (refresh tokens, pull-based ingest, the files/documents
split, multipart checksums, task lease, idempotency key) are in
[milestones.md](../milestones.md#decisions-after-the-design). Promote one to an ADR when it needs
alternatives written down.

## Notes on the source

- The PAS titles ADR-003 "Failed Task Handling (DLQ & Scheduler)", but its content is about
  deployment and configuration; it is titled by its content here.
- Some cross-references in the PAS point to numbers from an earlier draft (ADR-011, ADR-013,
  ADR-016, ADR-017, and ADR-008 for the watchdog). They were resolved by meaning when these records
  were written; they do not refer to ADR-011 to ADR-014 above.

## Template

```markdown
# ADR-NNN: <decision, as a statement>

**Status:** proposed | accepted | superseded by ADR-NNN.

## Decision required
## Context
## Alternatives evaluated
## Decision
## Consequences
```
