# 3. Our own token issuer, signed with KMS

Status: accepted

## Decision

The auth service issues ES256 JWTs signed with an asymmetric KMS key; `kid` is the key
version, so rotation is a new key version plus a JWKS that lists both. User tokens come from
login/refresh, service tokens from a client-credentials grant (`token_use` claim). API
Gateway's JWT authorizer and every service verify against our `/.well-known/jwks.json`.

## Consequences

No Cognito dependency, and the private key never leaves KMS. We own refresh-token storage
and revocation.
