# SamVibhag Firestore → Realtime Database proposal — Milestone 2

Status: proposal for review only; derived from local code and `firestore-to-realtime-database-audit.md`. No production Console inspection, data write, migration execution, rules deployment, code cutover, or remote Git operation has occurred. This is not an approved production write plan.

## 1. Proposed logical JSON tree

Use an application-versioned namespace so unrelated/existing RTDB root data is not merged or replaced by default. The proposed namespace is `/samvibhag/v1`; its availability must be checked read-only in Firebase Console first. Each example below is a decoded logical view. The migration transport layer must encode values and keys that RTDB JSON cannot directly represent (see type/key policy).

```json
{
  "samvibhag": {
    "v1": {
      "users": {
        "{authUid}": {
          "profile": {
            "uid": "{authUid}",
            "email": "person@example.invalid",
            "displayName": "Person",
            "username": "person_1",
            "usernameSearch": "person_1",
            "phoneNumber": "+910000000000",
            "currencyCode": "INR",
            "createdAt": { "__type": "firestoreTimestamp", "seconds": 0, "nanoseconds": 0 }
          }
        }
      },
      "usernames": {
        "{normalizedUsername}": { "uid": "{authUid}", "username": "{normalizedUsername}" }
      },
      "groups": {
        "{groupId}": {
          "data": {
            "id": "{groupId}", "name": "Trip", "groupName": "Trip",
            "createdBy": "{creatorAuthUid}", "createdAt": "original timestamp value"
          },
          "memberUidOrder": { "000000": "{uid}", "000001": "{uid}" },
          "memberUids": { "{uid}": true },
          "memberNames": { "000000": "Display Name", "000001": "Offline Person" },
          "memberEmails": { "000000": "person@example.invalid" },
          "memberUsernames": { "000000": "person_1" },
          "memberIdentities": {
            "{uid}": { "uid": "{uid}", "name": "Display Name", "identityStatus": "verified" }
          },
          "expenses": {
            "{safeExpenseKey}": {
              "sourceId": "original expense id", "title": "Meal", "amount": 1200.0,
              "paidBy": "Display Name", "splitBetween": ["Display Name"],
              "date": "original ISO-8601 string", "category": "Food",
              "splitType": "equal", "customSplits": { "encoded map keys": "see key policy" }
            }
          },
          "recordedSettlements": {
            "{safeSettlementKey}": {
              "sourceId": "original settlement id", "fromUser": "Debtor",
              "toUser": "Creditor", "amount": 250.0, "isSettled": true,
              "settledAt": "original ISO-8601 string"
            }
          },
          "activities": {
            "{safeActivityId}": {
              "id": "original activity id", "groupId": "{groupId}",
              "type": "expense_created", "performedByUid": "{uid}",
              "performedByName": "Person", "message": "...",
              "timestamp": { "__type": "firestoreTimestamp", "seconds": 0, "nanoseconds": 0 },
              "metadata": { "...": "..." }
            }
          }
        }
      },
      "userGroups": { "{uid}": { "{groupId}": true } },
      "migrationRuns": {
        "{runId}": {
          "manifest": { "state": "staging", "sourceProjectId": "samvibhag-a2299" },
          "sourceArchive": { "...": "immutable encoded Firestore source snapshots" },
          "verification": { "...": "counts and hashes; no personal field dumps" }
        }
      }
    }
  }
}
```

`data`/`profile` retain the source fields and their original names. Child paths and the `userGroups` index are access/query projections, not replacements for source fields. Source-preserving migration snapshots are kept separately under a unique run ID and must be protected from client writes. `migrationRuns` is a proposed temporary operational archive; retention and whether it belongs in the same RTDB instance or a separately encrypted backup store require approval and live-instance review.

`memberUidOrder` and the ordered member-name/email/username lists preserve the arrays independently and in order. They intentionally do not imply positional relationships. `memberUids` is an authorization lookup index. `memberIdentities` is populated only from an existing explicit UID/name identity record or a verified, unambiguous migration; it is not synthesized by joining parallel arrays except under the constrained legacy rule below. Do not create fake Authentication UIDs for offline members.

The destination path key encoder must be reversible and deterministic. Firestore document IDs, usernames, UIDs, or dynamic map keys that contain RTDB-forbidden key characters (`.`, `#`, `$`, `/`, `[`, `]`, control characters) must not be used raw as RTDB keys. Use a URL-safe reversible encoding (e.g. UTF-8 base64url with a fixed safe prefix) and retain the exact original key/ID in the stored record. To avoid an encoded key colliding with a legal original key, reserve the encoding prefix and encode any original key beginning with that prefix too. This applies recursively to arbitrary maps such as `customSplits` and flexible activity metadata. Reject collisions after encoding and verify decode(encode(key)) equals the source key.

Missing fields remain absent. Explicit Firestore `null` needs an explicit tagged-null envelope because writing `null` to RTDB removes a node. Firestore Timestamp values use the tagged representation above (seconds plus nanoseconds); do not replace the original with only milliseconds. A derived millisecond sort/index field may be added separately and must not be confused with the preserved source value. Firestore int/double values remain numeric in the logical view; exact source numeric kind is retained in the archive/type manifest if SDK JSON serialization would otherwise collapse it. Boolean, string, list order, and nested values are preserved. Any encountered Firestore type not supported by the application (for example reference, geopoint, or bytes) must be represented with a tagged value and reported; unknown values are a stop condition until explicitly mapped.

## 2. Complete source-to-destination mapping

| Firestore source | Proposed RTDB destination | Mapping notes / integrity checks |
|---|---|---|
| `users/{uid}` | `/samvibhag/v1/users/{safe(uid)}/profile` | Preserve Auth UID as `uid` and as source ID. Copy every source field, including optional/unknown fields, through the type-preserving encoder. Keep variants (`phone` and `phoneNumber`, `currency` and `currencyCode`, `avatarLocalPath` and `photoUrl`) separately; do not coalesce them or infer precedence during migration. FCM tokens are personal/security-sensitive; access should be restricted to the owning UID and trusted backend. |
| `usernames/{normalizedUsername}` | `/samvibhag/v1/usernames/{safe(normalizedUsername)}` | Preserve source ID, all fields, `uid` relationship, optional email, and timestamp. Validate no two source documents claim the same UID/username incompatibly; do not resolve by last-write-wins. |
| `groups/{groupId}` group metadata | `/samvibhag/v1/groups/{safe(groupId)}/data` | Copy all fields except separately projected embedded arrays (`expenses`, `recordedSettlements`, member arrays, `memberIdentities`) into `data`; also preserve complete source snapshot in the run archive. Preserve both `name` and `groupName`, `createdBy`, avatar path, timestamps, last-updated fields, and any unknown fields exactly. Do not replace absent fields with model defaults. |
| `groups/{groupId}.members[]` | `/groups/{safe(groupId)}/memberNames/{zeroPaddedSourceIndex}` | Preserve display names independently and in exact order, including duplicates/blank values for audit. No UID is inferred from the corresponding index. |
| `groups/{groupId}.memberUids[]` | `/groups/{safe(groupId)}/memberUidOrder/{zeroPaddedSourceIndex}` and lookup `/userGroups/{safe(uid)}/{safe(groupId)}: true`, `/groups/{safe(groupId)}/memberUids/{safe(uid)}: true` | Preserve ordered source list exactly; use set-like lookups only as projections. Verify every UID remains a stable Auth UID string and creator relation matches source. Duplicate UID occurrences remain in ordered source projection; lookup remains one membership. |
| `groups/{groupId}.memberEmails[]`, `.memberUsernames[]` | `/groups/{safe(groupId)}/memberEmails/{index}`, `/memberUsernames/{index}` | Preserve each array independently; do not pair by index with names/UIDs. Emails are not auth keys. |
| `groups/{groupId}.memberIdentities[]` | `/groups/{safe(groupId)}/memberIdentities/{safe(uid)}` where UID unique; retain exact list in archive | Accept only well-formed entries with nonempty name/UID and unique consistent mapping. If duplicate UID maps to differing names or same name maps to multiple UIDs, mark unresolved and block settlement authorization for that member. Never overwrite identity conflicts. |
| `groups/{groupId}.expenses[]` | `/groups/{safe(groupId)}/expenses/{safe(expense.id)}` | Preserve expense ID and all fields (`title`, `amount`, `paidBy`, `splitBetween`, `date`, `category`, `splitType`, `customSplits`, unknown fields). Encode dynamic split-map keys reversibly. Keep display-name parties unchanged. Do not infer/persist `payerUid` unless a separately verified member identity exists; if later needed, store it as an explicitly derived field with provenance, not as a source field. Duplicate/missing IDs: keep original array entry in immutable run archive and stop active projection pending a stable, deterministic, documented record key; never silently overwrite. |
| `groups/{groupId}.recordedSettlements[]` | `/groups/{safe(groupId)}/recordedSettlements/{safe(settlement.id)}` | Preserve ID, `fromUser`, `toUser`, `amount`, `isSettled`, optional `settledAt`, aliases as originally stored, and unknown fields. Do not infer payer UID from creator, name, or expense author. Missing/duplicate IDs remain archived and block active projection pending resolution; the model currently may generate a random UUID while parsing an absent ID, which must not be mistaken for a source ID. |
| `groups/{groupId}/activities/{activityId}` | `/groups/{safe(groupId)}/activities/{safe(activityId)}` | Preserve document ID, all fields, metadata, timestamp, and group relationship. Keep deterministic historical IDs as-is. Encode arbitrary metadata keys/values. Check that IDs remain unique after safe-key encoding. |
| Auth users/providers | Not copied into RTDB | Firebase Authentication remains independent and is not changed. RTDB uses Auth UIDs for authorization. Validate UID references against Auth only using authorized, read-only Admin inspection in a later approved process; never migrate passwords, provider credentials, or delete/create auth users. |
| Firebase Storage | No application records found using Firebase Storage APIs | Do not copy or delete Storage objects based on the dependency alone. Group avatar URLs are Cloudinary URLs or local paths. Whether production Storage contains relevant data remains an unresolved Console question. |
| Cloudinary group images | Keep `avatarPath`/URL string in group data unchanged | Images are external to Firestore/RTDB; no image upload/copy/delete is part of this database migration. Verify URL accessibility and ownership separately if desired. |
| FCM tokens | Remain in `users/{uid}/profile/fcmTokens` (logical source field) | Preserve values only for authenticated owner/trusted notification backend. Do not log tokens in migration report. Existing Function uses them for push delivery. |
| Hive `samvibhag_storage/isDarkMode` | Not migrated | Local device UI preference, not Firestore data. Preserve local behavior; do not move user device settings as part of cloud data migration. |
| Migration run metadata | `/samvibhag/v1/migrationRuns/{runId}` or encrypted external manifest | Store run state, counts, hashes, errors by source path/doc ID (minimize PII), and archive pointers. Never store service-account credentials or access tokens. Prefer encrypted external archive when RTDB permissions/size make in-database archive unsuitable. |

No separate invitations collection, standalone expenses/settlements collection, or app-owned Storage object path was found in local code. This is a code-search result only; production-only paths may exist and must be checked read-only.

## 3. Membership and identity resolution

1. Preserve `createdBy` as the group creator Auth UID. Preserve `memberUids` as the authoritative source membership UID list; do not grant access from display name, email, or username.
2. Create membership lookup indexes only from actual source `memberUids[]`, plus creator UID only if the application’s existing membership semantics explicitly treat the creator as a member. Record any creator-not-in-memberUids discrepancy; do not silently modify the original source list.
3. Use existing `memberIdentities` entries as mappings only when structurally valid and unique. Validate that UID appears in the group membership set or is the creator. Retain contradictory source entries in the source archive and report them.
4. **Do not infer identity from parallel arrays, even when their lengths happen to match.** The app can add offline names without adding a UID, so equal lengths do not prove positional correspondence. A legacy group without explicit `memberIdentities` has no safe display-name-to-UID mapping for this migration. Leave it unresolved and fail closed for member settlement authorization until a separately reviewed, authoritative mapping is supplied.
5. Email/username arrays are never used to infer identity. Duplicate display names, offline members, missing UIDs, array drift, or conflicting identity mappings remain unresolved. Preserve their source positions and values; do not collapse duplicates in the audit/archive.
6. Expense payer (`paidBy`) and settlement parties (`fromUser`/`toUser`) remain source display-name values. In the existing balance calculation, settlement `fromUser` is the debtor/responsible payer and `toUser` is the creditor; neither is inferred from the expense creator or payer field. A UID authorization projection is made only through a verified group identity entry. For settlement rules/callables, unresolved payer UID means fail closed for that member; group-creator override remains keyed to `createdBy`.

## 4. Data preservation, destination protection, and repeatable run design

### Destination isolation

- First inspect RTDB instance URL, rules, and existing root data read-only. Do not create an instance or write any path during this milestone.
- Before an approved write run, export the entire existing destination to an access-controlled, encrypted backup and record its size/hash. Check whether `/samvibhag/v1` already exists. If it does, do not merge or overwrite it; stop and propose a fresh instance or a newly approved, unique staging namespace.
- Each approved attempt gets a unique `runId` and its own absent `/samvibhag/v1/migrationRuns/{runId}` staging tree or separately configured empty staging instance. The production namespace must never be overwritten by default. Write only deterministic paths under the run's isolated namespace until verified.
- For retries, compute a canonical source-record hash. If destination path is absent, write it. If present with the identical hash, count as already completed and skip. If present with a different hash, stop that record/run and report a conflict; never use blind `set()` overwrite as retry behavior.
- A later cutover projection into `/samvibhag/v1` is a separately approved action with a full RTDB backup, absent-target checks, and an explicit merge/activation procedure.

### Repeatable migration tool design (not implemented or run)

Prepare a Node.js Admin SDK utility using supported Firebase Admin APIs and Application Default Credentials or an explicitly approved secure local credential mechanism. Never embed service-account files in the client/app bundle or print credentials. Default command mode is dry-run and read-only. A production destination mode must require a separate explicit command flag and prior user approval; no such mode has been executed or authorized here.

1. Read Firestore collections `users`, `usernames`, `groups` in document-ID order with bounded pages (`limit` + `startAfter(lastDocument)`), never a single unbounded query. For each group, read its `activities` subcollection the same way. Embedded group arrays are read with their parent group document.
2. Convert each document recursively using the timestamp/null/special-type and safe-key policy. Preserve document IDs. Validate stable relationships and duplicate keys before any destination write. Malformed records and unresolved references become explicit errors; required-record errors fail the run rather than being silently skipped.
3. Produce a dry-run manifest with counts, source paths, key collisions, duplicates, unresolved references, projected bytes, and deterministic hashes. Use synthetic sample fixtures for development; no production write tests.
4. After approval and a separately authorized backup, use bounded RTDB multipath writes to deterministic run-scoped paths. A write journal records source path + source doc ID + checksum + status; logs must not contain profile values, FCM tokens, email/phone values, or credentials. Retry transient network errors with capped exponential backoff and jitter. Permanent validation/permission/conflict errors halt; do not skip and continue as if complete.
5. Support restart/resume by re-reading source and comparing source hash to journal/destination hash. If source changed since its recorded hash, flag it for delta processing; do not overwrite a changed destination blindly.
6. Verify destination by reading each expected path and checking ID, mapped fields, types, hashes, relationship edges, and counts. Check for unexpected records only within the isolated run namespace. Produce a local report with examined/written/skipped-identical/failed counts, missing/extra paths, mismatches, unresolved relations, and final `PASS` only if all required checks are clean. Never print `PASS` from request success alone.
7. Verify permissions separately with Firebase Emulator Suite. Test owner/self user reads/writes, cross-user denial, member group access, nonmember denial, creator rights, blocked self-membership grant, settlement payer/creator allow, unrelated member settlement deny, activity isolation, and callable auth/UID checks.

Pagination, batch sizes, API limits, and actual expected counts are to be fixed only after live inventory and a dry-run against the actual source size. The utility design does not imply permission to run it against production.

## 5. Timestamp and Firestore-value policy

- Preserve Firestore `Timestamp` as an explicit tagged value containing integer `seconds` and `nanoseconds`; optional `epochMillis` is derived solely for ordering/query support and is never the archival value.
- Preserve ISO-8601 strings such as current model-serialized expense dates and settlement times byte-for-byte (after confirming UTF-8 string equality). Do not normalize timezone suffix, precision, or missing/null to a current time.
- Preserve numeric epoch/time values as numbers with their source type metadata. Do not convert timestamps based only on field names.
- Keep missing fields absent. Represent explicit Firestore `null` as a tagged-null object in RTDB and restore null when decoding. Keep numeric, Boolean, string, array order, and map entry values typed. Record int/double source kind where SDK serialization would lose the distinction.
- Firestore server timestamp sentinels should not appear in a completed persisted document read. If any unresolved sentinel is encountered in source extraction, stop or reread after commit; do not replace it with migration time.
- Firestore document references, geopoints, bytes, and any unknown native value use tagged, lossless encodings only if implemented and round-trip tested; otherwise mark unsupported and stop. No conversion should silently stringify or drop values.

## 6. Concurrent writes, backup, and rollback

The local application currently has no migration change log, no uniform group `updatedAt`/version field, and no Firestore→RTDB dual-write. Group expenses and settlements are embedded arrays and can be replaced by client updates; activity events are separate writes. Therefore a long-running scan cannot be assumed to represent one consistent point in time, and a timestamp-only delta would be unsafe.

Safe options, to decide after live review:

- **Preferred minimal-risk first migration:** prepare and verify an immutable baseline while Firestore remains primary. Before taking the final consistent snapshot, enter a documented write freeze for app mutations (including auth/profile, group, expenses, settlements, member changes, and activity writers); drain in-flight clients/functions; record a cutoff; read the source; then verify. Resume Firestore writes only when the app remains Firestore-backed. This avoids missed-write gaps but requires an operational maintenance window and cannot support uninterrupted migration.
- **If zero-downtime is required:** first design and test an explicit durable change-capture/outbox or carefully ordered dual-write path with idempotency/versioning, failure handling, and reconciliation. This requires a separate local implementation/review milestone and approval before any production deployment. Existing code does not supply this mechanism.

Before any production write, export a read-only Firestore backup using an official supported export/backup process, with manifest, counts, retention/access controls, and verification. Also back up any existing RTDB content before proposing a destination. Keep immutable source exports, hashes, migration logs, and destination run data. Firestore is not deleted or modified by the proposed copy.

Rollback is not just changing an app URL if RTDB has accepted new writes. Keep Firestore untouched and read-only as a recovery snapshot until reviewed; keep RTDB and post-cutover writes intact. To resume the old Firestore app without losing RTDB-era changes, require a separately reviewed, approved, verified reverse-reconciliation/replay process, or keep the new data available from RTDB until replay is approved. Do not discard RTDB changes or claim lossless rollback without verified replay. No production dual-write, freeze, restore, or reverse migration is authorized by this proposal.

## 7. Security Rules and Cloud Functions compatibility plan

- Preserve Authentication as the identity provider; use `auth.uid` only. Keep user profile paths owner-only, with narrowly scoped trusted access for lookup/notifications as actually required. Do not expose all profile fields to all authenticated users to support username search.
- Build RTDB authorization from trusted `/groups/{gid}/memberUids/{uid}` and creator `groups/{gid}/data/createdBy` fields. Clients must not write these authority indexes directly. Only approved callable/backend code can add/remove membership and atomically update `/userGroups` and group membership indexes. Rules must prevent a user from granting themselves access or changing `createdBy`.
- General group reads/writes should require group membership and preserve current intended business operations. Evaluate each child path separately; no broad root-level authenticated read/write. Activity write policy should match current immutable activity intent, while trusted backend settlement logs remain server-owned.
- Settlement payer authorization cannot be proven from a display name in a client rule. A trusted callable should resolve `fromUser` through the verified UID identity projection and verify current membership; authorize that payer or the group creator; recompute/validate settlement details server-side; then apply one atomic RTDB multipath update to settlement state and activity. Unresolved mapping denies the payer action. Preserve creator override. This replaces existing Firestore Admin callables only after separate implementation/testing approval.
- Reimplement the existing `notifyOnMemberAdded` Firestore trigger as an RTDB trigger only if its semantics remain needed, driven by trusted membership writes and excluding the actor. Preserve FCM token privacy and remove client-bundled privileged credentials in a separately approved security remediation; do not migrate service account credentials into RTDB.
- Current functions `addGroupMember`, `migrateGroupMemberIdentities`, `manageSettlement`, and `deleteGroup` use Admin Firestore, and the group create/delete workflows also have direct Firestore client code. They remain active Firestore code until a complete replacement/cutover is approved. The local Firestore rules and deployed rules are not confirmed identical. No rules or functions are deployed under this plan.
- Compile and exercise proposed RTDB rules in Emulator Suite against the same tested cases before any deploy. Production rules, indexes, database URL, Cloud Function region/runtime and existing triggers must be inspected in Console first.

## 8. Tests to perform before any production migration

No migration tool exists yet and no tests were run for this documentation-only milestone. Later non-production tests should use synthetic fixtures and Firebase Emulator Suite (Auth, Firestore source, RTDB destination, Functions) rather than production data. Include:

- Round-trip source-value encoder/decoder tests: timestamps with nanos, strings, null versus absent, nested maps with forbidden RTDB key characters, arrays/order, numeric types, booleans, metadata, unknown values, and safe ID encoding/collision.
- Synthetic end-to-end fixture containing one user, username, group, registered and offline members, an ambiguous/duplicate name, expense with custom splits, settled and pending settlement records, activities, optional fields, and mixed timestamp forms.
- Pagination boundary, retry after partial write, identical-hash resume, conflicting-hash abort, duplicate/missing ID abort, invalid reference, and malformed source tests.
- Count/hash and relation verifier tests including orphaned membership indexes, missing users, ambiguous identities, duplicate IDs, and unexpected destination records.
- RTDB Emulator security tests listed above, plus callable tests for unauthenticated, nonmember, creator, payer, ambiguous payer, and forged membership inputs.
- Application integration tests for auth/profile lookup, group list isolation, expense create/edit/delete, ordered history, settlement/balance parity, reconnect/retry, and complete path absence from active Firestore after a future approved code cutover.

## 9. Read-only live Console questions still unresolved

Before finalizing this design or authorizing a production write, inspect project `samvibhag-a2299` in Firebase Console with read-only access and answer:

1. Does the authenticated account have access to this exact project? Which Firebase project is selected?
2. What is the RTDB instance URL/region? Does an RTDB instance already exist; what top-level paths/data and deployed rules exist? Is `/samvibhag/v1` absent?
3. What Firestore database location is used? What are actual counts and field variants for `users`, `usernames`, `groups`, and every `groups/*/activities` subcollection? Are there additional root collections/subcollections or production-only fields not found in code?
4. Are there missing/duplicate IDs, conflicting names/UID mappings, group creator/member discrepancies, malformed records, active writes, or other clients/versions still writing Firestore?
5. What Firestore rules and indexes are deployed? Do they differ from local `firestore.rules`? Are there Rules/Functions side effects or other writers not represented in this repository?
6. Which Cloud Functions, triggers, regions, schedules, runtimes, and versions are deployed? Are any third-party integrations or scheduled processes reading/writing these paths?
7. Which Auth providers are enabled? Are there provider-specific UID or profile-field cases that need preserve-only mapping?
8. Does Firebase Storage contain app data despite no local SDK call? Are Cloudinary images or any external integrations expected to be migrated?
9. What backup/export method, access policy, retention period, maintenance window, and allowed downtime are available? If a migration has concurrent changes, who can freeze all writers and how are stale clients handled?
10. Is there a requirement to use the default RTDB root, a new instance, or this versioned namespace? Existing RTDB users or other apps might already depend on root paths.
11. How should records with no stable ID, unmapped/offline members, duplicate display names, or unsupported Firestore values be handled? Default proposal is fail the active projection and request resolution while preserving exact source archive.
12. Who should have access to the encrypted source and destination backups and for how long? Exports contain personal profile fields and FCM tokens.

## 10. Gate / decision requested

This document proposes a versioned, isolated, type-preserving structure and a source-preserving staged migration. It intentionally does not select a production instance or execute any step. Please review the schema, mapping, timestamp and identity policy, and concurrency/rollback strategy. Live Console verification remains outstanding because Computer Use is unavailable. I will stop here pending your review and explicit approval before Milestone 3 or any production-write preparation.
