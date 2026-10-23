# Milestone 7.0 — SDK verification and source-consistency preflight

This document prepares a non-production Firestore SDK check and compares source-consistency strategies. It does not authorize Firebase initialization, emulator startup, live export, or production access. No approach below has been selected or activated.

## Local prerequisite check

The repository has `@google-cloud/firestore` 7.11.6 installed under `functions/node_modules`; the adapter pins that version and calls `db.settings({useBigInt:true})` before its first collection query when lossless numeric mode is requested. The public SDK documentation says integer fields decode as `BigInt` and floating-point fields remain JavaScript `number`.

The Firebase CLI is not on `PATH`, `firebase-tools` is not installed in `functions/node_modules`, and the repository's `firebase.json` has no `emulators` configuration. Java is available. No emulator was started, downloaded, or contacted. Thus the existing fake-client tests do not verify the SDK's actual response decoding.

An emulator-backed integration test **can** verify the installed SDK's runtime behavior without production credentials or production network access, provided a Firestore Emulator is provisioned and the test explicitly targets loopback. That prerequisite is not currently met. Provisioning Firebase CLI/emulator binaries and adding a disposable test configuration requires separate approval; do not claim SDK runtime verification until that test actually passes.

### Proposed emulator test contract

Use a disposable project ID such as `demo-samvibhag-sdk-verify`, a Firestore Emulator bound to `127.0.0.1` on a known port, and the already installed Firestore 7.11.6 package. The test must fail before creating a client unless the project ID is the disposable `demo-*` ID and `FIRESTORE_EMULATOR_HOST` resolves only to loopback. Construct a client with the explicit demo project ID; do not load ADC, Admin credentials, `.env` files, or production configuration. Do not use the production Firebase project ID.

Seed one synthetic document with Firestore wire types that are explicit at the source: signed int64 minimum and maximum, a value above JavaScript's safe integer range, ordinary positive and negative integers, an integral-valued double, a fractional double, negative zero, and a timestamp with nonzero nanoseconds. A typed Firestore Emulator REST fixture can distinguish `integerValue` decimal strings from `doubleValue`; alternatively use an SDK write path only after confirming that it does not coerce the intended types. Then read through the actual SDK with `useBigInt:true` and through `readFirestoreSnapshot`.

Assertions should verify:

- all integer values arrive as `bigint` and exactly equal the source int64 decimal values, including both signed limits;
- all floating values arrive as JavaScript `number`, the integral-valued double remains a double, and `Object.is(value, -0)` remains true for negative zero;
- the timestamp retains exact seconds and nanoseconds;
- the adapter's type manifest distinguishes Integer, Double, and Timestamp; and the JSON export/restore round trip reproduces the same values and numeric/timestamp tags;
- `db.settings({useBigInt:true})` occurs before the first query and all test reads target the emulator host.

The emulator is a test dependency, not proof of production IAM, production record fidelity, or concurrent-write consistency. Keep fake-client tests as fast contract tests. Record SDK version, emulator version, disposable project ID, test inputs/counts, and pass/fail status without logging document values.

## Source-consistency options

The current adapter performs separately paged reads of `users`, `usernames`, `groups`, and each group's `activities`. Those reads do not form a single Firestore transaction or point-in-time snapshot. `pointInTimeConsistent` must remain false until an approved strategy and its evidence establish a stable cutoff.

| Approach | Benefits | Main costs and failure modes | Evidence needed before relying on it |
| --- | --- | --- | --- |
| Authorized write freeze | Smallest new technical surface; once every writer is stopped and in-flight writes are drained, a multi-query scan can observe a stable source. Avoids replay ordering and deduplication machinery. | Maintenance window and blocked user writes; missed client, admin, scheduled, or Cloud Function writer invalidates the freeze. In-flight transactions, retries, offline clients, and queued local writes can cross the boundary. A freeze that starts after a scan begins does not repair earlier inconsistency. | Complete inventory of app, callable, trigger, scheduled, admin, and operational write paths; an approved freeze procedure that covers them all; evidence of the enforced start/end and drained in-flight work; write audit/telemetry showing no writes during the entire read interval; stable repeated counts/checks; an explicit offline-client/reconnect policy. These checks are operational evidence, not a claim that the scan API itself is transactional. |
| Durable change capture and reconciliation | Can keep Firestore writable during a baseline scan; captures changes for later replay and supports a controlled catch-up point. | Requires new application/backend changes and a durable event/outbox or equivalent. Events may be duplicated, delayed, reordered, or lost; deletes need tombstones; embedded expense/settlement array replacements and separate activity writes need complete capture; multi-document operations may not be atomic in the capture stream. A cursor gap or writer that bypasses capture makes the result incomplete. | Proof every mutation path emits a durable, versioned event; idempotent replay and delete handling; persisted watermark/cursor with gap detection; fault-injection tests for retries, reordering, outages, and restarts; reconciliation of every source record and relationship at a final fence; evidence capture has drained through that fence. A separately approved short write freeze may still be required to establish the final fence. |

Neither approach is selected here. The current application has no durable change log, uniform per-record version, or Firestore-to-RTDB dual-write. A timestamp-only delta is not sufficient evidence because embedded arrays can be replaced and separate writes can race. Any implementation, maintenance window, production write gate, or deployment needs a separate authorization and review.

## Pre-export operational gate

Complete and retain evidence for every item before considering a live export. A missing or inconclusive item is a stop condition.

1. **Project and identity:** Independently verify the intended project is `samvibhag-a2299` and the ADC principal is the approved dedicated inventory identity `samvibhag-migration-inventory@samvibhag-a2299.iam.gserviceaccount.com`. Prefer short-lived authorized impersonation over a downloaded service-account key. Verify project context and principal without printing tokens or credential contents. Stop on mismatch, ambiguity, or an identity that cannot be verified.
2. **Effective permissions:** Have an authorized administrator inspect effective IAM, including inherited bindings and conditions. Confirm the principal can perform only the Firestore reads needed for the audited queries, and has no Firestore write, database administration, IAM, deployment, or RTDB write capability. Use a reviewed least-privilege role; a project ID or role name alone is not proof of effective permissions. Stop if a broad/inherited/conditional grant cannot be explained or the required reads cannot be authorized.
3. **Scope:** Confirm the reviewed source scope remains `users`, `usernames`, `groups`, and `groups/{groupId}/activities`; establish whether any additional production collections or subcollections contain migration-relevant records. Stop if scope is not complete or any added path has not been reviewed and authorized. The local fixture CLI is not a live exporter.
4. **Consistency:** Approve one source-consistency strategy above and collect its evidence before export. Stop if writers, in-flight operations, offline clients, or event gaps cannot be accounted for. The export manifest must not claim point-in-time consistency based only on successful pagination.
5. **Artifact access:** Select an approved local or controlled storage location with encryption at rest and access limited to named operators/reviewers. Exclude source exports from repository commits, shared/synced folders, shell histories, debug output, and unencrypted temporary storage. Treat source values as sensitive, including profile data and possible tokens. Verify temporary files and crash leftovers have an access-controlled cleanup policy.
6. **Retention and recovery:** Obtain an approved retention period, owner, backup location, deletion procedure, and legal/operational hold policy before extraction. Verify that backup copies inherit the same access controls and encryption. Stop if the artifact cannot be retained long enough for verification or securely disposed of under policy.
7. **Integrity and completeness:** After a successful export, require the exact completion marker and required files; run the shared reader to verify schema version, byte length, SHA-256, type descriptors, IDs, and recomputed counts; compare source-read counters and aggregate counts with an independently reviewed inventory; and verify the checksum again after any approved transfer. A hash detects accidental changes only when compared to a trusted value; it is not a signature if the same actor can replace the export and marker. Keep raw identifiers and record-level details out of the validation report. Stop on missing marker, mismatch, partial read, unsupported value, count difference, or unverified transfer.

Evidence should include approval references, project/principal and effective-permission review results, audited path list, selected consistency strategy and its evidence, artifact ACL/encryption and retention confirmation, SDK/emulator test result, export validation status/counts, and integrity verification. Do not include secrets or record-level contents in the evidence bundle.

## Destination-layout decision remains open

The JSON export is a source archive and does not select an RTDB projection. The proposal describes active collections under `/samvibhag/v1/{users,usernames,groups,userGroups}` plus `migrationRuns`; the local planner writes projected data and source archives below `/samvibhag/v1/migrationRuns/{runId}`. Top-level active collections simplify application reads but need a separately reviewed activation/conflict/rollback design. Run-scoped staging isolates attempts and supports verification, but needs a promotion process, retention policy, extra storage, and possible app-path changes. No layout is chosen or applied in Milestone 7.0. A separate decision must settle conflict handling, activation, retention, security rules, and recovery before migration planning or any RTDB write.
