# DocBridge distribution platform

Upload files once and deliver each one to many binders and folders on the document platform,
across regions, tracking every delivery. An open project that also tries out languages side by
side: Go services and Lambdas, a Python task worker, a React web app, Java later, Terraform.

## Read first

| What | Where |
|---|---|
| What must be built and how well | [docs/requirements.md](docs/requirements.md) |
| Why, for whom, the user flows | [docs/blueprint.md](docs/blueprint.md) |
| How it is built | [docs/architecture/](docs/architecture/README.md) |
| Why it is built that way | [docs/adr/](docs/adr/README.md) |
| What to do next, and who is doing it | [docs/milestones.md](docs/milestones.md) |

The design comes from DocBridge PAS-002. Where the code and the docs disagree, check
[Divergences](docs/milestones.md#divergences-between-the-pas-and-m0) before picking a side.

## Working on a milestone

1. Open [docs/milestones.md](docs/milestones.md). Pick the next unticked item of the current
   milestone, unless you were given one.
2. Mark it `(in progress: <your branch or session>)` and set the milestone to `In progress`, so
   parallel agents don't take the same item.
3. Read the ADRs and architecture pages the item touches. If the item contradicts them, stop and
   ask; don't quietly diverge.
4. Do the work, test first where it fits.
5. Run the [checks](#checks-before-every-commit). All must pass.
6. Tick the item **in the same commit as the work**, with a one-line note if anything differs from
   the plan (a changed route, a follow-up, a moved item). Update the milestone's status line when
   it changes.
7. New decision? Add it to "Decisions after the design" in the milestones file, or write an ADR if
   alternatives were weighed. Never rewrite an accepted ADR: supersede it.

Never delete an unfinished item to make a milestone look done: move it, and say where it went.

## Checks before every commit

Run them for every change, and report the result honestly. Never commit red, and never skip,
disable or loosen a test, lint rule, type check or grants assertion to get green: fix the cause or
stop and say what is failing.

| Changed | Run |
|---|---|
| Anything | `just check` (= `just gen`, `just lint`, `just test`) |
| `contracts/` or `db/migrations/` | after `just gen`, `git status` shows the regenerated files; commit them with the change |
| `db/` (migrations, seed, grants) | `just up`, then `just test-integration` (the grants test) |
| `infra/` | `just tf-check`; also `tflint` and `checkov` if installed (CI runs both) |
| `docker-compose.yml`, `local/` | `just down -v && just up`, then hit `/healthz` on every service |
| Docs only | check links and that Mermaid blocks still render (GitHub preview) |

CI runs the same checks per area (`.github/workflows/`) plus the drift check: `just gen` must
leave no diff.

## Commands

```bash
just up                # whole local stack: Postgres, LocalStack, auth, api, platform eu + us
just down -v           # stop it and drop the data
just gen               # regenerate code from contracts/ and db/migrations/
just check             # gen + lint + test: the gate before every commit
just test-integration  # grants test against the local database (needs `just up`)
just build             # web app + dist/*.zip Lambda artifacts
just tf-check          # terraform fmt + validate for every root
```

Local ports: auth 8080, platform eu 8081 / us 8082, api 8090, LocalStack 4566, Postgres 5440
(`POSTGRES_PORT` overrides it). See [local/README.md](local/README.md).

## Rules that hold the structure together

- **Contracts first.** Change `contracts/openapi/*.yaml`, `contracts/events/*.json` or
  `db/migrations/*.sql` first, run `just gen`, then write the code against the generated types.
- **Never edit generated code:** `services/backend/internal/contracts/*/*.gen.go`,
  `services/backend/internal/store/*/{db,models,queries.sql}.go`, `web/src/api/generated/`,
  `services/task-worker/src/task_worker/contracts/task_message.py`.
- **Boundaries are enforced by tooling.** Go `internal/` packages; import-linter layers in the
  worker; one Postgres role per service. If a boundary blocks you, the design needs a change:
  discuss it, don't route around it.
- **The same tests for every implementation.** Rules shared by several implementations live once,
  as data, in `tests/shared-scenarios/`.

## Database

- Plain SQL with dbmate: `-- migrate:up` and `-- migrate:down`, and the down must work (CI runs
  up → down → up). Never edit a migration once it is on `main`; add a new one.
- Every new table gets its owner's grants in the migration that creates it
  ([ADR-014](docs/adr/014-table-ownership.md)). The grants test finds new tables on its own and
  fails if a role can write something it does not own. Cross-service writes go through the owning
  service's HTTP API.
- Queries live in `services/backend/internal/store/<owner>/queries.sql` (sqlc).
- Seed data is idempotent (`ON CONFLICT DO NOTHING`) and uses fixed UUIDs.

## Go (`services/backend`)

- Every HTTP response goes through `internal/envelope`; every protected route through
  `internal/jwtverify` (`Middleware`, `RequireKind`, `RequireScope`).
- Handlers stay `http.Handler`; `internal/httpserve` runs them in Lambda or as plain HTTP. Don't
  import Lambda types into service packages.
- Configuration comes from the environment through `internal/platform/config`; required settings
  use `Required`, so a binary reports every missing one at start.
- `gofmt` clean, `go vet` clean, table-driven tests, `-race` in CI.

## Python (`services/task-worker`)

- `domain` uses only the standard library; `application` imports only `domain`; adapters implement
  the ports in `application/ports.py`; `bootstrap` wires everything at import time (SnapStart
  captures it).
- Closed unions (`DeliveryError`, `Outcome`) are handled with `match` and `assert_never`; pyright
  strict must stay clean.
- Run tools through uv: `uv run --frozen <tool>`. Dependencies change only with `uv add`, which
  updates `uv.lock`.

## TypeScript (`web`)

- Strict mode; no `any`. API types come only from `src/api/generated`; requests go through
  `src/api/client.ts`.
- Code goes in `src/features/<feature>/`; shared UI in `src/components/`.
- Heavy work (hashing) runs in a web worker; the UI never blocks.

## Terraform (`infra`)

- Modules hold no environment values; `envs/<env>/terraform.tfvars` does. `envs/prod` links
  dev's `main.tf`, `variables.tf` and `outputs.tf`: change the composition once.
- A new Lambda goes through `modules/lambda-function` with its own least-privilege policy.
- A skipped checkov check needs a reason in `infra/.checkov.yaml`.
- Never run `apply` or `destroy` against a real account without explicit approval in the
  conversation.

## Secrets and security

- No secrets, keys or tokens in code, images or committed config. Runtime secrets come from Secrets
  Manager or the environment.
- Local test values (seed passwords, `local-worker-secret`, `*_local` role passwords, LocalStack
  `test` credentials) exist only for the local stack; never reuse them anywhere else.
- Return 404, not 403, for jobs and files the caller cannot see.

## Comments

Default to none. Write one line only when the why is not obvious from the code: a hidden
constraint, an invariant, a workaround. No comments that restate the code, no banners, no task
narration or "we chose X over Y" essays: decisions go in ADRs, task context in commit messages.

## Commits

- One logical change per commit, with its regenerated code, tests, and the milestones update.
- Subject in the imperative, under about 70 characters; the body says why.
- Don't commit or push unless asked. Never force-push `main`.

## Toolchain gotchas

- **Go 1.27** (from `go.mod`), **Node 24**, **Python 3.13** through uv, **Terraform 1.16.6** pinned in
  `.terraform-version` (tfenv picks it up).
- **TypeScript stays on 5.x:** openapi-typescript 7 crashes with TypeScript 7.
- **sqlc 1.31.1:** the version is written into the generated files, so another version makes the
  drift check fail. CI pins it.
- `just gen` regenerates the Python model with `--formatters builtin`; other formatters produce a
  diff in CI.
- Docker must be running for `just up` and `just test-integration`.

## Working in parallel

- Split work along milestone items that touch different files; two agents never edit the same
  files at once.
- Claim the item in `docs/milestones.md` before starting, and keep each session on its own branch.
- Contract and migration changes go first and alone: other work builds on the generated code.
