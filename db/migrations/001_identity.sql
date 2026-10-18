-- migrate:up
-- Owned by auth_svc.

CREATE TABLE auth.users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         citext NOT NULL UNIQUE,
    display_name  text NOT NULL,
    password_hash text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE auth.teams (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE auth.team_members (
    team_id uuid NOT NULL REFERENCES auth.teams (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    role    text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),
    PRIMARY KEY (team_id, user_id)
);
CREATE INDEX team_members_user_idx ON auth.team_members (user_id);

-- Refresh tokens are stored hashed and rotated on every refresh.
CREATE TABLE auth.refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    token_hash  bytea NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    replaced_by uuid REFERENCES auth.refresh_tokens (id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON auth.refresh_tokens (user_id);

-- Clients of the client-credentials grant (e.g. task-worker with documents:ingest).
CREATE TABLE auth.service_clients (
    client_id   text PRIMARY KEY,
    secret_hash text NOT NULL,
    scopes      text[] NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- DocBridge resolves token sub -> user and team membership for access checks.
GRANT USAGE ON SCHEMA auth TO docbridge_svc;
GRANT SELECT (id, email, display_name) ON auth.users TO docbridge_svc;
GRANT SELECT ON auth.team_members TO docbridge_svc;

-- migrate:down
DROP TABLE auth.service_clients;
DROP TABLE auth.refresh_tokens;
DROP TABLE auth.team_members;
DROP TABLE auth.teams;
DROP TABLE auth.users;
