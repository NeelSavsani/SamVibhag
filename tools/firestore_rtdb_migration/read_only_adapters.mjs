// Read-only adapters for an explicitly supplied Firebase Admin client.
// This module never initializes Firebase, discovers credentials, or writes data.

import { MigrationError } from './migrate.mjs';
import { createRequire } from 'node:module';

const functionsRequire = createRequire(new URL('../../functions/package.json', import.meta.url));

const DEFAULT_COLLECTIONS = ['users', 'usernames', 'groups'];
export const FIRESTORE_INVENTORY_LIMITS = Object.freeze({
  pageSize: 200,
  maxRecords: 10000,
  maxRecordBytes: 256 * 1024,
  maxTotalBytes: 16 * 1024 * 1024,
});
export const LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION = '7.11.6';
export const RTDB_INVENTORY_COLLECTION_PATHS = Object.freeze([
  '/samvibhag/v1/users',
  '/samvibhag/v1/usernames',
  '/samvibhag/v1/groups',
  '/samvibhag/v1/userGroups',
  '/samvibhag/v1/migrationRuns',
]);
export const RTDB_INVENTORY_LIMITS = Object.freeze({
  pageSize: 1,
  maxRecords: 10000,
  maxRecordBytes: 256 * 1024,
  maxTotalBytes: 16 * 1024 * 1024,
  maxRssBytes: 256 * 1024 * 1024,
});
const RTDB_INVENTORY_LIMIT_CAPS = Object.freeze({
  pageSize: 25,
  maxRecords: 10000,
  maxRecordBytes: 256 * 1024,
  maxTotalBytes: 16 * 1024 * 1024,
  maxRssBytes: 256 * 1024 * 1024,
});

function pointerPart(value) {
  return String(value).replaceAll('~', '~0').replaceAll('/', '~1');
}

function pointer(...parts) {
  return `/${parts.map(pointerPart).join('/')}`;
}

function compareIds(left, right) {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}

function configureLosslessNumericDecoding(db, sdkVersion) {
  let installedVersion;
  try { installedVersion = functionsRequire('@google-cloud/firestore/package.json').version; }
  catch { throw new MigrationError('firestore_sdk_version_unavailable'); }
  if (installedVersion !== LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION || sdkVersion !== installedVersion) {
    throw new MigrationError('unsupported_firestore_sdk_version');
  }
  if (typeof db.settings !== 'function') throw new MigrationError('numeric_mode_unavailable');
  try { db.settings({ useBigInt: true }); }
  catch { throw new MigrationError('numeric_mode_unavailable'); }
}

function doubleDescriptor(value) {
  if (!Number.isFinite(value)) throw new MigrationError('numeric_type_unverified');
  const buffer = Buffer.alloc(8);
  buffer.writeDoubleBE(value);
  return { type: 'Double', ieee754Hex: buffer.toString('hex') };
}

function normalizeFirestoreValue(value, typeMap, sourcePointer, types, unsupportedValues, preserveNumericTypes) {
  if (typeof value === 'bigint') {
    if (value < -(1n << 63n) || value > (1n << 63n) - 1n) throw new MigrationError('numeric_type_unverified');
    typeMap[sourcePointer] = { type: 'Integer', integerDecimal: String(value) };
    return Number(value);
  }
  if (typeof value === 'number' && preserveNumericTypes) {
    typeMap[sourcePointer] = doubleDescriptor(value);
    return value;
  }
  if (value === null || typeof value !== 'object') return value;
  if (types.Timestamp && value instanceof types.Timestamp) {
    typeMap[sourcePointer] = {
      type: 'Timestamp',
      seconds: value.seconds,
      nanoseconds: value.nanoseconds,
    };
    return null;
  }
  const unsupportedType = ['GeoPoint', 'DocumentReference', 'Bytes'].find((name) => types[name] && value instanceof types[name]);
  if (unsupportedType) return unsupportedValue(unsupportedType, sourcePointer, unsupportedValues);
  if (Array.isArray(value)) {
    return value.map((item, index) => normalizeFirestoreValue(item, typeMap, `${sourcePointer}/${index}`, types, unsupportedValues, preserveNumericTypes));
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    return unsupportedValue(value.constructor?.name ?? 'UnknownSDKValue', sourcePointer, unsupportedValues);
  }
  const result = {};
  for (const key of Object.keys(value)) {
    Object.defineProperty(result, key, {
      value: normalizeFirestoreValue(value[key], typeMap, `${sourcePointer}/${pointerPart(key)}`, types, unsupportedValues, preserveNumericTypes),
      enumerable: true,
      writable: true,
      configurable: true,
    });
  }
  return result;
}

function unsupportedValue(type, sourcePointer, unsupportedValues) {
  if (!unsupportedValues) throw new MigrationError('unsupported_firestore_value', `${type} requires an approved mapping at ${sourcePointer}.`, { type });
  unsupportedValues.push({ type, sourcePointer });
  // This sentinel is for structural inventory only. Never pass a captured
  // inventory snapshot to buildMigrationPlan or any migration writer.
  return { __inventoryUnsupportedType: type };
}

async function readPagedCollection(collectionRef, { pageSize, path, onPage, budget, limits, dataCache }) {
  if (!Number.isInteger(pageSize) || pageSize < 1) throw new MigrationError('invalid_page_size', 'Page size must be a positive integer.');
  const docs = [];
  let cursor = null;
  while (true) {
    let query = collectionRef.orderBy('__name__').limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (!page || !Array.isArray(page.docs)) throw new MigrationError('malformed_firestore_page', `Invalid page returned for ${path}.`);
    if (page.docs.length > pageSize) throw new MigrationError('page_size_exceeded', `Firestore returned more than ${pageSize} documents for ${path}.`);
    if (page.docs.length === 0) break;
    for (const doc of page.docs) {
      if (!doc || typeof doc.id !== 'string' || !doc.id || typeof doc.data !== 'function') {
        throw new MigrationError('malformed_firestore_document', `Malformed Firestore document in ${path}.`);
      }
      if (budget.records >= limits.maxRecords) throw new MigrationError('firestore_record_limit_exceeded');
      let data;
      let serialized;
      try {
        data = doc.data();
        // BigInt mode is optional in Firestore SDK settings. For byte-budget
        // estimation only, represent it as the corresponding JS Number; the
        // exact signed decimal has already been captured from integerValue.
        serialized = JSON.stringify(data, (_key, value) => typeof value === 'bigint' ? Number(value) : value);
      } catch {
        throw new MigrationError('numeric_type_unverified');
      }
      if (typeof serialized !== 'string') throw new MigrationError('malformed_firestore_document');
      const bytes = Buffer.byteLength(serialized, 'utf8');
      if (bytes > limits.maxRecordBytes) throw new MigrationError('firestore_record_size_exceeded');
      if (budget.bytes + bytes > limits.maxTotalBytes) throw new MigrationError('firestore_total_size_exceeded');
      budget.records++;
      budget.bytes += bytes;
      dataCache.set(doc, data);
      docs.push(doc);
    }
    cursor = page.docs.at(-1);
    onPage?.({ count: page.docs.length });
    if (page.docs.length < pageSize) break;
  }
  return docs;
}

/**
 * Read users, usernames, groups, and each group's activities using stable
 * document-ID pagination. `db` and SDK value classes must be supplied by the
 * caller; this module does not initialize an Admin app. Setting
 * `preserveNumericTypes` uses the documented Firestore `useBigInt` setting and
 * is supported only with the locally verified SDK version.
 */
export async function readFirestoreSnapshot({
  db,
  pageSize = FIRESTORE_INVENTORY_LIMITS.pageSize,
  limits = {},
  collections = DEFAULT_COLLECTIONS,
  types = {},
  onPage,
  unsupportedValues,
  preserveNumericTypes = false,
  firestoreSdkVersion,
}) {
  if (!db || typeof db.collection !== 'function') throw new MigrationError('missing_firestore_client', 'An explicitly initialized Firestore client is required.');
  if (!limits || Object.keys(limits).some((key) => !Object.hasOwn(FIRESTORE_INVENTORY_LIMITS, key))) throw new MigrationError('invalid_firestore_inventory_limits');
  const sourceLimits = { ...FIRESTORE_INVENTORY_LIMITS, ...limits, pageSize };
  if (!Number.isSafeInteger(sourceLimits.pageSize) || sourceLimits.pageSize < 1 || sourceLimits.pageSize > FIRESTORE_INVENTORY_LIMITS.pageSize ||
      !Number.isSafeInteger(sourceLimits.maxRecords) || sourceLimits.maxRecords < 1 || sourceLimits.maxRecords > FIRESTORE_INVENTORY_LIMITS.maxRecords ||
      !Number.isSafeInteger(sourceLimits.maxRecordBytes) || sourceLimits.maxRecordBytes < 1 || sourceLimits.maxRecordBytes > FIRESTORE_INVENTORY_LIMITS.maxRecordBytes ||
      !Number.isSafeInteger(sourceLimits.maxTotalBytes) || sourceLimits.maxTotalBytes < 1 || sourceLimits.maxTotalBytes > FIRESTORE_INVENTORY_LIMITS.maxTotalBytes) {
    throw new MigrationError('invalid_firestore_inventory_limits');
  }
  if (preserveNumericTypes) configureLosslessNumericDecoding(db, firestoreSdkVersion);
  const typeMap = {};
  const budget = { records: 0, bytes: 0 };
  const dataCache = new WeakMap();
  const output = { format: 'samvibhag-firestore-fixture-v1', types: typeMap, collections: {}, readStats: { recordsRead: 0, estimatedJsonBytes: 0, limits: sourceLimits } };
  const sourceCollections = [...new Set(collections)].sort(compareIds);

  for (const collectionName of sourceCollections) {
    if (!['users', 'usernames', 'groups'].includes(collectionName)) {
      throw new MigrationError('unapproved_collection', `Collection '${collectionName}' is not in the audited source set.`);
    }
    const sourceDocs = await readPagedCollection(db.collection(collectionName), { ...sourceLimits, path: collectionName, onPage, budget, limits: sourceLimits, dataCache });
    const mappedDocs = [];
    for (const doc of sourceDocs) {
      const docPointer = pointer(collectionName, doc.id);
      const data = normalizeFirestoreValue(dataCache.get(doc), typeMap, `${docPointer}/data`, types, unsupportedValues, preserveNumericTypes);
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new MigrationError('malformed_firestore_document', `${docPointer} must contain an object.`);
      if (collectionName === 'groups') {
        const activityDocs = await readPagedCollection(doc.ref.collection('activities'), { ...sourceLimits, path: `${collectionName}/${doc.id}/activities`, onPage, budget, limits: sourceLimits, dataCache });
        const activities = activityDocs.map((activity) => ({
          id: activity.id,
          data: normalizeFirestoreValue(dataCache.get(activity), typeMap, `${pointer(collectionName, doc.id, 'activities', activity.id)}`, types, unsupportedValues, preserveNumericTypes),
        }));
        mappedDocs.push({ id: doc.id, data, subcollections: { activities } });
      } else {
        mappedDocs.push({ id: doc.id, data });
      }
    }
    output.collections[collectionName] = mappedDocs;
  }
  output.readStats.numericDecoding = preserveNumericTypes ? 'useBigInt' : 'unverified';
  if (preserveNumericTypes) output.readStats.numericSdkVersion = firestoreSdkVersion;
  output.readStats.recordsRead = budget.records;
  output.readStats.estimatedJsonBytes = budget.bytes;
  return output;
}

const FORBIDDEN_RTDB_KEY = /[.#$\[\]/\u0000-\u001f\u007f]/u;

function serializedStringBytes(value) {
  let bytes = 2; // JSON quotes
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code === 0x22 || code === 0x5c || code === 0x08 || code === 0x09 || code === 0x0a || code === 0x0c || code === 0x0d) bytes += 2;
    else if (code < 0x20) bytes += 6;
    else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length && value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) {
      bytes += 4;
      index++;
    } else if (code >= 0xd800 && code <= 0xdfff) bytes += 6;
    else if (code <= 0x7f) bytes++;
    else if (code <= 0x7ff) bytes += 2;
    else bytes += 3;
  }
  return bytes;
}

function inspectRecord(value) {
  const counts = { invalidKeys: 0, objectNodes: 0, arrayNodes: 0, scalarNodes: 0 };
  const stack = [value];
  let bytes = 0;
  const seen = new Set();
  while (stack.length) {
    const current = stack.pop();
    if (current === null) { bytes += 4; counts.scalarNodes++; continue; }
    if (typeof current === 'string') { bytes += serializedStringBytes(current); counts.scalarNodes++; continue; }
    if (typeof current === 'boolean') { bytes += current ? 4 : 5; counts.scalarNodes++; continue; }
    if (typeof current === 'number' && Number.isFinite(current)) { bytes += Buffer.byteLength(String(current)); counts.scalarNodes++; continue; }
    if (typeof current !== 'object') throw new MigrationError('unsupported_rtdb_value');
    if (seen.has(current)) throw new MigrationError('unsupported_rtdb_value');
    seen.add(current);
    if (Array.isArray(current)) {
      counts.arrayNodes++;
      bytes += 2 + Math.max(0, current.length - 1);
      for (let index = current.length - 1; index >= 0; index--) stack.push(current[index]);
    } else {
      counts.objectNodes++;
      const keys = Object.keys(current);
      bytes += 2 + Math.max(0, keys.length - 1);
      for (const key of keys) {
        if (!key || FORBIDDEN_RTDB_KEY.test(key)) counts.invalidKeys++;
        bytes += serializedStringBytes(key) + 1;
        stack.push(current[key]);
      }
    }
  }
  return { bytes, counts };
}

function validateBoundedLimits(limits) {
  const keys = Object.keys(RTDB_INVENTORY_LIMITS);
  if (!limits || Object.keys(limits).some((key) => !keys.includes(key))) throw new MigrationError('invalid_rtdb_inventory_limits');
  const merged = { ...RTDB_INVENTORY_LIMITS, ...limits };
  if (Object.keys(merged).some((key) => !Number.isSafeInteger(merged[key]) || merged[key] < 1 || merged[key] > RTDB_INVENTORY_LIMIT_CAPS[key])) {
    throw new MigrationError('invalid_rtdb_inventory_limits');
  }
  return merged;
}

/**
 * Inspect schema-defined RTDB collections using one-key pages. Each page is
 * measured and discarded before another is requested. RTDB still returns the
 * complete value of each selected child, so maxRecordBytes is checked as soon
 * as that child is received; it cannot prevent an oversized single-child
 * response from being materialized by the SDK.
 */
export async function readRealtimeDatabaseBoundedInventory(options) {
  const allowedOptions = new Set(['database', 'limits', 'getRssBytes']);
  if (!options || Object.keys(options).some((key) => !allowedOptions.has(key))) throw new MigrationError('unapproved_rtdb_path');
  const database = options.database;
  if (!database || typeof database.ref !== 'function') throw new MigrationError('missing_rtdb_client');
  const limits = validateBoundedLimits(options.limits ?? {});
  const getRssBytes = options.getRssBytes ?? (() => process.memoryUsage().rss);
  if (typeof getRssBytes !== 'function') throw new MigrationError('invalid_rtdb_inventory_limits');
  const report = {
    inventoryStatus: 'complete_for_configured_scope',
    checkedPaths: [],
    collectionCounts: Object.fromEntries(RTDB_INVENTORY_COLLECTION_PATHS.map((path) => [path.slice('/samvibhag/v1/'.length), 0])),
    recordCount: 0,
    estimatedJsonBytes: 0,
    maxObservedRssBytes: 0,
    structuralNodeCounts: { objects: 0, arrays: 0, scalars: 0 },
    issueCounts: { duplicateKeys: 0, invalidKeys: 0, oversizedRecords: 0, unsupportedValues: 0, limitExceeded: 0, readFailures: 0 },
    scopeIsWholeNamespace: false,
  };
  report.limits = limits;
  const stop = (path, status, issue) => {
    report.inventoryStatus = 'incomplete_for_configured_scope';
    report.checkedPaths.push({ path, status });
    if (issue) report.issueCounts[issue]++;
  };

  for (const path of RTDB_INVENTORY_COLLECTION_PATHS) {
    const collectionName = path.slice('/samvibhag/v1/'.length);
    const seenKeys = new Set();
    let cursor;
    let collectionRecords = 0;
    try {
      while (true) {
        const ref = database.ref(path);
        let query = ref.orderByKey().limitToFirst(limits.pageSize);
        if (cursor !== undefined) query = query.startAfter(cursor);
        const snapshot = await query.get();
        report.maxObservedRssBytes = Math.max(report.maxObservedRssBytes, getRssBytes());
        if (report.maxObservedRssBytes > limits.maxRssBytes) {
          stop(path, 'limit_exceeded', 'limitExceeded');
          return report;
        }
        if (!snapshot || typeof snapshot.forEach !== 'function') {
          stop(path, 'failed', 'readFailures');
          return report;
        }
        const pageKeys = [];
        let pageRecords = 0;
        let limitIssue;
        snapshot.forEach((child) => {
          if (limitIssue) return true;
          if (pageRecords >= limits.pageSize) { limitIssue = 'limitExceeded'; return true; }
          const key = child?.key;
          if (typeof key !== 'string' || !key || FORBIDDEN_RTDB_KEY.test(key)) {
            report.issueCounts.invalidKeys++;
            limitIssue = 'invalidKey';
            return true;
          }
          if (seenKeys.has(key)) {
            report.issueCounts.duplicateKeys++;
            limitIssue = 'duplicateKey';
            return true;
          }
          if (report.recordCount >= limits.maxRecords) { limitIssue = 'limitExceeded'; return true; }
          seenKeys.add(key);
          pageKeys.push(key);
          pageRecords++;
          let inspected;
          try { inspected = inspectRecord(child.val()); }
          catch { report.issueCounts.unsupportedValues++; limitIssue = 'unsupportedValue'; return true; }
          if (inspected.counts.invalidKeys) {
            report.issueCounts.invalidKeys += inspected.counts.invalidKeys;
            limitIssue = 'invalidKey';
            return true;
          }
          if (inspected.bytes > limits.maxRecordBytes) {
            report.issueCounts.oversizedRecords++;
            limitIssue = 'oversizedRecord';
            return true;
          }
          if (report.estimatedJsonBytes + inspected.bytes > limits.maxTotalBytes) { limitIssue = 'limitExceeded'; return true; }
          report.estimatedJsonBytes += inspected.bytes;
          report.recordCount++;
          report.collectionCounts[collectionName]++;
          report.structuralNodeCounts.objects += inspected.counts.objectNodes;
          report.structuralNodeCounts.arrays += inspected.counts.arrayNodes;
          report.structuralNodeCounts.scalars += inspected.counts.scalarNodes;
        });
        if (limitIssue) {
          const invalid = limitIssue === 'duplicateKey' || limitIssue === 'invalidKey' || limitIssue === 'unsupportedValue';
          const reason = limitIssue === 'duplicateKey' || limitIssue === 'invalidKey' || limitIssue === 'unsupportedValue' || limitIssue === 'oversizedRecord' ? null : 'limitExceeded';
          stop(path, invalid ? 'invalid_data' : 'limit_exceeded', reason);
          return report;
        }
        if (pageRecords === 0) {
          report.checkedPaths.push({ path, status: collectionRecords === 0 ? 'accessible_absent' : 'accessible_present' });
          break;
        }
        collectionRecords += pageRecords;
        cursor = pageKeys.at(-1);
        if (pageRecords < limits.pageSize) {
          report.checkedPaths.push({ path, status: 'accessible_present' });
          break;
        }
      }
    } catch {
      stop(path, 'failed', 'readFailures');
      return report;
    }
  }
  return report;
}

