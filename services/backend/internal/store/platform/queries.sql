-- name: ListBindersByRegion :many
SELECT id, name, region
FROM platform.binders
WHERE region = $1 AND id > $2
ORDER BY id
LIMIT $3;

-- name: ListFoldersByBinder :many
SELECT id, parent_id, name
FROM platform.folders
WHERE binder_id = $1
ORDER BY name;

-- name: GetDocument :one
SELECT id, binder_id, folder_id, name, content_type, size_bytes, checksum_sha256, storage_key, created_at
FROM platform.documents
WHERE id = $1;
