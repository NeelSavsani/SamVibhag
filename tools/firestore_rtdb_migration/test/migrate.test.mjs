import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import {
  TOOL_DIR,
  MigrationError,
  SimulatedInterruption,
  applyPlanLocally,
  buildMigrationPlan,
  canManageSettlement,
  canonicalJson,
  decodeFirestoreValue,
  decodeKey,
  encodeFirestoreValue,
  encodeKey,
  hashValue,
  createMemoryStore,
  main as migrationMain,
  paginateDocuments,
  safeCliError,
  verifyPlan,
} from '../migrate.mjs';
import { readFirestoreSnapshot, readRealtimeDatabaseBoundedInventory, RTDB_INVENTORY_COLLECTION_PATHS, RTDB_INVENTORY_LIMITS } from '../read_only_adapters.mjs';
import {
  EXPECTED_PROJECT_ID,
  EXPECTED_DATABASE_URL,
  EXPECTED_ADC_PRINCIPAL,
  buildInventoryAppOptions,
  buildStructuralInventoryReport,
  main,
  parseInventoryArgs,
  runInventory,
  RTDB_RULES_UID,
  verifyRtdbAuthOverride,
  verifyAdcIdentity,
} from '../inventory_runner.mjs';

const fixturePath = path.join(TOOL_DIR, 'fixtures', 'synthetic-source.json');
const fixture = () => JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const errCode = (fn, code) => assert.throws(fn, (error) => error instanceof MigrationError && error.code === code);
const configuredPathChecks = (status = 'accessible_absent') => RTDB_INVENTORY_COLLECTION_PATHS.map((path) => ({ path, status }));
function fakeRtdb(recordsByPath = {}, { failPath, customPage } = {}) {
  return {
    ref(path) {
      assert.equal(RTDB_INVENTORY_COLLECTION_PATHS.includes(path), true);
      return {
        orderByKey() { return this; },
        limitToFirst(size) { this.pageSize = size; return this; },
        startAfter(cursor) { this.cursor = cursor; return this; },
        async get() {
          if (path === failPath) throw new Error('synthetic private path failure');
          if (customPage) return customPage(path, this);
          const records = recordsByPath[path] ?? {};
          const keys = Object.keys(records).sort().filter((key) => this.cursor === undefined || key > this.cursor);
          const page = keys.slice(0, this.pageSize);
          const children = page.map((key) => ({ key, val: () => records[key] }));
          return {
            exists: () => children.length > 0,
            forEach(callback) { for (const child of children) if (callback(child) === true) break; },
          };
        },
      };
    },
  };
}

test('round trips mixed Firestore values, explicit null, timestamps, dynamic keys, and marker-shaped source maps', () => {
  const input = {
    timestamp: null,
    missingIsNotPresent: undefined,
    explicitNull: null,
    integer: 42,
    decimal: 3.125,
    values: [true, 'x', null, { 'with.dot': 1, _k_d2l0aC5kb3Q: 2, 'slash/name': 3, 'unicode-₹': 4 }],
    literal: { __rtdbType: 'firestoreNull', entries: { arbitrary: 'not an envelope' } },
  };
  delete input.missingIsNotPresent;
  const typeMap = {
    '/timestamp': { type: 'Timestamp', seconds: 1700000000, nanoseconds: 999999999 },
    '/integer': { type: 'Integer' },
    '/decimal': { type: 'Double' },
  };
  const encoded = encodeFirestoreValue(input, { typeMap });
  const decoded = decodeFirestoreValue(encoded);
  assert.deepEqual(decoded, {
    timestamp: { __firestoreFixtureType: 'Timestamp', seconds: 1700000000, nanoseconds: 999999999 },
    explicitNull: null,
    integer: 42,
    decimal: 3.125,
    values: [true, 'x', null, { 'with.dot': 1, _k_d2l0aC5kb3Q: 2, 'slash/name': 3, 'unicode-₹': 4 }],
    literal: { __rtdbType: 'firestoreNull', entries: { arbitrary: 'not an envelope' } },
  });
  assert.equal(Object.hasOwn(decoded, 'missingIsNotPresent'), false);
  assert.equal(encoded.entries.timestamp.value.__rtdbType, 'firestoreTimestamp');
  assert.equal(encoded.entries.integer.value.sourceKind, 'Integer');
  assert.notEqual(encoded.entries.explicitNull.value, undefined);
});

test('key encoding is reversible and avoids collisions with reserved-prefix keys', () => {
  const keys = ['', 'simple', 'with.dot', 'slash/name', '_k_d2l0aC5kb3Q', 'unicode-₹', 'control\u0001'];
  const outputs = keys.map(encodeKey);
  assert.equal(new Set(outputs).size, outputs.length);
  for (let i = 0; i < keys.length; i++) assert.equal(decodeKey(outputs[i]), keys[i]);
  assert.equal(encodeKey('with.dot'), '_k_d2l0aC5kb3Q');
  assert.notEqual(encodeKey('_k_d2l0aC5kb3Q'), encodeKey('with.dot'));
});

test('fixture pagination uses bounded pages and stable document-id ordering', () => {
  const source = fixture();
  source.collections.users.reverse();
  const plan = buildMigrationPlan(source, { pageSize: 1 });
  assert.equal(plan.sourceCounts.users, 2);
  const userWrites = plan.writes.filter((write) => write.path.includes('projected') && write.path.includes('users'));
  assert.deepEqual(userWrites.map((write) => write.sourceId).sort(), ['uid_creator', 'uid_riya']);
  assert.equal(plan.writes.length > 1, true);
  const pages = paginateDocuments([{ id: 'c' }, { id: 'a' }, { id: 'b' }], 2);
  assert.deepEqual(pages.map((page) => page.docs.map((doc) => doc.id)), [['a', 'b'], ['c']]);
  assert.deepEqual(pages.map((page) => page.nextCursor), ['b', 'c']);
});

test('dry plan hashes and verifies all projected and archived records', () => {
  const plan = buildMigrationPlan(fixture(), { pageSize: 2 });
  const report = applyPlanLocally(plan, createMemoryStore());
  assert.equal(report.status, 'verified-local-fixture');
  assert.equal(report.sourceCounts.users, 2);
  assert.equal(report.sourceCounts.groups, 1);
  assert.equal(report.sourceCounts.expenses, 1);
  assert.equal(report.sourceCounts.settlements, 1);
  assert.equal(report.sourceCounts.activities, 1);
  assert.equal(report.verification.expectedRecordCount, report.verification.verifiedRecordCount);
  assert.equal(report.verification.ok, true);
  const settlementWrite = buildMigrationPlan(fixture()).writes.find((write) => write.sourcePath.endsWith('recordedSettlements[0]'));
  assert.deepEqual(decodeFirestoreValue(settlementWrite.value.data), {
    id: 'settle_001', fromUser: 'Offline Member', toUser: 'Riya', amount: 20.5, isSettled: true, settledAt: null,
  });
});

test('interrupted local apply resumes deterministically and skips already matching records', () => {
  const plan = buildMigrationPlan(fixture(), { pageSize: 1 });
  const store = createMemoryStore();
  assert.throws(() => applyPlanLocally(plan, store, { failAfter: 3 }), SimulatedInterruption);
  const resumed = applyPlanLocally(plan, store);
  assert.equal(resumed.status, 'verified-local-fixture');
  assert.ok(resumed.identicalPathsSkipped >= 3);
  const repeated = applyPlanLocally(plan, store);
  assert.equal(repeated.writtenThisCall, 0);
  assert.equal(repeated.identicalPathsSkipped, plan.writes.length);
});

test('existing conflicting destination record is never overwritten', () => {
  const plan = buildMigrationPlan(fixture());
  const first = plan.writes[0];
  const tree = {};
  let node = tree;
  for (const segment of first.path.slice(0, -1)) node = node[segment] ??= {};
  node[first.path.at(-1)] = { altered: true };
  const store = createMemoryStore({ tree, journal: {}, runId: plan.runId });
  const before = canonicalJson(store.load());
  errCode(() => applyPlanLocally(plan, store), 'destination_conflict');
  assert.equal(canonicalJson(store.load()), before);
});

test('destination verification reports unexpected records in the isolated run namespace', () => {
  const plan = buildMigrationPlan(fixture());
  const store = createMemoryStore();
  applyPlanLocally(plan, store);
  const state = store.load();
  const parent = [...plan.writes[0].path.slice(0, -1)];
  let node = state.tree;
  for (const segment of parent) node = node[segment];
  node.unexpectedSyntheticRecord = { unexpected: true };
  const verified = verifyPlan(plan, state.tree);
  assert.equal(verified.ok, false);
  assert.equal(verified.unexpectedCount, 1);
  assert.equal(Object.hasOwn(verified, 'unexpected'), false);
});

test('planner consumes index-based timestamp manifest paths for embedded expenses and settlements', () => {
  const source = fixture();
  const group = source.collections.groups[0];
  group.data.expenses[0].date = null;
  group.data.recordedSettlements[0].settledAt = null;
  source.types['/groups/group_one/data/expenses/0/date'] = { type: 'Timestamp', seconds: 1710000000, nanoseconds: 123456789 };
  source.types['/groups/group_one/data/recordedSettlements/0/settledAt'] = { type: 'Timestamp', seconds: 1710000001, nanoseconds: 987654321 };

  const plan = buildMigrationPlan(source);
  const expenseWrite = plan.writes.find((write) => write.sourcePath.endsWith('expenses[0]'));
  const settlementWrite = plan.writes.find((write) => write.sourcePath.endsWith('recordedSettlements[0]'));
  const archiveWrite = plan.writes.find((write) => write.path.includes('sourceArchive') && write.path.at(-1) === 'document');
  const expenseDate = expenseWrite.value.data.entries.date.value;
  const settlementDate = settlementWrite.value.data.entries.settledAt.value;

  assert.equal(expenseDate.__rtdbType, 'firestoreTimestamp');
  assert.equal(settlementDate.__rtdbType, 'firestoreTimestamp');
  assert.deepEqual(decodeFirestoreValue(expenseWrite.value.data).date, {
    __firestoreFixtureType: 'Timestamp', seconds: 1710000000, nanoseconds: 123456789,
  });
  assert.deepEqual(decodeFirestoreValue(settlementWrite.value.data).settledAt, {
    __firestoreFixtureType: 'Timestamp', seconds: 1710000001, nanoseconds: 987654321,
  });
  assert.notEqual(expenseDate.__rtdbType, 'firestoreNull');
  assert.notEqual(settlementDate.__rtdbType, 'firestoreNull');
  const archivedGroup = decodeFirestoreValue(archiveWrite.value);
  assert.deepEqual(archivedGroup.expenses[0].date, {
    __firestoreFixtureType: 'Timestamp', seconds: 1710000000, nanoseconds: 123456789,
  });
  assert.deepEqual(archivedGroup.recordedSettlements[0].settledAt, {
    __firestoreFixtureType: 'Timestamp', seconds: 1710000001, nanoseconds: 987654321,
  });
});

test('planner rejects unapproved fixture collections without exposing their names or records', () => {
  const source = fixture();
  source.collections.privateInvitations = [{ id: 'private-invite-id', data: { token: 'synthetic-private-token' } }];
  assert.throws(() => buildMigrationPlan(source), (error) => {
    assert.equal(error.code, 'unsupported_source_collections');
    assert.deepEqual(error.details, { unexpectedCollectionCount: 1 });
    assert.equal(error.message.includes('privateInvitations'), false);
    assert.equal(JSON.stringify(error.details).includes('private-invite-id'), false);
    return true;
  });
});

test('verification and fixture CLI diagnostics expose aggregate counts, not record data', () => {
  const plan = buildMigrationPlan(fixture());
  const store = createMemoryStore();
  applyPlanLocally(plan, store);
  const report = verifyPlan(plan, store.load().tree);
  const serializedReport = JSON.stringify(report);
  const serializedApplyReport = JSON.stringify(store.load().report);
  for (const privateValue of ['group_one', 'meal_001', 'settle_001', 'uid_creator', 'Offline Member']) {
    assert.equal(serializedReport.includes(privateValue), false);
    assert.equal(serializedApplyReport.includes(privateValue), false);
  }
  assert.deepEqual(Object.keys(report).sort(), ['expectedRecordCount', 'missingCount', 'mismatchedCount', 'ok', 'unexpectedCount', 'verifiedRecordCount'].sort());

  const errorJson = JSON.stringify(safeCliError(new MigrationError('unresolved_member_name', 'Private Member Name at groups/private-group', {
    sourcePath: 'groups/private-group/expenses/secret', name: 'Private Member Name', token: 'synthetic-private-token',
  })));
  for (const privateValue of ['Private Member Name', 'private-group', 'secret', 'synthetic-private-token']) assert.equal(errorJson.includes(privateValue), false);
  assert.deepEqual(JSON.parse(errorJson), { status: 'failed', code: 'unresolved_member_name' });

  const cliError = spawnSync(process.execPath, [path.join(TOOL_DIR, 'migrate.mjs'), '--synthetic-private-name'], { encoding: 'utf8' });
  assert.equal(cliError.status, 1);
  assert.equal(cliError.stderr.includes('synthetic-private-name'), false);
  assert.deepEqual(JSON.parse(cliError.stderr), { status: 'failed', code: 'invalid_argument' });

  const previousLog = console.log;
  let output = '';
  console.log = (line) => { output += line; };
  try { migrationMain(['--dry-run']); } finally { console.log = previousLog; }
  for (const privateValue of ['group_one', 'meal_001', 'uid_creator', 'Creator', 'creator@example.invalid']) assert.equal(output.includes(privateValue), false);
  assert.equal(JSON.parse(output).mode, 'dry-run-read-only-local-fixture');
});

test('legacy from/to settlement aliases map explicitly while preserving source values', () => {
  const source = fixture();
  const legacy = source.collections.groups[0].data.recordedSettlements[0];
  delete legacy.fromUser;
  delete legacy.toUser;
  legacy.from = 'Offline Member';
  legacy.to = 'Riya';
  const plan = buildMigrationPlan(source);
  const settlementWrite = plan.writes.find((write) => write.sourcePath.endsWith('recordedSettlements[0]'));
  const projected = decodeFirestoreValue(settlementWrite.value.data);
  assert.equal(projected.from, 'Offline Member');
  assert.equal(projected.to, 'Riya');
  assert.equal(projected.fromUser, 'Offline Member');
  assert.equal(projected.toUser, 'Riya');
  assert.equal(plan.sourceCounts.settlements, 1);

  const sourceArchive = plan.writes.find((write) => write.path.includes('sourceArchive') && write.path.at(-1) === 'document');
  const archivedGroup = decodeFirestoreValue(sourceArchive.value);
  assert.equal(Object.hasOwn(archivedGroup.recordedSettlements[0], 'fromUser'), false);
  assert.equal(archivedGroup.recordedSettlements[0].from, 'Offline Member');
  assert.equal(archivedGroup.recordedSettlements[0].to, 'Riya');
});

test('legacy settlement aliases reject conflicting, malformed, and ambiguous parties', () => {
  const conflicting = fixture();
  conflicting.collections.groups[0].data.recordedSettlements[0].from = 'Creator';
  errCode(() => buildMigrationPlan(conflicting), 'conflicting_settlement_alias');

  const malformed = fixture();
  delete malformed.collections.groups[0].data.recordedSettlements[0].fromUser;
  malformed.collections.groups[0].data.recordedSettlements[0].from = 42;
  errCode(() => buildMigrationPlan(malformed), 'malformed_settlement_alias');

  const ambiguous = fixture();
  ambiguous.collections.groups[0].data.members.push('Riya');
  delete ambiguous.collections.groups[0].data.recordedSettlements[0].fromUser;
  ambiguous.collections.groups[0].data.recordedSettlements[0].from = 'Riya';
  errCode(() => buildMigrationPlan(ambiguous), 'ambiguous_member_name');
});

test('duplicate source document and embedded expense IDs fail before producing a plan', () => {
  const duplicateDoc = fixture();
  duplicateDoc.collections.users.push(structuredClone(duplicateDoc.collections.users[0]));
  errCode(() => buildMigrationPlan(duplicateDoc), 'duplicate_document_id');

  const duplicateExpense = fixture();
  duplicateExpense.collections.groups[0].data.expenses.push(structuredClone(duplicateExpense.collections.groups[0].data.expenses[0]));
  errCode(() => buildMigrationPlan(duplicateExpense), 'duplicate_expense_id');

  const duplicateSettlement = fixture();
  duplicateSettlement.collections.groups[0].data.recordedSettlements.push(structuredClone(duplicateSettlement.collections.groups[0].data.recordedSettlements[0]));
  errCode(() => buildMigrationPlan(duplicateSettlement), 'duplicate_settlement_id');

  const duplicateActivity = fixture();
  duplicateActivity.collections.groups[0].subcollections.activities.push(structuredClone(duplicateActivity.collections.groups[0].subcollections.activities[0]));
  errCode(() => buildMigrationPlan(duplicateActivity), 'destination_path_collision');
});

test('malformed records, unsupported Firestore values, and unresolved references fail explicitly', () => {
  const malformed = fixture();
  delete malformed.collections.groups[0].data.createdBy;
  errCode(() => buildMigrationPlan(malformed), 'missing_group_creator');

  const unsupported = fixture();
  unsupported.collections.users[0].data.unsupported = 'not serialized';
  unsupported.types['/users/uid_creator/data/unsupported'] = { type: 'DocumentReference', path: 'groups/group_one' };
  errCode(() => buildMigrationPlan(unsupported), 'unsupported_firestore_value');

  const orphanType = fixture();
  orphanType.types['/users/uid_creator/data/missingField'] = { type: 'Timestamp', seconds: 0, nanoseconds: 0 };
  errCode(() => buildMigrationPlan(orphanType), 'orphan_type_descriptor');

  const badRelation = fixture();
  badRelation.collections.usernames[0].data.uid = 'not_a_user';
  errCode(() => buildMigrationPlan(badRelation), 'unresolved_username_user');
});

test('malformed expense/settlement details and unknown split members fail safely', () => {
  const expense = fixture();
  expense.collections.groups[0].data.expenses[0].splitBetween = ['Missing Person'];
  errCode(() => buildMigrationPlan(expense), 'unresolved_member_name');

  const settlement = fixture();
  settlement.collections.groups[0].data.recordedSettlements[0].amount = Number.NaN;
  errCode(() => buildMigrationPlan(settlement), 'malformed_settlement');
});

test('ambiguous explicit UID/name mappings fail; no parallel-array positional inference occurs', () => {
  const ambiguous = fixture();
  ambiguous.collections.users.push({ id: 'uid_other', data: { uid: 'uid_other', displayName: 'Riya' } });
  ambiguous.collections.groups[0].data.members.push('Riya');
  ambiguous.collections.groups[0].data.memberUids.push('uid_other');
  ambiguous.collections.groups[0].data.memberIdentities.push({ name: 'Riya', uid: 'uid_other' });
  errCode(() => buildMigrationPlan(ambiguous), 'ambiguous_member_name');

  const legacy = fixture();
  delete legacy.collections.groups[0].data.memberIdentities;
  legacy.collections.groups[0].data.members = ['Creator', 'Riya'];
  legacy.collections.groups[0].data.expenses[0].splitBetween = ['Riya'];
  legacy.collections.groups[0].data.expenses[0].customSplits = { Riya: 120.5 };
  legacy.collections.groups[0].data.recordedSettlements[0].fromUser = 'Riya';
  legacy.collections.groups[0].data.recordedSettlements[0].toUser = 'Creator';
  const plan = buildMigrationPlan(legacy);
  const identityWrites = plan.writes.filter((write) => write.path.includes('memberIdentities'));
  assert.equal(identityWrites.length, 0);
  assert.equal(legacy.collections.groups[0].data.members.length, legacy.collections.groups[0].data.memberUids.length);
  assert.equal(canManageSettlement(legacy.collections.groups[0].data, { fromUser: 'Riya' }, 'uid_riya'), false);
});

test('settlement authorization accepts responsible payer UID and creator, rejects other member and ambiguous mapping', () => {
  const group = fixture().collections.groups[0].data;
  const settlement = group.recordedSettlements[0];
  assert.equal(canManageSettlement(group, settlement, 'uid_creator'), true);
  assert.equal(canManageSettlement(group, settlement, 'uid_riya'), false);
  assert.equal(canManageSettlement(group, settlement, 'uid_missing'), false);

  const payerSettlement = { ...settlement, fromUser: 'Riya' };
  assert.equal(canManageSettlement(group, payerSettlement, 'uid_riya'), true);
  const ambiguous = { ...group, memberIdentities: [...group.memberIdentities, { name: 'Offline Member', uid: 'uid_riya' }] };
  assert.equal(canManageSettlement(ambiguous, settlement, 'uid_riya'), false);
  assert.equal(canManageSettlement(ambiguous, settlement, 'uid_creator'), true);
});

test('invalid timestamps, key collisions, and corrupt encoded values fail', () => {
  errCode(() => encodeFirestoreValue(null, { typeMap: { '': { type: 'Timestamp', seconds: 0, nanoseconds: 1_000_000_000 } } }), 'malformed_timestamp');
  const badKey = { a: 1, 'a.b': 2 };
  const encoded = encodeFirestoreValue(badKey);
  assert.equal(decodeFirestoreValue(encoded)['a.b'], 2);
  assert.notEqual(encodeKey('a.b'), encodeKey('_k_YS5i'));
  errCode(() => decodeKey('_k_not-valid!!'), 'invalid_encoded_key');
});

test('unresolved duplicate display name referenced by an expense fails rather than guessing a UID', () => {
  const source = fixture();
  source.collections.groups[0].data.members.push('Riya');
  source.collections.groups[0].data.expenses[0].paidBy = 'Riya';
  errCode(() => buildMigrationPlan(source), 'ambiguous_member_name');
});

test('report hashes are deterministic across source document ordering and page sizes', () => {
  const sourceA = fixture();
  const sourceB = fixture();
  sourceB.collections.users.reverse();
  sourceB.collections.groups.reverse();
  const planA = buildMigrationPlan(sourceA, { pageSize: 1 });
  const planB = buildMigrationPlan(sourceB, { pageSize: 50 });
  assert.equal(planA.sourceHash, planB.sourceHash);
  assert.equal(planA.expectedDestinationHash, planB.expectedDestinationHash);
  assert.equal(hashValue({ b: 2, a: 1 }), hashValue({ a: 1, b: 2 }));
});

test('read-only Firestore adapter pages audited collections and group activities in document-id order', async () => {
  class FakeTimestamp {
    constructor(seconds, nanoseconds) { this.seconds = seconds; this.nanoseconds = nanoseconds; }
  }
  const records = {
    users: [
      { id: 'uid_b', data: () => ({ createdAt: new FakeTimestamp(22, 3), displayName: 'B' }) },
      { id: 'uid_a', data: () => ({ displayName: 'A' }) },
    ],
    usernames: [],
    groups: [],
  };
  const activityData = [{ id: 'event_b', data: () => ({ timestamp: new FakeTimestamp(33, 4), groupId: 'g' }) }, { id: 'event_a', data: () => ({ groupId: 'g' }) }];
  const pages = [];
  const collectionRef = (_name, docs) => ({
    orderBy(field) { assert.equal(field, '__name__'); return this; },
    limit(size) { this.pageSize = size; return this; },
    startAfter(cursor) { this.cursor = cursor; return this; },
    async get() {
      const sorted = [...docs].sort((a, b) => Buffer.compare(Buffer.from(a.id), Buffer.from(b.id)));
      const start = this.cursor ? sorted.findIndex((doc) => doc.id === this.cursor.id) + 1 : 0;
      return { docs: sorted.slice(start, start + this.pageSize) };
    },
  });
  records.groups = [{
    id: 'g',
    data: () => ({ id: 'g', createdBy: 'uid_a', members: ['A', 'Offline'], memberUids: ['uid_a'], expenses: [], recordedSettlements: [] }),
    ref: { collection: (name) => { assert.equal(name, 'activities'); return collectionRef('activities', activityData); } },
  }];
  const snapshot = await readFirestoreSnapshot({
    db: { collection: (name) => collectionRef(name, records[name]) },
    pageSize: 1,
    types: { Timestamp: FakeTimestamp },
    onPage: (page) => pages.push(page),
  });

  assert.deepEqual(snapshot.collections.users.map((doc) => doc.id), ['uid_a', 'uid_b']);
  assert.deepEqual(snapshot.collections.groups[0].data.members, ['A', 'Offline']);
  assert.deepEqual(snapshot.collections.groups[0].subcollections.activities.map((doc) => doc.id), ['event_a', 'event_b']);
  assert.deepEqual(snapshot.types['/users/uid_b/data/createdAt'], { type: 'Timestamp', seconds: 22, nanoseconds: 3 });
  assert.deepEqual(snapshot.types['/groups/g/activities/event_b/timestamp'], { type: 'Timestamp', seconds: 33, nanoseconds: 4 });
  assert.equal(snapshot.readStats.recordsRead, 5);
  assert.ok(snapshot.readStats.estimatedJsonBytes > 0);
  assert.ok(pages.length >= 4);
  assert.equal(buildMigrationPlan(snapshot).sourceCounts.activities, 2);
});

test('Firestore inventory enforces capped total record and byte limits without exposing values', async () => {
  const docs = [
    { id: 'private-id-a', data: () => ({ note: 'synthetic-secret-value' }) },
    { id: 'private-id-b', data: () => ({ note: 'another-value' }) },
  ];
  const collection = {
    orderBy() { return this; },
    limit(size) { this.size = size; return this; },
    startAfter(cursor) { this.cursor = cursor; return this; },
    async get() {
      const start = this.cursor ? docs.findIndex((doc) => doc.id === this.cursor.id) + 1 : 0;
      return { docs: docs.slice(start, start + this.size) };
    },
  };
  await assert.rejects(readFirestoreSnapshot({ db: { collection: () => collection }, pageSize: 1, limits: { maxRecords: 1 } }),
    (error) => error instanceof MigrationError && error.code === 'firestore_record_limit_exceeded' && !error.message.includes('private-id'));
  await assert.rejects(readFirestoreSnapshot({ db: { collection: () => collection }, pageSize: 1, limits: { maxRecordBytes: 8 } }),
    (error) => error instanceof MigrationError && error.code === 'firestore_record_size_exceeded' && !error.message.includes('synthetic-secret-value'));
  await assert.rejects(readFirestoreSnapshot({ db: { collection: () => collection }, pageSize: 1, limits: { maxTotalBytes: 8 } }),
    (error) => error instanceof MigrationError && error.code === 'firestore_total_size_exceeded' && !error.message.includes('another-value'));
  await assert.rejects(readFirestoreSnapshot({ db: { collection: () => { throw new Error('network must not occur'); } }, pageSize: 201 }),
    (error) => error instanceof MigrationError && error.code === 'invalid_firestore_inventory_limits');
});

test('read-only adapter refuses unaudited collections and unsupported Firebase SDK values', async () => {
  await assert.rejects(
    readFirestoreSnapshot({ db: { collection: () => { throw new Error('must not read'); } }, collections: ['adminSecrets'] }),
    (error) => error instanceof MigrationError && error.code === 'unapproved_collection',
  );
  class FakeGeoPoint { constructor() { this.latitude = 1; this.longitude = 2; } }
  const doc = { id: 'u', data: () => ({ location: new FakeGeoPoint() }) };
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [doc] }; } };
  await assert.rejects(
    readFirestoreSnapshot({ db: { collection: () => emptyCollection }, types: { GeoPoint: FakeGeoPoint } }),
    (error) => error instanceof MigrationError && error.code === 'unsupported_firestore_value',
  );
});

test('bounded RTDB inventory pages schema-derived root collections and counts empty paths', async () => {
  assert.deepEqual(RTDB_INVENTORY_COLLECTION_PATHS, [
    '/samvibhag/v1/users', '/samvibhag/v1/usernames', '/samvibhag/v1/groups',
    '/samvibhag/v1/userGroups', '/samvibhag/v1/migrationRuns',
  ]);
  const records = {
    '/samvibhag/v1/users': { u1: { profile: { uid: 'u1' } }, u2: { profile: { uid: 'u2' } } },
    '/samvibhag/v1/groups': { g1: { data: { id: 'g1' }, expenses: { e1: { amount: 2 } } } },
  };
  let largestPageSize = 0;
  const database = fakeRtdb(records);
  const instrumented = { ref(path) { const ref = database.ref(path); const limitToFirst = ref.limitToFirst; ref.limitToFirst = function(size) { largestPageSize = Math.max(largestPageSize, size); return limitToFirst.call(this, size); }; return ref; } };
  const report = await readRealtimeDatabaseBoundedInventory({ database: instrumented, limits: { pageSize: 1 } });
  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(report.collectionCounts.users, 2);
  assert.equal(report.collectionCounts.groups, 1);
  assert.equal(report.collectionCounts.usernames, 0);
  assert.equal(report.checkedPaths.length, RTDB_INVENTORY_COLLECTION_PATHS.length);
  assert.equal(report.checkedPaths[1].status, 'accessible_absent');
  assert.equal(largestPageSize, 1);
  assert.equal(report.scopeIsWholeNamespace, false);
});

test('bounded RTDB inventory fails incomplete on duplicate and invalid record keys', async () => {
  const duplicate = await readRealtimeDatabaseBoundedInventory({
    database: fakeRtdb({}, { customPage(path, query) {
      if (path !== RTDB_INVENTORY_COLLECTION_PATHS[0]) return { forEach() {} };
      return { forEach(callback) { callback({ key: query.cursor ? 'dup' : 'dup', val: () => ({ safe: true }) }); } };
    } }),
    limits: { pageSize: 1 },
  });
  assert.equal(duplicate.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(duplicate.issueCounts.duplicateKeys, 1);
  assert.equal(duplicate.checkedPaths[0].status, 'invalid_data');

  const invalid = await readRealtimeDatabaseBoundedInventory({
    database: fakeRtdb({ [RTDB_INVENTORY_COLLECTION_PATHS[0]]: { 'private.name@example.invalid': { x: 1 } } }),
  });
  assert.equal(invalid.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(invalid.issueCounts.invalidKeys, 1);
  assert.equal(JSON.stringify(invalid).includes('private.name@example.invalid'), false);
});

test('bounded RTDB inventory stops on oversized records and configured record/byte/RSS limits', async () => {
  const largeSecret = 'synthetic-secret-do-not-report';
  const oversized = await readRealtimeDatabaseBoundedInventory({
    database: fakeRtdb({ [RTDB_INVENTORY_COLLECTION_PATHS[0]]: { u1: { payload: largeSecret + 'x'.repeat(512) } } }),
    limits: { maxRecordBytes: 64 },
  });
  assert.equal(oversized.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(oversized.issueCounts.oversizedRecords, 1);
  assert.equal(oversized.checkedPaths[0].status, 'limit_exceeded');
  assert.equal(JSON.stringify(oversized).includes(largeSecret), false);

  const records = { [RTDB_INVENTORY_COLLECTION_PATHS[0]]: { a: 'a', b: 'b' } };
  const countLimited = await readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(records), limits: { pageSize: 1, maxRecords: 1 } });
  assert.equal(countLimited.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(countLimited.issueCounts.limitExceeded, 1);

  const byteLimited = await readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(records), limits: { pageSize: 1, maxTotalBytes: 1 } });
  assert.equal(byteLimited.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(byteLimited.issueCounts.limitExceeded, 1);

  const rssLimited = await readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(), getRssBytes: () => 1024, limits: { maxRssBytes: 100 } });
  assert.equal(rssLimited.inventoryStatus, 'incomplete_for_configured_scope');
  assert.equal(rssLimited.issueCounts.limitExceeded, 1);
});

test('bounded RTDB inventory reports partial path failures without claiming completion', async () => {
  const report = await readRealtimeDatabaseBoundedInventory({
    database: fakeRtdb({ [RTDB_INVENTORY_COLLECTION_PATHS[0]]: { u1: { profile: true } } }, { failPath: RTDB_INVENTORY_COLLECTION_PATHS[1] }),
  });
  assert.equal(report.inventoryStatus, 'incomplete_for_configured_scope');
  assert.deepEqual(report.checkedPaths.map(({ status }) => status), ['accessible_present', 'failed']);
  assert.equal(report.recordCount, 1);
  assert.equal(report.issueCounts.readFailures, 1);
  assert.equal(JSON.stringify(report).includes('synthetic private path failure'), false);
});

test('RTDB inventory requires the exact limited-privilege override before any read', async () => {
  assert.equal(verifyRtdbAuthOverride({ uid: RTDB_RULES_UID }), true);
  assert.deepEqual(buildInventoryAppOptions({ credential: 'fake-credential', databaseUrl: EXPECTED_DATABASE_URL }), {
    credential: 'fake-credential',
    projectId: EXPECTED_PROJECT_ID,
    databaseURL: EXPECTED_DATABASE_URL,
    databaseAuthVariableOverride: { uid: RTDB_RULES_UID },
  });
  for (const invalidOverride of [undefined, null, {}, { uid: 'wrong-uid' }, { uid: RTDB_RULES_UID, admin: true }, [RTDB_RULES_UID]]) {
    assert.throws(() => verifyRtdbAuthOverride(invalidOverride),
      (error) => error instanceof MigrationError && error.code === 'rtdb_auth_override_unverified');
  }

  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  for (const override of [undefined, { uid: 'wrong-uid' }]) {
    let firestoreReads = 0;
    let rtdbReads = 0;
    await assert.rejects(runInventory({
      argv: inventoryArgs,
      resolveAdcIdentity: async () => ({
        projectId: EXPECTED_PROJECT_ID,
        credentialProjectId: EXPECTED_PROJECT_ID,
        principal: inventoryArgs[4],
      }),
      createClients: async () => ({
        databaseAuthVariableOverride: override,
        firestore: { collection() { firestoreReads++; return emptyCollection; } },
        database: { ref() { rtdbReads++; throw new Error('RTDB must not be read'); } },
      }),
    }), (error) => error instanceof MigrationError && error.code === 'rtdb_auth_override_unverified');
    assert.equal(firestoreReads, 0);
    assert.equal(rtdbReads, 0);
  }
});

test('bounded RTDB inventory never invokes fake write operations', async () => {
  const invoked = [];
  const forbiddenWrite = (operation) => () => { invoked.push(operation); throw new Error(`forbidden ${operation}`); };
  const database = fakeRtdb({}, { customPage(path, query) {
    invoked.push(`get:${path}:${query.pageSize}`);
    return { forEach() {} };
  } });
  const ref = database.ref;
  database.ref = (path) => ({
    ...ref(path),
    set: forbiddenWrite('set'), update: forbiddenWrite('update'), remove: forbiddenWrite('remove'),
    push: forbiddenWrite('push'), transaction: forbiddenWrite('transaction'),
  });
  const report = await readRealtimeDatabaseBoundedInventory({ database });
  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(invoked.length, RTDB_INVENTORY_COLLECTION_PATHS.length);
  assert.ok(invoked.every((entry) => entry.startsWith('get:/samvibhag/v1/')));
});

test('structural report carries partial bounded-read status without claiming unseen paths', () => {
  const bounded = {
    inventoryStatus: 'incomplete_for_configured_scope',
    checkedPaths: [{ path: RTDB_INVENTORY_COLLECTION_PATHS[0], status: 'failed' }],
    collectionCounts: {}, recordCount: 0, estimatedJsonBytes: 0, maxObservedRssBytes: 0,
    structuralNodeCounts: { objects: 0, arrays: 0, scalars: 0 }, issueCounts: { readFailures: 1 }, limits: RTDB_INVENTORY_LIMITS,
  };
  const report = buildStructuralInventoryReport({ snapshot: fixture(), rtdbBoundedInventory: bounded });
  assert.equal(report.inventoryStatus, 'incomplete_for_configured_scope');
  assert.deepEqual(report.realtimeDatabase.checkedPaths, bounded.checkedPaths);
  assert.equal(report.realtimeDatabase.checkedPaths.length, 1);
  assert.equal(report.realtimeDatabase.wholeDatabaseInventoried, false);
});

test('bounded RTDB inventory rejects arbitrary path options and unreasonable pagination settings', async () => {
  await assert.rejects(readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(), paths: ['/'] }),
    (error) => error instanceof MigrationError && error.code === 'unapproved_rtdb_path');
  await assert.rejects(readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(), limits: { pageSize: 1000 } }),
    (error) => error instanceof MigrationError && error.code === 'invalid_rtdb_inventory_limits');
  await assert.rejects(readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(), limits: { maxRecords: 10001 } }),
    (error) => error instanceof MigrationError && error.code === 'invalid_rtdb_inventory_limits');
  await assert.rejects(readRealtimeDatabaseBoundedInventory({ database: fakeRtdb(), limits: { maxRecordBytes: 1024 * 1024 } }),
    (error) => error instanceof MigrationError && error.code === 'invalid_rtdb_inventory_limits');
});

const inventoryArgs = [
  'inventory',
  '--database-url', EXPECTED_DATABASE_URL,
  '--expected-principal', EXPECTED_ADC_PRINCIPAL,
  '--confirm-database-url-verified',
  '--confirm-firestore-read-only-iam-verified',
  '--confirm-rtdb-read-only-rules-verified',
];

test('read-only inventory aborts before client creation when ADC credentials are missing', async () => {
  let clientsCreated = false;
  await assert.rejects(runInventory({
    argv: inventoryArgs,
    resolveAdcIdentity: async () => null,
    createClients: async () => { clientsCreated = true; throw new Error('must not initialize'); },
  }), (error) => error instanceof MigrationError && error.code === 'adc_identity_unverified');
  assert.equal(clientsCreated, false);
});

test('inventory rejects project and principal mismatches before creating clients', async () => {
  for (const identity of [
    { projectId: 'other-project', credentialProjectId: EXPECTED_PROJECT_ID, principal: inventoryArgs[4] },
    { projectId: EXPECTED_PROJECT_ID, credentialProjectId: EXPECTED_PROJECT_ID, principal: 'other@example.invalid' },
  ]) {
    let clientsCreated = false;
    await assert.rejects(runInventory({
      argv: inventoryArgs,
      resolveAdcIdentity: async () => identity,
      createClients: async () => { clientsCreated = true; throw new Error('must not initialize'); },
    }));
    assert.equal(clientsCreated, false);
  }
});

test('invalid CLI arguments abort before ADC lookup or client initialization', async () => {
  const previousExitCode = process.exitCode;
  const previousError = console.error;
  const errors = [];
  console.error = (line) => errors.push(line);
  try {
    await main(['inventory', '--write']);
    assert.equal(process.exitCode, 1);
    assert.deepEqual(errors.map((line) => JSON.parse(line)), [{ status: 'aborted', completeness: 'incomplete_for_configured_scope', code: 'unsupported_command_option' }]);
  } finally {
    process.exitCode = previousExitCode;
    console.error = previousError;
  }
});

test('read-only inventory pins both ADC and credential project IDs', async () => {
  assert.equal(EXPECTED_PROJECT_ID, 'samvibhag-a2299');
  assert.equal(EXPECTED_ADC_PRINCIPAL, 'samvibhag-migration-inventory@samvibhag-a2299.iam.gserviceaccount.com');
  assert.throws(() => verifyAdcIdentity({ projectId: 'wrong-project', credentialProjectId: 'wrong-project', principal: EXPECTED_ADC_PRINCIPAL }),
    (error) => error instanceof MigrationError && error.code === 'project_mismatch');
  assert.throws(() => verifyAdcIdentity({ projectId: EXPECTED_PROJECT_ID, credentialProjectId: 'wrong-project', principal: EXPECTED_ADC_PRINCIPAL }),
    (error) => error instanceof MigrationError && error.code === 'project_mismatch');
  assert.throws(() => verifyAdcIdentity({ projectId: EXPECTED_PROJECT_ID, credentialProjectId: EXPECTED_PROJECT_ID, principal: 'other@samvibhag-a2299.iam.gserviceaccount.com' }),
    (error) => error instanceof MigrationError && error.code === 'principal_mismatch');
});

test('conflicting expected-principal argument is rejected before ADC lookup or client initialization', async () => {
  const args = [...inventoryArgs];
  args[4] = 'someone-else@samvibhag-a2299.iam.gserviceaccount.com';
  errCode(() => parseInventoryArgs(args), 'principal_mismatch');
  let adcLookups = 0;
  let clientInitializations = 0;
  await assert.rejects(runInventory({
    argv: args,
    resolveAdcIdentity: async () => { adcLookups++; return null; },
    createClients: async () => { clientInitializations++; throw new Error('must not initialize'); },
  }), (error) => error instanceof MigrationError && error.code === 'principal_mismatch');
  assert.equal(adcLookups, 0);
  assert.equal(clientInitializations, 0);
});

test('inventory requires an explicit valid RTDB URL and read-only confirmations', () => {
  errCode(() => parseInventoryArgs(['inventory', ...inventoryArgs.slice(2).filter((arg) => arg !== '--database-url' && arg !== EXPECTED_DATABASE_URL)]), 'missing_database_url');
  errCode(() => parseInventoryArgs(['inventory', '--database-url', 'http://sample.firebaseio.com', ...inventoryArgs.slice(3)]), 'invalid_database_url');
  errCode(() => parseInventoryArgs(['inventory', '--database-url', 'https://other-default-rtdb.firebaseio.com', ...inventoryArgs.slice(3)]), 'invalid_database_url');
  errCode(() => parseInventoryArgs(inventoryArgs.filter((arg) => arg !== '--confirm-rtdb-read-only-rules-verified')), 'missing_read_only_confirmation');
  assert.equal(parseInventoryArgs(inventoryArgs).databaseUrl, EXPECTED_DATABASE_URL);
  const limited = parseInventoryArgs([...inventoryArgs, '--page-size', '25', '--max-records', '9999']);
  assert.deepEqual(limited.rtdbLimits, { pageSize: 25, maxRecords: 9999 });
  for (const args of [
    [...inventoryArgs, '--page-size', '26'],
    [...inventoryArgs, '--max-records', '10001'],
    [...inventoryArgs, '--page-size', '2', '--page-size', '3'],
    [...inventoryArgs, '--max-records', 'Infinity'],
  ]) errCode(() => parseInventoryArgs(args), args.at(-1) === '3' ? 'duplicate_option' : 'invalid_inventory_limit');
});

test('inventory applies configured RTDB page and record ceilings to the bounded adapter', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const report = await runInventory({
    argv: [...inventoryArgs, '--page-size', '3', '--max-records', '12'],
    resolveAdcIdentity: async () => ({
      projectId: EXPECTED_PROJECT_ID,
      credentialProjectId: EXPECTED_PROJECT_ID,
      principal: inventoryArgs[4],
    }),
    createClients: async () => ({
      databaseAuthVariableOverride: { uid: RTDB_RULES_UID },
      firestore: { collection: () => emptyCollection },
      database: fakeRtdb(),
    }),
  });
  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(report.realtimeDatabase.limits.pageSize, 3);
  assert.equal(report.realtimeDatabase.limits.maxRecords, 12);
});

test('inventory scope rejects unauthorized collection paths before querying them', async () => {
  let requested = null;
  await assert.rejects(readFirestoreSnapshot({
    db: { collection: (name) => { requested = name; throw new Error('unexpected database query'); } },
    collections: ['adminSecrets'],
  }), (error) => error instanceof MigrationError && error.code === 'unapproved_collection');
  assert.equal(requested, null);
  errCode(() => parseInventoryArgs(['inventory', '--collection', 'adminSecrets', ...inventoryArgs.slice(1)]), 'unsupported_command_option');
});

test('structural inventory report excludes private document values and summarizes existing RTDB paths', () => {
  const source = fixture();
  source.collections.users[0].data.email = 'private.person@example.invalid';
  source.collections.users[0].data.fcmTokens = ['private-token-value'];
  source.collections.groups[0].data.members.push('Private Member Name');
  delete source.collections.groups[0].data.recordedSettlements[0].fromUser;
  source.collections.groups[0].data.recordedSettlements[0].from = 'Private Member Name';
  const report = buildStructuralInventoryReport({
    snapshot: source,
    rtdbPathChecks: configuredPathChecks('accessible_present'),
  });
  const safeJson = JSON.stringify(report);
  for (const privateValue of ['private.person@example.invalid', 'private-token-value', 'Private Member Name', 'privateUid', 'secret-token', 'private@example.invalid']) {
    assert.equal(safeJson.includes(privateValue), false);
  }
  assert.equal(report.sourceCounts.users, 2);
  assert.equal(report.sourceCounts.expenses, 1);
  assert.equal(report.sourceCounts.recordedSettlements, 1);
  assert.equal(report.sourceCounts.activities, 1);
  assert.deepEqual(report.legacySettlementAliases, { fromAlias: 1, toAlias: 0, eitherAlias: 1 });
  assert.deepEqual(report.realtimeDatabase.checkedPaths, configuredPathChecks('accessible_present'));
  assert.equal(report.realtimeDatabase.wholeDatabaseInventoried, false);
  assert.equal(report.realtimeDatabase.pointInTimeConsistent, false);
  assert.equal(report.containsDocumentValues, false);
});

test('unsupported Firestore types are counted by type without field values or record paths', async () => {
  class FakeGeoPoint { constructor() { this.latitude = 51.5; this.longitude = -0.12; } }
  const users = [{ id: 'user-id-with-private-data', data: () => ({ email: 'hidden@example.invalid', location: new FakeGeoPoint() }) }];
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const userCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: users }; } };
  const unsupportedValues = [];
  const snapshot = await readFirestoreSnapshot({
    db: { collection: (name) => name === 'users' ? userCollection : emptyCollection },
    types: { GeoPoint: FakeGeoPoint },
    unsupportedValues,
  });
  const report = buildStructuralInventoryReport({ snapshot, rtdbPathChecks: configuredPathChecks(), unsupportedValues });
  const safeJson = JSON.stringify(report);
  assert.deepEqual(report.unsupportedTypeCounts, { GeoPoint: 1 });
  assert.equal(safeJson.includes('hidden@example.invalid'), false);
  assert.equal(safeJson.includes('user-id-with-private-data'), false);
  assert.equal(safeJson.includes('51.5'), false);
  assert.equal(report.migrationReadinessStatus, 'blocked_unsupported_source_values');
});

test('inventory report sanitizes unsupported type labels and rejects malformed activity snapshots', () => {
  const source = fixture();
  const report = buildStructuralInventoryReport({
    snapshot: source,
    rtdbPathChecks: configuredPathChecks(),
    unsupportedValues: [{ type: 'private-user@example.invalid token-secret' }],
  });
  const safeJson = JSON.stringify(report);
  assert.deepEqual(report.unsupportedTypeCounts, { UnknownSDKValue: 1 });
  assert.equal(safeJson.includes('private-user@example.invalid'), false);
  assert.equal(safeJson.includes('token-secret'), false);
  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(report.migrationReadinessStatus, 'blocked_unsupported_source_values');

  delete source.collections.groups[0].subcollections.activities;
  errCode(() => buildStructuralInventoryReport({ snapshot: source, rtdbPathChecks: configuredPathChecks() }), 'malformed_inventory_snapshot');
});

test('mixed supported and unsupported Firestore values block migration readiness without blocking inventory status', async () => {
  class FakeTimestamp { constructor(seconds, nanoseconds) { this.seconds = seconds; this.nanoseconds = nanoseconds; } }
  class FakeGeoPoint { constructor() { this.latitude = 10; this.longitude = 20; } }
  class FakeBytes { constructor() { this._buffer = Buffer.from('private-bytes'); } }
  const docs = [
    { id: 'synthetic-supported', data: () => ({ createdAt: new FakeTimestamp(123, 456) }) },
    { id: 'synthetic-unsupported', data: () => ({ location: new FakeGeoPoint(), attachment: new FakeBytes() }) },
  ];
  const usersCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs }; } };
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const unsupportedValues = [];
  const snapshot = await readFirestoreSnapshot({
    db: { collection: (name) => name === 'users' ? usersCollection : emptyCollection },
    types: { Timestamp: FakeTimestamp, GeoPoint: FakeGeoPoint, Bytes: FakeBytes },
    unsupportedValues,
  });
  const report = buildStructuralInventoryReport({ snapshot, rtdbPathChecks: configuredPathChecks(), unsupportedValues });
  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(report.migrationReadinessStatus, 'blocked_unsupported_source_values');
  assert.deepEqual(report.migrationReadinessIssueCounts, { unsupportedFirestoreValues: 2 });
  assert.deepEqual(report.unsupportedTypeCounts, { GeoPoint: 1, Bytes: 1 });
  assert.ok(snapshot.types['/users/synthetic-supported/data/createdAt']);
  assert.equal(JSON.stringify(report).includes('private-bytes'), false);
  assert.equal(JSON.stringify(report).includes('synthetic-unsupported'), false);
});

test('Firestore page failure rejects the inventory without returning a partial report or reading RTDB', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const failingCollection = { orderBy() { return this; }, limit() { return this; }, async get() { throw new Error('sensitive query details'); } };
  let rtdbRead = false;
  await assert.rejects(runInventory({
    argv: inventoryArgs,
    resolveAdcIdentity: async () => ({
      projectId: EXPECTED_PROJECT_ID,
      credentialProjectId: EXPECTED_PROJECT_ID,
      principal: inventoryArgs[4],
    }),
    createClients: async () => ({
      databaseAuthVariableOverride: { uid: RTDB_RULES_UID },
      firestore: { collection: (name) => name === 'users' ? failingCollection : emptyCollection },
      database: { ref() { rtdbRead = true; throw new Error('must not read RTDB after Firestore failure'); } },
    }),
  }), /sensitive query details/);
  assert.equal(rtdbRead, false);
});

test('required RTDB path failure returns unmistakably incomplete sanitized report', async () => {
  const emptyCollection = { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } };
  const report = await runInventory({
    argv: inventoryArgs,
    resolveAdcIdentity: async () => ({
      projectId: EXPECTED_PROJECT_ID,
      credentialProjectId: EXPECTED_PROJECT_ID,
      principal: inventoryArgs[4],
    }),
    createClients: async () => ({
      databaseAuthVariableOverride: { uid: RTDB_RULES_UID },
      firestore: { collection: () => emptyCollection },
      database: { ref(path) {
        assert.equal(path, RTDB_INVENTORY_COLLECTION_PATHS[0]);
        return { orderByKey() { return this; }, limitToFirst() { return this; }, async get() { throw new Error('secret-url private-value'); } };
      } },
    }),
  });
  assert.equal(report.inventoryStatus, 'incomplete_for_configured_scope');
  assert.deepEqual(report.realtimeDatabase.checkedPaths, [{ path: RTDB_INVENTORY_COLLECTION_PATHS[0], status: 'failed' }]);
  assert.equal(JSON.stringify(report).includes('secret-url'), false);
});

test('inventory report rejects path results outside the fixed allowlist', () => {
  const source = fixture();
  errCode(() => buildStructuralInventoryReport({
    snapshot: source,
    rtdbPathChecks: [{ path: '/users', status: 'accessible_absent' }],
  }), 'malformed_rtdb_path_checks');
  const incomplete = buildStructuralInventoryReport({
    snapshot: source,
    rtdbPathChecks: [{ path: RTDB_INVENTORY_COLLECTION_PATHS[0], status: 'failed' }],
  });
  assert.equal(incomplete.inventoryStatus, 'incomplete_for_configured_scope');
});

test('a root-only RTDB result cannot claim completeness for the five-path inventory scope', () => {
  errCode(() => buildStructuralInventoryReport({
    snapshot: fixture(),
    rtdbPathChecks: [{ path: '/samvibhag/v1', status: 'accessible_present' }],
  }), 'malformed_rtdb_path_checks');
});

test('Firestore pagination failure after a successful page rejects instead of returning a partial snapshot', async () => {
  let page = 0;
  const users = {
    orderBy() { return this; },
    limit() { return this; },
    startAfter() { return this; },
    async get() {
      page++;
      if (page === 1) return { docs: [{ id: 'synthetic-user', data: () => ({ displayName: 'Synthetic' }) }] };
      throw new Error('synthetic second-page failure');
    },
  };
  await assert.rejects(readFirestoreSnapshot({
    db: { collection: (name) => name === 'users' ? users : { orderBy() { return this; }, limit() { return this; }, async get() { return { docs: [] }; } } },
    pageSize: 1,
  }), /synthetic second-page failure/);
  assert.equal(page, 2);
});

test('all mutating, migration, deployment, and unknown command options are rejected', () => {
  const forbidden = ['--write', '--delete', '--deploy', '--migrate', '--cutover', '--apply-local', '--target', '--collection', '--verbose', '--dry-run'];
  for (const option of forbidden) {
    errCode(() => parseInventoryArgs(['inventory', option, ...inventoryArgs.slice(1)]), 'unsupported_command_option');
  }
  for (const command of ['write', 'delete', 'deploy', 'migrate', 'cutover', 'unknown']) {
    errCode(() => parseInventoryArgs([command, ...inventoryArgs.slice(1)]), 'inventory_only');
  }
});
