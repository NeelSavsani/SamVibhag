#!/usr/bin/env node

// Guarded read-only production inventory. This is separate from migrate.mjs,
// whose CLI remains synthetic-fixture-only. No writes or deploy APIs are used.
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { MigrationError } from './migrate.mjs';
import { readFirestoreSnapshot, readRealtimeDatabaseBoundedInventory, RTDB_INVENTORY_COLLECTION_PATHS, RTDB_INVENTORY_LIMITS } from './read_only_adapters.mjs';

export const EXPECTED_PROJECT_ID = 'samvibhag-a2299';
export const EXPECTED_DATABASE_URL = 'https://samvibhag-a2299-default-rtdb.asia-southeast1.firebasedatabase.app';
export const EXPECTED_ADC_PRINCIPAL = 'samvibhag-migration-inventory@samvibhag-a2299.iam.gserviceaccount.com';
export const RTDB_RULES_UID = 'samvibhag-migration-inventory-reader';
const ALLOWED_OPTIONS = new Set([
  '--database-url',
  '--expected-principal',
  '--page-size',
  '--max-records',
  '--confirm-database-url-verified',
  '--confirm-firestore-read-only-iam-verified',
  '--confirm-rtdb-read-only-rules-verified',
]);
const KNOWN_UNSUPPORTED_TYPES = new Set(['GeoPoint', 'DocumentReference', 'Bytes', 'Timestamp', 'UnknownSDKValue']);
const RTDB_PATH_STATUSES = new Set(['accessible_present', 'accessible_absent', 'failed']);

/** Require the exact limited-privilege RTDB identity; null/default Admin access is forbidden. */
export function verifyRtdbAuthOverride(override) {
  if (!override || typeof override !== 'object' || Array.isArray(override) ||
      Object.getPrototypeOf(override) !== Object.prototype ||
      Object.keys(override).length !== 1 || override.uid !== RTDB_RULES_UID) {
    throw new MigrationError('rtdb_auth_override_unverified', 'The required RTDB limited-privilege identity is missing or invalid.');
  }
  return true;
}

export function buildInventoryAppOptions({ credential, databaseUrl }) {
  return {
    credential,
    projectId: EXPECTED_PROJECT_ID,
    databaseURL: databaseUrl,
    databaseAuthVariableOverride: { uid: RTDB_RULES_UID },
  };
}

export function parseInventoryArgs(argv) {
  if (argv[0] !== 'inventory') throw new MigrationError('inventory_only', 'Only the inventory command is supported.');
  const options = {
    command: 'inventory',
    expectedPrincipal: EXPECTED_ADC_PRINCIPAL,
    rtdbLimits: { pageSize: RTDB_INVENTORY_LIMITS.pageSize, maxRecords: RTDB_INVENTORY_LIMITS.maxRecords },
  };
  const suppliedLimits = new Set();
  let principalAssertionSeen = false;
  for (let index = 1; index < argv.length; index++) {
    const key = argv[index];
    if (!ALLOWED_OPTIONS.has(key)) throw new MigrationError('unsupported_command_option', `Unsupported option '${key}'.`);
    if (key.startsWith('--confirm-')) {
      if (options[key]) throw new MigrationError('invalid_confirmation', `Duplicate confirmation option '${key}'.`);
      options[key] = true;
      continue;
    }
    const value = argv[++index];
    if (!value || value.startsWith('--')) throw new MigrationError('missing_option_value', `Option '${key}' requires a value.`);
    if (key === '--page-size' || key === '--max-records') {
      if (suppliedLimits.has(key)) throw new MigrationError('duplicate_option');
      suppliedLimits.add(key);
      if (!/^\d{1,8}$/u.test(value)) throw new MigrationError('invalid_inventory_limit');
      const number = Number(value);
      const field = key === '--page-size' ? 'pageSize' : 'maxRecords';
      const cap = key === '--page-size' ? 25 : RTDB_INVENTORY_LIMITS.maxRecords;
      if (!Number.isSafeInteger(number) || number < 1 || number > cap) throw new MigrationError('invalid_inventory_limit');
      options.rtdbLimits[field] = number;
      continue;
    }
    const field = key === '--database-url' ? 'databaseUrl' : 'expectedPrincipal';
    if (field === 'expectedPrincipal') {
      if (principalAssertionSeen) throw new MigrationError('duplicate_option');
      principalAssertionSeen = true;
      if (value !== EXPECTED_ADC_PRINCIPAL) throw new MigrationError('principal_mismatch');
      continue;
    }
    if (options[field] !== undefined) throw new MigrationError('duplicate_option', `Option '${key}' was supplied more than once.`);
    options[field] = value;
  }
  if (!options.databaseUrl) throw new MigrationError('missing_database_url', 'An explicitly verified RTDB URL is required.');
  for (const confirmation of [
    '--confirm-database-url-verified',
    '--confirm-firestore-read-only-iam-verified',
    '--confirm-rtdb-read-only-rules-verified',
  ]) {
    if (!options[confirmation]) throw new MigrationError('missing_read_only_confirmation', `Required verification is missing: ${confirmation}.`);
  }
  validateDatabaseUrl(options.databaseUrl);
  return options;
}

function validateDatabaseUrl(value) {
  let url;
  try { url = new URL(value); }
  catch { throw new MigrationError('invalid_database_url', 'The RTDB URL is invalid.'); }
  if (value !== EXPECTED_DATABASE_URL || url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
      !(url.hostname.endsWith('.firebaseio.com') || url.hostname.endsWith('.firebasedatabase.app'))) {
    throw new MigrationError('invalid_database_url', 'The RTDB URL must be a verified HTTPS Firebase database origin without credentials, path, query, or fragment.');
  }
}

export function verifyAdcIdentity(identity) {
  if (!identity || typeof identity.projectId !== 'string' || typeof identity.credentialProjectId !== 'string' || typeof identity.principal !== 'string') {
    throw new MigrationError('adc_identity_unverified', 'ADC identity could not be verified; inventory aborted.');
  }
  if (identity.projectId !== EXPECTED_PROJECT_ID || identity.credentialProjectId !== EXPECTED_PROJECT_ID) {
    throw new MigrationError('project_mismatch', 'ADC project does not match the pinned SamVibhag project; inventory aborted.');
  }
  if (identity.principal !== EXPECTED_ADC_PRINCIPAL) {
    throw new MigrationError('principal_mismatch', 'ADC principal does not match the explicitly approved principal; inventory aborted.');
  }
  return true;
}

function blankCounts() {
  return {
    users: 0,
    usernames: 0,
    groups: 0,
    activities: 0,
    expenses: 0,
    recordedSettlements: 0,
  };
}

function isNonEmptyId(value) { return typeof value === 'string' && value.trim().length > 0; }
function duplicates(values) {
  const seen = new Set();
  let count = 0;
  for (const value of values) {
    if (seen.has(value)) count++;
    seen.add(value);
  }
  return count;
}

/** Build an aggregate-only report. Never includes profile fields, UIDs, names, or tokens. */
export function buildStructuralInventoryReport({ snapshot, rtdbPathChecks, rtdbBoundedInventory, unsupportedValues = [] }) {
  const collections = snapshot?.collections;
  if (!collections || !Array.isArray(collections.users) || !Array.isArray(collections.usernames) || !Array.isArray(collections.groups)) {
    throw new MigrationError('malformed_inventory_snapshot', 'The audited Firestore inventory snapshot is incomplete.');
  }
  const boundedChecks = rtdbBoundedInventory?.checkedPaths;
  const checkedPaths = boundedChecks ?? rtdbPathChecks;
  const expectedPaths = RTDB_INVENTORY_COLLECTION_PATHS;
  if (!Array.isArray(checkedPaths) || checkedPaths.length > expectedPaths.length ||
      checkedPaths.some((check, index) => check?.path !== expectedPaths[index] ||
        !(RTDB_PATH_STATUSES.has(check?.status) || check?.status === 'limit_exceeded' || check?.status === 'invalid_data'))) {
    throw new MigrationError('malformed_rtdb_path_checks', 'The fixed RTDB inventory path results are incomplete or malformed.');
  }
  const counts = blankCounts();
  counts.users = collections.users.length;
  counts.usernames = collections.usernames.length;
  counts.groups = collections.groups.length;
  const userIds = new Set(collections.users.map((doc) => doc.id));
  const duplicateIds = { users: 0, usernames: 0, groups: 0, activities: 0, expenses: 0, recordedSettlements: 0 };
  const missingIds = { activities: 0, expenses: 0, recordedSettlements: 0 };
  const orphanRelationships = {
    usernamesToUsers: 0,
    groupCreatorsToUsers: 0,
    groupMembersToUsers: 0,
    memberIdentitiesToMembers: 0,
    expensePartyNames: 0,
    settlementPartyNames: 0,
    activityGroupReferences: 0,
  };
  const legacySettlementAliases = { fromAlias: 0, toAlias: 0, eitherAlias: 0 };

  for (const key of ['users', 'usernames', 'groups']) {
    duplicateIds[key] = duplicates(collections[key].map((doc) => doc.id));
  }
  for (const username of collections.usernames) {
    if (!userIds.has(username?.data?.uid)) orphanRelationships.usernamesToUsers++;
  }
  const groupIds = new Set(collections.groups.map((doc) => doc.id));
  for (const group of collections.groups) {
    if (!group || typeof group.id !== 'string' || !group.data || typeof group.data !== 'object' || Array.isArray(group.data) ||
        !group.subcollections || !Array.isArray(group.subcollections.activities)) {
      throw new MigrationError('malformed_inventory_snapshot', 'A group or its audited activities collection is malformed.');
    }
    const data = group?.data ?? {};
    const members = Array.isArray(data.members) ? data.members : [];
    const memberUids = Array.isArray(data.memberUids) ? data.memberUids : [];
    if (!userIds.has(data.createdBy)) orphanRelationships.groupCreatorsToUsers++;
    for (const uid of new Set(memberUids)) if (!userIds.has(uid)) orphanRelationships.groupMembersToUsers++;
    for (const identity of Array.isArray(data.memberIdentities) ? data.memberIdentities : []) {
      if (!memberUids.includes(identity?.uid) && identity?.uid !== data.createdBy) orphanRelationships.memberIdentitiesToMembers++;
    }
    const expenses = Array.isArray(data.expenses) ? data.expenses : [];
    const settlements = Array.isArray(data.recordedSettlements) ? data.recordedSettlements : [];
    counts.expenses += expenses.length;
    counts.recordedSettlements += settlements.length;
    duplicateIds.expenses += duplicates(expenses.filter((record) => isNonEmptyId(record?.id)).map((record) => record.id));
    duplicateIds.recordedSettlements += duplicates(settlements.filter((record) => isNonEmptyId(record?.id)).map((record) => record.id));
    missingIds.expenses += expenses.filter((record) => !isNonEmptyId(record?.id)).length;
    missingIds.recordedSettlements += settlements.filter((record) => !isNonEmptyId(record?.id)).length;

    const hasUniqueName = (name) => members.filter((candidate) => candidate === name).length === 1;
    for (const expense of expenses) {
      if (!hasUniqueName(expense?.paidBy)) orphanRelationships.expensePartyNames++;
      for (const name of Array.isArray(expense?.splitBetween) ? expense.splitBetween : []) {
        if (!hasUniqueName(name)) orphanRelationships.expensePartyNames++;
      }
      for (const name of Object.keys(expense?.customSplits ?? {})) {
        if (!hasUniqueName(name)) orphanRelationships.expensePartyNames++;
      }
    }
    for (const settlement of settlements) {
      const hasFromAlias = settlement?.from !== undefined;
      const hasToAlias = settlement?.to !== undefined;
      if (hasFromAlias) legacySettlementAliases.fromAlias++;
      if (hasToAlias) legacySettlementAliases.toAlias++;
      if (hasFromAlias || hasToAlias) legacySettlementAliases.eitherAlias++;
      if (!hasUniqueName(settlement?.fromUser ?? settlement?.from) || !hasUniqueName(settlement?.toUser ?? settlement?.to)) {
        orphanRelationships.settlementPartyNames++;
      }
    }

    const activities = group.subcollections.activities;
    counts.activities += activities.length;
    for (const activity of activities) {
      if (!activity || typeof activity.id !== 'string' || !activity.data || typeof activity.data !== 'object' || Array.isArray(activity.data)) {
        throw new MigrationError('malformed_inventory_snapshot', 'An audited activity record is malformed.');
      }
    }
    duplicateIds.activities += duplicates(activities.filter((activity) => isNonEmptyId(activity?.id)).map((activity) => activity.id));
    missingIds.activities += activities.filter((activity) => !isNonEmptyId(activity?.id)).length;
    for (const activity of activities) if (activity?.data?.groupId && activity.data.groupId !== group.id) orphanRelationships.activityGroupReferences++;
  }

  const unsupportedTypeCounts = {};
  for (const issue of unsupportedValues) {
    const candidate = typeof issue?.type === 'string' ? issue.type : 'UnknownSDKValue';
    const type = KNOWN_UNSUPPORTED_TYPES.has(candidate) ? candidate : 'UnknownSDKValue';
    unsupportedTypeCounts[type] = (unsupportedTypeCounts[type] ?? 0) + 1;
  }
  const unsupportedValueCount = Object.values(unsupportedTypeCounts).reduce((total, count) => total + count, 0);

  const rtdbComplete = rtdbBoundedInventory
    ? rtdbBoundedInventory.inventoryStatus === 'complete_for_configured_scope' && checkedPaths.length === expectedPaths.length && checkedPaths.every((check) => check.status === 'accessible_present' || check.status === 'accessible_absent')
    : checkedPaths.length === expectedPaths.length && checkedPaths.every((check) => check.status === 'accessible_present' || check.status === 'accessible_absent');
  return {
    reportType: 'samvibhag-read-only-structural-inventory-v1',
    inventoryStatus: rtdbComplete ? 'complete_for_configured_scope' : 'incomplete_for_configured_scope',
    migrationReadinessStatus: unsupportedValueCount > 0 ? 'blocked_unsupported_source_values' : 'not_assessed_by_inventory',
    migrationReadinessIssueCounts: { unsupportedFirestoreValues: unsupportedValueCount },
    projectId: EXPECTED_PROJECT_ID,
    sourceScope: ['users', 'usernames', 'groups', 'groups/{groupId}/activities'],
    sourceCounts: counts,
    ...(snapshot.readStats ? { firestoreRead: snapshot.readStats } : {}),
    duplicateIds,
    missingIds,
    orphanRelationships,
    legacySettlementAliases,
    unsupportedTypeCounts,
    realtimeDatabase: {
      checkedPaths,
      ...(rtdbBoundedInventory ? {
        collectionCounts: rtdbBoundedInventory.collectionCounts,
        recordCount: rtdbBoundedInventory.recordCount,
        estimatedJsonBytes: rtdbBoundedInventory.estimatedJsonBytes,
        maxObservedRssBytes: rtdbBoundedInventory.maxObservedRssBytes,
        structuralNodeCounts: rtdbBoundedInventory.structuralNodeCounts,
        issueCounts: rtdbBoundedInventory.issueCounts,
        limits: rtdbBoundedInventory.limits,
      } : {}),
      wholeDatabaseInventoried: false,
      pointInTimeConsistent: false,
    },
    containsDocumentValues: false,
  };
}

export async function runInventory({ argv, resolveAdcIdentity, createClients }) {
  const options = parseInventoryArgs(argv);
  if (typeof resolveAdcIdentity !== 'function' || typeof createClients !== 'function') {
    throw new MigrationError('inventory_dependencies_missing', 'Inventory dependencies are unavailable.');
  }
  const identity = await resolveAdcIdentity();
  verifyAdcIdentity(identity);
  const clients = await createClients(options);
  // Validate the installed app's captured options before any source or RTDB read.
  // This also makes an injected full-privilege/fallback client fail closed.
  verifyRtdbAuthOverride(clients?.databaseAuthVariableOverride);
  const unsupportedValues = [];
  const snapshot = await readFirestoreSnapshot({
    db: clients.firestore,
    pageSize: 200,
    types: clients.types,
    unsupportedValues,
  });
  const rtdbBoundedInventory = await readRealtimeDatabaseBoundedInventory({ database: clients.database, limits: options.rtdbLimits });
  return buildStructuralInventoryReport({ snapshot, rtdbPathChecks: rtdbBoundedInventory.checkedPaths, rtdbBoundedInventory, unsupportedValues });
}

function adminRequire() {
  const functionsPackage = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../functions/package.json');
  return createRequire(functionsPackage);
}

async function resolveInstalledAdcIdentity(expectedProjectId) {
  const require = adminRequire();
  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  const credential = await auth.getClient();
  const projectId = await auth.getProjectId();
  const credentialMetadata = await auth.getCredentials();
  const principal = credentialMetadata.client_email;
  if (!projectId || projectId !== expectedProjectId || !principal) {
    throw new MigrationError('adc_identity_unverified', 'ADC project or service-account principal could not be verified.');
  }
  // `credential` is intentionally not logged or returned; it remains private to GoogleAuth.
  void credential;
  return { projectId, credentialProjectId: credentialMetadata.project_id, principal };
}

async function createInstalledAdminClients(options) {
  const require = adminRequire();
  const admin = require('firebase-admin');
  const credential = admin.credential.applicationDefault();
  const app = admin.initializeApp(buildInventoryAppOptions({ credential, databaseUrl: options.databaseUrl }),
    `samvibhag-readonly-inventory-${process.pid}`);
  const databaseAuthVariableOverride = app.options?.databaseAuthVariableOverride;
  verifyRtdbAuthOverride(databaseAuthVariableOverride);
  return {
    firestore: admin.firestore(app),
    database: admin.database(app),
    databaseAuthVariableOverride,
    types: {
      Timestamp: admin.firestore.Timestamp,
      GeoPoint: admin.firestore.GeoPoint,
      DocumentReference: admin.firestore.DocumentReference,
      Bytes: admin.firestore.Blob,
    },
  };
}

export async function main(argv = process.argv.slice(2)) {
  try {
    // Parse and require every safety confirmation before ADC lookup or SDK initialization.
    const options = parseInventoryArgs(argv);
    const report = await runInventory({
      argv,
      resolveAdcIdentity: () => resolveInstalledAdcIdentity(EXPECTED_PROJECT_ID),
      createClients: createInstalledAdminClients,
    });
    console.log(JSON.stringify(report, null, 2));
    if (report.inventoryStatus !== 'complete_for_configured_scope') process.exitCode = 1;
    return options;
  } catch (error) {
    const code = error instanceof MigrationError && /^[a-z0-9_]{1,64}$/u.test(error.code) ? error.code : 'inventory_failed';
    // Never print exception messages: SDK errors can contain URLs or source details.
    console.error(JSON.stringify({
      status: 'aborted',
      completeness: 'incomplete_for_configured_scope',
      code,
    }));
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
