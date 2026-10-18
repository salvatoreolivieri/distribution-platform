# ADR-003: Deployment automation and runtime configuration

**Status:** accepted.

The PAS titles this record "Failed Task Handling (DLQ & Scheduler)", but its content decides
deployment and configuration; it is titled by its content here. Failed-task handling is decided in
[ADR-002](002-async-processing.md), [ADR-009](009-file-arrival-detection.md) and decision 5
(task lease) in [milestones.md](../milestones.md#decisions-after-the-design).

## Decision required

What baseline do we adopt for deployment automation and for runtime configuration and secrets?

## Context

DocBridge is a cloud application: web frontend, APIs, background workers, storage and queues. It
runs in several environments (for example staging and production) and integrates with external
systems. We want to minimise operational risk and manual work by standardising how the system is
deployed and configured, especially secrets and environment-specific values.

## Alternatives evaluated

### 1. Partially manual deployments and inline configuration

- \+ Fast to start: console changes, config files.
- \+ Little tooling up front.
- − Environments are hard to reproduce and roll back safely.
- − High risk of leaking secrets in code or config files.

### 2. Automated deployments, environment-based configuration and a secrets manager (chosen)

- \+ IaC plus CI/CD give repeatable, auditable deployments with minimal manual steps.
- − Needs an initial investment in pipelines and IaC.
- − Engineers must understand and maintain the deployment and configuration tooling.

### 3. One shared environment with global configuration

- \+ Simple at first: one environment to manage.
- − Unsuitable for regulated or enterprise settings: no staging or sandbox.

## Decision

Option 2. DocBridge is deployed by automated pipelines on infrastructure-as-code. No manual changes
in production beyond the initial cloud account and credentials setup.

All runtime configuration (database URLs, AWS credentials and roles, service endpoints, feature
flags) is injected through environment variables or a managed secrets/configuration service. No
secrets or environment-specific values in code, Docker images or plain-text config in source
control.
