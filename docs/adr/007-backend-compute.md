# ADR-007: Compute for the backend services

**Status:** superseded by [ADR-010](010-compute-api-gateway-and-lambda.md). Kept for its
reasoning: the modular-monolith arguments still apply to the second, Java implementation of the
DocBridge API.

## Decision required

What compute runs the backend service, and how is it deployed: one modular monolith on EKS, one
modular monolith on ECS Fargate, or separate ECS services (microservices)?

## Context

The backend service is DocBridge's synchronous core, in the private VPC behind the internal ALB.
The SPA reaches it only through the API Gateway HTTP API: the JWT authorizer checks the token,
then the request goes over the VPC Link to the ALB. It handles:

- **Job creation:** validates the request, writes the job, its files and tasks to PostgreSQL, and
  starts the watchdog's deadline.
- **Upload and download:** hands out presigned POST and GET URLs. Bytes go straight between the
  client and S3, so the service never streams files.
- **Status and history reads:** job and task state written by the Lambdas; the fallback when a
  WebSocket push is missed.
- **Search, edit and delete documents.**

## Alternatives evaluated

### 1. Modular monolith on EKS: one Deployment, internal service-oriented modules

- \+ One build, one pipeline, one artifact; modules talk in-process, with no network latency or
  partial failures between them.
- \+ Boundaries enforced in code (module APIs, no shared internals, one schema per module), so a
  module can be extracted later if it must scale alone.
- \+ Local transactions across modules; no sagas or outbox.
- \+ The company's standard EKS platform: shared ingress, observability, secrets, CIS-aligned
  hardening, GitOps.
- \+ HPA on CPU or request rate absorbs bursts; pods hold persistent connection pools.
- − The EKS control plane costs money and adds operational surface (upgrades, add-ons), though both
  are shared if the cluster already exists.
- − All modules scale and deploy together; one bad module can affect the whole process.
- − Module boundaries erode unless lint or architecture tests enforce them.

### 2. Modular monolith on ECS Fargate: one ECS service

- \+ The same monolith benefits as option 1.
- \+ Simplest compute: no cluster, no nodes.
- − Outside the company's Kubernetes platform, so ingress, observability and policy tooling must be
  set up again.
- − Autoscaling and deployment features are more limited than Kubernetes (HPA, PDBs, progressive
  rollouts).

### 3. Microservices: one ECS Fargate service per domain

- \+ Each service scales and deploys on its own.
- \+ Faults stay inside one service.
- − N pipelines, task definitions and alarm sets for a team and load that don't need them.
- − Calls between services cross the network: latency, retries, timeouts, circuit breakers.
- − Cross-service consistency needs sagas or an outbox; contracts need versioning.
- − Each service keeps its own connection pool, multiplying PostgreSQL connections.
- − Splits services before the real scaling seams are known.

## Decision (at the time)

Option 1: one modular monolith on EKS, behind the internal ALB, split into modules: jobs, uploads
(presigned URLs), status, destinations. Bytes go to S3 and async work runs on Lambda, so the service
is light on CPU and heavy on transactions, which favours in-process modules and local transactions.
EKS over ECS because it is the company standard (and to learn it).

Later replaced by ADR-010: every backend service is a Go Lambda behind API Gateway.
