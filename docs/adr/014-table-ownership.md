# ADR-014: Table ownership enforced by database roles

**Status:** accepted. Implements decision A2.

## Decision

One database. Every table has exactly one writer service; writes to another service's tables go
through that service's HTTP API. Each service connects with its own Postgres role, which has write
grants only on the tables it owns:

| Owner | Role | Tables |
|---|---|---|
| Auth | `auth_svc` | users, refresh_tokens, service_clients |
| Platform | `platform_svc` | teams, team_members, binders, folders, documents |
| DocBridge | `docbridge_svc` | jobs, files, tasks, status_events, ws_connections |
| Task worker | `worker_svc` | none owned; column-level `UPDATE` on tasks and `INSERT` on status_events |

Roles and grants come from `db/migrations/000_roles.sql` and the grants in each later migration.
`services/backend/internal/store/grants_test.go` asserts the rule in CI: every role's `INSERT`,
`UPDATE` and `DELETE` against a table it does not own must fail.

## Open point

Decision A2 says "one schema; any service may read any table". M0 implemented one schema per owner
(`auth`, `platform`, `docbridge`) with explicit read grants, and put teams and team_members in
`auth` instead of `platform`. Settle this at the start of M1 (see
[milestones.md](../milestones.md#divergences-between-the-pas-and-m0)): either amend this record to
schemas-per-owner, or collapse to one schema. The grants test enforces whichever is chosen.

## Consequences

Services share one RDS instance without being able to corrupt each other's data. Every new table
must be given an owner in the migration that creates it, and the grants test learns about it
automatically (it fails on a table in a schema with no owning role).
