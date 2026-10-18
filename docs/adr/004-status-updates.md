# ADR-004: Task and job status updates

**Status:** accepted.

## Decision required

How does the browser receive task and job status updates while a job runs?

## Context

A job fans out into up to 2,000 tasks that resolve over seconds to minutes. Statuses must "update
automatically as work progresses"; the mechanism is ours to choose. The job dashboard is the core
screen, so update latency is visible quality. Scale is modest: up to 200 concurrent users, each
usually watching one job.

## Alternatives evaluated

### 1. Short polling (refetch job status every 2–3 seconds)

- \+ Simplest: one existing endpoint, no connection state anywhere.
- \+ Works through the existing edge unchanged.
- \+ At 200 concurrent users, about 70 req/s of cheap indexed reads; load is a non-issue.
- − Updates lag by up to the polling interval; the dashboard feels stepped, not live.
- − Most requests return nothing new: the chattiest option per unit of information.

### 2. Server-Sent Events (SSE)

- \+ Natural fit: a strictly one-way, server-to-client stream.
- \+ Native browser support with automatic reconnect and `Last-Event-ID` resume.
- \+ Little client and server code.
- − Incompatible with our edge: API Gateway HTTP API buffers responses and caps connections at 30 s,
  so SSE needs a second, public ingress (a public ALB) that bypasses the gateway.
- − That second ingress breaks the [ADR-001](001-route-traffic.md) posture (no public service
  exposure, JWT enforced at one edge) and splits auth enforcement across two paths.

### 3. WebSockets through the API Gateway WebSocket API (chosen)

- \+ A managed edge built for persistent connections; services stay private, consistent with
  ADR-001.
- \+ True push: status changes reach the dashboard in near real time.
- \+ Auth on connect, managed connection lifecycle, push through the post-to-connection API; no
  sockets terminated on our compute.
- − Bidirectional machinery for a one-way need.
- − Needs a connection registry (which user and job each connection watches) and push plumbing from
  the status-update path to the gateway.
- − A second gateway to configure and monitor.
- − The client handles reconnects and catching up on missed updates itself.

## Decision

Option 3. At this scale all three work; the choice is driven by architectural consistency and
product quality. The WebSocket API delivers real-time push while every service stays private and
every client entry point stays managed at the edge.
