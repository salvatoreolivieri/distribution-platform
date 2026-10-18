# Technical design

A monorepo of independently deployed services, each in a language chosen to try that language
out ([ADR-011](../adr/011-one-language-per-service.md)):

- **TypeScript** for the frontend (React + Vite).
- **Go** for the auth, platform and DocBridge API services and the small Lambdas.
- **Python** for the task worker: ports and adapters, no framework ([ADR-012](../adr/012-python-task-worker.md)).
- **Java** for a second implementation of the DocBridge API, after M5.
- **Terraform** for the infrastructure.

The languages share only language-neutral contracts: OpenAPI, JSON Schema and SQL migrations.

## Layout

```
contracts/
  openapi/              common (envelope, pagination, errors), auth, platform, docbridge
  events/               task-message.schema.json, s3-upload-event.md
db/
  migrations/           dbmate; 000_roles.sql first (roles, schemas, grants)
  seed/                 teams, nested folders, mixed grants
web/                    React + Vite; src/api/generated from openapi-typescript (never edited)
services/
  backend/              Go module
    cmd/                auth, platform, api, upload-handler, dlq-handler, watchdog, ws
    internal/
      jwtverify/        JWKS cache, user vs service tokens, envelope errors
      envelope/         response bodies from common.yaml
      httpserve/        same handler as Lambda (API Gateway v2) or plain HTTP
      platform/         config, logging, AWS clients
      auth/ platformsvc/ httpapi/        one package per HTTP service
      access/ destinations/ jobs/ files/ DocBridge domain packages
      uploads/ dlq/ watchdog/ ws/        Lambda handlers
      contracts/        oapi-codegen output (never edited)
      store/{auth,platform,docbridge}/   sqlc output per owner + grants_test.go
  task-worker/          Python 3.13, uv
    src/task_worker/{domain,application,adapters,contracts,bootstrap}
  api-java/             after M5: Java modular monolith, same contract
infra/
  bootstrap/            state bucket, GitHub OIDC deploy role (applied once, by hand)
  modules/              network, database, storage, auth, api, websocket, processing, lambda-function
  envs/dev, envs/prod   prod links dev's main.tf; differs in tfvars and backend only
tests/
  e2e/ api-conformance/ load/ shared-scenarios/
local/                  LocalStack init, failure-injection configs, local README
scripts/                build-lambdas.sh, db-role-passwords.sh
docs/                   this folder
```

## Rules that hold the structure together

1. **Contracts first.** `contracts/openapi/`, `contracts/events/` and `db/migrations/` are the only
   things the languages share. Derived code is generated with `just gen`: oapi-codegen and sqlc for
   Go, openapi-typescript for the web, datamodel-codegen for Python. CI fails if generated code is
   out of date.
2. **Boundaries enforced by tooling, not by convention.**
   - Go: `internal/` packages, so the binaries in `cmd/` cannot import each other.
   - Python: import-linter contracts in CI (layers `bootstrap → adapters → application → domain`;
     `domain` and `application` cannot import psycopg, boto3 or httpx). Pyright strict checks that
     every `match` on a closed union handles all its cases.
   - Java: Gradle subprojects, so the compiler rejects imports in the wrong direction; ArchUnit for
     what the compiler cannot check.
   - Database: one role per service; the grants test fails if a role can write a table it does not
     own.
3. **The same tests for every implementation.** `tests/api-conformance` and `tests/e2e` are
   black-box. The Java API is done when it passes the same suite as the Go API.
4. **Shared rules written once, as data.** The task transition scenarios in
   `tests/shared-scenarios/` run in every implementation that changes task status.
5. **Language-neutral infrastructure.** Terraform modules describe what exists; `envs/` supplies
   the values. One `lambda-function` module covers Go, Python and Java. `just build` produces the
   artifacts Terraform deploys.
6. **Route by route.** In `infra/modules/api` each route group points at its backend independently,
   so moving an endpoint to another implementation is a configuration change.
