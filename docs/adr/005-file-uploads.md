# ADR-005: File uploads and downloads

**Status:** accepted. Multipart checksums are refined by decision 4 in
[milestones.md](../milestones.md#decisions-after-the-design).

## Decision required

Do file bytes move directly between the browser and S3 (presigned URLs), or through our API servers?

## Context

Users upload up to 100 files per session (2 MB average, 1 GB maximum), and team members later
download staged files. The UI must never freeze during upload, file integrity must be verifiable
end to end, and job submission must be acknowledged in under 500 ms whatever the batch size. Files
are encrypted at rest with KMS-managed server-side encryption, so nothing key-related travels with
the bytes.

## Alternatives evaluated

### 1. Presigned transfers: presigned POST for uploads, presigned GET for downloads, each scoped to one object with a short expiry (chosen)

- \+ The API scales with request volume, not upload bandwidth; a 1 GB transfer never holds an API
  connection.
- \+ Presigned POST policies enforce a hard size ceiling (`content-length-range`) and the content
  type at the storage layer.
- \+ A client-supplied SHA-256 is verified by S3 on write for single-request uploads, and
  re-verified over the bytes before delivery: end-to-end integrity. On the multipart path S3
  checksums parts, not the assembled object, so a later whole-object check closes the chain for
  large files.
- \+ Parallel browser-to-S3 uploads keep the UI responsive with per-file progress.
- − Upload completion is not observed in-band, so the system needs a signal from storage rather
  than a claim from the client ([ADR-009](009-file-arrival-detection.md)).
- − URL issuance is an extra request per file.
- − A presigned URL is a bearer credential while valid (mitigated by single-object scope and short
  expiry).

### 2. Proxy all file bytes through the API servers

- \+ Upload success and failure are observed directly by the API.
- \+ One place for validation and virus or type scanning.
- \+ No bearer-credential URLs at all.
- − The API must scale with aggregate file bandwidth; slow 1 GB uploads hold connections for minutes.
- − Every byte transits twice (browser → API → S3), doubling transfer cost and latency.
- − Resumable uploads must be built by hand.

### 3. Hybrid: proxied uploads, presigned downloads

- \+ In-band upload observation where it matters most.
- \+ Downloads still bypass servers, as required.
- − Keeps all of option 2's upload-side scaling and connection problems.
- − Two transfer mechanisms to build, secure and test instead of one.

## Decision

Option 1, in both directions. The API stays out of the byte path entirely.

- Every presigned URL is issued only after an authorization check (team membership for downloads,
  session ownership for uploads), is scoped to exactly one object key, and expires quickly.
  Uploads use presigned **POST** rather than PUT because POST policies can enforce a maximum object
  size and PUT cannot.
- The bytes are checked again before ingest; the platform recomputes the SHA-256 on receipt and
  rejects a mismatch with 422, so mismatched bytes are never ingested. With pull-based ingest
  (decision 2) bytes never pass through the worker: the platform verifies the full SHA-256 while
  copying into its own bucket. A missing or mismatched object fails the task with a clear reason,
  never silently.
- Files above the multipart threshold (about 100 MB) upload with S3 multipart. Initiation is lazy
  (`POST /files/:fileId/multipart` when the client starts that file), part URLs can be re-signed
  within the session, and within-session resume keeps the upload id on the client.
