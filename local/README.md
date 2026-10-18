# Local environment

`just up` starts Postgres, LocalStack (S3, SQS, KMS), the auth service, the DocBridge API and
two platform containers, one per region. It applies the migrations, enables the service
roles and loads the seed.

| Service | URL |
|---|---|
| auth | http://localhost:8080 |
| platform (eu) | http://localhost:8081 |
| platform (us) | http://localhost:8082 |
| DocBridge API | http://localhost:8090 |
| Postgres | postgres://migrator:migrator@localhost:5440/docbridge (`POSTGRES_PORT` to change) |
| LocalStack | http://localhost:4566 |

## Failure injection

Each platform container reads `faults/platform-<region>.json`. Rules apply to the ingest API
(`/internal/v1/*`): `error_rate` (0..1), `forced_status`, `latency_ms`, and per-binder
overrides under `binders`. Edit the file and run `docker compose restart platform-eu`.

Seed users all have the password `password`; see `db/seed/seed.sql`.
