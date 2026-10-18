# ADR-008: Worker authentication to the document platform

**Status:** accepted.

## Decision required

How do delivery workers authenticate to the document platform API?

## Context

Delivery workers call the platform's ingest endpoint. Every platform endpoint must reject
unauthenticated requests. On the read path DocBridge forwards the end user's JWT, but workers run
asynchronously, possibly minutes after submission: the user's 15-minute token may have expired, and
holding user tokens in queue messages would spread bearer credentials through SQS, logs and
retries. Workers need their own identity, while the platform still verifies that the submitting
user is authorized at the destination (the `onBehalfOf` check at time of use).

## Alternatives evaluated

### 1. Service token from the auth service (client credentials) (chosen)

The worker exchanges its own credential for a short-lived service JWT; requests carry the service
JWT plus an `onBehalfOf` user id.

- \+ One auth mechanism system-wide: the platform validates every caller, user or service, against
  the same JWKS through one middleware.
- \+ Clear separation: the service token proves "this is the delivery worker", `onBehalfOf` names the
  user, and the platform re-checks that user's membership at ingest.
- − The auth service becomes a runtime dependency of delivery; if it is down, deliveries fail
  (handled by the transient retry and DLQ path).
- − The worker credential must be stored (Secrets Manager) and rotated.
- − A few days of work: token endpoint, scope validation, token caching across warm invocations.

### 2. IAM-signed requests (SigV4)

- \+ No credential to store; the Lambda execution role is the identity, rotated by AWS.
- \+ AWS-idiomatic, no standing secrets.
- − Splits the platform's auth into two mechanisms (JWT for users, SigV4 for services) to build,
  test and secure.
- − SigV4 verification on the platform side is nontrivial custom code, or forces the platform behind
  an internal API Gateway.
- − Couples the platform's auth to AWS and breaks the local docker compose setup.

### 3. mTLS between workers and the platform

- \+ Strong mutual authentication at the transport layer.
- − Certificate issuance, distribution and rotation is heavy machinery for one internal edge.
- − mTLS termination adds configuration out of proportion to the need.
- − Identity is "holds the cert", coarser than scoped tokens; `onBehalfOf` still needs an
  application-layer mechanism.

### 4. Static shared API key in a header, stored in Secrets Manager

- \+ Trivial to implement and test locally.
- \+ No new auth flows.
- − A long-lived bearer secret with no expiry, scopes or subject; a leak means full ingest access
  until rotated by hand.
- − No standard validation or audit story; exactly the pattern the rest of the design avoids.

## Decision

Option 1: a service token issued by the auth service.

- One verification path on the platform (every caller is a JWT against the same JWKS), a scoped,
  short-lived, auditable worker identity, and a clean split between "who is calling" (the token)
  and "is this allowed" (the `onBehalfOf` membership check at time of use).
- The auth dependency is acceptable: delivery already has a retry and DLQ path for transient
  failures, and auth is the smallest, most stable service.
- Implementation: worker credential in Secrets Manager; token cached in the Lambda execution context
  across warm invocations and refreshed on expiry; scope limited to `documents:ingest`; local
  compose uses the same flow against the local auth container, so dev and cloud behave the same.
