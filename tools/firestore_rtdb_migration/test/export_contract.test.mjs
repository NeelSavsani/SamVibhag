import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION, readFirestoreSnapshot } from '../read_only_adapters.mjs';
import {
  buildJsonExport,
  ExportContractError,
  publishSyntheticExport,
  publishSyntheticFixtureExport,
  readPublishedSyntheticExport,
  readSyntheticFixture,
  restoreJsonExport,
  safeExportFailure,
  syntheticExportPaths,
  validateJsonExport,
} from '../json_export.mjs';

const syntheticFixturePath = path.join(syntheticExportPaths.fixtureRoot, 'export-contract-source.json');
const clone = (value) => structuredClone(value);
const rejectsCode = (operation, code) => assert.throws(operation, (error) => error instanceof ExportContractError && error.code === code);

test('versioned export preserves source IDs, nested JSON, activities, and missing versus null', () => {
  const prepared = buildJsonExport(readSyntheticFixture(syntheticFixturePath));
  const source = prepared.export;
  assert.equal(source.format, 'samvibhag-firestore-json-export-v1');
  assert.equal(source.collections.users[0].id, 'user_doc_1');
  assert.equal(source.collections.users[0].data.uid, 'user_doc_1');
  assert.equal(source.collections.groups[0].id, 'group_source');
  assert.equal(source.collections.groups[0].data.id, 'embedded_group_field_is_distinct');
  assert.equal(Object.hasOwn(source.collections.users[0].data, 'fieldThatWasMissing'), false);
  assert.equal(source.collections.users[0].data.explicitNull, null);
  assert.deepEqual(source.collections.users[0].data.nested, { list: ['first', null, { value: 'last' }] });
  assert.equal(source.collections.groups[0].subcollections.activities[0].id, 'activity_source');
  assert.equal(source.collections.groups[0].subcollections.activities[0].data.id, 'embedded_activity_field_is_distinct');
  assert.equal(source.collections.groups[0].data.expenses[0].customSplits['Offline Member'], '4.25');
  assert.equal(source.collections.groups[0].data.recordedSettlements[0].from, 'Offline Member');
  assert.equal(prepared.validation.exportStatus, 'complete');
  assert.equal(prepared.validation.serializationFidelityStatus, 'faithful');
  assert.equal(prepared.validation.projectionReadinessStatus, 'not_assessed');
});

test('numeric manifest distinguishes safe integers, large exact integers, and doubles across JSON round trips', () => {
  const prepared = buildJsonExport(readSyntheticFixture(syntheticFixturePath));
  const reparsed = JSON.parse(JSON.stringify(prepared.export));
  const restored = restoreJsonExport(reparsed).collections;
  const user = restored.users[0].data;
  assert.equal(user.safeInteger, 7n);
  assert.equal(user.exactLargeInteger, 9007199254740993n);
  assert.equal(user.floatingValue, 7);
  assert.equal(restored.groups[0].data.expenses[0].amount, 12.5);
  const numericTypes = reparsed.typeManifest.filter(({ type }) => type === 'Integer' || type === 'Double');
  assert.deepEqual(numericTypes.map(({ type }) => type), ['Double', 'Integer', 'Double', 'Double', 'Integer']);
  assert.equal(numericTypes.find(({ pointer }) => pointer.endsWith('/exactLargeInteger')).integerDecimal, '9007199254740993');
  assert.equal(numericTypes.find(({ pointer }) => pointer.endsWith('/floatingValue')).ieee754Hex, '401c000000000000');
  assert.equal(numericTypes.find(({ pointer }) => pointer.endsWith('/negativeZero')).ieee754Hex, '8000000000000000');
  assert.equal(Object.is(user.negativeZero, -0), true);
});

test('adapter numeric values without captured type descriptors fail closed', () => {
  const snapshot = readSyntheticFixture(syntheticFixturePath);
  delete snapshot.types['/users/user_doc_1/data/floatingValue'];
  rejectsCode(() => buildJsonExport(snapshot), 'numeric_type_unverified');
});

test('read-only adapter output is not assigned missing integer type information by the exporter', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = {
    orderBy() { return this; }, limit() { return this; },
    async get() { return { docs: [{ id: 'synthetic-user', data: () => ({ uid: 'synthetic-user', balance: 9007199254740992 }) }] }; },
  };
  const snapshot = await readFirestoreSnapshot({ db: { collection: (name) => name === 'users' ? userCollection : emptyCollection } });
  assert.equal(Object.keys(snapshot.types).length, 0);
  rejectsCode(() => buildJsonExport(snapshot), 'numeric_type_unverified');
});

test('adapter uses documented BigInt decoding for exact int64 and double distinction', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = {
    orderBy() { return this; }, limit() { return this; },
    async get() { return { docs: [{
      id: 'synthetic-user',
      data: () => ({
        uid: 'synthetic-user', safeInteger: 7n, exactLargeInteger: 9007199254740993n,
        maxInt64: 9223372036854775807n, minimumInt64: -9223372036854775808n,
        integralDouble: 7, negativeZero: -0, nested: { values: [4, 4] },
      }),
    }] }; },
  };
  const settings = [];
  const db = {
    settings(value) { settings.push(value); },
    collection(name) { assert.deepEqual(settings, [{ useBigInt: true }]); return name === 'users' ? userCollection : emptyCollection; },
  };
  userCollection.get = async () => ({ docs: [{
    id: 'synthetic-user',
    data: () => ({
      uid: 'synthetic-user', safeInteger: 7n, exactLargeInteger: 9007199254740993n,
      maxInt64: 9223372036854775807n, minimumInt64: -9223372036854775808n,
      integralDouble: 7, negativeZero: -0, nested: { values: [4n, 4] },
    }),
  }] });
  const snapshot = await readFirestoreSnapshot({
    db,
    preserveNumericTypes: true,
    firestoreSdkVersion: LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION,
  });
  assert.equal(snapshot.types['/users/synthetic-user/data/exactLargeInteger'].integerDecimal, '9007199254740993');
  assert.equal(snapshot.types['/users/synthetic-user/data/integralDouble'].type, 'Double');
  assert.equal(snapshot.types['/users/synthetic-user/data/integralDouble'].ieee754Hex, '401c000000000000');
  assert.equal(snapshot.types['/users/synthetic-user/data/nested/values/0'].integerDecimal, '4');
  assert.equal(snapshot.types['/users/synthetic-user/data/nested/values/1'].type, 'Double');

  const prepared = buildJsonExport(snapshot);
  const restored = restoreJsonExport(JSON.parse(JSON.stringify(prepared.export))).collections.users[0].data;
  assert.equal(restored.exactLargeInteger, 9007199254740993n);
  assert.equal(restored.maxInt64, 9223372036854775807n);
  assert.equal(restored.minimumInt64, -9223372036854775808n);
  assert.equal(restored.integralDouble, 7);
  assert.equal(Object.is(restored.negativeZero, -0), true);
  assert.equal(restored.nested.values[0], 4n);
  assert.equal(restored.nested.values[1], 4);
});

test('lossless numeric mode rejects unknown SDK versions or unavailable public settings before reads', async () => {
  let collectionCalls = 0;
  const db = { collection() { collectionCalls++; throw new Error('must not query'); } };
  await assert.rejects(
    readFirestoreSnapshot({ db, preserveNumericTypes: true, firestoreSdkVersion: 'unknown' }),
    (error) => error.code === 'unsupported_firestore_sdk_version',
  );
  await assert.rejects(
    readFirestoreSnapshot({ db, preserveNumericTypes: true, firestoreSdkVersion: LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION }),
    (error) => error.code === 'numeric_mode_unavailable',
  );
  assert.equal(collectionCalls, 0);
});

test('decoded JavaScript numbers without public BigInt mode remain untyped and cannot be exported faithfully', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = {
    orderBy() { return this; }, limit() { return this; },
    async get() { return { docs: [{ id: 'synthetic-user', data: () => ({ uid: 'synthetic-user', integerOrDouble: 7 }) }] }; },
  };
  const snapshot = await readFirestoreSnapshot({ db: { collection: (name) => name === 'users' ? userCollection : emptyCollection } });
  assert.equal(Object.keys(snapshot.types).length, 0);
  rejectsCode(() => buildJsonExport(snapshot), 'numeric_type_unverified');
});

test('optional SDK BigInt decoding is reduced only after exact integer capture', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = {
    orderBy() { return this; }, limit() { return this; },
    async get() { return { docs: [{
      id: 'synthetic-user',
      data: () => ({ balance: 9007199254740993n }),
    }] }; },
  };
  const snapshot = await readFirestoreSnapshot({
    db: { settings() {}, collection: (name) => name === 'users' ? userCollection : emptyCollection },
    preserveNumericTypes: true,
    firestoreSdkVersion: LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION,
  });
  const prepared = buildJsonExport(snapshot);
  const restored = restoreJsonExport(JSON.parse(JSON.stringify(prepared.export))).collections.users[0].data;
  assert.equal(restored.balance, 9007199254740993n);
});

test('inventory-only unsupported sentinels cannot be exported as source values', async () => {
  class FakeGeoPoint { constructor() { this.latitude = 12; this.longitude = 34; } }
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = {
    orderBy() { return this; }, limit() { return this; },
    async get() { return { docs: [{ id: 'synthetic-user', data: () => ({ uid: 'synthetic-user', location: new FakeGeoPoint() }) }] }; },
  };
  const unsupportedValues = [];
  const snapshot = await readFirestoreSnapshot({
    db: { collection: (name) => name === 'users' ? userCollection : emptyCollection },
    types: { GeoPoint: FakeGeoPoint },
    unsupportedValues,
  });
  assert.equal(unsupportedValues.length, 1);
  rejectsCode(() => buildJsonExport(snapshot, { unsupportedValues }), 'unsupported_firestore_value');
  rejectsCode(() => buildJsonExport(snapshot), 'unsupported_firestore_value');
});

test('timestamp manifest requires exact null placeholders and valid seconds/nanoseconds', () => {
  const invalidPlaceholder = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  invalidPlaceholder.collections.users[0].data.createdAt = 'not-null';
  rejectsCode(() => validateJsonExport(invalidPlaceholder), 'type_placeholder_mismatch');

  const invalidNanos = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  invalidNanos.typeManifest.find(({ type }) => type === 'Timestamp').nanoseconds = 1_000_000_000;
  rejectsCode(() => validateJsonExport(invalidNanos), 'malformed_timestamp');

  const invalidSeconds = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  invalidSeconds.typeManifest.find(({ type }) => type === 'Timestamp').seconds = 253402300800;
  rejectsCode(() => validateJsonExport(invalidSeconds), 'malformed_timestamp');

  const orphan = readSyntheticFixture(syntheticFixturePath);
  orphan.types['/users/missing_document/data/createdAt'] = { type: 'Timestamp', seconds: 0, nanoseconds: 0 };
  rejectsCode(() => buildJsonExport(orphan), 'orphan_type_descriptor');

  const duplicatedTimestamp = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  const timestampDescriptor = duplicatedTimestamp.typeManifest.find(({ type }) => type === 'Timestamp');
  duplicatedTimestamp.typeManifest.push({ ...timestampDescriptor });
  duplicatedTimestamp.counts.typeDescriptors++;
  rejectsCode(() => validateJsonExport(duplicatedTimestamp), 'duplicate_type_descriptor');

  const malformedPointer = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  malformedPointer.typeManifest.find(({ type }) => type === 'Timestamp').pointer += '~2';
  rejectsCode(() => validateJsonExport(malformedPointer), 'malformed_type_pointer');

  const orphanPlaceholder = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  orphanPlaceholder.typeManifest.find(({ type }) => type === 'Timestamp').pointer = '/users/user_doc_1/data/missingTimestamp';
  rejectsCode(() => validateJsonExport(orphanPlaceholder), 'orphan_type_descriptor');
});

test('type manifest rejects duplicate pointers, unsupported types, and invalid numeric descriptors', () => {
  const duplicate = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  duplicate.typeManifest.push({ ...duplicate.typeManifest[0] });
  duplicate.counts.typeDescriptors++;
  rejectsCode(() => validateJsonExport(duplicate), 'duplicate_type_descriptor');

  const unsupported = readSyntheticFixture(syntheticFixturePath);
  unsupported.types['/users/user_doc_1/data/explicitNull'] = { type: 'GeoPoint' };
  rejectsCode(() => buildJsonExport(unsupported), 'unsupported_firestore_type');

  const malformedLargeInteger = readSyntheticFixture(syntheticFixturePath);
  malformedLargeInteger.types['/users/user_doc_1/data/exactLargeInteger'].integerDecimal = '9007199254740993x';
  rejectsCode(() => buildJsonExport(malformedLargeInteger), 'integer_exact_value_unverified');
  malformedLargeInteger.types['/users/user_doc_1/data/exactLargeInteger'].integerDecimal = '9223372036854775808';
  rejectsCode(() => buildJsonExport(malformedLargeInteger), 'malformed_integer_descriptor');
});

test('count manifest separates Firestore documents from embedded expense and settlement counts', () => {
  const source = buildJsonExport(readSyntheticFixture(syntheticFixturePath)).export;
  assert.deepEqual(source.counts, {
    users: 1,
    usernames: 0,
    groups: 1,
    activities: 1,
    expenses: 1,
    recordedSettlements: 1,
    firestoreDocumentsIncludingActivities: 3,
    typeDescriptors: 8,
  });
  source.counts.expenses++;
  rejectsCode(() => validateJsonExport(source), 'count_manifest_mismatch');
});

test('duplicate document, activity, expense, and settlement IDs are rejected', () => {
  const cases = [
    (source) => source.collections.users.push(clone(source.collections.users[0])),
    (source) => source.collections.groups[0].subcollections.activities.push(clone(source.collections.groups[0].subcollections.activities[0])),
    (source) => source.collections.groups[0].data.expenses.push(clone(source.collections.groups[0].data.expenses[0])),
    (source) => source.collections.groups[0].data.recordedSettlements.push(clone(source.collections.groups[0].data.recordedSettlements[0])),
  ];
  const codes = ['duplicate_document_id', 'duplicate_activity_id', 'duplicate_expense_id', 'duplicate_settlement_id'];
  cases.forEach((mutate, index) => {
    const source = readSyntheticFixture(syntheticFixturePath);
    mutate(source);
    rejectsCode(() => buildJsonExport(source), codes[index]);
  });
});

test('missing document, activity, expense, and settlement IDs are rejected', () => {
  const cases = [
    (source) => { delete source.collections.users[0].id; },
    (source) => { delete source.collections.groups[0].subcollections.activities[0].id; },
    (source) => { delete source.collections.groups[0].data.expenses[0].id; },
    (source) => { delete source.collections.groups[0].data.recordedSettlements[0].id; },
  ];
  const codes = ['malformed_source_record', 'malformed_activity', 'missing_expense_id', 'missing_settlement_id'];
  cases.forEach((mutate, index) => {
    const source = readSyntheticFixture(syntheticFixturePath);
    mutate(source);
    rejectsCode(() => buildJsonExport(source), codes[index]);
  });
});

test('faithful export can be complete while ambiguous relationships block projection readiness', () => {
  const source = readSyntheticFixture(syntheticFixturePath);
  source.collections.groups[0].data.members.push('Synthetic Alice');
  source.collections.groups[0].data.recordedSettlements[0].fromUser = 'different party';
  const prepared = buildJsonExport(source);
  assert.equal(prepared.validation.exportStatus, 'complete');
  assert.equal(prepared.validation.serializationFidelityStatus, 'faithful');
  assert.equal(prepared.validation.projectionReadinessStatus, 'blocked_known_source_issues');
  assert.ok(prepared.validation.projectionIssueCounts.ambiguousExpenseParties > 0);
  assert.ok(prepared.validation.projectionIssueCounts.conflictingSettlementAliases > 0);
  assert.equal(prepared.export.collections.groups[0].data.recordedSettlements[0].from, 'Offline Member');
});

test('empty collections are explicit and count as zero without double-counting embedded records', () => {
  const source = readSyntheticFixture(syntheticFixturePath);
  source.collections.users = [];
  source.collections.usernames = [];
  source.collections.groups = [];
  source.types = {};
  const prepared = buildJsonExport(source);
  assert.deepEqual(prepared.export.collections, { users: [], usernames: [], groups: [] });
  assert.equal(prepared.export.counts.firestoreDocumentsIncludingActivities, 0);
  assert.equal(prepared.export.counts.expenses, 0);
  assert.equal(prepared.export.counts.recordedSettlements, 0);
  assert.equal(prepared.validation.projectionReadinessStatus, 'not_assessed');
});

test('record, total-byte, and document limits fail before artifact publication', () => {
  const source = readSyntheticFixture(syntheticFixturePath);
  rejectsCode(() => buildJsonExport(source, { limits: { maxRecordBytes: 8 } }), 'source_record_size_exceeded');
  rejectsCode(() => buildJsonExport(source, { limits: { maxRecordBytes: 100_000, maxTotalBytes: 8 } }), 'source_total_size_exceeded');
  rejectsCode(() => buildJsonExport(source, { limits: { maxDocumentsIncludingActivities: 2 } }), 'source_document_limit_exceeded');
  rejectsCode(() => buildJsonExport(source, { limits: { maxRecordBytes: 300_000 } }), 'invalid_export_limits');
});

test('source read counters that do not match serialized document totals fail closed', () => {
  const source = readSyntheticFixture(syntheticFixturePath);
  source.readStats = { recordsRead: 4, estimatedJsonBytes: 10, limits: {} };
  rejectsCode(() => buildJsonExport(source), 'source_read_count_mismatch');
});

test('failed synthetic reads and each artifact publication stage leave no complete artifact', async () => {
  const uniqueId = (suffix) => `synthetic-export-${process.pid}-${suffix}`;
  const assertNoArtifacts = (id) => {
    assert.equal(fs.existsSync(path.join(syntheticExportPaths.outputRoot, id)), false);
    if (fs.existsSync(syntheticExportPaths.outputRoot)) {
      assert.equal(fs.readdirSync(syntheticExportPaths.outputRoot).some((entry) => entry.startsWith(`.tmp-${id}-`)), false);
    }
  };

  const readId = uniqueId('read');
  assert.throws(() => publishSyntheticFixtureExport({ fixturePath: path.join(syntheticExportPaths.fixtureRoot, 'export-contract-malformed.json'), exportId: readId }),
    (error) => error instanceof ExportContractError && error.code === 'fixture_read_failed');
  assertNoArtifacts(readId);

  const partialReadId = uniqueId('partial-read');
  let userPage = 0;
  const pagedUsers = {
    orderBy() { return this; }, limit() { return this; }, startAfter() { return this; },
    async get() {
      userPage++;
      if (userPage === 1) return { docs: [{ id: 'synthetic-user', data: () => ({ uid: 'synthetic-user' }) }] };
      throw new Error('synthetic partial page failure');
    },
  };
  await assert.rejects((async () => {
    const partialSnapshot = await readFirestoreSnapshot({
      db: { collection: (name) => name === 'users' ? pagedUsers : { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } } },
      pageSize: 1,
    });
    publishSyntheticExport(partialSnapshot, { exportId: partialReadId });
  })());
  assertNoArtifacts(partialReadId);

  for (const stage of ['serialization', 'validation', 'write_export', 'write_complete_manifest', 'publish', 'publish_complete_manifest']) {
    const id = uniqueId(stage);
    assert.throws(() => publishSyntheticFixtureExport({
      fixturePath: syntheticFixturePath,
      exportId: id,
      hooks: { [stage]: () => { throw new Error('private synthetic failure details'); } },
    }), (error) => error instanceof ExportContractError && error.code === `stage_${stage}_failed`);
    assertNoArtifacts(id);
  }

  const invalidatedDuringValidationId = uniqueId('invalidated-during-validation');
  assert.throws(() => publishSyntheticFixtureExport({
    fixturePath: syntheticFixturePath,
    exportId: invalidatedDuringValidationId,
    hooks: { validation: (reloaded) => { reloaded.collections.users[0].data.createdAt = 'tampered'; } },
  }), (error) => error instanceof ExportContractError && error.code === 'type_placeholder_mismatch');
  assertNoArtifacts(invalidatedDuringValidationId);

  const beforeCompletionMarkerId = uniqueId('before-completion-marker');
  assert.throws(() => publishSyntheticFixtureExport({
    fixturePath: syntheticFixturePath,
    exportId: beforeCompletionMarkerId,
    hooks: { write_complete_manifest: () => { throw new Error('private marker failure'); } },
  }), (error) => error instanceof ExportContractError && error.code === 'stage_write_complete_manifest_failed');
  assertNoArtifacts(beforeCompletionMarkerId);

  const racedDestinationId = uniqueId('raced-destination');
  const racedDestination = path.join(syntheticExportPaths.outputRoot, racedDestinationId);
  try {
    assert.throws(() => publishSyntheticFixtureExport({
      fixturePath: syntheticFixturePath,
      exportId: racedDestinationId,
      hooks: { publish: () => {
        fs.mkdirSync(racedDestination, { recursive: true });
        fs.writeFileSync(path.join(racedDestination, 'preserve-me.txt'), 'existing');
      } },
    }), (error) => error instanceof ExportContractError && error.code === 'export_artifact_exists');
    assert.equal(fs.readFileSync(path.join(racedDestination, 'preserve-me.txt'), 'utf8'), 'existing');
  } finally {
    fs.rmSync(racedDestination, { recursive: true, force: true });
  }

  const invalidId = uniqueId('bad-snapshot');
  const invalidSnapshot = readSyntheticFixture(syntheticFixturePath);
  delete invalidSnapshot.types['/users/user_doc_1/data/floatingValue'];
  assert.throws(() => publishSyntheticExport(invalidSnapshot, { exportId: invalidId }),
    (error) => error instanceof ExportContractError && error.code === 'numeric_type_unverified');
  assertNoArtifacts(invalidId);
});

test('successful publication validates and restores the full synthetic export', () => {
  const exportId = `synthetic-export-${process.pid}-success`;
  const finalDirectory = path.join(syntheticExportPaths.outputRoot, exportId);
  try {
    const manifest = publishSyntheticFixtureExport({ fixturePath: syntheticFixturePath, exportId });
    assert.equal(manifest.exportStatus, 'complete');
    assert.equal(manifest.serializationFidelityStatus, 'faithful');
    assert.equal(manifest.projectionReadinessStatus, 'not_assessed');
    assert.deepEqual(fs.readdirSync(finalDirectory).sort(), ['complete.json', 'export.json']);
    const complete = JSON.parse(fs.readFileSync(path.join(finalDirectory, 'complete.json'), 'utf8'));
    const exportData = JSON.parse(fs.readFileSync(path.join(finalDirectory, 'export.json'), 'utf8'));
    assert.equal(complete.exportStatus, 'complete');
    const published = readPublishedSyntheticExport(exportId);
    assert.deepEqual(published.validation.counts, complete.counts);
    assert.equal(published.export.format, 'samvibhag-firestore-json-export-v1');
    const decoded = restoreJsonExport(published.export).collections;
    assert.equal(decoded.users[0].id, 'user_doc_1');
    assert.equal(decoded.users[0].data.createdAt.seconds, 1790000000);
    assert.equal(decoded.users[0].data.createdAt.nanoseconds, 123456789);
    assert.equal(decoded.users[0].data.exactLargeInteger, 9007199254740993n);
    assert.equal(Object.is(decoded.users[0].data.negativeZero, -0), true);
    assert.equal(decoded.groups[0].data.recordedSettlements[0].settledAt.seconds, 1790000100);
    assert.equal(decoded.groups[0].data.recordedSettlements[0].settledAt.nanoseconds, 987654321);
    assert.equal(decoded.groups[0].subcollections.activities[0].data.createdAt.seconds, 1790000200);
    assert.deepEqual(validateJsonExport(exportData).counts, complete.counts);
    assert.deepEqual(validateJsonExport(exportData).counts, complete.counts);
  } finally {
    fs.rmSync(finalDirectory, { recursive: true, force: true });
  }
});

test('shared reader requires a valid completion marker and verifies export integrity and manifests', () => {
  const created = [];
  const id = (suffix) => `synthetic-reader-${process.pid}-${suffix}`;
  const publish = (suffix) => {
    const exportId = id(suffix);
    publishSyntheticFixtureExport({ fixturePath: syntheticFixturePath, exportId });
    created.push(path.join(syntheticExportPaths.outputRoot, exportId));
    return path.join(syntheticExportPaths.outputRoot, exportId);
  };
  const refreshIntegrity = (directory) => {
    const exportBytes = fs.readFileSync(path.join(directory, 'export.json'));
    const markerPath = path.join(directory, 'complete.json');
    const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
    marker.exportIntegrity = {
      algorithm: 'sha256',
      bytes: exportBytes.length,
      digest: crypto.createHash('sha256').update(exportBytes).digest('hex'),
    };
    fs.writeFileSync(markerPath, `${JSON.stringify(marker, null, 2)}\n`);
  };

  try {
    assert.throws(() => readPublishedSyntheticExport('.tmp-interrupted'), (error) => error.code === 'temporary_artifact_rejected');
    assert.throws(() => readPublishedSyntheticExport('../outside'), (error) => error.code === 'invalid_export_id');

    const markerless = publish('markerless');
    fs.rmSync(path.join(markerless, 'complete.json'));
    assert.throws(() => readPublishedSyntheticExport(path.basename(markerless)), (error) => error.code === 'completion_marker_missing');

    const markerTampered = publish('marker-tampered');
    const markerPath = path.join(markerTampered, 'complete.json');
    const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
    marker.format = 'unknown-export-version';
    fs.writeFileSync(markerPath, JSON.stringify(marker));
    assert.throws(() => readPublishedSyntheticExport(path.basename(markerTampered)), (error) => error.code === 'completion_marker_invalid');

    const markerIntegrityTampered = publish('marker-integrity');
    const integrityMarkerPath = path.join(markerIntegrityTampered, 'complete.json');
    const integrityMarker = JSON.parse(fs.readFileSync(integrityMarkerPath, 'utf8'));
    integrityMarker.exportIntegrity.digest = '0'.repeat(64);
    fs.writeFileSync(integrityMarkerPath, JSON.stringify(integrityMarker));
    assert.throws(() => readPublishedSyntheticExport(path.basename(markerIntegrityTampered)), (error) => error.code === 'export_integrity_mismatch');

    const markerCountsTampered = publish('marker-counts');
    const countsMarkerPath = path.join(markerCountsTampered, 'complete.json');
    const countsMarker = JSON.parse(fs.readFileSync(countsMarkerPath, 'utf8'));
    countsMarker.counts.users++;
    fs.writeFileSync(countsMarkerPath, JSON.stringify(countsMarker));
    assert.throws(() => readPublishedSyntheticExport(path.basename(markerCountsTampered)), (error) => error.code === 'completion_manifest_mismatch');

    const dataTampered = publish('data-tampered');
    const dataPath = path.join(dataTampered, 'export.json');
    const exportData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
    exportData.collections.users[0].data.displayName = 'Changed';
    fs.writeFileSync(dataPath, JSON.stringify(exportData));
    assert.throws(() => readPublishedSyntheticExport(path.basename(dataTampered)), (error) => error.code === 'export_integrity_mismatch');

    const truncated = publish('truncated');
    fs.writeFileSync(path.join(truncated, 'export.json'), '{"format":');
    refreshIntegrity(truncated);
    assert.throws(() => readPublishedSyntheticExport(path.basename(truncated)), (error) => error.code === 'export_json_invalid');

    const badCounts = publish('bad-counts');
    const badCountsPath = path.join(badCounts, 'export.json');
    const badCountsData = JSON.parse(fs.readFileSync(badCountsPath, 'utf8'));
    badCountsData.counts.activities++;
    fs.writeFileSync(badCountsPath, JSON.stringify(badCountsData));
    refreshIntegrity(badCounts);
    assert.throws(() => readPublishedSyntheticExport(path.basename(badCounts)), (error) => error.code === 'count_manifest_mismatch');

    const invalidTypes = publish('invalid-types');
    const invalidTypePath = path.join(invalidTypes, 'export.json');
    const invalidTypeData = JSON.parse(fs.readFileSync(invalidTypePath, 'utf8'));
    invalidTypeData.typeManifest.find(({ type }) => type === 'Timestamp').nanoseconds = 1_000_000_000;
    fs.writeFileSync(invalidTypePath, JSON.stringify(invalidTypeData));
    refreshIntegrity(invalidTypes);
    assert.throws(() => readPublishedSyntheticExport(path.basename(invalidTypes)), (error) => error.code === 'malformed_timestamp');

    const extraFile = publish('extra-file');
    fs.writeFileSync(path.join(extraFile, 'unexpected.txt'), 'private');
    assert.throws(() => readPublishedSyntheticExport(path.basename(extraFile)), (error) => error.code === 'artifact_contents_invalid');
  } finally {
    for (const directory of created) fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('shared reader rejects a symlink in place of a published export directory', (t) => {
  const targetId = `synthetic-reader-target-${process.pid}`;
  const linkId = `synthetic-reader-link-${process.pid}`;
  const target = path.join(syntheticExportPaths.outputRoot, targetId);
  const link = path.join(syntheticExportPaths.outputRoot, linkId);
  try {
    publishSyntheticFixtureExport({ fixturePath: syntheticFixturePath, exportId: targetId });
    try { fs.symlinkSync(target, link, 'junction'); }
    catch (error) {
      if (['EPERM', 'EACCES', 'ENOTSUP'].includes(error?.code)) {
        t.skip('this Windows environment does not permit creating a directory symlink');
        return;
      }
      throw error;
    }
    assert.throws(() => readPublishedSyntheticExport(linkId), (error) => error.code === 'artifact_directory_invalid');
  } finally {
    fs.rmSync(link, { recursive: true, force: true });
    fs.rmSync(target, { recursive: true, force: true });
  }
});

test('publication refuses an existing export directory without replacing its contents', () => {
  const exportId = `synthetic-export-${process.pid}-conflict`;
  const finalDirectory = path.join(syntheticExportPaths.outputRoot, exportId);
  try {
    fs.mkdirSync(finalDirectory, { recursive: true });
    fs.writeFileSync(path.join(finalDirectory, 'sentinel.txt'), 'preserve-existing');
    assert.throws(() => publishSyntheticFixtureExport({ fixturePath: syntheticFixturePath, exportId }),
      (error) => error instanceof ExportContractError && error.code === 'export_artifact_exists');
    assert.equal(fs.readFileSync(path.join(finalDirectory, 'sentinel.txt'), 'utf8'), 'preserve-existing');
  } finally {
    fs.rmSync(finalDirectory, { recursive: true, force: true });
  }
});

test('failure diagnostics expose only a stable code and status values', () => {
  const source = readSyntheticFixture(syntheticFixturePath);
  source.types['/users/user_doc_1/data/explicitNull'] = { type: 'private@example.invalid token-value' };
  let failure;
  try { buildJsonExport(source); } catch (error) { failure = safeExportFailure(error); }
  assert.deepEqual(failure, {
    exportStatus: 'incomplete',
    serializationFidelityStatus: 'blocked',
    projectionReadinessStatus: 'blocked',
    code: 'unsupported_firestore_type',
    containsRecordValues: false,
  });
  assert.equal(JSON.stringify(failure).includes('private@example.invalid'), false);
  assert.equal(JSON.stringify(failure).includes('token-value'), false);
  assert.deepEqual(safeExportFailure(new ExportContractError('artifact_publication_failed')), {
    exportStatus: 'incomplete',
    serializationFidelityStatus: 'not_published',
    projectionReadinessStatus: 'not_assessed',
    code: 'artifact_publication_failed',
    containsRecordValues: false,
  });
  assert.equal(safeExportFailure(new Error('private local path')).serializationFidelityStatus, 'unverified');
});
