# Milestones

## M0: Foundation

| Commit | Scope |
|---|---|
| Monorepo setup | contracts split into common/auth/platform/docbridge; Go binaries auth, platform, api, upload-handler, dlq-handler, watchdog, ws; shared jwtverify, envelope, platform/; store split by owner; Python worker scaffold with an empty handler; web types from openapi-typescript |
| Infrastructure as code | network, database, storage, auth, api, websocket, processing, lambda-function modules; dev and prod envs |
| Local environment | docker-compose with Postgres, LocalStack and two platform containers (one per region) with failure injection; migrations from 000_roles.sql; seed; `just up` |
| CI/CD | one workflow per area, generated-code drift check, grants integration test, deploy to dev on merge |

Demo: infra deployed to dev, all pipelines green, `just up` starts the whole stack locally,
and the grants test proves the ownership rule.
