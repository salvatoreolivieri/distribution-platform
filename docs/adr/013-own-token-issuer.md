# ADR-013: Our own token issuer, signing with KMS

**Status:** accepted. Implements decision A1 ("everything is built in-house: no external or managed
identity service") and replaces the Cognito user pool of the original Technical Design.

## Decision

- The auth service issues ES256 JWTs signed with an asymmetric KMS key (`ECC_NIST_P256`,
  `SIGN_VERIFY`). The private key never leaves KMS. `kid` is the key version, so rotation is a new
  key version published in the JWKS next to the old one.
- User tokens come from login and refresh: claims `sub` (user id), `email`, `iat`, `exp`,
  15-minute lifetime. Service tokens come from the client-credentials grant: `sub` (client id),
  `scope`, `token_use: "service"` ([ADR-008](008-worker-authentication.md)).
- Refresh tokens rotate on every use; presenting an already-used token revokes the whole family
  (decision 1 in [milestones.md](../milestones.md#decisions-after-the-design)).
- The auth service publishes `/.well-known/openid-configuration` and `/.well-known/jwks.json`.
  API Gateway's JWT authorizer reads the JWKS through the discovery document; every service
  verifies tokens with `internal/jwtverify` against the same JWKS.

## Consequences

No Cognito dependency, and the same flow runs locally (against the local auth container and the
LocalStack KMS key). We own password hashing (argon2id), refresh-token storage, revocation and rate
limiting on login and register.
