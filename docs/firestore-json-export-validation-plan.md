# Firestore JSON export and validation plan

Status: local, synthetic-fixture-only export contract. `json_export.mjs` implements the serializer, validator, and local artifact publication boundary for approved synthetic fixture files only. It is not a live Firestore exporter. No Firebase initialization, ADC resolution, production read, destination write, or layout decision was made. Any future live exporter requires separate review and authorization.

## 1. Destination layout decision remains open

The current proposal and planner describe different destination layouts. This plan records the trade-offs without selecting either layout.

| Option | Benefits | Costs and risks | Evidence/decision needed |
| --- | --- | --- | --- |
| Top-level active collections under `/samvibhag/v1/{users,usernames,groups,userGroups}` | Matches the logical application schema in `realtime-database-schema-proposal.md`; application queries can use stable paths directly; avoids a permanent extra run namespace in every read. | A partial write can appear at active paths before verification; requires a separately designed activation/cutover and rollback; may conflict with pre-existing data; source archive and active projection have separate lifecycle and access needs. | Read-only evidence of existing destination paths and size; approved conflict/retention policy; atomic or versioned activation design; application query and rules design.
| Isolated staging under `/samvibhag/v1/migrationRuns/{runId}` | Isolates retries; supports conflict checks and verification before promotion; keeps each attempt distinguishable; an incomplete attempt need not be treated as active app data. | App cannot consume staging data without a later promotion/copy or app-path change; duplicates data and increases storage; run and archive retention/access need design; promotion still needs a separate safe procedure. | Run-ID lifecycle and cleanup policy; size/backup plan; promotion procedure; rules that prevent client mutation and isolate run data.

The present local planner uses `migrationRuns/{runId}/projected/...` and `migrationRuns/{runId}/sourceArchive/...`. The schema proposal describes active collections at the top level and also a `migrationRuns` area. The local inventory's five fixed paths reflect those proposal children, not proof that the production tree has this shape. No implementation in this milestone changes the planner, runner, or destination paths. A decision requires review and a separately approved change.

## 2. Versioned export JSON contract

The existing `readFirestoreSnapshot` adapter returns a fixture-shaped object. The contract serializer accepts only that synthetic snapshot format and emits a distinct versioned format. It stores Firestore document IDs separately from source fields and writes special typed values as `null` placeholders described by a strict manifest. This avoids reserved wrapper collisions with ordinary source maps.

Proposed logical shape (synthetic values only):

```json
{
  "format": "samvibhag-firestore-json-export-v1",
  "scope": ["users", "usernames", "groups", "groups/{groupId}/activities"],
  "collections": {
    "users": [{ "id": "synthetic-uid", "data": { "uid": "synthetic-uid" } }],
    "usernames": [{ "id": "synthetic_name", "data": { "uid": "synthetic-uid" } }],
    "groups": [{
      "id": "synthetic-group-id",
      "data": {
        "members": ["Synthetic Member", "Offline Member"],
        "memberUids": ["synthetic-uid"],
        "expenses": [],
        "recordedSettlements": []
      },
      "subcollections": {
        "activities": [{ "id": "synthetic-activity-id", "data": { "groupId": "synthetic-group-id" } }]
      }
    }]
  },
  "typeManifest": [
    { "pointer": "/users/synthetic-uid/data/createdAt", "type": "Timestamp", "placeholder": "null", "seconds": 1700000000, "nanoseconds": 123456789 },
    { "pointer": "/users/synthetic-uid/data/count", "type": "Integer", "placeholder": "null", "integerDecimal": "9007199254740993" },
    { "pointer": "/users/synthetic-uid/data/rate", "type": "Double", "placeholder": "null", "ieee754Hex": "3ff0000000000000" }
  ],
  "counts": {
    "users": 1,
    "usernames": 1,
    "groups": 1,
    "activities": 1,
    "expenses": 0,
    "recordedSettlements": 0,
    "firestoreDocumentsIncludingActivities": 4,
    "typeDescriptors": 3
  }
}
```

This is an envelope example, not a destination schema. `id` is the Firestore document ID and stays separate from `data`; if the source document also has an `id` or `uid` field, preserve it as ordinary source data. Validate equality only where existing code already requires it (currently, planner validation checks `users/{uid}.data.uid` against the user document ID). Do not silently overwrite a source field with a document ID.

For a valid export:

- `collections.users`, `collections.usernames`, and `collections.groups` are arrays of `{id,data}` records. Each group has `subcollections.activities`, also an array of `{id,data}` records. Empty collections are explicit empty arrays. Do not omit a collection or group activity list because it is empty or unreadable; unreadable/incomplete scope makes export fail.
- Preserve original source field names, absent fields, explicit `null`, array order, nested maps, and unknown ordinary JSON-compatible fields. Expenses and settlements remain embedded in each group's `data` exactly as sourced; the exporter does not recalculate amounts, splits, balances, settlement status, or aliases.
- Preserve source Firestore IDs exactly in `id`. Any eventual RTDB key encoding is a separate projection concern. It must be deterministic/reversible, collision-checked, and must never replace the source ID in this export.
- `typeManifest` is an array so duplicate pointers can be detected. Pointers use escaped source IDs and JSON-Pointer-style escaping of `~` and `/`; embedded expense/settlement pointers use the actual array index. Activity pointers follow the adapter convention `/groups/{groupId}/activities/{activityId}/{field...}` and resolve into that activity's `data`. Each descriptor must resolve to an existing `null` placeholder, and `counts.typeDescriptors` must equal the manifest length. Duplicate, malformed, or orphan descriptors invalidate the export.
- Timestamp descriptors require seconds in Firestore's supported range (`-62,135,596,800` through `253,402,300,799`) and integer nanoseconds from `0` through `999,999,999`; the serializer preserves both exactly and never converts them to milliseconds.
- An `Integer` descriptor serializes as a `null` data placeholder plus canonical signed decimal text in `integerDecimal`, constrained to the Firestore signed 64-bit range. A finite, safe JavaScript integer can be converted to decimal only when the source descriptor explicitly says `Integer`. Values beyond JavaScript's safe integer range are accepted only when an upstream source adapter supplies the exact decimal string with the `Integer` descriptor and a null placeholder; otherwise they fail closed.
- A `Double` descriptor serializes as a `null` placeholder plus the exact 8-byte IEEE-754 binary64 bit pattern encoded as 16 lowercase hex digits in `ieee754Hex`. This preserves distinctions such as an integral-valued double and negative zero. Non-finite values are rejected. Restoration reconstructs the typed values using the manifest; a JSON number without an explicit numeric type descriptor is rejected rather than classified by its appearance.
- The local installed `@google-cloud/firestore` package is version 7.11.6. Its public `Settings.useBigInt` documentation states that integers deserialize to `BigInt` and floating-point values remain JavaScript `number`. This is sufficient to distinguish supported integer and double values without depending on `_fieldsProto`. Lossless adapter reads explicitly request `db.settings({useBigInt:true})` before any query and compare both the caller's expected version and the locally resolved package metadata with `7.11.6`; unknown versions or missing settings support fail before reads. `BigInt` values are range-checked as signed int64 and retain exact decimal text; finite numbers in this configured mode are encoded as exact binary64 bits. Without this explicit mode, ordinary JavaScript numbers remain untyped and the exporter rejects them.
- The tests use fake snapshots returning `BigInt` for integers and `number` for doubles, and verify that the settings call precedes collection reads. They establish adapter/export behavior for that public contract shape only. They do not initialize the real SDK, exercise transport/deserialization, verify a custom converter, or establish any production record fidelity. Those require a separate non-production integration test using the installed SDK and representative synthetic emulator data. Never infer Integer versus Double from JavaScript numbers in an unconfigured mode.
- Keep missing properties absent and explicit Firestore null as JSON `null`. Do not use truthiness/defaulting that merges the two states. The export is source data; RTDB's inability to store `null` is handled only by a separately reviewed destination encoder.
- The count manifest is redundant by design. Recompute it from serialized records and reject any mismatch. Counts are users, usernames, groups, activities, embedded expenses, embedded recorded settlements, Firestore documents including activity documents (`users + usernames + groups + activities`), and type descriptors. Do not count embedded expenses/settlements as Firestore documents.

## 3. Type policy and fail-closed cases

The adapter recognizes Firestore `Timestamp` and captures seconds/nanoseconds. In lossless numeric mode, the documented `useBigInt` result distinguishes Firestore integers from doubles before JSON serialization. The local export contract encodes timestamps as seconds/nanoseconds, integers as canonical signed int64 decimal strings, and finite doubles as IEEE-754 binary64 bits. Integer versus double remains explicit even when both would be rendered as the same JavaScript number (for example, `7`); negative zero is preserved. Unclassified numbers and unsupported values fail closed. Synthetic tests exercise both signed integer limits, values beyond JavaScript's safe range, integral-valued doubles, nested arrays/maps, and JSON serialize/deserialize round trips.

Export validation must fail closed on values whose source semantics are not encoded and tested. At minimum:

- `GeoPoint`, `DocumentReference`, Firestore `Bytes`/Blob, vector values, and unknown SDK classes are unsupported by the export contract. Do not serialize them as empty maps, strings, coordinates, or guessed sentinels. Count a safe type code in inventory and stop export or quarantine the whole source record in a separately approved lossless representation; never omit the field silently.
- Timestamp descriptors require safe integer seconds and integer nanoseconds in `[0, 1_000_000_000)`, and each descriptor must point to a present corresponding value placeholder. Orphan, duplicate, malformed, or unsupported descriptors fail validation.
- Integer/Double distinction, large integer precision, non-finite numbers, custom classes, and cyclic values need explicit handling. JSON cannot represent cycles or `NaN`/infinities; do not stringify them to lossy values. Fail before writing an export file if a value is unsupported or cannot round-trip.
- Firestore `null`, missing property, and an absent document are distinct states. Preserve each separately.

The read-only inventory adapter can replace unsupported fields with an inventory sentinel while counting their type; that behavior is for structural inventory only. The export serializer rejects the sentinel and any non-JSON SDK class. Such a snapshot is not a lossless export and must never be passed to the migration planner as if source values were preserved. No GeoPoint, DocumentReference, Bytes/Blob, or unknown-class conversion is defined here.

## 4. Identity, relationships, and business-field validation

Validation is diagnostic only. It must not mutate export data or infer identities.

- Require nonempty, unique Firestore document IDs within each collection and unique activity document IDs within their parent group. Detect duplicate embedded expense and settlement IDs per group, plus missing IDs; report safe issue codes and block any projection that requires those IDs.
- Preserve `users/{uid}` identity and any source `data.uid`. The planner's current invariant requires them to agree when `data.uid` is present. Preserve username document IDs and validate each username's `data.uid` resolves to an exported user; detect incompatible duplicate username claims rather than selecting a winner.
- Preserve `groups/{groupId}.data.createdBy`, `members[]`, `memberUids[]`, `memberEmails[]`, `memberUsernames[]`, and `memberIdentities[]` independently and in order. Check creator/member/identity references against stable user UIDs and report unresolved edges. Never pair parallel arrays by index; offline members and array drift make that ambiguous. Names, email addresses, and usernames are not stable authorization identities.
- Preserve each expense's original fields, ID, amount, payer name, split list, split type, custom split map, date and optional fields. Check structural validity and duplicate/missing IDs. Custom split map keys and values must be preserved exactly; do not recalculate totals or infer payer UIDs from names.
- Preserve each settlement and its original aliases. The local planner maps `from` to `fromUser` and `to` to `toUser` only when canonical fields are absent, rejects conflicting/malformed aliases, and preserves the original archived source. Export validation should report alias presence/conflicts separately and must not canonicalize the source JSON.
- Preserve each activity document ID and all data/metadata. When an activity includes `groupId`, validate it matches the containing group; absent `groupId` remains absent rather than being injected into the export.

## 5. Count validation and privacy-safe report

The export's count manifest must exactly match recomputed counts. Validation should also confirm:

1. Every configured collection exists as an array and every group has an activities array.
2. Total document count equals `users + usernames + groups + activities`.
3. Embedded expense and settlement counts equal the sum across all group documents.
4. No duplicate/missing IDs, malformed records, unresolved required UID relationships, unsupported value types, or type-manifest inconsistencies remain unreported.
5. Pagination reached the end of every audited source path and no limit/read/serialization error occurred. Otherwise status is incomplete and no complete export is emitted.

Export status, serialization fidelity, and projection readiness are separate fields. A complete source export reports `exportStatus: complete` and `serializationFidelityStatus: faithful`. Projection readiness is either `blocked_known_source_issues` (for unresolved relationships, ambiguous display-name parties, or conflicting settlement aliases detected by the source-only checks) or `not_assessed`; it is never reported as migration-ready by this exporter. Unsupported source types fail export and produce no complete artifact. They also block future projection until an explicit lossless encoding is approved.

The validation report must contain only aggregate values, for example:

```json
{
  "reportType": "samvibhag-export-validation-v1",
  "exportStatus": "complete",
  "serializationFidelityStatus": "faithful",
  "projectionReadinessStatus": "not_assessed",
  "scope": "audited_firestore_paths_only",
  "pointInTimeConsistent": false,
  "counts": { "users": 0, "usernames": 0, "groups": 0, "activities": 0, "expenses": 0, "recordedSettlements": 0, "documentsIncludingActivities": 0 },
  "countManifestMatches": true,
  "projectionIssueCounts": { "unresolvedUidRelationships": 0, "ambiguousExpenseParties": 0, "ambiguousSettlementParties": 0, "conflictingSettlementAliases": 0, "activityGroupMismatches": 0 },
  "issueCodes": [],
  "containsRecordValues": false
}
```

Allowed report content: fixed scope labels, status values, aggregate counts, and allowlisted diagnostic codes. Do not include document IDs, personal values, source paths containing IDs, arbitrary field/map keys, exception messages, credentials, tokens, per-record hashes, or export file paths. The actual JSON export necessarily contains source records and is sensitive; it must be stored locally with access controls and must not be confused with the aggregate validation report. A failed export reports `incomplete`; fidelity is `blocked` for unsupported or malformed source values, `unverified` for source-read/limit failures, and `not_published` for artifact-publication failures. Projection readiness is `blocked` only when source blockers are known, otherwise `not_assessed`. It never reports `complete` with skipped records.

## 6. Failure-safe local publication

The synthetic utility accepts only the checked-in synthetic fixture names under `fixtures/`; it does not accept database clients, credentials, arbitrary source paths, or network callbacks. It applies the fixed caps of 10,000 Firestore documents including activities, 256 KiB per document/activity record, and 16 MiB total serialized source data. Limits may be lowered for local tests but not raised.

Publication stages `export.json` and a pending marker in a temporary directory under `output/synthetic-exports/` after source reading, serialization, JSON parse-back, and type/count/relationship validation succeed. The completion marker contains the export format version, aggregate validation results, exact export byte length, and SHA-256 of the export bytes. Publication validates the parsed artifact before publishing, then exclusively creates the final directory (so a racing pre-existing destination cannot be overwritten), moves the staged files into that markerless directory, and publishes `complete.json` as the final atomic step. `readPublishedSyntheticExport(exportId)` is the shared reader: it rejects unsafe IDs, temporary directories, missing markers, extra files, malformed/tampered markers, integrity mismatches, truncated JSON, invalid type manifests, and count mismatches with stable error codes. It recomputes export counts/statuses and compares them with the marker before returning source data. Caught failures remove staging or an unpublished directory created by this run and emit only a stable code. Tests inject validation mutation, pre-marker failure, destination collision, marker removal/tampering, export modification/truncation, count mismatch, and malformed type metadata. A real process interruption may leave a `.tmp-*` directory, or a final directory without `complete.json`; the reader rejects both. A crash after the marker's atomic rename leaves the fully validated pair, subject to the local filesystem's durability behavior. Production consumers must revalidate the artifact and separately establish source consistency.

The existing adapter aborts on a page failure and returns no partial snapshot. Synthetic tests also inject a partial-page failure and verify no final artifact is published. A read-freeze or change-capture method is still required before any live process can claim a coherent source snapshot.

## 7. Synthetic-only implementation and test plan

The local contract module is implemented, but it is not a live exporter. It consumes only synthetic fixture snapshots and contains no Firebase imports or network/credential code. It must not be extended to accept live Firestore clients without a separate approval and security review.

Synthetic tests should cover:

- exact export shape for empty and populated collections, stable document IDs, group activities, embedded expense/settlement preservation, nested maps, optional fields, explicit null, and array order;
- timestamp seconds/nanoseconds and numeric type-manifest round trips;
- safe and large integer decimal preservation, integral-valued double distinction, negative zero, and failure when source numeric kind/value metadata is absent;
- duplicate/missing document, activity, expense, and settlement IDs; malformed count manifests; count arithmetic and count mismatch;
- stable UID relationships, offline members, duplicate display names, independent member arrays, orphan username/group/activity references, and no positional UID inference;
- custom split values and settlement aliases preserved; conflicting/malformed aliases fail closed;
- GeoPoint, DocumentReference, Bytes, unknown classes, invalid numeric values, and malformed/orphan type descriptors cause a safe failure without losing a source field;
- privacy-safe reports on success and failure: no record data, IDs, personal values, arbitrary keys, paths, secrets, or raw exception text;
- injected failures during source read, serialization, validation, artifact write, completion-manifest write, and final publication never leave a final directory that appears complete;
- configured per-record, total-byte, and document-count limits fail before publication.

These tests can establish local serializer/validator behavior only. They cannot establish production record counts, permissions, schema, size, coherent point-in-time consistency, RTDB layout safety, or deployed rule behavior.

## 8. Assumptions and unresolved decisions

- Audited Firestore scope remains `users`, `usernames`, `groups`, and `groups/{groupId}/activities`; no live inventory has verified that production contains no other relevant collections/subcollections.
- The current adapter fixture format is an input shape, not itself the durable export format. The new format is synthetic-tested; it has not been populated from production.
- It is unresolved whether active data belongs at top-level `/samvibhag/v1` collections or remains run-scoped below `migrationRuns/{runId}`; no destination layout was selected here.
- Numeric distinction now uses the documented public `useBigInt` setting, gated to the locally verified SDK version. A real SDK integration test is still outstanding; synthetic fake values cannot establish the SDK's runtime settings behavior or production-data fidelity. Custom converters remain unsupported for claims of source fidelity unless separately verified.
- Production schema variants, unsupported Firestore values, RTDB contents and size, concurrent writes, backup/retention obligations, and a consistent source snapshot method require authorized verification.
- A local successful JSON validation would establish only structural consistency of that particular export, not authorization to write, migrate, deploy, or cut over.
- Milestone 7.0's emulator-only SDK verification contract, write-freeze versus change-capture comparison, and pre-export operational gate are documented in [milestone-7-sdk-consistency-preflight.md](milestone-7-sdk-consistency-preflight.md). The Firebase CLI and Emulator Suite are not currently configured or installed here; actual SDK decoding remains unverified.
