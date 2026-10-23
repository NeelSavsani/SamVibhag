import assert from 'node:assert/strict';
import test from 'node:test';
import { readRealtimeDatabaseBoundedInventory, RTDB_INVENTORY_COLLECTION_PATHS } from '../read_only_adapters.mjs';

test('synthetic paginated memory probe uses a fake client and measures local JSON-shaped object handling', async (t) => {
  const users = {};
  for (let index = 0; index < 4000; index++) {
    users[`synthetic-user-${String(index).padStart(5, '0')}`] = {
      profile: { uid: `synthetic-user-${index}`, displayName: `Synthetic Member ${index}`, notes: 'x'.repeat(512) },
    };
  }
  const before = process.memoryUsage();
  let afterRead;
  let largestPage = 0;
  let refCalls = 0;
  const database = {
    ref(path) {
      assert.ok(RTDB_INVENTORY_COLLECTION_PATHS.includes(path));
      refCalls++;
      return {
        orderByKey() { return this; },
        limitToFirst(size) { this.pageSize = size; largestPage = Math.max(largestPage, size); return this; },
        startAfter(cursor) { this.cursor = cursor; return this; },
        async get() {
          // A synthetic client exposes only the requested page to the adapter.
          const keys = Object.keys(path === RTDB_INVENTORY_COLLECTION_PATHS[0] ? users : {}).filter((key) => this.cursor === undefined || key > this.cursor).sort();
          const children = keys.slice(0, this.pageSize).map((key) => ({ key, val: () => users[key] }));
          afterRead = process.memoryUsage();
          return { forEach(callback) { for (const child of children) if (callback(child) === true) break; } };
        },
      };
    },
  };
  const report = await readRealtimeDatabaseBoundedInventory({
    database,
    limits: { pageSize: 25, maxRecords: 5000, maxRecordBytes: 4096, maxTotalBytes: 4 * 1024 * 1024 },
  });

  assert.equal(report.inventoryStatus, 'complete_for_configured_scope');
  assert.equal(report.recordCount, 4000);
  assert.equal(largestPage, 25);
  assert.ok(refCalls > 160);
  assert.ok(afterRead && Number.isFinite(afterRead.heapUsed));
  t.diagnostic(JSON.stringify({
    probe: 'synthetic_fake_client_only',
    estimatedRecordBytes: report.estimatedJsonBytes,
    heapDeltaBytes: afterRead.heapUsed - before.heapUsed,
    rssDeltaBytes: afterRead.rss - before.rss,
    maxObservedRssBytes: report.maxObservedRssBytes,
    firebaseSdkTransportOrDeserializationMeasured: false,
  }));
});
