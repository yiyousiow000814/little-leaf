'use strict';
// Actual shipped/current vault sources, deterministic synthetic storage only.
// No browser profile, player save, native engine, or external I/O is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const { webcrypto } = require('node:crypto');
const { FixtureIDB } = require('./fixtures/save_log_idb_fixture');
const root = path.resolve(process.env.LITTLE_LEAF_SOURCE_ROOT || path.join(__dirname, '..'));
const baselineRevision = 'e9fcf09fe5a975de73b0749e4b3e8484e5e3b2ae';
const baseline = execFileSync('git', ['show', baselineRevision + ':web/little_leaf_vault.js'], { cwd: root, encoding: 'utf8' });
const source = fs.readFileSync(path.join(root, 'web/little_leaf_vault.js'), 'utf8');
const logSource = fs.readFileSync(path.join(root, 'web/little_leaf_save_log.js'), 'utf8');
const shell = fs.readFileSync(path.join(root, 'web/little_leaf_shell.html'), 'utf8');
const report = { synthetic_only: true, real_browser: false, baseline_revision: baselineRevision, scope: 'Actual vault parity through an atomic IndexedDB model; no browser or Godot UI claim', checks: [] };
const check = (condition, name) => { assert(condition, name); report.checks.push(name); };
const fixture = JSON.stringify({ schema: 'little_leaf_reconstructed_cafe', version: 15, new_reconstruction: true, checkout_format: 'little_leaf.checkout.v1', layout_motion_format: 'little_leaf.layout_motion.v1', coins: 42000, synthetic_marker: 'PRIVATE_PAYLOAD_MARKER_é中文' });
class FixedDate extends Date { constructor(...args) { super(...(args.length ? args : [1770000000000])); } static now() { return 1770000000000; } }

async function run(scenario, variant) {
  const factory = new FixtureIDB(), events = [], results = [];
  let serial = 0;
  const context = vm.createContext({ indexedDB: factory, crypto: { subtle: webcrypto.subtle, randomUUID: () => 'abcdef01-0000-4000-8000-' + String(++serial).padStart(12, '0') },
    Date: FixedDate, TextEncoder, TextDecoder, Uint8Array, Int8Array, TypeError, DOMException, URL, setTimeout, clearTimeout });
  if (variant === 'active') {
    vm.runInContext(logSource, context);
    const logger = context.LittleLeafSaveLog;
    context.LittleLeafSaveLog = { ...logger, record(event, fields) { events.push({ event, commits: factory.commits, aborts: factory.aborts, lastOperation: factory.trace.at(-1)?.[0] }); return logger.record(event, fields); } };
  } else if (variant === 'throwing') context.LittleLeafSaveLog = { record() { throw new Error('PRIVATE_OBSERVER_ERROR'); } };
  else if (variant === 'throwing-getter') Object.defineProperty(context, 'LittleLeafSaveLog', { get() { throw new Error('PRIVATE_OBSERVER_GETTER'); } });
  vm.runInContext(variant === 'baseline' ? baseline : source, context);
  const api = context.LittleLeafVault;
  const recordResult = value => { results.push(value); return value; };
  if (scenario === 'legacy') {
    const payload = JSON.parse(fixture); payload.version = 13; delete payload.layout_motion_format;
    factory.databases.set('/userfs', { version: 1, queue: [], stores: new Map([['FILE_DATA', new Map([['/userfs/PRIVATE_PATH_MARKER/little_leaf_cafe_v13.json', { mode: 33188, timestamp: new Date(0), contents: new Int8Array(new TextEncoder().encode(JSON.stringify(payload)).buffer) }]])]]) });
  }
  if (scenario === 'durability-fallback') factory.fallbackStrict = true;
  let client = context.__littleLeafVault;
  if (scenario === 'unavailable') {
    factory.throwOpen = true; recordResult(await client.boot()); factory.throwOpen = false;
    recordResult(await new Promise(resolve => api.retry(text => resolve(JSON.parse(text))))); client = context.__littleLeafVault;
  }
  if (scenario === 'not-ready') recordResult(await client.commit(fixture, 0, 'abcdef01-0000-4000-8000-000000000001'));
  const boot = recordResult(await client.boot()), before = factory.snapshot();
  if (scenario === 'invalid') {
    recordResult(await client.commit('{PRIVATE_BAD_JSON}', boot.revision, boot.profileId));
    recordResult(await client.commit(fixture, boot.revision, boot.profileId));
  } else if (scenario === 'conflict') {
    const stale = api.createClient(); recordResult(await stale.boot());
    recordResult(await client.commit(fixture, boot.revision, boot.profileId));
    recordResult(await stale.commit(fixture, boot.revision, boot.profileId));
    recordResult(await stale.commit(fixture, boot.revision, boot.profileId)); stale.close();
  } else if (scenario === 'busy') {
    const first = client.commit(fixture, boot.revision, boot.profileId);
    recordResult(await client.commit(fixture, boot.revision, boot.profileId)); recordResult(await first);
  } else if (scenario === 'callback') {
    recordResult(await new Promise(resolve => client.save(fixture, boot.revision, boot.profileId, text => resolve(JSON.parse(text)))));
  } else if (scenario === 'quota') {
    factory.throwPut = true; recordResult(await client.commit(fixture, boot.revision, boot.profileId));
  } else if (scenario === 'abort') {
    factory.abortAfterPut = true; recordResult(await client.commit(fixture, boot.revision, boot.profileId));
  } else if (scenario === 'corrupt') {
    recordResult(await client.commit(fixture, boot.revision, boot.profileId));
    const rows = factory.databases.get(api.DB_NAME).stores.get('profiles'), active = rows.get('active');
    active.payload = active.payload.replace('42000', '42001');
    const damaged = factory.snapshot();
    const rejected = api.createClient(); recordResult(await rejected.boot()); rejected.close();
    recordResult(await client.commit(fixture, boot.revision + 1, boot.profileId));
    results.push({ damagedUnchanged: damaged === factory.snapshot() });
  } else {
    const saved = recordResult(await client.commit(fixture, boot.revision, boot.profileId));
    client.close(); client = api.createClient(); recordResult(await client.boot());
    if (scenario === 'legacy') recordResult(await client.commit(fixture, saved.revision, saved.profileId));
  }
  const after = factory.snapshot(), bootJson = client.bootJson; client.close();
  const diagnostic = variant === 'active' ? { text: context.LittleLeafSaveLog.text(), snapshot: context.LittleLeafSaveLog.snapshot() } : null;
  return JSON.parse(JSON.stringify({ results, before, after, bootJson, trace: factory.trace, requestSucceededBeforeAbort: factory.requestSucceededBeforeAbort, events, diagnostic }));
}
(async () => {
  check(shell.includes(source.trim()), 'Standalone vault exactly matches the shell copy');
  check(shell.includes(logSource.trim()), 'Standalone diagnostic exactly matches the shell copy');
  for (const scenario of ['fresh', 'legacy', 'invalid', 'conflict', 'busy', 'abort', 'corrupt', 'unavailable', 'durability-fallback', 'callback', 'not-ready', 'quota']) {
    const reference = await run(scenario, 'baseline');
    for (const variant of ['absent', 'active', 'throwing', 'throwing-getter']) {
      const actual = await run(scenario, variant);
      for (const field of ['results', 'before', 'after', 'bootJson', 'trace', 'requestSucceededBeforeAbort']) assert.deepEqual(actual[field], reference[field], scenario + '/' + variant + ': ' + field + ' changed');
      check(true, scenario + '/' + variant + ': return values, full storage bytes and operations match reviewed pre-diagnostic main');
      if (variant === 'active') {
        check(actual.events.some(row => row.event === 'boot_requested'), scenario + ': boot request is observable');
        const text = JSON.stringify(actual.diagnostic);
        check(!['PRIVATE_PAYLOAD_MARKER', 'PRIVATE_PATH_MARKER', 'PRIVATE_ERROR_MARKER', 'PRIVATE_BAD_JSON', 'abcdef01-0000-4000-8000-', 'little_leaf_reconstructed_cafe'].some(secret => text.includes(secret)), scenario + ': diagnostic excludes save data, paths, raw errors and complete identity');
        const confirmed = actual.events.filter(row => row.event === 'save_confirmed');
        const successes = actual.results.filter(row => row.ok && row.durable);
        check(confirmed.length === successes.length, scenario + ': confirmation count equals acknowledged durable transactions');
        check(confirmed.every((row, index) => row.commits === index + 1 && row.lastOperation === 'complete'), scenario + ': every confirmation follows its own transaction completion');
        check(actual.events.filter(row => row.event === 'save_submitted').every(row => row.lastOperation === 'put'), scenario + ': submitted is emitted only after the storage write is enqueued');
        if (scenario === 'quota') check(actual.before === actual.after && !actual.events.some(row => row.event === 'save_submitted'), 'Synchronous quota failure leaves storage unchanged and never claims submission');
        if (scenario === 'abort') check(actual.requestSucceededBeforeAbort && confirmed.length === 0 && actual.before === actual.after, 'Successful put followed by abort is never reported saved and leaves all stored rows unchanged');
        if (scenario === 'corrupt') check(actual.results.at(-1).damagedUnchanged, 'Corrupt authority is left untouched');
      }
    }
  }
  report.passed = true; report.total_checks = report.checks.length;
  if (process.env.SAVE_LOG_REPORT) fs.writeFileSync(process.env.SAVE_LOG_REPORT, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
