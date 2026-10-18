# 4. Table ownership enforced by database roles

Status: accepted

## Decision

Each service owns a Postgres schema (`auth`, `platform`, `docbridge`) and connects with its
own role (`auth_svc`, `platform_svc`, `docbridge_svc`, `worker_svc`), each with its own
secret. A role can write only the tables its service owns; the worker can update only the
task columns it needs. An integration test asserts that every other write fails.

## Consequences

Services share one RDS instance without being able to corrupt each other's data. Cross-service
reads go through APIs, or through explicit read grants.
