-- migrate:up
-- Owned by platform_svc. Each platform deployment serves the binders of its region.

CREATE TABLE platform.binders (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    region     text NOT NULL CHECK (region IN ('eu', 'us')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX binders_region_idx ON platform.binders (region);

CREATE TABLE platform.folders (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    binder_id  uuid NOT NULL REFERENCES platform.binders (id) ON DELETE CASCADE,
    parent_id  uuid REFERENCES platform.folders (id) ON DELETE CASCADE,
    name       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX folders_sibling_name_idx
    ON platform.folders (binder_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'), name);
CREATE INDEX folders_parent_idx ON platform.folders (parent_id);

-- A grant on a binder applies to all its folders; a grant on a folder applies to its
-- subtree and overrides the binder grant. Principals are auth users or teams.
CREATE TABLE platform.access_grants (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    binder_id      uuid NOT NULL REFERENCES platform.binders (id) ON DELETE CASCADE,
    folder_id      uuid REFERENCES platform.folders (id) ON DELETE CASCADE,
    principal_type text NOT NULL CHECK (principal_type IN ('user', 'team')),
    principal_id   uuid NOT NULL,
    level          text NOT NULL CHECK (level IN ('none', 'read', 'write')),
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX access_grants_unique_idx
    ON platform.access_grants (binder_id, coalesce(folder_id, '00000000-0000-0000-0000-000000000000'), principal_type, principal_id);
CREATE INDEX access_grants_principal_idx ON platform.access_grants (principal_type, principal_id);

CREATE TABLE platform.documents (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    binder_id       uuid NOT NULL REFERENCES platform.binders (id),
    folder_id       uuid NOT NULL REFERENCES platform.folders (id),
    name            text NOT NULL,
    content_type    text,
    size_bytes      bigint NOT NULL CHECK (size_bytes >= 0),
    checksum_sha256 text NOT NULL,
    storage_key     text NOT NULL UNIQUE,
    idempotency_key text NOT NULL UNIQUE,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX documents_folder_idx ON platform.documents (folder_id);
CREATE INDEX documents_name_trgm_idx ON platform.documents USING gin (name gin_trgm_ops);

-- DocBridge builds the destination tree and checks write access before submit.
GRANT USAGE ON SCHEMA platform TO docbridge_svc;
GRANT SELECT ON platform.binders, platform.folders, platform.access_grants TO docbridge_svc;

-- migrate:down
DROP TABLE platform.documents;
DROP TABLE platform.access_grants;
DROP TABLE platform.folders;
DROP TABLE platform.binders;
