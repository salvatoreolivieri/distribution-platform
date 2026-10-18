#!/usr/bin/env bash
# Builds every Lambda artifact into dist/<name>.zip. Terraform references these paths.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
mkdir -p "$dist"

# Go: one zip per binary, each containing a `bootstrap` executable for provided.al2023 on arm64.
for cmd in "$root"/services/backend/cmd/*/; do
  name="$(basename "$cmd")"
  out="$(mktemp -d)"
  (cd "$root/services/backend" && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
    go build -trimpath -tags lambda.norpc -ldflags="-s -w" -o "$out/bootstrap" "./cmd/$name")
  (cd "$out" && zip -q -X "$dist/$name.zip" bootstrap)
  rm -rf "$out"
  echo "built dist/$name.zip"
done

# Python worker: the package plus its runtime dependencies, as wheels for Lambda's arm64 Linux.
out="$(mktemp -d)"
(cd "$root/services/task-worker" &&
  uv export --frozen --no-dev --no-emit-project --format requirements-txt > "$out/requirements.txt" &&
  uv pip install --quiet --target "$out/pkg" --python-platform aarch64-manylinux2014 \
    --python-version 3.13 --only-binary :all: -r "$out/requirements.txt" &&
  cp -R src/task_worker "$out/pkg/")
(cd "$out/pkg" && find . -name '__pycache__' -prune -exec rm -rf {} + && zip -q -r -X "$dist/task-worker.zip" .)
rm -rf "$out"
echo "built dist/task-worker.zip"
