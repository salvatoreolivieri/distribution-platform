# S3 upload event

The staging bucket sends `s3:ObjectCreated:*` notifications for the `staging/` prefix to the
`upload-events` SQS queue. The upload-handler reads only these fields of each record in the
message body (`Records[]`):

| Field | Used for |
|---|---|
| `eventName` | Must start with `ObjectCreated:`; anything else is ignored. |
| `s3.bucket.name` | Sanity check against the configured staging bucket. |
| `s3.object.key` | URL-encoded. Format: `staging/{jobId}/{fileId}`. Identifies the file. |
| `s3.object.size` | Compared with `files.size_bytes` declared at submit. |
| `s3.object.eTag` | Logged for tracing. |
| `s3.object.sequencer` | Orders events for the same key; older events are dropped. |

S3 also sends a `s3:TestEvent` message when the notification is configured. The handler
acknowledges and drops it.

The checksum is not in the event. The browser uploads with `x-amz-checksum-sha256`, S3
verifies it on write, and the upload-handler reads it back with `HeadObject`
(`ChecksumMode=ENABLED`) before marking the file uploaded.
