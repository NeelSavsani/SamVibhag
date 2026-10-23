// Versioned source-export contract and synthetic-fixture-only artifact writer.
// This module has no Firebase SDK, credential, ADC, RTDB, or network code.
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION } from './read_only_adapters.mjs';

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = path.resolve(TOOL_DIR, 'fixtures');
const EXPORT_ROOT = path.resolve(TOOL_DIR, 'output', 'synthetic-exports');
const EXPORT_SCOPE = Object.freeze(['users', 'usernames', 'groups', 'groups/{groupId}/activities']);
const COLLECTION_NAMES = Object.freeze(['users', 'usernames', 'groups']);
const EXPORT_FORMAT = 'samvibhag-firestore-json-export-v1';
const SAFE_EXPORT_ID = /^[A-Za-z0-9_-]{1,80}$/u;
const INTEGER_DECIMAL = /^-?(?:0|[1-9]\d*)$/u;
const IEEE754_HEX = /^[0-9a-f]{16}$/u;
const FIRESTORE_INTEGER_MIN = -(1n << 63n);
const FIRESTORE_INTEGER_MAX = (1n << 63n) - 1n;
const FIRESTORE_TIMESTAMP_MIN_SECONDS = -62135596800;
const FIRESTORE_TIMESTAMP_MAX_SECONDS = 253402300799;
export const EXPORT_LIMITS = Object.freeze({ maxDocumentsIncludingActivities: 10000, maxRecordBytes: 256 * 1024, maxTotalBytes: 16 * 1024 * 1024 });

export class ExportContractError extends Error {
  constructor(code) {
    super(code);
    this.name = 'ExportContractError';
    this.code = /^[a-z0-9_]{1,64}$/u.test(code) ? code : 'export_failed';
  }
}

function fail(code) { throw new ExportContractError(code); }

function isFirestoreIntegerDecimal(value) {
  if (typeof value !== 'string' || !INTEGER_DECIMAL.test(value) || value === '-0') return false;
  const integer = BigInt(value);
  return integer >= FIRESTORE_INTEGER_MIN && integer <= FIRESTORE_INTEGER_MAX;
}

function isFirestoreTimestamp(seconds, nanoseconds) {
  return Number.isSafeInteger(seconds) && seconds >= FIRESTORE_TIMESTAMP_MIN_SECONDS && seconds <= FIRESTORE_TIMESTAMP_MAX_SECONDS &&
    Number.isInteger(nanoseconds) && nanoseconds >= 0 && nanoseconds < 1_000_000_000;
}

function escapePointerPart(value) {
  return String(value).replaceAll('~', '~0').replaceAll('/', '~1');
}

function parsePointer(pointer) {
  if (typeof pointer !== 'string' || !pointer.startsWith('/') || pointer === '/') fail('malformed_type_pointer');
  const raw = pointer.slice(1).split('/');
  if (raw.some((part) => /~(?![01])/u.test(part))) fail('malformed_type_pointer');
  return raw.map((part) => part.replaceAll('~1', '/').replaceAll('~0', '~'));
}

function resolveSourcePointer(collections, pointer) {
  const parts = parsePointer(pointer);
  const collection = parts.shift();
  const documentId = parts.shift();
  if (!COLLECTION_NAMES.includes(collection) || typeof documentId !== 'string') fail('malformed_type_pointer');
  const sourceDocument = collections[collection].find((doc) => doc.id === documentId);
  if (!sourceDocument) fail('orphan_type_descriptor');

  let value;
  if (parts[0] === 'data') {
    parts.shift();
    value = sourceDocument.data;
  } else if (collection === 'groups' && parts[0] === 'activities') {
    parts.shift();
    const activityId = parts.shift();
    const activity = sourceDocument.subcollections.activities.find((record) => record.id === activityId);
    if (!activity) fail('orphan_type_descriptor');
    value = activity.data;
  } else {
    fail('malformed_type_pointer');
  }

  let parent;
  let key;
  for (const part of parts) {
    if (!value || typeof value !== 'object') fail('orphan_type_descriptor');
    parent = value;
    if (Array.isArray(value)) {
      if (!/^(?:0|[1-9]\d*)$/u.test(part)) fail('orphan_type_descriptor');
      key = Number(part);
      if (!Number.isSafeInteger(key) || key >= value.length) fail('orphan_type_descriptor');
    } else {
      key = part;
    }
    if (!Object.hasOwn(parent, key)) fail('orphan_type_descriptor');
    value = parent[key];
  }
  if (parts.length === 0) fail('malformed_type_pointer');
  return { value, parent, key };
}

function pointerForData(collection, documentId, segments) {
  return `/${escapePointerPart(collection)}/${escapePointerPart(documentId)}/data${segments.map((part) => `/${escapePointerPart(part)}`).join('')}`;
}

function pointerForActivity(groupId, activityId, segments) {
  return `/groups/${escapePointerPart(groupId)}/activities/${escapePointerPart(activityId)}${segments.map((part) => `/${escapePointerPart(part)}`).join('')}`;
}

function visitNumbers(value, pointer, found) {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) fail('unsupported_numeric_value');
    found.add(pointer);
    return;
  }
  if (value === null || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    value.forEach((entry, index) => visitNumbers(entry, `${pointer}/${index}`, found));
    return;
  }
  if (Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null) fail('unsupported_source_value');
  for (const key of Object.keys(value)) visitNumbers(value[key], `${pointer}/${escapePointerPart(key)}`, found);
}

function numberPointers(collections) {
  const found = new Set();
  for (const name of COLLECTION_NAMES) {
    for (const doc of collections[name]) {
      visitNumbers(doc.data, pointerForData(name, doc.id, []), found);
      if (name === 'groups') {
        for (const activity of doc.subcollections.activities) {
          visitNumbers(activity.data, pointerForActivity(doc.id, activity.id, []), found);
        }
      }
    }
  }
  return found;
}

function cloneJsonValue(value, active = new Set()) {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) fail('unsupported_numeric_value');
    return value;
  }
  if (typeof value !== 'object') fail('unsupported_source_value');
  if (active.has(value)) fail('cyclic_source_value');
  active.add(value);
  let copy;
  if (Array.isArray(value)) copy = value.map((entry) => cloneJsonValue(entry, active));
  else {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) fail('unsupported_source_value');
    if (Object.hasOwn(value, '__inventoryUnsupportedType')) fail('unsupported_firestore_value');
    copy = {};
    for (const key of Object.keys(value)) {
      Object.defineProperty(copy, key, { value: cloneJsonValue(value[key], active), enumerable: true, writable: true, configurable: true });
    }
  }
  active.delete(value);
  return copy;
}

function validateAndNormalizeCollections(snapshot) {
  if (!snapshot || snapshot.format !== 'samvibhag-firestore-fixture-v1' || !snapshot.collections || typeof snapshot.collections !== 'object') fail('invalid_source_snapshot');
  const keys = Object.keys(snapshot.collections).sort();
  if (keys.length !== COLLECTION_NAMES.length || keys.some((key, index) => key !== [...COLLECTION_NAMES].sort()[index])) fail('unsupported_source_collections');

  const collections = {};
  for (const name of COLLECTION_NAMES) {
    const input = snapshot.collections[name];
    if (!Array.isArray(input)) fail('malformed_source_collection');
    const seen = new Set();
    collections[name] = input.map((record) => {
      if (!record || typeof record.id !== 'string' || record.id.length === 0 || seen.has(record.id) || !record.data || typeof record.data !== 'object' || Array.isArray(record.data)) {
        fail(seen.has(record?.id) ? 'duplicate_document_id' : 'malformed_source_record');
      }
      seen.add(record.id);
      const result = { id: record.id, data: cloneJsonValue(record.data) };
      if (name === 'groups') {
        for (const field of ['expenses', 'recordedSettlements']) {
          if (record.data[field] === undefined) continue;
          if (!Array.isArray(record.data[field])) fail(field === 'expenses' ? 'malformed_expenses' : 'malformed_settlements');
          const embeddedIds = new Set();
          for (const embedded of record.data[field]) {
            if (!embedded || typeof embedded.id !== 'string' || embedded.id.length === 0) fail(field === 'expenses' ? 'missing_expense_id' : 'missing_settlement_id');
            if (embeddedIds.has(embedded.id)) fail(field === 'expenses' ? 'duplicate_expense_id' : 'duplicate_settlement_id');
            embeddedIds.add(embedded.id);
          }
        }
        const activities = record.subcollections?.activities;
        if (!Array.isArray(activities)) fail('missing_activities_collection');
        const activityIds = new Set();
        result.subcollections = { activities: activities.map((activity) => {
          if (!activity || typeof activity.id !== 'string' || activity.id.length === 0 || activityIds.has(activity.id) || !activity.data || typeof activity.data !== 'object' || Array.isArray(activity.data)) {
            fail(activityIds.has(activity?.id) ? 'duplicate_activity_id' : 'malformed_activity');
          }
          activityIds.add(activity.id);
          return { id: activity.id, data: cloneJsonValue(activity.data) };
        }) };
      } else if (record.subcollections !== undefined) {
        fail('unexpected_subcollection');
      }
      return result;
    });
  }
  return collections;
}

function numericEncoding(type, descriptor, sourceValue) {
  if (type === 'Integer') {
    let integerDecimal;
    if (Number.isSafeInteger(sourceValue)) {
      integerDecimal = String(sourceValue);
      if (descriptor.integerDecimal !== undefined && descriptor.integerDecimal !== integerDecimal) fail('numeric_descriptor_mismatch');
    } else if (typeof sourceValue === 'number' && Number.isInteger(sourceValue) && typeof descriptor.integerDecimal === 'string' && INTEGER_DECIMAL.test(descriptor.integerDecimal) && Number(descriptor.integerDecimal) === sourceValue) {
      // The upstream SDK integerValue proto supplies the exact decimal. data()
      // may have rounded it to a Number, so only accept the matching rounded
      // view when the source descriptor carries that exact raw integer.
      integerDecimal = descriptor.integerDecimal;
    } else if (sourceValue === null && typeof descriptor.integerDecimal === 'string' && INTEGER_DECIMAL.test(descriptor.integerDecimal)) {
      integerDecimal = descriptor.integerDecimal;
    } else {
      fail('integer_exact_value_unverified');
    }
    if (!isFirestoreIntegerDecimal(integerDecimal)) fail('malformed_integer_descriptor');
    return { pointer: '', type, placeholder: 'null', integerDecimal };
  }
  if (type === 'Double') {
    let bits;
    if (typeof sourceValue === 'number' && Number.isFinite(sourceValue)) {
      const buffer = Buffer.alloc(8);
      buffer.writeDoubleBE(sourceValue);
      bits = buffer.toString('hex');
      if (descriptor.ieee754Hex !== undefined && descriptor.ieee754Hex !== bits) fail('numeric_descriptor_mismatch');
    } else if (sourceValue === null && typeof descriptor.ieee754Hex === 'string' && IEEE754_HEX.test(descriptor.ieee754Hex)) {
      bits = descriptor.ieee754Hex;
      const buffer = Buffer.from(bits, 'hex');
      if (!Number.isFinite(buffer.readDoubleBE())) fail('unsupported_numeric_value');
    } else {
      fail('double_exact_value_unverified');
    }
    return { pointer: '', type, placeholder: 'null', ieee754Hex: bits };
  }
  fail('unsupported_firestore_type');
}

function computeCounts(collections, typeDescriptorCount = 0) {
  const counts = { users: collections.users.length, usernames: collections.usernames.length, groups: collections.groups.length, activities: 0, expenses: 0, recordedSettlements: 0 };
  for (const group of collections.groups) {
    counts.activities += group.subcollections.activities.length;
    if (group.data.expenses !== undefined) {
      if (!Array.isArray(group.data.expenses)) fail('malformed_expenses');
      counts.expenses += group.data.expenses.length;
    }
    if (group.data.recordedSettlements !== undefined) {
      if (!Array.isArray(group.data.recordedSettlements)) fail('malformed_settlements');
      counts.recordedSettlements += group.data.recordedSettlements.length;
    }
  }
  counts.firestoreDocumentsIncludingActivities = counts.users + counts.usernames + counts.groups + counts.activities;
  counts.typeDescriptors = typeDescriptorCount;
  return counts;
}

function validateSourceLimits(snapshot, collections, limits = EXPORT_LIMITS) {
  if (!limits || Object.keys(limits).some((key) => !Object.hasOwn(EXPORT_LIMITS, key))) fail('invalid_export_limits');
  for (const key of Object.keys(EXPORT_LIMITS)) {
    if (!Number.isSafeInteger(limits[key] ?? EXPORT_LIMITS[key]) || (limits[key] ?? EXPORT_LIMITS[key]) < 1 || (limits[key] ?? EXPORT_LIMITS[key]) > EXPORT_LIMITS[key]) fail('invalid_export_limits');
  }
  const counts = computeCounts(collections);
  if (counts.firestoreDocumentsIncludingActivities > (limits.maxDocumentsIncludingActivities ?? EXPORT_LIMITS.maxDocumentsIncludingActivities)) fail('source_document_limit_exceeded');
  let totalBytes = 0;
  const inspect = (record) => {
    let serialized;
    try { serialized = JSON.stringify(record.data); }
    catch { fail('unsupported_source_value'); }
    if (typeof serialized !== 'string') fail('unsupported_source_value');
    const bytes = Buffer.byteLength(serialized, 'utf8');
    if (bytes > (limits.maxRecordBytes ?? EXPORT_LIMITS.maxRecordBytes)) fail('source_record_size_exceeded');
    totalBytes += bytes;
    if (totalBytes > (limits.maxTotalBytes ?? EXPORT_LIMITS.maxTotalBytes)) fail('source_total_size_exceeded');
  };
  for (const name of COLLECTION_NAMES) {
    for (const record of collections[name]) {
      inspect(record);
      if (name === 'groups') for (const activity of record.subcollections.activities) inspect(activity);
    }
  }
  if (snapshot.readStats !== undefined) {
    const stats = snapshot.readStats;
    if (!stats || !Number.isSafeInteger(stats.recordsRead) || stats.recordsRead !== counts.firestoreDocumentsIncludingActivities) fail('source_read_count_mismatch');
    if (!Number.isSafeInteger(stats.estimatedJsonBytes) || stats.estimatedJsonBytes < 0 || stats.estimatedJsonBytes > (limits.maxTotalBytes ?? EXPORT_LIMITS.maxTotalBytes)) fail('source_total_size_exceeded');
    if (stats.limits && (stats.limits.maxRecords > EXPORT_LIMITS.maxDocumentsIncludingActivities || stats.limits.maxRecordBytes > EXPORT_LIMITS.maxRecordBytes || stats.limits.maxTotalBytes > EXPORT_LIMITS.maxTotalBytes)) fail('invalid_export_limits');
  }
}

function projectionIssueCounts(collections) {
  const counts = { unresolvedUidRelationships: 0, ambiguousExpenseParties: 0, ambiguousSettlementParties: 0, conflictingSettlementAliases: 0, activityGroupMismatches: 0 };
  const userIds = new Set(collections.users.map((record) => record.id));
  for (const user of collections.users) if (user.data.uid !== undefined && user.data.uid !== user.id) counts.unresolvedUidRelationships++;
  for (const username of collections.usernames) if (!userIds.has(username.data.uid)) counts.unresolvedUidRelationships++;
  for (const group of collections.groups) {
    const data = group.data;
    const members = Array.isArray(data.members) ? data.members : [];
    const memberUids = Array.isArray(data.memberUids) ? data.memberUids : [];
    if (!userIds.has(data.createdBy)) counts.unresolvedUidRelationships++;
    if (data.memberUids !== undefined && !Array.isArray(data.memberUids)) counts.unresolvedUidRelationships++;
    for (const uid of memberUids) if (!userIds.has(uid)) counts.unresolvedUidRelationships++;
    for (const identity of Array.isArray(data.memberIdentities) ? data.memberIdentities : []) {
      if (!memberUids.includes(identity?.uid) && identity?.uid !== data.createdBy) counts.unresolvedUidRelationships++;
    }
    const uniqueMember = (name) => typeof name === 'string' && members.filter((candidate) => candidate === name).length === 1;
    for (const expense of Array.isArray(data.expenses) ? data.expenses : []) {
      const parties = [expense?.paidBy, ...(Array.isArray(expense?.splitBetween) ? expense.splitBetween : []), ...Object.keys(expense?.customSplits ?? {})];
      for (const party of parties) if (!uniqueMember(party)) counts.ambiguousExpenseParties++;
    }
    for (const settlement of Array.isArray(data.recordedSettlements) ? data.recordedSettlements : []) {
      if (settlement?.from !== undefined && settlement?.fromUser !== undefined && settlement.from !== settlement.fromUser) counts.conflictingSettlementAliases++;
      if (settlement?.to !== undefined && settlement?.toUser !== undefined && settlement.to !== settlement.toUser) counts.conflictingSettlementAliases++;
      if (!uniqueMember(settlement?.fromUser ?? settlement?.from) || !uniqueMember(settlement?.toUser ?? settlement?.to)) counts.ambiguousSettlementParties++;
    }
    for (const activity of group.subcollections.activities) {
      if (activity.data.groupId !== undefined && activity.data.groupId !== group.id) counts.activityGroupMismatches++;
    }
  }
  return counts;
}

export function validateJsonExport(exportData) {
  if (!exportData || exportData.format !== EXPORT_FORMAT || JSON.stringify(exportData.scope) !== JSON.stringify(EXPORT_SCOPE)) fail('invalid_export_format');
  if (Object.keys(exportData).sort().join(',') !== ['collections', 'counts', 'format', 'scope', 'typeManifest'].sort().join(',')) fail('invalid_export_format');
  const collections = validateNormalizedCollections(exportData.collections);
  const recomputedCounts = computeCounts(collections, exportData.typeManifest?.length ?? 0);
  if (!exportData.counts || Object.keys(recomputedCounts).some((key) => exportData.counts[key] !== recomputedCounts[key]) || Object.keys(exportData.counts).length !== Object.keys(recomputedCounts).length) fail('count_manifest_mismatch');

  if (!Array.isArray(exportData.typeManifest)) fail('malformed_type_manifest');
  const seenPointers = new Set();
  for (const descriptor of exportData.typeManifest) {
    if (!descriptor || typeof descriptor.pointer !== 'string' || seenPointers.has(descriptor.pointer)) fail(seenPointers.has(descriptor?.pointer) ? 'duplicate_type_descriptor' : 'malformed_type_manifest');
    seenPointers.add(descriptor.pointer);
    const resolved = resolveSourcePointer(collections, descriptor.pointer);
    if (resolved.value !== null || descriptor.placeholder !== 'null') fail('type_placeholder_mismatch');
    if (descriptor.type === 'Timestamp') {
      if (Object.keys(descriptor).some((key) => !['pointer', 'type', 'placeholder', 'seconds', 'nanoseconds'].includes(key))) fail('malformed_timestamp');
      if (!isFirestoreTimestamp(descriptor.seconds, descriptor.nanoseconds)) fail('malformed_timestamp');
    } else if (descriptor.type === 'Integer') {
      if (Object.keys(descriptor).some((key) => !['pointer', 'type', 'placeholder', 'integerDecimal'].includes(key))) fail('malformed_integer_descriptor');
      if (!isFirestoreIntegerDecimal(descriptor.integerDecimal)) fail('malformed_integer_descriptor');
    } else if (descriptor.type === 'Double') {
      if (Object.keys(descriptor).some((key) => !['pointer', 'type', 'placeholder', 'ieee754Hex'].includes(key))) fail('malformed_double_descriptor');
      if (typeof descriptor.ieee754Hex !== 'string' || !IEEE754_HEX.test(descriptor.ieee754Hex) || !Number.isFinite(Buffer.from(descriptor.ieee754Hex, 'hex').readDoubleBE())) fail('malformed_double_descriptor');
    } else {
      fail('unsupported_firestore_type');
    }
  }

  if (numberPointers(collections).size > 0) fail('untyped_export_number');
  const issueCounts = projectionIssueCounts(collections);
  const blocked = Object.values(issueCounts).some((count) => count > 0);
  return {
    exportStatus: 'complete',
    serializationFidelityStatus: 'faithful',
    projectionReadinessStatus: blocked ? 'blocked_known_source_issues' : 'not_assessed',
    pointInTimeConsistent: false,
    counts: recomputedCounts,
    projectionIssueCounts: issueCounts,
    containsRecordValues: false,
  };
}

function validateNormalizedCollections(input) {
  if (!input || typeof input !== 'object') fail('malformed_export_collections');
  const wrapper = { format: 'samvibhag-firestore-fixture-v1', collections: input };
  const collections = validateAndNormalizeCollections(wrapper);
  return collections;
}

function replaceSourceValue(collections, pointer, replacement) {
  const resolved = resolveSourcePointer(collections, pointer);
  if (resolved.parent === undefined) fail('malformed_type_pointer');
  resolved.parent[resolved.key] = replacement;
}

export function buildJsonExport(snapshot, { unsupportedValues = [], limits = EXPORT_LIMITS } = {}) {
  if (!snapshot?.types || typeof snapshot.types !== 'object' || Array.isArray(snapshot.types)) fail('malformed_type_manifest');
  if (!Array.isArray(unsupportedValues) || unsupportedValues.length > 0 || (Array.isArray(snapshot.unsupportedValues) && snapshot.unsupportedValues.length > 0)) fail('unsupported_firestore_value');
  const collections = validateAndNormalizeCollections(snapshot);
  validateSourceLimits(snapshot, collections, limits);
  const numericPointers = numberPointers(collections);
  const hasNumericDescriptors = Object.values(snapshot.types).some((descriptor) => descriptor?.type === 'Integer' || descriptor?.type === 'Double');
  if (hasNumericDescriptors && snapshot.readStats &&
      (snapshot.readStats.numericDecoding !== 'useBigInt' || snapshot.readStats.numericSdkVersion !== LOSSLESS_NUMERIC_FIRESTORE_SDK_VERSION)) {
    fail('numeric_mode_unverified');
  }
  const descriptors = [];
  for (const pointer of Object.keys(snapshot.types).sort()) {
    const descriptor = snapshot.types[pointer];
    if (!descriptor || typeof descriptor.type !== 'string') fail('malformed_type_manifest');
    const sourceAllowedFields = descriptor.type === 'Timestamp' ? ['type', 'seconds', 'nanoseconds']
      : descriptor.type === 'Integer' ? ['type', 'integerDecimal']
        : descriptor.type === 'Double' ? ['type', 'ieee754Hex'] : ['type'];
    if (Object.keys(descriptor).some((key) => !sourceAllowedFields.includes(key))) fail('malformed_type_manifest');
    const resolved = resolveSourcePointer(collections, pointer);
    let entry;
    if (descriptor.type === 'Timestamp') {
      if (resolved.value !== null || !isFirestoreTimestamp(descriptor.seconds, descriptor.nanoseconds)) fail('malformed_timestamp');
      entry = { pointer, type: 'Timestamp', placeholder: 'null', seconds: descriptor.seconds, nanoseconds: descriptor.nanoseconds };
    } else if (descriptor.type === 'Integer' || descriptor.type === 'Double') {
      const numeric = numericEncoding(descriptor.type, descriptor, resolved.value);
      entry = { ...numeric, pointer };
      numericPointers.delete(pointer);
      replaceSourceValue(collections, pointer, null);
    } else {
      fail('unsupported_firestore_type');
    }
    descriptors.push(entry);
  }
  if (numericPointers.size > 0) fail('numeric_type_unverified');
  const counts = computeCounts(collections);
  counts.typeDescriptors = descriptors.length;
  const exportData = {
    format: EXPORT_FORMAT,
    scope: [...EXPORT_SCOPE],
    collections,
    typeManifest: descriptors,
    counts,
  };
  const validation = validateJsonExport(exportData);
  return { export: exportData, validation };
}

export function restoreJsonExport(exportData) {
  const validation = validateJsonExport(exportData);
  const restored = cloneJsonValue(exportData.collections);
  for (const descriptor of exportData.typeManifest) {
    const target = resolveSourcePointer(restored, descriptor.pointer);
    let value;
    if (descriptor.type === 'Timestamp') value = { __firestoreExportType: 'Timestamp', seconds: descriptor.seconds, nanoseconds: descriptor.nanoseconds };
    else if (descriptor.type === 'Integer') value = BigInt(descriptor.integerDecimal);
    else {
      const buffer = Buffer.from(descriptor.ieee754Hex, 'hex');
      value = buffer.readDoubleBE();
    }
    target.parent[target.key] = value;
  }
  return { collections: restored, validation };
}

export function safeExportFailure(error) {
  const code = error instanceof ExportContractError ? error.code : 'export_failed';
  const publicationCodes = new Set([
    'invalid_export_id', 'export_artifact_exists', 'artifact_publication_failed',
    'stage_write_export_failed', 'stage_write_complete_manifest_failed', 'stage_publish_failed', 'stage_publish_complete_manifest_failed',
  ]);
  const unverifiedCodes = new Set(['export_failed', 'fixture_read_failed', 'fixture_path_outside_allowlist', 'stage_source_read_failed', 'source_document_limit_exceeded', 'source_record_size_exceeded', 'source_total_size_exceeded', 'source_read_count_mismatch']);
  const fidelityStatus = publicationCodes.has(code) ? 'not_published' : unverifiedCodes.has(code) ? 'unverified' : 'blocked';
  const projectionStatus = publicationCodes.has(code) || unverifiedCodes.has(code) ? 'not_assessed' : 'blocked';
  return {
    exportStatus: 'incomplete',
    serializationFidelityStatus: fidelityStatus,
    projectionReadinessStatus: projectionStatus,
    code,
    containsRecordValues: false,
  };
}

function runHook(hooks, stage, context) {
  try { hooks?.[stage]?.(context); }
  catch (error) { throw new ExportContractError(`stage_${stage}_failed`); }
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function sha256Integrity(bytes) {
  return {
    algorithm: 'sha256',
    bytes: bytes.length,
    digest: crypto.createHash('sha256').update(bytes).digest('hex'),
  };
}

function readArtifactFile(filePath, code) {
  try {
    const info = fs.lstatSync(filePath);
    if (!info.isFile() || info.isSymbolicLink()) fail('artifact_file_invalid');
    return fs.readFileSync(filePath);
  } catch (error) {
    if (error instanceof ExportContractError) throw error;
    fail(code);
  }
}

/**
 * Read a completed local export from the fixed synthetic output directory.
 * The completion marker is required, its hash is checked over the exact export
 * bytes, and all export/marker counts and statuses are recomputed before data is
 * returned. This API does not accept arbitrary paths or connect to Firebase.
 */
export function readPublishedSyntheticExport(exportId) {
  if (typeof exportId === 'string' && exportId.startsWith('.tmp-')) fail('temporary_artifact_rejected');
  if (typeof exportId !== 'string' || !SAFE_EXPORT_ID.test(exportId)) fail('invalid_export_id');
  const directory = path.join(EXPORT_ROOT, exportId);
  let directoryInfo;
  try { directoryInfo = fs.lstatSync(directory); }
  catch { fail('export_artifact_missing'); }
  if (!directoryInfo.isDirectory() || directoryInfo.isSymbolicLink()) fail('artifact_directory_invalid');
  const markerPath = path.join(directory, 'complete.json');
  if (!fs.existsSync(markerPath)) fail('completion_marker_missing');
  let directoryEntries;
  try { directoryEntries = fs.readdirSync(directory).sort(); }
  catch { fail('export_artifact_unreadable'); }
  if (canonicalJson(directoryEntries) !== canonicalJson(['complete.json', 'export.json'])) fail('artifact_contents_invalid');
  const markerBytes = readArtifactFile(markerPath, 'completion_marker_unreadable');
  let marker;
  try { marker = JSON.parse(markerBytes.toString('utf8')); }
  catch { fail('completion_marker_invalid'); }
  const markerKeys = ['containsRecordValues', 'counts', 'exportIntegrity', 'exportStatus', 'format', 'pointInTimeConsistent', 'projectionIssueCounts', 'projectionReadinessStatus', 'serializationFidelityStatus'];
  if (!marker || typeof marker !== 'object' || Array.isArray(marker) ||
      canonicalJson(Object.keys(marker).sort()) !== canonicalJson(markerKeys) ||
      marker.format !== EXPORT_FORMAT || marker.exportStatus !== 'complete' ||
      marker.serializationFidelityStatus !== 'faithful' ||
      !['not_assessed', 'blocked_known_source_issues'].includes(marker.projectionReadinessStatus) ||
      marker.pointInTimeConsistent !== false || marker.containsRecordValues !== false ||
      !marker.exportIntegrity || typeof marker.exportIntegrity !== 'object' || Array.isArray(marker.exportIntegrity) ||
      canonicalJson(Object.keys(marker.exportIntegrity).sort()) !== canonicalJson(['algorithm', 'bytes', 'digest']) ||
      marker.exportIntegrity.algorithm !== 'sha256' || !Number.isSafeInteger(marker.exportIntegrity.bytes) || marker.exportIntegrity.bytes < 0 ||
      typeof marker.exportIntegrity.digest !== 'string' || !/^[0-9a-f]{64}$/u.test(marker.exportIntegrity.digest)) {
    fail('completion_marker_invalid');
  }

  const exportBytes = readArtifactFile(path.join(directory, 'export.json'), 'export_file_unreadable');
  const actualIntegrity = sha256Integrity(exportBytes);
  if (marker.exportIntegrity.bytes !== actualIntegrity.bytes || marker.exportIntegrity.digest !== actualIntegrity.digest) fail('export_integrity_mismatch');
  let exportData;
  try { exportData = JSON.parse(exportBytes.toString('utf8')); }
  catch { fail('export_json_invalid'); }
  const validation = validateJsonExport(exportData);
  if (canonicalJson(marker.counts) !== canonicalJson(validation.counts) ||
      canonicalJson(marker.projectionIssueCounts) !== canonicalJson(validation.projectionIssueCounts) ||
      marker.serializationFidelityStatus !== validation.serializationFidelityStatus ||
      marker.projectionReadinessStatus !== validation.projectionReadinessStatus) {
    fail('completion_manifest_mismatch');
  }
  return { export: exportData, validation, completeManifest: marker };
}

export function readSyntheticFixture(fixturePath = path.join(FIXTURE_DIR, 'export-contract-source.json')) {
  const resolved = path.resolve(fixturePath);
  const allowedFiles = new Set(['synthetic-source.json', 'export-contract-source.json', 'export-contract-malformed.json']);
  if (path.dirname(resolved) !== FIXTURE_DIR || !allowedFiles.has(path.basename(resolved))) fail('fixture_path_outside_allowlist');
  try {
    const source = JSON.parse(fs.readFileSync(resolved, 'utf8'));
    if (!source || source.format !== 'samvibhag-firestore-fixture-v1') fail('invalid_source_snapshot');
    return source;
  } catch (error) {
    if (error instanceof ExportContractError) throw error;
    fail('fixture_read_failed');
  }
}

export function publishSyntheticExport(snapshot, { exportId, hooks = {} } = {}) {
  if (typeof exportId !== 'string' || !SAFE_EXPORT_ID.test(exportId)) fail('invalid_export_id');
  const outputRoot = EXPORT_ROOT;
  const finalDirectory = path.join(outputRoot, exportId);
  let temporaryDirectory;
  let finalDirectoryPublished = false;
  try {
    fs.mkdirSync(outputRoot, { recursive: true });
    if (fs.existsSync(finalDirectory)) fail('export_artifact_exists');
    temporaryDirectory = fs.mkdtempSync(path.join(outputRoot, `.tmp-${exportId}-`));
    runHook(hooks, 'serialization');
    const prepared = buildJsonExport(snapshot);
    const serializedExport = `${JSON.stringify(prepared.export)}\n`;
    const reloaded = JSON.parse(serializedExport);
    runHook(hooks, 'validation', reloaded);
    const finalValidation = validateJsonExport(reloaded);
    runHook(hooks, 'write_export');
    fs.writeFileSync(path.join(temporaryDirectory, 'export.json'), serializedExport, { flag: 'wx' });
    const completeManifest = {
      format: EXPORT_FORMAT,
      exportStatus: 'complete',
      serializationFidelityStatus: finalValidation.serializationFidelityStatus,
      projectionReadinessStatus: finalValidation.projectionReadinessStatus,
      pointInTimeConsistent: false,
      counts: finalValidation.counts,
      projectionIssueCounts: finalValidation.projectionIssueCounts,
      containsRecordValues: false,
      exportIntegrity: sha256Integrity(Buffer.from(serializedExport, 'utf8')),
    };
    runHook(hooks, 'write_complete_manifest');
    fs.writeFileSync(path.join(temporaryDirectory, 'complete.pending.json'), `${JSON.stringify({ exportStatus: 'pending' })}\n`, { flag: 'wx' });
    runHook(hooks, 'publish');
    // Reserve the final directory exclusively to close the exists-check/rename
    // race. It is intentionally markerless until the final atomic marker rename;
    // consumers must ignore it if the process stops before that point.
    try { fs.mkdirSync(finalDirectory); }
    catch (error) {
      if (error?.code === 'EEXIST') fail('export_artifact_exists');
      throw error;
    }
    finalDirectoryPublished = true;
    fs.renameSync(path.join(temporaryDirectory, 'export.json'), path.join(finalDirectory, 'export.json'));
    fs.renameSync(path.join(temporaryDirectory, 'complete.pending.json'), path.join(finalDirectory, 'complete.pending.json'));
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
    temporaryDirectory = undefined;
    runHook(hooks, 'publish_complete_manifest');
    const pendingManifest = path.join(finalDirectory, 'complete.json.tmp');
    fs.writeFileSync(pendingManifest, `${JSON.stringify(completeManifest, null, 2)}\n`, { flag: 'wx' });
    fs.rmSync(path.join(finalDirectory, 'complete.pending.json'));
    fs.renameSync(pendingManifest, path.join(finalDirectory, 'complete.json'));
    return completeManifest;
  } catch (error) {
    if (temporaryDirectory && fs.existsSync(temporaryDirectory)) {
      try { fs.rmSync(temporaryDirectory, { recursive: true, force: true }); } catch { /* final directory remains unpublished */ }
    }
    if (finalDirectoryPublished && !fs.existsSync(path.join(finalDirectory, 'complete.json'))) {
      try { fs.rmSync(finalDirectory, { recursive: true, force: true }); } catch { /* no complete marker is present */ }
    }
    if (error instanceof ExportContractError) throw error;
    fail('artifact_publication_failed');
  }
}

export function publishSyntheticFixtureExport({ fixturePath, exportId, hooks } = {}) {
  runHook(hooks, 'source_read');
  const snapshot = readSyntheticFixture(fixturePath);
  return publishSyntheticExport(snapshot, { exportId, hooks });
}

export const syntheticExportPaths = Object.freeze({ outputRoot: EXPORT_ROOT, fixtureRoot: FIXTURE_DIR });
