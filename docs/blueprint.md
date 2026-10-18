# Blueprint

Source: DocBridge PAS-002. What the system must do is in [requirements.md](requirements.md);
how it is built is in [architecture/](architecture/README.md).

## What problem we're solving and why

Clinical trial coordinators routinely **need to upload the same set of files to many destinations
at once**. The client needs a tool that lets a user:

- select multiple files in one session, seeing and acting only on the parts of the hierarchy they
  are authorized to access;
- map each file to one or more destinations in the hierarchy (teams, binders, folders);
- submit the whole batch in one action;
- track the progress of every individual upload;
- know exactly which uploads succeeded and which failed.

DocBridge is a standalone web application that delivers files into the document platform through
its API.

**Current state.** Ten regulatory files must land in 15 different team binders across 5 hospitals.
Today that is one file at a time, one destination at a time: slow and error-prone.

**Impact.** Without a tool like this, time is wasted and mistakes happen, because there is no single
source of truth and no central place to handle the files.

## Job stories

- When a **guest lands on the application**, redirect them to the `/login` page, so that **the
  system is usable only by authenticated, authorized users**.
- When a **user enters valid credentials**, redirect them to the dashboard, so that they can
  **browse the files available to them** (based on real permissions).
- When a user **selects a destination and a file to upload**, provide a **job submission view**,
  so that they can **see the details and status** of every file in the job.
- When a user **searches for a file**, show every matching file with its storage path, so that they
  find what they need without navigating teams, binders and folders.
- When a user **selects a document**, let them **view its contents** without downloading it, and
  **download it** when needed.
- When a user **selects a document**, let them **edit its title or destination**, so that files
  stay correctly organised.
- When a user **selects a document**, let them **delete it**, so that they can remove files they no
  longer need.
- When a user **checks the audit trail**, show **who sent each document**, which document, where it
  was placed and whether the send succeeded, so that every transfer can be traced.

## User flows

Each flow has a Mermaid transcription (reviewable in diffs) and the original diagram from the PAS.
The originals predate some later decisions (for example, they show a Cognito authorizer, while
[ADR-013](adr/013-own-token-issuer.md) has our own issuer); where they disagree, the decisions in
[milestones.md](milestones.md#decisions-after-the-design) and the ADRs win.

### Flow 1: Browse files

1. **Log in**.
2. The session is kept with **token-based authentication**.
3. **Browse the files** available, based on real permissions.

```mermaid
sequenceDiagram
    actor U as User
    participant W as Web client
    participant G as API Gateway
    participant A as Auth service
    participant P as Document platform
    U->>W: Log in
    W->>G: Login request
    G->>A: Authenticate user
    A-->>W: Token and regions
    U->>W: View teams
    W->>G: Teams the user belongs to (DocBridge-enabled)
    G->>P: Query available teams
    P-->>W: Team list
    loop User expands a team
        W->>G: Request binders
        G->>P: Query binders
        P-->>W: Binders
    end
    loop User expands a folder
        W->>G: Request folder contents
        G->>P: Query contents
        P-->>W: Folders and documents
    end
    U->>W: Select destination
```

![Flow 1: browse files](architecture/diagrams/flow-1-browse.png)

### Flow 2: Distribute files (with live updates)

1. Select one or more **destinations**: a binder or a folder nested inside it.
2. Submit an upload job, then follow the details and status of every file, so the user understands
   what is happening during delivery.

```mermaid
sequenceDiagram
    actor U as User
    participant W as Web client
    participant G as API Gateway
    participant D as DocBridge API
    participant DB as PostgreSQL
    participant S as Staging bucket
    participant UQ as upload-events queue
    participant UH as Upload handler
    participant TQ as tasks queue
    participant DL as Delivery worker
    participant A as Auth service
    participant P as Document platform
    participant WS as WebSocket API
    U->>W: Select files and map each to destinations
    W->>W: SHA-256 per file (web worker)
    W->>G: POST /jobs
    G->>D: Forward (JWT validated)
    D->>DB: Insert job, files, tasks (pending)
    D-->>W: 201 jobId + one upload target per file
    W->>WS: Subscribe to the job
    loop Each file, in parallel
        W->>S: Presigned POST (or multipart parts)
        S->>UQ: ObjectCreated event
        UQ->>UH: Event
        UH->>S: Check size and checksum
        UH->>DB: pending → uploaded (conditional)
        UH->>TQ: One message per destination (batch)
    end
    loop Each task
        TQ->>DL: Task message
        DL->>DB: Claim: pending → in_progress
        DL->>A: Service token (cached)
        DL->>P: Ingest (idempotent on the task id)
        P->>S: Copy bytes, verify SHA-256
        P-->>DL: 201 / transient / permanent error
        DL->>DB: completed or failed (+ reason), status event
        DL->>WS: Push task update
        WS-->>W: Live update
    end
```

![Flow 2: distribute files](architecture/diagrams/flow-2-distribute.png)

### Flow 3: Track and job history

1. **Track** every document sent, with a clear log of what was submitted, when and by whom.
2. See the **history of submitted jobs**.

```mermaid
sequenceDiagram
    actor U as User
    participant W as Web client
    participant G as API Gateway
    participant D as DocBridge API
    participant DB as PostgreSQL
    participant WS as WebSocket API
    participant DL as Delivery worker
    U->>W: Open job list
    W->>G: Request jobs
    G->>D: Forward
    D->>DB: Query jobs (aggregate counts)
    D-->>W: Job list
    U->>W: Select a job
    W->>G: Request job tasks
    G->>D: Forward
    D->>DB: Query tasks
    D-->>W: Task details
    W->>WS: Subscribe to updates
    loop Status changes
        DL->>WS: Push status update
        WS-->>W: Live update
    end
```

![Flow 3: track jobs](architecture/diagrams/flow-3-track.png)

### Flow 4: Retrieve a file

1. **View** a file (without downloading it) and **download** it.

```mermaid
sequenceDiagram
    actor U as User
    participant W as Web client
    participant G as API Gateway
    participant D as DocBridge API
    participant DB as PostgreSQL
    participant S as Staging bucket
    U->>W: Open a teammate's job, select a file
    W->>G: Request download URL
    G->>D: Forward (JWT validated)
    D->>DB: Verify team membership
    alt Authorized
        D->>D: Presign GET (120 s)
        D-->>W: Download URL
        W->>S: Download directly
    else Not authorized
        D-->>W: 404 (existence is not revealed)
    end
```

![Flow 4: retrieve a file](architecture/diagrams/flow-4-retrieve.png)

### Flow 5: Interact with the platform

1. **Search** for a document by name, across nested folders.
2. **Edit** the document's title or its destination.
3. **Delete** the document.
4. **Outcome:** the user can navigate and work with the uploaded files inside the platform.

Search, rename and delete belong to the Platform API since decision 3 ("Split files"); the
original diagram shows them on the DocBridge API.

```mermaid
sequenceDiagram
    actor U as User
    participant W as Web client
    participant G as API Gateway
    participant P as Document platform
    participant DB as PostgreSQL
    participant S as Storage
    rect rgb(235, 242, 255)
    note over U,S: Search by name (across nested folders)
    U->>W: Type in the search bar, press Enter
    W->>G: GET /documents?query=
    G->>P: Forward (JWT validated)
    P->>DB: Documents the caller can see, name or path ILIKE query, not deleted
    P-->>W: 200 items: id, name, path, status
    end
    rect rgb(255, 248, 235)
    note over U,S: Rename
    U->>W: Edit the name, press Enter
    W->>G: PATCH /documents/:id {name}
    G->>P: Forward
    P->>DB: UPDATE name (visible, not deleted)
    P-->>W: 200 {id, name}
    end
    rect rgb(255, 238, 238)
    note over U,S: Delete
    U->>W: Delete, confirm
    W->>G: DELETE /documents/:id
    G->>P: Forward
    P->>DB: Soft delete (deleted_at = now()), audit kept
    P->>S: Delete the stored object
    P-->>W: 204
    end
```

![Flow 5: interact with the platform](architecture/diagrams/flow-5-interact.png)

## Decisions with architectural impact

| Question | Record |
|---|---|
| How do we route public API traffic from the internet to our internal services? | [ADR-001](adr/001-route-traffic.md), [ADR-010](adr/010-compute-api-gateway-and-lambda.md) |
| How do we handle async job tasks independently of each other? | [ADR-002](adr/002-async-processing.md) |
| How do we deploy and configure the system (automation, configuration, secrets)? | [ADR-003](adr/003-deployment-and-configuration.md) |
| How does the browser receive task and job status updates while a job runs? | [ADR-004](adr/004-status-updates.md) |
| Do file bytes go straight between the browser and S3 (presigned URLs), or through our servers? | [ADR-005](adr/005-file-uploads.md) |
| What compute runs the queue consumers? | [ADR-006](adr/006-queue-consumer-compute.md) |
| What compute runs the backend services, and how are they deployed? | [ADR-007](adr/007-backend-compute.md), [ADR-010](adr/010-compute-api-gateway-and-lambda.md) |
| How do delivery workers authenticate to the document platform? | [ADR-008](adr/008-worker-authentication.md) |
| What tells the system a file has arrived, and what enqueues its tasks? | [ADR-009](adr/009-file-arrival-detection.md) |

The full list, including the decisions recorded while building, is in [adr/](adr/README.md).
