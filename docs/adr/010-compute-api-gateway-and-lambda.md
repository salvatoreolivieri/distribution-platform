# ADR-010: Every backend service is a Go Lambda behind API Gateway

**Status:** accepted. Supersedes the internal ALB and VPC Link of [ADR-001](001-route-traffic.md)
and all of [ADR-007](007-backend-compute.md).

Source: PAS-002, "Decisions", row "Stack": "Go services and Lambdas, React web, Terraform,
API Gateway + Lambda. Auth and Platform are two more Go binaries."

## Context

ADR-001 and ADR-007 assumed long-running containers (ECS, then EKS) behind an internal ALB. Then
the queue consumers moved to Lambda ([ADR-006](006-queue-consumer-compute.md)), and the services
turned out to be light on CPU and heavy on short transactions: bytes never pass through them
([ADR-005](005-file-uploads.md)). Running a cluster and an ALB for three small HTTP services, next
to a Lambda tier that needs RDS Proxy anyway, doubles the compute models without a matching
benefit.

## Decision

- `auth`, `platform` and `api` are Go binaries in `services/backend/cmd/`, deployed as Lambdas.
  API Gateway (HTTP API, payload v2) integrates with them directly; there is no VPC Link and no
  ALB.
- The edge from ADR-001 stays: one HTTP API, a JWT authorizer on every route except the ones that
  issue tokens, managed throttling. Route groups map to backends in `infra/modules/api`, so moving
  a group to another implementation (the Java API) is a configuration change.
- The same binaries run as plain HTTP servers outside Lambda (`internal/httpserve`), which is how
  docker compose runs them.
- PostgreSQL is reached through RDS Proxy with IAM authentication, as for the workers.

## Consequences

- One compute model for the whole backend; scale to zero; no cluster to operate.
- No resident process: connection pools live per execution environment, behind RDS Proxy.
- The failure-mode rows that mention ECS (restarts, 2 tasks across AZs) no longer apply; Lambda,
  API Gateway, SQS and S3 are multi-AZ managed services.
- If learning EKS becomes a goal again (ADR-007's motivation), revisit this record: the binaries
  already run as HTTP servers and only the infrastructure would change.
