# Token signing key and service credentials.
# The auth service signs ES256 JWTs with this asymmetric key; kid is the key version, so a
# rotation is a new key version published in the JWKS next to the old one.

resource "aws_kms_key" "jwt" {
  description              = "${var.name} JWT signing (ES256)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
}

resource "aws_kms_alias" "jwt" {
  name          = "alias/${var.name}-jwt"
  target_key_id = aws_kms_key.jwt.key_id
}

# Client credentials for each service that calls another API, e.g. the worker calling the
# platform's /internal/v1 ingest with the documents:ingest scope. The auth service stores a
# hash of the secret; the caller reads the secret from here.
resource "random_password" "client_secret" {
  for_each = var.service_clients
  length   = 48
  special  = false
}

resource "aws_secretsmanager_secret" "client" {
  for_each = var.service_clients
  name     = "${var.name}/clients/${each.key}"
}

resource "aws_secretsmanager_secret_version" "client" {
  for_each  = var.service_clients
  secret_id = aws_secretsmanager_secret.client[each.key].id
  secret_string = jsonencode({
    clientId     = each.key
    clientSecret = random_password.client_secret[each.key].result
    scope        = join(" ", each.value)
  })
}
