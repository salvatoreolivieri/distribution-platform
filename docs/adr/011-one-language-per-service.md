# ADR-011: One language per service, sharing only contracts

**Status:** accepted.

## Context

This is an open project, partly for experimenting with languages. Services written in different
languages must still behave as one system.

## Decision

Each service picks its own language: TypeScript for the web app, Go for the API services and small
Lambdas, Python for the task worker ([ADR-012](012-python-task-worker.md)), Java for a second
implementation of the DocBridge API after M5, Terraform for infrastructure.

They share only language-neutral contracts: OpenAPI documents (`contracts/openapi/`), JSON Schemas
(`contracts/events/`) and SQL migrations (`db/migrations/`). Code derived from them is generated
with `just gen` and committed; CI fails when it drifts.

## Consequences

- Adding or replacing an implementation means implementing a contract and passing the black-box
  suites (`tests/api-conformance`, `tests/e2e`), without touching other services.
- Rules shared by several implementations are written once, as data
  (`tests/shared-scenarios/task-transitions.json`).
- Every language adds a toolchain to CI and to the developer setup.
