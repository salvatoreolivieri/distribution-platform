# DocBridge distribution platform

Upload files once and deliver each of them to several binders and folders on the document
platform, across regions, and track every delivery.

It is also an open project for trying out languages side by side. Every service is deployed
on its own, and the languages share only language-neutral contracts:

| Part | Language | Where |
|---|---|---|
| Web app | TypeScript, React + Vite | `web/` |
| Auth, platform, DocBridge API, small Lambdas | Go | `services/backend/` |
| Task worker | Python 3.13 | `services/task-worker/` |
| DocBridge API, second implementation (after M5) | Java | `services/api-java/` |
| Infrastructure | Terraform | `infra/` |

## Layout

```
contracts/      OpenAPI (common, auth, platform, docbridge) and event JSON Schemas
db/             dbmate migrations and seed data
web/            React app; API types generated with openapi-typescript
services/
  backend/      Go module: cmd/{auth,platform,api,upload-handler,dlq-handler,watchdog,ws}
  task-worker/  Python, ports and adapters, Lambda + SnapStart
infra/          Terraform: bootstrap, modules, envs/{dev,prod}
tests/          e2e, api-conformance, load, shared-scenarios
docs/           architecture, ADRs, milestones
```

## Getting started

Requirements: Go, Node 22+, [uv](https://docs.astral.sh/uv/), [just](https://just.systems),
Docker, Terraform 1.10+, dbmate.

```bash
just gen     # regenerate code from contracts/
just lint
just test
just build   # web app + dist/*.zip Lambda artifacts
```

## Rules that hold the structure together

1. **Contracts first.** `contracts/openapi/`, `contracts/events/` and `db/migrations/` are the
   only things the languages share. Derived code is generated with `just gen`, and CI fails
   when it is out of date.
2. **Boundaries enforced by tooling.** Go `internal/` packages; import-linter layer contracts
   for the Python worker; Gradle subprojects and ArchUnit for Java; one Postgres role per
   service, so a service cannot write tables it does not own.
3. **The same tests for every implementation.** `tests/api-conformance` and `tests/e2e` are
   black-box.
4. **Shared rules written once, as data.** `tests/shared-scenarios/` is run by every
   implementation of the task transitions.
5. **Language-neutral infrastructure.** One `lambda-function` Terraform module for Go,
   Python and Java; `just build` produces the artifacts Terraform deploys.
6. **Route by route.** Each API Gateway route group points at its backend independently.
