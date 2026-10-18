# API design

Every route requires a JWT except the auth routes that issue tokens. The OpenAPI documents in
`contracts/openapi/` are the source of truth for the code; this page is the design they follow.

## Response envelope

Every endpoint returns the same shape on success and failure, so clients handle responses uniformly.

```ts
/** A single error entry. */
export type ApiError = {
  /** Machine-readable code, e.g. "VALIDATION_ERROR". */
  code: string;
  /** Human-readable description. */
  message: string;
  /** Optional: which input field caused the error. */
  field?: string;
};

/** Successful response: data is present, errors is always empty. */
export type ApiSuccess<T> = {
  success: true;
  status: number;
  data: T;
  errors: [];
  message: string;
};

/** Failed response: data is null, errors has at least one entry. */
export type ApiFailure = {
  success: false;
  status: number;
  data: null;
  errors: ApiError[];
  message: string;
};

/** Discriminated on `success`: `if (res.success)` narrows `res.data` to `T`. */
export type ApiResponse<T> = ApiSuccess<T> | ApiFailure;

/** Offset-based pagination metadata for list endpoints. */
export type Pagination = {
  page: number;       // current page (1-based)
  limit: number;      // items per page
  total: number;      // total items across all pages
  totalPages: number; // ceil(total / limit)
};

export type ApiPaginatedSuccess<T> = ApiSuccess<T[]> & { pagination: Pagination };
export type ApiPaginatedResponse<T> = ApiPaginatedSuccess<T> | ApiFailure;
```

Every list endpoint uses the paginated envelope, with no exceptions.

## Auth service

| Method + path | Request | Response |
|---|---|---|
| `POST /api/v1/auth/register` | `{email, password, name}` | 201 `{id, email, name}` |
| `POST /api/v1/auth/login` | `{email, password}` | 200 `{accessToken, expiresIn: 900, tokenType: "Bearer", refreshToken}` |
| `POST /api/v1/auth/logout` | – | 204; revokes the refresh-token family |
| `POST /api/v1/auth/token` | `{clientId, clientSecret, scope}` | 200 `{accessToken, expiresIn: 900, tokenType: "Bearer"}` (service JWT, [ADR-008](../adr/008-worker-authentication.md)) |
| `POST /api/v1/auth/refresh` | `{refreshToken}` | 200 `{accessToken, expiresIn: 900, tokenType: "Bearer", refreshToken}` |
| `GET /.well-known/jwks.json` | – | 200 JWKS; every service validates against it |
| `GET /.well-known/openid-configuration` | – | 200 discovery document; API Gateway's JWT authorizer reads `jwks_uri` from it |

User JWT claims: `sub` (user id), `email`, `exp`, `iat`. Service JWT claims: `sub` (client id),
`scope`, `token_use: "service"`.

The refresh token is sent as an `httpOnly; Secure; SameSite=Strict` cookie scoped to
`/api/v1/auth`. Access tokens remain valid up to 15 minutes after logout (no `jti` denylist).

## Document platform

| Method + path | Response |
|---|---|
| `GET /api/v1/teams?docbridgeEnabled=true` | Teams the token subject belongs to: `[{id, name, region}]` |
| `GET /api/v1/teams/:teamId/binders` | 403 if not a member. `[{id, name}]` |
| `GET /api/v1/binders/:binderId/contents` | One level: `{folders: [...], documents: [...]}` |
| `GET /api/v1/folders/:folderId/contents` | One level inside a folder: `{folders: [...], documents: [...]}` |
| `GET /api/v1/documents?query=` | Search by name across nested folders, limited to what the caller can see (decision 3) |
| `PATCH /api/v1/documents/:id` | Rename (decision 3) |
| `DELETE /api/v1/documents/:id` | Delete (decision 3) |

Membership is resolved through folder → binder → team.

### Ingest (decision 2)

`PUT /internal/v1/documents/{sourceTaskId}`, service JWT with scope `documents:ingest`. Pull-based:
bytes never pass through the worker.

Body: `{onBehalfOfUserId, teamId, binderId, folderId?, name, contentType, sizeBytes, sha256, sourceUrl}`;
`sourceUrl` is a presigned GET valid for about 15 minutes. The platform verifies the full SHA-256
while copying into its documents bucket. Idempotency comes from the `PUT` on `sourceTaskId`.

| Response | Meaning | Worker treats it as |
|---|---|---|
| 201 | Created | Completed |
| 200 | Replay with the same payload | Completed |
| 409 | Replay with a different payload | Permanent |
| 422 `CHECKSUM_MISMATCH` | Bytes don't match `sha256` | Permanent |
| 404 `DESTINATION_NOT_FOUND` | Binder or folder gone | Permanent |
| 403 `ACCESS_REVOKED` | Membership changed, or DocBridge disabled after submission | Permanent |
| 429, 5xx, timeout | – | Transient: retried |

## DocBridge API

| Method + path | Request | Response |
|---|---|---|
| `POST /api/v1/jobs` | `{files: [{name, sizeBytes, contentType, sha256}]` (max 100), `mappings: [{fileIndex, destinations: [{teamId, binderId, folderId?}]}]}` | 201 `{jobId, taskCount, uploads: [{fileId, presignedPostFieldsOrMultipartPlan}]}` in under 500 ms. `fileIndex`, not `fileId`: this call mints the ids. `uploads` follows the order of `files`. Optional `Idempotency-Key` header: a replay returns 200 with the existing job; the same key with a different payload returns 422 `IDEMPOTENCY_KEY_REUSED`. |
| `GET /api/v1/jobs?page=&limit=` | – | `[{jobId, createdAt, taskCount, counts, aggregateStatus}]`, one aggregate query |
| `GET /api/v1/jobs/:id` | – | Job + counts. Visible to the submitter or a member of at least one destination team; otherwise 404 |
| `GET /api/v1/jobs/:id/tasks?status=&page=&limit=100` | – | Paginated tasks with `failureReason` (2,000 tasks never in one response). Same visibility as `GET /jobs/:id` |
| `GET /api/v1/jobs/:id/events?taskId=&page=&limit=` | – | Paginated `status_events`: the log view |
| `POST /api/v1/files/:fileId/multipart` | `{uploadId?, parts?: [{partNumber, sha256}]}` (optional body) | `{uploadId, parts: [{partNumber, url}], completeUrl, abortUrl}`. No body: `CreateMultipartUpload` (with `ChecksumAlgorithm=SHA256`) and return everything. With a body: re-sign the listed parts for that `uploadId`, plus fresh `completeUrl` and `abortUrl`. Submitter only. |
| `POST /api/v1/files/:fileId/download-url` | – | `{url, expiresIn: 120}`. POST on purpose: it mints a short-lived credential |

## WebSocket API

| Route | Behaviour |
|---|---|
| `$connect` | JWT in a query parameter (browsers cannot set WebSocket headers). Validated against the JWKS; inserts a `ws_connections` row. Rejected → 401, no connection. |
| `subscribe` | `{action: "subscribe", jobId}`. Checks the caller may view the job (same rule as `GET /jobs/:id`) and sets `job_id` on the connection. One subscription per connection: `subscribe` replaces the current job. |
| `unsubscribe` | Clears `job_id`. |
| `$disconnect` | Deletes the connection row. |

Push message: `{type: "task_update", jobId, taskId, status, failureReason?, counts: {...}}`. The
counts ride along so the client updates the aggregate without refetching. Connections that return
410 Gone are deleted.
