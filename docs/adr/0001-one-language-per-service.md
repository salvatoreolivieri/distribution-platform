# 1. One language per service, sharing only contracts

Status: accepted

## Context

This is an open project, partly for experimenting with languages. Services written in
different languages must still behave as one system.

## Decision

Each service picks its own language. They share only OpenAPI documents, JSON Schemas and SQL
migrations under `contracts/` and `db/`. Code derived from them is generated and checked in;
CI fails when it drifts.

## Consequences

Adding or replacing a language means implementing a contract and passing the black-box
suites, without touching other services. Every new language adds a toolchain to CI.
