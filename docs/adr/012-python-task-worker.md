# ADR-012: The task worker is written in Python

**Status:** accepted. Replaces the Java worker named in the PAS (Technical Design and the
"Stack" decision).

## Decision

The delivery worker is Python 3.13, ports and adapters, no framework, packaged as a Lambda zip with
SnapStart. Layer boundaries, which Gradle subprojects would have enforced in Java, are enforced by
import-linter contracts in CI:

- layers: `bootstrap → adapters → application → domain`;
- `domain` and `application` may not import psycopg, boto3, botocore, httpx or pydantic;
- `domain` imports nothing else from the worker.

Pyright runs in strict mode, so every `match` on a closed union (`DeliveryError`, `Outcome`)
must handle all cases.

## Consequences

Java remains for the second DocBridge API implementation. The `lambda-function` Terraform module
supports Go, Python and Java runtimes. Python SnapStart needs work at import time (wiring, clients)
and a reconnect after restore for anything holding a connection.
