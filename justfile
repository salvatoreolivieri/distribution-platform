# DocBridge monorepo tasks. `just` lists them.

set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Regenerate all code derived from contracts/ (CI fails if the result differs from git)
gen:
    cd services/backend && go generate ./...
    cd web && npm run -s gen
    cd services/task-worker && uv run --frozen datamodel-codegen \
        --input ../../contracts/events/task-message.schema.json --input-file-type jsonschema \
        --output src/task_worker/contracts/task_message.py \
        --output-model-type pydantic_v2.BaseModel --target-python-version 3.13 \
        --use-standard-collections --disable-timestamp --formatters builtin

# Build the web app and every Lambda artifact into dist/
build:
    cd web && npm run -s build
    ./scripts/build-lambdas.sh

# Unit tests for every service
test:
    cd services/backend && go test ./...
    cd services/task-worker && uv run --frozen pytest
    cd web && npm test

# Linters and type checkers for every service
lint:
    cd services/backend && test -z "$(gofmt -l .)" && go vet ./...
    cd services/task-worker && uv run --frozen ruff check . && uv run --frozen ruff format --check . \
        && uv run --frozen pyright && uv run --frozen lint-imports
    cd web && npm run -s lint
