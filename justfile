# DocBridge monorepo tasks. `just` lists them.

set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Regenerate all code derived from contracts/ (CI fails if the result differs from git)
gen:
    cd services/backend && sqlc generate && go generate ./...
    cd web && npm run -s gen
    cd services/task-worker && uv run --frozen datamodel-codegen \
        --input ../../contracts/events/task-message.schema.json --input-file-type jsonschema \
        --output src/task_worker/contracts/task_message.py \
        --output-model-type pydantic_v2.BaseModel --target-python-version 3.13 \
        --use-standard-collections --disable-timestamp --formatters builtin

# Start the whole local stack, apply migrations and load the seed
up:
    docker compose up -d --build --wait
    just seed
    @echo "auth :8080  api :8090  platform eu :8081 us :8082  (see local/README.md)"

# Stop the local stack (add `-v` to drop the database volume)
down *args:
    docker compose down {{args}}

# Load db/seed into the local database (idempotent)
seed:
    docker compose exec -T postgres psql -U migrator -d docbridge -v ON_ERROR_STOP=1 -q < db/seed/seed.sql

# Apply pending migrations to the local database
migrate:
    docker compose run --rm migrate --wait up

# Build the web app and every Lambda artifact into dist/
build:
    cd web && npm run -s build
    ./scripts/build-lambdas.sh

# Unit tests for every service
test:
    cd services/backend && go test ./...
    cd services/task-worker && uv run --frozen pytest
    cd web && npm test

# Integration tests against the local stack (`just up` first): the grants test
test-integration:
    cd services/backend && go test -tags integration -count=1 ./internal/store/

# Linters and type checkers for every service
lint:
    cd services/backend && test -z "$(gofmt -l .)" && go vet ./...
    cd services/task-worker && uv run --frozen ruff check . && uv run --frozen ruff format --check . \
        && uv run --frozen pyright && uv run --frozen lint-imports
    cd web && npm run -s lint

# Format and validate every Terraform root
tf-check:
    terraform fmt -check -recursive infra
    for d in infra/bootstrap infra/envs/dev infra/envs/prod; do \
        terraform -chdir=$d init -backend=false -input=false >/dev/null && terraform -chdir=$d validate; \
    done

# Plan an environment (needs AWS credentials and `just build` artifacts): just tf-plan dev
tf-plan env="dev":
    terraform -chdir=infra/envs/{{env}} init -input=false
    terraform -chdir=infra/envs/{{env}} plan -input=false -out=tfplan
