-- migrate:up
-- Owned by docbridge_svc. The worker may only move tasks through their statuses and append
-- task events.

CREATE TABLE docbridge.jobs (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by   uuid NOT NULL,
    status       text NOT NULL DEFAULT 'uploading'
                 CHECK (status IN ('uploading', 'processing', 'completed', 'completed_with_errors', 'failed')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
CREATE INDEX jobs_created_by_idx ON docbridge.jobs (created_by, created_at DESC);
CREATE INDEX jobs_completed_at_idx ON docbridge.jobs (completed_at) WHERE completed_at IS NOT NULL;

CREATE TABLE docbridge.files (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id            uuid NOT NULL REFERENCES docbridge.jobs (id) ON DELETE CASCADE,
    name              text NOT NULL,
    content_type      text,
    size_bytes        bigint NOT NULL CHECK (size_bytes >= 0),
    checksum_sha256   text NOT NULL,
    staging_key       text NOT NULL UNIQUE,
    status            text NOT NULL DEFAULT 'pending_upload'
                      CHECK (status IN ('pending_upload', 'uploaded', 'upload_failed', 'expired')),
    upload_expires_at timestamptz NOT NULL,
    uploaded_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX files_job_idx ON docbridge.files (job_id);
CREATE INDEX files_pending_idx ON docbridge.files (upload_expires_at) WHERE status = 'pending_upload';

CREATE TABLE docbridge.tasks (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id          uuid NOT NULL REFERENCES docbridge.files (id) ON DELETE CASCADE,
    region           text NOT NULL CHECK (region IN ('eu', 'us')),
    binder_id        uuid NOT NULL,
    folder_id        uuid NOT NULL,
    status           text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'skipped')),
    attempts         integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    lease_expires_at timestamptz,
    error_code       text,
    document_id      uuid,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (file_id, region, binder_id, folder_id)
);
CREATE INDEX tasks_pending_idx ON docbridge.tasks (updated_at) WHERE status = 'pending';
CREATE INDEX tasks_lease_idx ON docbridge.tasks (lease_expires_at) WHERE status = 'in_progress';

-- Append-only log of every status change; actor values match the components that act.
CREATE TABLE docbridge.task_events (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id     uuid NOT NULL REFERENCES docbridge.tasks (id) ON DELETE CASCADE,
    actor       text NOT NULL CHECK (actor IN ('api', 'upload_handler', 'worker', 'dlq_handler', 'watchdog', 'user')),
    from_status text,
    to_status   text NOT NULL,
    error_code  text,
    detail      jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_events_task_idx ON docbridge.task_events (task_id, created_at);

GRANT UPDATE (status, attempts, lease_expires_at, error_code, document_id, updated_at) ON docbridge.tasks TO worker_svc;
GRANT INSERT ON docbridge.task_events TO worker_svc;

-- migrate:down
DROP TABLE docbridge.task_events;
DROP TABLE docbridge.tasks;
DROP TABLE docbridge.files;
DROP TABLE docbridge.jobs;
