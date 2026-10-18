#!/usr/bin/env bash
# Gives each service role LOGIN and its password. Run after `dbmate up`.
#
#   DATABASE_URL           migrator connection (superuser locally, RDS master in AWS)
#   <ROLE>_PASSWORD        e.g. AUTH_SVC_PASSWORD; defaults to "<role>_local" when unset
#
# In AWS, CI exports the passwords from the Secrets Manager secrets the database module
# creates, so the proxy and the database agree.
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

for role in auth_svc platform_svc docbridge_svc worker_svc; do
  var="$(echo "$role" | tr '[:lower:]' '[:upper:]')_PASSWORD"
  password="${!var:-${role}_local}"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -v role="$role" -v password="$password" <<'SQL'
ALTER ROLE :"role" WITH LOGIN PASSWORD :'password';
SQL
  echo "role $role: login enabled"
done
