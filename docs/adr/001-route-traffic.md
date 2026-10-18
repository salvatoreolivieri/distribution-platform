# ADR-001: Route public traffic

**Status:** accepted. The edge (API Gateway HTTP API with a JWT authorizer) stands; the internal
ALB and VPC Link behind it are superseded by [ADR-010](010-compute-api-gateway-and-lambda.md).

## Decision required

How do we route public API traffic from the internet to our internal services?

## Context

DocBridge exposes an HTTP API used by a browser SPA. Behind it sit several services (auth service,
DocBridge API, document platform), with more likely later. Every endpoint must reject
unauthenticated requests. At the time of this decision, services ran as containers on ECS inside
a VPC.

## Alternatives evaluated

### 1. Single public ALB, path/host rules to one target group per service

- \+ Simplest correct setup: one routing layer to configure and debug.
- \+ Native fit for ECS: target groups, health checks, per-service scaling.
- \+ Cheapest at our traffic level.
- − Services sit behind a public entry point; no network boundary between the internet and the ALB.
- − JWT validation happens inside each service; no rejection at the edge.
- − No managed throttling; rate limiting must be built in the application.

### 2. API Gateway (HTTP API) as public edge → VPC Link → internal ALB → services (chosen)

- \+ JWTs validated at the edge by a native JWT authorizer; invalid traffic never enters the
  private network.
- \+ Managed throttling at the edge.
- \+ Services and ALB live entirely in private subnets with zero public exposure.
- − Two routing layers make debugging harder.
- − VPC Link and authorizer add configuration surface.
- − Extra per-request cost over an ALB alone.

### 3. API Gateway only, direct integrations to services

- \+ One managed edge with auth and throttling.
- \+ No ALB to run.
- − HTTP API still needs a VPC Link and a load balancer or Cloud Map to reach ECS.
- − Loses ALB-style per-service target groups and health-check-driven routing.

## Decision

Option 2: API Gateway (HTTP API) as the public edge, internal ALB for service routing.

- Unauthenticated traffic is rejected before it enters the VPC, services have no public exposure,
  and the design exercises both edge security and load balancing, an explicit goal of this
  project. HTTP API (not REST API) because it has a native JWT authorizer and VPC Link at roughly a
  third of the REST API cost.
- Login and registration routes have no JWT authorizer, since they issue the tokens.
- Rollout: deploy the services and the internal ALB first and verify them from inside the VPC, then
  add API Gateway and the JWT authorizer in front, so the layering is understood rather than
  inherited.
