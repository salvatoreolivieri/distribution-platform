-- migrate:up
-- One role per service, one schema per owner. A role can write only the schema its service
-- owns; cross-service access is an explicit, read-only grant. Passwords are not set here:
-- scripts/db-role-passwords.sh sets them (locally from env, in AWS from Secrets Manager).

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm; -- M4 document search

DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['auth_svc', 'platform_svc', 'docbridge_svc', 'worker_svc'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO auth_svc, platform_svc, docbridge_svc, worker_svc;

CREATE SCHEMA auth;
CREATE SCHEMA platform;
CREATE SCHEMA docbridge;

-- Owners: full DML on every table the migrations create in their schema.
GRANT USAGE ON SCHEMA auth TO auth_svc;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO auth_svc;

GRANT USAGE ON SCHEMA platform TO platform_svc;
ALTER DEFAULT PRIVILEGES IN SCHEMA platform GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO platform_svc;

GRANT USAGE ON SCHEMA docbridge TO docbridge_svc;
ALTER DEFAULT PRIVILEGES IN SCHEMA docbridge GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO docbridge_svc;

-- The worker reads DocBridge tables; its writes are granted per table in 003_jobs.sql.
GRANT USAGE ON SCHEMA docbridge TO worker_svc;
ALTER DEFAULT PRIVILEGES IN SCHEMA docbridge GRANT SELECT ON TABLES TO worker_svc;

-- migrate:down
DROP SCHEMA IF EXISTS docbridge CASCADE;
DROP SCHEMA IF EXISTS platform CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;
-- Revokes the remaining privileges (public schema, default privileges) so the roles can go.
DROP OWNED BY auth_svc, platform_svc, docbridge_svc, worker_svc;
GRANT USAGE ON SCHEMA public TO PUBLIC;
DROP ROLE IF EXISTS worker_svc;
DROP ROLE IF EXISTS docbridge_svc;
DROP ROLE IF EXISTS platform_svc;
DROP ROLE IF EXISTS auth_svc;
