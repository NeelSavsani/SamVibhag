#!/usr/bin/env node

// Fixture-only Firestore → RTDB migration prototype.
// This module has no Firebase SDK, credential, or network code by design.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = path.join(TOOL_DIR, 'fixtures');
const OUTPUT_DIR = path.join(TOOL_DIR, 'output');
const RUN_ROOT = ['samvibhag', 'v1', 'migrationRuns'];
const KEY_PREFIX = '_k_';
const SOURCE_COLLECTIONS = new Set(['users', 'usernames', 'groups']);

export class MigrationError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'MigrationError';
    this.code = code;
    this.details = details;
  }
}

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function hashValue(value) {
  return crypto.createHash('sha256').update(canonicalJson(value)).digest('hex');
}

function forbiddenRtdbKey(key) {
  return /[.#$/\[\]\u0000-\u001f\u007f]/u.test(key);
}

export function encodeKey(key) {
  if (typeof key !== 'string') throw new MigrationError('invalid_key', 'RTDB keys must originate from strings.');
  if (key.length === 0 || forbiddenRtdbKey(key) || key.startsWith(KEY_PREFIX)) {
    return `${KEY_PREFIX}${Buffer.from(key, 'utf8').toString('base64url')}`;
  }
  return key;
}

export function decodeKey(key) {
  if (!key.startsWith(KEY_PREFIX)) return key;
  try {
    const decoded = Buffer.from(key.slice(KEY_PREFIX.length), 'base64url').toString('utf8');
    if (encodeKey(decoded) !== key) throw new Error('non-canonical key');
    return decoded;
  } catch {
    throw new MigrationError('invalid_encoded_key', `Invalid encoded key: ${key}`);
  }
}

function pointerChild(pointer, key) {
  return `${pointer}/${String(key).replaceAll('~', '~0').replaceAll('/', '~1')}`;
}

function sourcePointer(...segments) {
  return segments.reduce((pointer, segment) => pointerChild(pointer, segment), '');
}

function assertNoKeyCollisions(encodedKeys, pointer) {
  const seen = new Map();
  for (const [sourceKey, encoded] of encodedKeys) {
    const prior = seen.get(encoded);
    if (prior !== undefined && prior !== sourceKey) {
      throw new MigrationError('key_collision', `Source keys collide after RTDB encoding at ${pointer}.`, { sourceKeys: [prior, sourceKey] });
    }
    seen.set(encoded, sourceKey);
  }
}

function typeDescriptorAt(typeMap, pointer) {
  return typeMap[pointer];
}

export function encodeFirestoreValue(value, { typeMap = {}, pointer = '' } = {}) {
  const descriptor = typeDescriptorAt(typeMap, pointer);
  if (descriptor) {
    const type = descriptor.type;
    if (type === 'Timestamp') {
      if (!Number.isSafeInteger(descriptor.seconds) || !Number.isInteger(descriptor.nanoseconds) || descriptor.nanoseconds < 0 || descriptor.nanoseconds >= 1_000_000_000) {
        throw new MigrationError('malformed_timestamp', `Invalid Firestore Timestamp at ${pointer}.`);
      }
      return { __rtdbType: 'firestoreTimestamp', seconds: descriptor.seconds, nanoseconds: descriptor.nanoseconds };
    }
    if (type === 'Integer' || type === 'Double') {
      if (typeof value !== 'number' || !Number.isFinite(value)) throw new MigrationError('malformed_number', `Invalid ${type} at ${pointer}.`);
      return { __rtdbType: 'firestoreNumber', sourceKind: type, value };
    }
    throw new MigrationError('unsupported_firestore_value', `Unsupported Firestore value type '${type}' at ${pointer}.`, { pointer, type });
  }

  if (value === null) return { __rtdbType: 'firestoreNull' };
  if (typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new MigrationError('unsupported_number', `Non-finite number at ${pointer}.`);
    return value;
  }
  if (Array.isArray(value)) {
    const items = {};
    value.forEach((item, index) => {
      items[String(index).padStart(10, '0')] = encodeFirestoreValue(item, { typeMap, pointer: pointerChild(pointer, index) });
    });
    return { __rtdbType: 'firestoreArray', length: value.length, items };
  }
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const keys = Object.keys(value).sort();
    const encodedKeys = keys.map((key) => [key, encodeKey(key)]);
    assertNoKeyCollisions(encodedKeys, pointer);
    const entries = {};
    for (const [sourceKey, encoded] of encodedKeys) {
      entries[encoded] = {
        key: sourceKey,
        value: encodeFirestoreValue(value[sourceKey], { typeMap, pointer: pointerChild(pointer, sourceKey) }),
      };
    }
    return { __rtdbType: 'firestoreMap', entries };
  }
  throw new MigrationError('unsupported_value', `Unsupported value at ${pointer}.`, { pointer, jsType: typeof value });
}

export function decodeFirestoreValue(value) {
  if (value === null || typeof value !== 'object') return value;
  if (value.__rtdbType === 'firestoreNull') return null;
  if (value.__rtdbType === 'firestoreTimestamp') return { __firestoreFixtureType: 'Timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds };
  if (value.__rtdbType === 'firestoreNumber') return value.value;
  if (value.__rtdbType === 'firestoreArray') {
    const result = [];
    for (let i = 0; i < value.length; i++) {
      const key = String(i).padStart(10, '0');
      if (!Object.hasOwn(value.items, key)) throw new MigrationError('malformed_array', `Missing array item ${i}.`);
      result.push(decodeFirestoreValue(value.items[key]));
    }
    if (Object.keys(value.items).length !== value.length) throw new MigrationError('malformed_array', 'Array has unexpected indexed items.');
    return result;
  }
  if (value.__rtdbType === 'firestoreMap') {
    const result = {};
    const decodedKeys = new Set();
    for (const [safeKey, entry] of Object.entries(value.entries)) {
      const sourceKey = entry?.key;
      if (typeof sourceKey !== 'string' || encodeKey(sourceKey) !== safeKey || decodedKeys.has(sourceKey)) {
        throw new MigrationError('malformed_map', 'Map key metadata is invalid or colliding.');
      }
      decodedKeys.add(sourceKey);
      Object.defineProperty(result, sourceKey, { value: decodeFirestoreValue(entry.value), enumerable: true, writable: true, configurable: true });
    }
    return result;
  }
  throw new MigrationError('unknown_envelope', 'Unknown encoded Firestore value envelope.');
}

function compareIds(left, right) {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}

export function paginateDocuments(documents, pageSize, afterId = null) {
  if (!Number.isInteger(pageSize) || pageSize < 1) throw new MigrationError('invalid_page_size', 'Page size must be a positive integer.');
  const ordered = [...documents].sort((a, b) => compareIds(a.id, b.id));
  const cursorIndex = afterId == null ? -1 : ordered.findIndex((document) => document.id === afterId);
  if (afterId != null && cursorIndex < 0) throw new MigrationError('invalid_cursor', `Pagination cursor '${afterId}' was not found.`);
  const start = cursorIndex + 1;
  const pages = [];
  for (let offset = start; offset < ordered.length; offset += pageSize) {
    const docs = ordered.slice(offset, offset + pageSize);
    pages.push({ docs, nextCursor: docs.at(-1)?.id ?? afterId });
  }
  return pages;
}

function sourceDocuments(fixture, collection, pageSize) {
  const documents = fixture.collections?.[collection];
  if (!Array.isArray(documents)) throw new MigrationError('malformed_collection', `Fixture collection '${collection}' must be an array.`);
  const seen = new Set();
  for (const [index, sourceDocument] of documents.entries()) {
    const document = { ...sourceDocument, index };
    if (!document || typeof document.id !== 'string' || !document.id || !document.data || typeof document.data !== 'object' || Array.isArray(document.data)) {
      throw new MigrationError('malformed_document', `Malformed document in '${collection}'.`);
    }
    if (seen.has(document.id)) throw new MigrationError('duplicate_document_id', `Duplicate document ID '${document.id}' in '${collection}'.`, { collection, id: document.id });
    seen.add(document.id);
  }
  return paginateDocuments(documents, pageSize).flatMap((page) => page.docs);
}

function validateTypeMap(fixture) {
  for (const [pointer, descriptor] of Object.entries(fixture.types ?? {})) {
    if (!pointer.startsWith('/') || !descriptor || typeof descriptor.type !== 'string') {
      throw new MigrationError('malformed_type_manifest', `Invalid Firestore type descriptor at '${pointer}'.`);
    }
    const segments = pointer.slice(1).split('/').map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'));
    const [collection, documentId, section, ...rest] = segments;
    const sourceDocument = fixture.collections?.[collection]?.find((doc) => doc.id === documentId);
    let value;
    if (!sourceDocument) throw new MigrationError('orphan_type_descriptor', `Type descriptor points to a missing source document at '${pointer}'.`);
    if (section === 'data') value = sourceDocument.data;
    else if (collection === 'groups' && ['expenses', 'recordedSettlements'].includes(section)) {
      value = sourceDocument.data?.[section]?.find((record) => record.id === rest.shift());
    } else if (collection === 'groups' && section === 'activities') {
      value = sourceDocument.subcollections?.activities?.find((record) => record.id === rest.shift())?.data;
    } else {
      throw new MigrationError('malformed_type_manifest', `Unsupported source type path '${pointer}'.`);
    }
    for (const segment of rest) {
      if (!value || typeof value !== 'object' || !Object.hasOwn(value, segment)) {
        throw new MigrationError('orphan_type_descriptor', `Type descriptor points to a missing fixture value at '${pointer}'.`);
      }
      value = value[segment];
    }
  }
}

function pathString(segments) {
  return `/${segments.join('/')}`;
}

function addWrite(writes, sourcePath, sourceId, destinationSegments, value) {
  const destination = pathString(destinationSegments);
  if (writes.has(destination)) throw new MigrationError('destination_path_collision', `Multiple records map to ${destination}.`, { sourcePath, sourceId });
  writes.set(destination, { path: destinationSegments, sourcePath, sourceId, value, hash: hashValue(value) });
}

function requireStrings(value, sourcePath, field, { optional = false } = {}) {
  if (value === undefined && optional) return [];
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== 'string')) {
    throw new MigrationError('malformed_record', `${sourcePath}.${field} must be an array of strings.`);
  }
  return value;
}

function ensureUniqueName(name, members, sourcePath) {
  const matches = members.filter((member) => member === name);
  if (matches.length !== 1) {
    throw new MigrationError(matches.length ? 'ambiguous_member_name' : 'unresolved_member_name', `${sourcePath} refers to '${name}', which matches ${matches.length} group member names.`, { name, matches: matches.length });
  }
}

export function canManageSettlement(groupData, settlement, uid) {
  if (!uid || !settlement || typeof settlement.fromUser !== 'string') return false;
  if (groupData.createdBy === uid) return true;
  const memberUids = Array.isArray(groupData.memberUids) ? groupData.memberUids : [];
  if (!memberUids.includes(uid)) return false;
  const identities = Array.isArray(groupData.memberIdentities) ? groupData.memberIdentities : [];
  const matches = identities.filter((identity) => identity && identity.name === settlement.fromUser && identity.uid);
  const uidMatches = identities.filter((identity) => identity && identity.uid === uid);
  const nameMatches = (groupData.members ?? []).filter((name) => name === settlement.fromUser);
  return matches.length === 1 && uidMatches.length === 1 && nameMatches.length === 1 && matches[0].uid === uid;
}

function groupWrites(groupDoc, runId, typeMap, pageSize, writes, counts, userIds) {
  const groupId = groupDoc.id;
  const sourcePath = `groups/${groupId}`;
  const data = groupDoc.data;
  if (typeof data.createdBy !== 'string' || !data.createdBy) throw new MigrationError('missing_group_creator', `${sourcePath}.createdBy is required for safe authorization.`);
  const members = requireStrings(data.members, sourcePath, 'members', { optional: true });
  const memberUids = requireStrings(data.memberUids, sourcePath, 'memberUids', { optional: true });
  const memberEmails = requireStrings(data.memberEmails, sourcePath, 'memberEmails', { optional: true });
  const memberUsernames = requireStrings(data.memberUsernames, sourcePath, 'memberUsernames', { optional: true });
  if (members.some((name) => !name.trim())) {
    throw new MigrationError('malformed_member_name', `${sourcePath}.members contains an empty name.`);
  }
  if (memberUids.some((uid) => !uid)) throw new MigrationError('malformed_member_uid', `${sourcePath}.memberUids contains an empty UID.`);
  for (const uid of new Set(memberUids)) {
    if (!userIds.has(uid)) throw new MigrationError('unresolved_member_profile', `${sourcePath}.memberUids references missing users/${uid}.`, { groupId, uid });
  }

  const identities = data.memberIdentities ?? [];
  if (!Array.isArray(identities)) throw new MigrationError('malformed_identities', `${sourcePath}.memberIdentities must be an array when present.`);
  const identityUids = new Set();
  const namesToUids = new Map();
  for (const identity of identities) {
    if (!identity || typeof identity.name !== 'string' || !identity.name || typeof identity.uid !== 'string' || !identity.uid) {
      throw new MigrationError('malformed_identity', `${sourcePath} contains an incomplete member identity.`);
    }
    if (identityUids.has(identity.uid)) throw new MigrationError('ambiguous_member_uid', `${sourcePath} maps one UID more than once.`, { uid: identity.uid });
    const prior = namesToUids.get(identity.name);
    if (prior && prior !== identity.uid) throw new MigrationError('ambiguous_member_name', `${sourcePath} maps display name '${identity.name}' to multiple UIDs.`, { name: identity.name });
    if (!memberUids.includes(identity.uid) && identity.uid !== data.createdBy) {
      throw new MigrationError('identity_not_member', `${sourcePath} identity UID is not a group member or creator.`, { uid: identity.uid });
    }
    identityUids.add(identity.uid);
    namesToUids.set(identity.name, identity.uid);
  }

  const groupRoot = [...RUN_ROOT, runId, 'projected', 'groups', encodeKey(groupId)];
  const excluded = new Set(['expenses', 'recordedSettlements', 'members', 'memberUids', 'memberEmails', 'memberUsernames', 'memberIdentities']);
  const metadata = Object.fromEntries(Object.entries(data).filter(([key]) => !excluded.has(key)));
  addWrite(writes, sourcePath, groupId, [...groupRoot, 'data'], encodeFirestoreValue(metadata, { typeMap, pointer: sourcePointer('groups', groupId, 'data') }));

  const orderedArrays = [
    ['members', members, 'memberNames'],
    ['memberUids', memberUids, 'memberUidOrder'],
    ['memberEmails', memberEmails, 'memberEmails'],
    ['memberUsernames', memberUsernames, 'memberUsernames'],
  ];
  for (const [field, entries, destinationField] of orderedArrays) {
    entries.forEach((entry, index) => addWrite(writes, `${sourcePath}.${field}[${index}]`, `${groupId}:${field}:${index}`, [...groupRoot, destinationField, String(index).padStart(10, '0')], encodeFirestoreValue(entry)));
  }
  const memberSet = new Set(memberUids);
  for (const uid of memberSet) {
    const userRoot = [...RUN_ROOT, runId, 'projected', 'userGroups', encodeKey(uid), encodeKey(groupId)];
    addWrite(writes, `${sourcePath}.memberUids`, uid, userRoot, true);
    addWrite(writes, `${sourcePath}.memberUids`, uid, [...groupRoot, 'memberUids', encodeKey(uid)], true);
  }
  // Current app queries groups by member UID OR createdBy, so retain creator access in this index.
  if (!memberSet.has(data.createdBy)) {
    addWrite(writes, `${sourcePath}.createdBy`, data.createdBy, [...RUN_ROOT, runId, 'projected', 'userGroups', encodeKey(data.createdBy), encodeKey(groupId)], { role: 'creator' });
  }
  for (const identity of identities) {
    addWrite(writes, `${sourcePath}.memberIdentities`, identity.uid, [...groupRoot, 'memberIdentities', encodeKey(identity.uid)], encodeFirestoreValue(identity));
  }

  const expenses = data.expenses ?? [];
  if (!Array.isArray(expenses)) throw new MigrationError('malformed_expenses', `${sourcePath}.expenses must be an array when present.`);
  const expenseIds = new Set();
  expenses.forEach((expense, index) => {
    const expensePath = `${sourcePath}.expenses[${index}]`;
    if (!expense || typeof expense !== 'object' || Array.isArray(expense) || typeof expense.id !== 'string' || !expense.id) {
      throw new MigrationError('missing_expense_id', `${expensePath} must have a nonempty stable id.`);
    }
    if (expenseIds.has(expense.id)) throw new MigrationError('duplicate_expense_id', `${sourcePath} has duplicate expense ID '${expense.id}'.`, { groupId, id: expense.id });
    expenseIds.add(expense.id);
    if (typeof expense.paidBy !== 'string') throw new MigrationError('malformed_expense', `${expensePath}.paidBy must be a string.`);
    ensureUniqueName(expense.paidBy, members, `${expensePath}.paidBy`);
    const splits = requireStrings(expense.splitBetween, expensePath, 'splitBetween');
    splits.forEach((name) => ensureUniqueName(name, members, `${expensePath}.splitBetween`));
    if (typeof expense.amount !== 'number' || !Number.isFinite(expense.amount) || expense.amount < 0) throw new MigrationError('malformed_expense_amount', `${expensePath}.amount must be a finite nonnegative number.`);
    if (expense.splitType === 'custom') {
      if (!expense.customSplits || typeof expense.customSplits !== 'object' || Array.isArray(expense.customSplits)) throw new MigrationError('malformed_custom_splits', `${expensePath}.customSplits must be a map.`);
      for (const [name, amount] of Object.entries(expense.customSplits)) {
        ensureUniqueName(name, members, `${expensePath}.customSplits`);
        if (typeof amount !== 'number' || !Number.isFinite(amount)) throw new MigrationError('malformed_custom_split_amount', `${expensePath}.customSplits contains a non-finite amount.`);
      }
    }
    addWrite(writes, expensePath, expense.id, [...groupRoot, 'expenses', encodeKey(expense.id)], {
      sourceId: expense.id,
      data: encodeFirestoreValue(expense, { typeMap, pointer: sourcePointer('groups', groupId, 'data', 'expenses', index) }),
    });
    counts.expenses++;
  });

  const settlements = data.recordedSettlements ?? [];
  if (!Array.isArray(settlements)) throw new MigrationError('malformed_settlements', `${sourcePath}.recordedSettlements must be an array when present.`);
  const settlementIds = new Set();
  settlements.forEach((settlement, index) => {
    const settlementPath = `${sourcePath}.recordedSettlements[${index}]`;
    if (!settlement || typeof settlement !== 'object' || Array.isArray(settlement) || typeof settlement.id !== 'string' || !settlement.id) {
      throw new MigrationError('missing_settlement_id', `${settlementPath} must have a nonempty stable id.`);
    }
    if (settlementIds.has(settlement.id)) throw new MigrationError('duplicate_settlement_id', `${sourcePath} has duplicate settlement ID '${settlement.id}'.`, { groupId, id: settlement.id });
    settlementIds.add(settlement.id);
    const fromUser = resolveSettlementAlias(settlement, 'fromUser', 'from', settlementPath);
    const toUser = resolveSettlementAlias(settlement, 'toUser', 'to', settlementPath);
    if (typeof fromUser !== 'string' || typeof toUser !== 'string' || fromUser === toUser || typeof settlement.amount !== 'number' || !Number.isFinite(settlement.amount) || settlement.amount < 0 || typeof settlement.isSettled !== 'boolean') {
      throw new MigrationError('malformed_settlement', `${settlementPath} has invalid parties, amount, or status.`);
    }
    ensureUniqueName(fromUser, members, `${settlementPath}.fromUser`);
    ensureUniqueName(toUser, members, `${settlementPath}.toUser`);
    // Keep legacy fields and all source values; add canonical party fields only
    // when an unambiguous from/to alias supplied the corresponding value.
    const projectedSettlement = { ...settlement, fromUser, toUser };
    addWrite(writes, settlementPath, settlement.id, [...groupRoot, 'recordedSettlements', encodeKey(settlement.id)], {
      sourceId: settlement.id,
      data: encodeFirestoreValue(projectedSettlement, { typeMap, pointer: sourcePointer('groups', groupId, 'data', 'recordedSettlements', index) }),
    });
    counts.settlements++;
  });

  const activities = groupDoc.subcollections?.activities ?? [];
  if (!Array.isArray(activities)) throw new MigrationError('malformed_activities', `${sourcePath}/activities must be an array.`);
  const activityDocs = activities.map((activity, index) => ({ ...activity, index }));
  const pagedActivities = paginateDocuments(activityDocs, pageSize);
  for (const page of pagedActivities) {
    for (const activity of page.docs) {
      if (typeof activity.id !== 'string' || !activity.id || !activity.data || typeof activity.data !== 'object' || Array.isArray(activity.data)) {
        throw new MigrationError('malformed_activity', `${sourcePath}/activities contains a malformed record.`);
      }
      if (activity.data.groupId && activity.data.groupId !== groupId) throw new MigrationError('activity_group_mismatch', `${sourcePath}/activities/${activity.id} has a different groupId.`);
      addWrite(writes, `${sourcePath}/activities/${activity.id}`, activity.id, [...groupRoot, 'activities', encodeKey(activity.id)], {
        sourceId: activity.id,
        data: encodeFirestoreValue(activity.data, { typeMap, pointer: sourcePointer('groups', groupId, 'activities', activity.id) }),
      });
      counts.activities++;
    }
  }
  counts.groups++;
  counts.sourceDocuments++;
  addWrite(writes, sourcePath, groupId, [...RUN_ROOT, runId, 'sourceArchive', 'groups', encodeKey(groupId), 'document'], encodeFirestoreValue(data, { typeMap, pointer: sourcePointer('groups', groupId, 'data') }));
  for (const activity of activityDocs) {
    addWrite(writes, `${sourcePath}/activities/${activity.id}`, activity.id, [...RUN_ROOT, runId, 'sourceArchive', 'groups', encodeKey(groupId), 'activities', encodeKey(activity.id)], encodeFirestoreValue(activity.data, { typeMap, pointer: sourcePointer('groups', groupId, 'activities', activity.id) }));
    counts.sourceDocuments++;
  }
}

function resolveSettlementAlias(settlement, canonicalField, aliasField, settlementPath) {
  const canonical = settlement[canonicalField];
  const alias = settlement[aliasField];
  if (alias !== undefined && typeof alias !== 'string') {
    throw new MigrationError('malformed_settlement_alias', `${settlementPath} contains an invalid ${aliasField} alias.`);
  }
  if (canonical !== undefined && alias !== undefined && canonical !== alias) {
    throw new MigrationError('conflicting_settlement_alias', `${settlementPath} has conflicting ${canonicalField} and ${aliasField} values.`);
  }
  return canonical ?? alias;
}

export function buildMigrationPlan(fixture, { pageSize = 100 } = {}) {
  if (!fixture || fixture.format !== 'samvibhag-firestore-fixture-v1' || !fixture.collections || typeof fixture.collections !== 'object') {
    throw new MigrationError('invalid_fixture', 'Expected a samvibhag-firestore-fixture-v1 fixture.');
  }
  const unexpectedCollectionCount = Object.keys(fixture.collections).filter((name) => !SOURCE_COLLECTIONS.has(name)).length;
  if (unexpectedCollectionCount > 0) {
    throw new MigrationError('unsupported_source_collections', 'Fixture contains source collections without an approved destination mapping.', { unexpectedCollectionCount });
  }
  validateTypeMap(fixture);
  const typeMap = fixture.types ?? {};
  const stableCollections = Object.fromEntries(Object.keys(fixture.collections).sort().map((collection) => [
    collection,
    Array.isArray(fixture.collections[collection])
      ? fixture.collections[collection].map((document) => collection === 'groups' && document?.subcollections?.activities
        ? { ...document, subcollections: { ...document.subcollections, activities: [...document.subcollections.activities].sort((a, b) => compareIds(a.id, b.id)) } }
        : document).sort((a, b) => compareIds(String(a?.id ?? ''), String(b?.id ?? '')))
      : fixture.collections[collection],
  ]));
  const sourceHash = hashValue({ collections: stableCollections, types: typeMap });
  const runId = `fixture_${sourceHash.slice(0, 20)}`;
  const writes = new Map();
  const counts = { users: 0, usernames: 0, groups: 0, expenses: 0, settlements: 0, activities: 0, sourceDocuments: 0 };
  const users = sourceDocuments(fixture, 'users', pageSize);
  const usernames = sourceDocuments(fixture, 'usernames', pageSize);
  const groups = sourceDocuments(fixture, 'groups', pageSize);
  const userIds = new Set(users.map((doc) => doc.id));

  users.forEach((doc, index) => {
    if (doc.data.uid !== undefined && doc.data.uid !== doc.id) throw new MigrationError('user_uid_mismatch', `users/${doc.id}.uid differs from its document ID.`);
    const root = [...RUN_ROOT, runId, 'projected', 'users', encodeKey(doc.id), 'profile'];
    addWrite(writes, `users/${doc.id}`, doc.id, root, { sourceId: doc.id, data: encodeFirestoreValue(doc.data, { typeMap, pointer: sourcePointer('users', doc.id, 'data') }) });
    addWrite(writes, `users/${doc.id}`, doc.id, [...RUN_ROOT, runId, 'sourceArchive', 'users', encodeKey(doc.id)], encodeFirestoreValue(doc.data, { typeMap, pointer: sourcePointer('users', doc.id, 'data') }));
    counts.users++;
    counts.sourceDocuments++;
  });
  for (const doc of usernames) {
    if (typeof doc.data.uid !== 'string' || !doc.data.uid) throw new MigrationError('malformed_username', `usernames/${doc.id}.uid is required.`);
    if (!userIds.has(doc.data.uid)) throw new MigrationError('unresolved_username_user', `usernames/${doc.id} references missing users/${doc.data.uid}.`);
    const value = { sourceId: doc.id, data: encodeFirestoreValue(doc.data, { typeMap, pointer: sourcePointer('usernames', doc.id, 'data') }) };
    addWrite(writes, `usernames/${doc.id}`, doc.id, [...RUN_ROOT, runId, 'projected', 'usernames', encodeKey(doc.id)], value);
    addWrite(writes, `usernames/${doc.id}`, doc.id, [...RUN_ROOT, runId, 'sourceArchive', 'usernames', encodeKey(doc.id)], encodeFirestoreValue(doc.data, { typeMap, pointer: sourcePointer('usernames', doc.id, 'data') }));
    counts.usernames++;
    counts.sourceDocuments++;
  }

  for (const doc of groups) {
    if (doc.data.createdBy && !userIds.has(doc.data.createdBy)) throw new MigrationError('unresolved_group_creator', `groups/${doc.id} references missing profile users/${doc.data.createdBy}.`);
    doc.index = doc.index ?? fixture.collections.groups.indexOf(doc);
    groupWrites(doc, runId, typeMap, pageSize, writes, counts, userIds);
  }
  return {
    runId,
    sourceHash,
    writes: [...writes.values()].sort((a, b) => pathString(a.path).localeCompare(pathString(b.path))),
    sourceCounts: { users: users.length, usernames: usernames.length, groups: groups.length, expenses: counts.expenses, settlements: counts.settlements, activities: counts.activities, sourceDocuments: counts.sourceDocuments },
    destinationCounts: { projectedRecords: [...writes.values()].filter((write) => write.path.includes('projected')).length, archivedRecords: [...writes.values()].filter((write) => write.path.includes('sourceArchive')).length },
    expectedDestinationHash: hashValue([...writes.values()].sort((a, b) => pathString(a.path).localeCompare(pathString(b.path))).map(({ path: segments, hash }) => ({ path: segments, hash }))),
  };
}

function getAt(tree, segments) {
  let current = tree;
  for (const segment of segments) {
    if (!current || typeof current !== 'object' || !Object.hasOwn(current, segment)) return undefined;
    current = current[segment];
  }
  return current;
}

function setAt(tree, segments, value) {
  let current = tree;
  for (const segment of segments.slice(0, -1)) {
    if (!Object.hasOwn(current, segment)) current[segment] = {};
    if (!current[segment] || typeof current[segment] !== 'object' || Array.isArray(current[segment])) {
      throw new MigrationError('destination_shape_conflict', `Destination parent at ${pathString(segments)} is not an object.`);
    }
    current = current[segment];
  }
  current[segments.at(-1)] = value;
}

export function createMemoryStore(initialState = null) {
  let state = initialState ? structuredClone(initialState) : { tree: {}, journal: {} };
  return {
    load: () => structuredClone(state),
    save: (next) => { state = structuredClone(next); },
  };
}

export class SimulatedInterruption extends Error {
  constructor() { super('Simulated interruption after a persisted local record.'); this.name = 'SimulatedInterruption'; }
}

export function applyPlanLocally(plan, store, { failAfter = Infinity } = {}) {
  const state = store.load() ?? { tree: {}, journal: {} };
  state.tree ??= {};
  state.journal ??= {};
  const prefix = [...RUN_ROOT, plan.runId];
  const existingRoot = getAt(state.tree, prefix);
  if (existingRoot !== undefined && state.runId !== plan.runId) {
    throw new MigrationError('run_namespace_conflict', `Migration run namespace ${pathString(prefix)} already exists for a different source.`);
  }
  state.runId = plan.runId;
  let committedThisCall = 0;
  let alreadyPresent = 0;
  for (const write of plan.writes) {
    const existing = getAt(state.tree, write.path);
    if (existing !== undefined) {
      if (hashValue(existing) !== write.hash) throw new MigrationError('destination_conflict', `Refusing to overwrite a different value at ${pathString(write.path)}.`, { sourcePath: write.sourcePath, sourceId: write.sourceId });
      state.journal[pathString(write.path)] = write.hash;
      alreadyPresent++;
      store.save(state);
      continue;
    }
    setAt(state.tree, write.path, write.value);
    state.journal[pathString(write.path)] = write.hash;
    committedThisCall++;
    store.save(state);
    if (committedThisCall >= failAfter) throw new SimulatedInterruption();
  }
  const verification = verifyPlan(plan, state.tree);
  state.report = {
    mode: 'local-fixture-only',
    sourceCounts: plan.sourceCounts,
    destinationCounts: plan.destinationCounts,
    writtenThisCall: committedThisCall,
    identicalPathsSkipped: alreadyPresent,
    verification,
    status: verification.ok ? 'verified-local-fixture' : 'failed-verification',
  };
  store.save(state);
  if (!verification.ok) throw new MigrationError('verification_failed', 'Destination verification found missing, mismatched, or unexpected values.', verification);
  return state.report;
}

export function verifyPlan(plan, tree) {
  const missing = [];
  const mismatched = [];
  const expected = new Set();
  const destinationRecords = [];
  const expectedChildren = new Map();
  for (const write of plan.writes) {
    const key = pathString(write.path);
    expected.add(key);
    for (let index = RUN_ROOT.length + 1; index < write.path.length; index++) {
      const parent = pathString(write.path.slice(0, index));
      if (!expectedChildren.has(parent)) expectedChildren.set(parent, new Set());
      expectedChildren.get(parent).add(write.path[index]);
    }
    const value = getAt(tree, write.path);
    if (value === undefined) missing.push(key);
    else if (hashValue(value) !== write.hash) mismatched.push(key);
    else destinationRecords.push({ path: write.path, hash: hashValue(value) });
  }
  const unexpected = [];
  for (const [parentPath, children] of expectedChildren) {
    const parentSegments = parentPath.split('/').slice(1);
    const actual = getAt(tree, parentSegments);
    if (!actual || typeof actual !== 'object') continue;
    for (const child of Object.keys(actual)) {
      if (!children.has(child)) unexpected.push(`${parentPath}/${child}`);
    }
  }
  const destinationHash = hashValue(destinationRecords.sort((a, b) => pathString(a.path).localeCompare(pathString(b.path))));
  return {
    ok: missing.length === 0 && mismatched.length === 0 && unexpected.length === 0 && destinationRecords.length === plan.writes.length && destinationHash === plan.expectedDestinationHash,
    expectedRecordCount: plan.writes.length,
    verifiedRecordCount: destinationRecords.length,
    missingCount: missing.length,
    mismatchedCount: mismatched.length,
    unexpectedCount: unexpected.length,
  };
}

function assertLocalPath(target, allowedRoot) {
  const resolvedRoot = path.resolve(allowedRoot);
  const resolvedTarget = path.resolve(target);
  if (resolvedTarget !== resolvedRoot && !resolvedTarget.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new MigrationError('path_outside_local_tool', `Path must remain inside ${resolvedRoot}.`);
  }
  return resolvedTarget;
}

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { throw new MigrationError('fixture_read_failed', `Could not read fixture: ${error.message}`); }
}

function writeJsonAtomically(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: 'w' });
  fs.renameSync(temporary, file);
}

function parseArgs(argv) {
  const options = { dryRun: true, pageSize: 100, fixture: path.join(FIXTURE_DIR, 'synthetic-source.json') };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dry-run') options.dryRun = true;
    else if (argv[i] === '--apply-local') options.dryRun = false;
    else if (argv[i] === '--fixture') options.fixture = argv[++i];
    else if (argv[i] === '--page-size') options.pageSize = Number(argv[++i]);
    else throw new MigrationError('invalid_argument', `Unsupported argument '${argv[i]}'.`);
  }
  options.fixture = assertLocalPath(options.fixture, FIXTURE_DIR);
  if (!Number.isInteger(options.pageSize) || options.pageSize < 1) throw new MigrationError('invalid_page_size', 'Page size must be a positive integer.');
  return options;
}

export function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const fixture = readJson(options.fixture);
  const plan = buildMigrationPlan(fixture, { pageSize: options.pageSize });
  if (options.dryRun) {
    console.log(JSON.stringify({ mode: 'dry-run-read-only-local-fixture', sourceCounts: plan.sourceCounts, destinationCounts: plan.destinationCounts, plannedRecordCount: plan.writes.length }, null, 2));
    return;
  }
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const statePath = assertLocalPath(path.join(OUTPUT_DIR, `${plan.runId}.json`), OUTPUT_DIR);
  const store = {
    load: () => fs.existsSync(statePath) ? readJson(statePath) : null,
    save: (state) => writeJsonAtomically(statePath, state),
  };
  const report = applyPlanLocally(plan, store);
  console.log(JSON.stringify(report, null, 2));
}

export function safeCliError(error) {
  const code = error instanceof MigrationError && /^[a-z0-9_]{1,64}$/u.test(error.code) ? error.code : 'migration_failed';
  return { status: 'failed', code };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); }
  catch (error) {
    console.error(JSON.stringify(safeCliError(error)));
    process.exitCode = 1;
  }
}
