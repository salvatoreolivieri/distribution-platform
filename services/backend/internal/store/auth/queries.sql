-- name: GetUserByEmail :one
SELECT id, email, display_name, password_hash
FROM auth.users
WHERE email = $1;

-- name: GetUserByID :one
SELECT id, email, display_name
FROM auth.users
WHERE id = $1;

-- name: GetServiceClient :one
SELECT client_id, secret_hash, scopes
FROM auth.service_clients
WHERE client_id = $1;
