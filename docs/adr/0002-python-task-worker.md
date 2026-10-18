# 2. The task worker is written in Python

Status: accepted (replaces the Java/Gradle worker in the technical design)

## Decision

The worker is Python 3.13 with ports and adapters and no framework, packaged as a Lambda zip
with SnapStart. Layer boundaries, which Gradle subprojects enforced in the Java design, are
enforced with import-linter contracts run in CI; pyright runs in strict mode.

## Consequences

Java remains for the second DocBridge API implementation after M5. The `lambda-function`
module supports Go, Python and Java runtimes.
