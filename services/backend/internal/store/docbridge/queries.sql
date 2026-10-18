-- name: GetJob :one
SELECT id, created_by, status, created_at, completed_at
FROM docbridge.jobs
WHERE id = $1;

-- name: ListTasksByFile :many
SELECT id, region, binder_id, folder_id, status, attempts, error_code, document_id
FROM docbridge.tasks
WHERE file_id = $1
ORDER BY created_at;

-- name: InsertTaskEvent :exec
INSERT INTO docbridge.task_events (task_id, actor, from_status, to_status, error_code)
VALUES ($1, $2, $3, $4, $5);
