'use strict';
// Demonstrates possible reset signatures with only disposable synthetic IDB.
// This does not identify the cause of any real player's missing progress.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { FixtureIDB, FixtureStore } = require('./inbox_transaction_fixture');
const root = path.resolve(__dirname, '..');
const payload = fs.readFileSync(path.join(__dirname, 'fixtures/startup-retry-v15.json'), 'utf8');
const report = { synthetic_only: true, real_browser: false, physical_ipad_safari: false, checks: [], signatures: [] };
function check(value, label) { assert(value, label); report.checks.push(label); }
function bytes(factory) {
  return JSON.stringify(Array.from(factory.databases, ([name, value]) => [name, Array.from(value.stores, ([key, rows]) => [key, Array.from(rows)])]));
}
async function run(file) {
  const factory = new FixtureIDB();
  const context = vm.createContext({ crypto: crypto.webcrypto, TextEncoder, TextDecoder, Uint8Array, Int8Array, structuredClone, setTimeout, clearTimeout, DOMException, indexedDB: factory });
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context);
  const api = context.LittleLeafVault;
  const first = api.createClient(), initial = await first.boot();
  check(initial.ok && initial.source === 'fresh' && initial.revision === 0, file + ': initial profile is uncommitted');
  const baseline = bytes(factory);
  const put = FixtureStore.prototype.put;
  FixtureStore.prototype.put = function () { throw new DOMException('Synthetic quota failure', 'QuotaExceededError'); };
  let failed;
  try { failed = await first.commit(payload, initial.revision, initial.profileId); }
  finally { FixtureStore.prototype.put = put; }
  check(!failed.ok && failed.code === 'QuotaExceededError' && !failed.durable, file + ': first write failure has no durable acknowledgement');
  check(bytes(factory) === baseline, file + ': failed first write preserves revision-zero authority');
  first.close();
  const reloaded = api.createClient(), afterFailure = await reloaded.boot();
  check(afterFailure.ok && afterFailure.source === 'fresh' && afterFailure.revision === 0 && afterFailure.profileId === initial.profileId, file + ': reload after failed first write is fresh with the SAME identity');
  const success = await reloaded.commit(payload, afterFailure.revision, afterFailure.profileId);
  check(success.ok && success.durable && success.revision === 1, file + ': later retry commits the original identity');
  reloaded.close();
  const afterSuccess = await api.createClient().boot();
  check(afterSuccess.ok && afterSuccess.source === 'authority' && afterSuccess.profileId === initial.profileId && afterSuccess.payload === payload, file + ': same storage restores after a completed write');
  const differentPartition = await api.createClient({ indexedDB: new FixtureIDB() }).boot();
  check(differentPartition.ok && differentPartition.source === 'fresh' && differentPartition.profileId !== initial.profileId, file + ': a different empty storage area is fresh with a NEW identity');
  report.signatures.push({ source: file, first_write_failure: { code: failed.code, next_boot: afterFailure.source, same_profile: afterFailure.profileId === initial.profileId }, committed_same_storage: afterSuccess.source, different_empty_storage: { source: differentPartition.source, same_profile: differentPartition.profileId === initial.profileId } });
}
(async () => {
  await run('tests/fixtures/inbox-vault-018.js');
  await run('web/little_leaf_vault.js');
  report.passed = true;
  console.log(JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
