'use strict';
// No browser, storage or network. Exercise the real logger with hostile inputs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(process.env.LITTLE_LEAF_SOURCE_ROOT || path.join(__dirname, '..'));
const source = fs.readFileSync(path.join(root, 'web/little_leaf_save_log.js'), 'utf8');
const report = { synthetic_only: true, scope: 'Diagnostic privacy, bounded lifetime and copy behavior', checks: [] };
const check = (condition, name) => { assert(condition, name); report.checks.push(name); };
function load(options = {}) {
  const effects = { storage: 0, network: 0, copies: [], removed: 0, focused: 0 };
  const forbiddenStorage = () => { effects.storage++; throw new Error('Unexpected diagnostic storage access'); };
  const forbiddenNetwork = () => { effects.network++; throw new Error('Unexpected diagnostic network request'); };
  const context = vm.createContext({ URL, TextEncoder, Date,
    location: { href: options.href || 'https://PRIVATE_USER:PRIVATE_PASSWORD@example.test/PRIVATE_PATH?secret=PRIVATE_QUERY#PRIVATE_FRAGMENT' },
    navigator: { userAgent: 'PRIVATE_UA Mozilla/5.0 Version/18.3 Safari/605.1.15', sendBeacon: forbiddenNetwork,
      clipboard: { writeText: value => { effects.copies.push(value); return options.rejectClipboard ? Promise.reject(new Error('Synthetic denial')) : Promise.resolve(); } } },
    document: { referrer: 'https://refer.example.test/PRIVATE_REFERRER?token=PRIVATE_TOKEN#PRIVATE_HASH',
      body: { appendChild() {} }, createElement() { return { value: '', style: {}, setAttribute() {}, focus() {}, select() {}, setSelectionRange() {}, remove() { effects.removed++; } }; },
      execCommand(command) { assert.equal(command, 'copy'); return !!options.fallbackWorks; },
      getElementById() { return { focus() { effects.focused++; } }; } },
    fetch: forbiddenNetwork, XMLHttpRequest: forbiddenNetwork, WebSocket: forbiddenNetwork
  });
  for (const property of ['indexedDB', 'localStorage', 'sessionStorage']) Object.defineProperty(context, property, { get: forbiddenStorage });
  vm.runInContext('top=globalThis', context);
  vm.runInContext(source, context);
  return { api: context.LittleLeafSaveLog, effects };
}
(async () => {
  const versions = load().api;
  for (const value of ['0.1.10', '0.1.10a', '0.1.10z', '0.1.8-alpha', '0.1.10a-rc.1']) {
    versions.setVersion(value);
    check(versions.text().startsWith('Little Leaf save log | app ' + value + '\n'), 'Supported release version is retained: ' + value);
  }
  versions.setVersion('0.1.10a');
  for (const value of ['0.1.10aa', '0.1.10A', 'v0.1.10a', '0.1', '0.1.10a\n', '<b>0.1.10a</b>', '0.1.10-' + 'a'.repeat(40), null, 10, {}, ['0.1.10a']]) {
    versions.setVersion(value);
    check(versions.text().startsWith('Little Leaf save log | app 0.1.10a\n'), 'Invalid version cannot replace the last valid header: ' + JSON.stringify(value));
  }
  const projectVersion = fs.readFileSync(path.join(root, 'project.godot'), 'utf8').match(/^config\/version="([^"]+)"$/m)[1];
  versions.setVersion(projectVersion);
  check(versions.text().startsWith('Little Leaf save log | app ' + projectVersion + '\n'), 'Current project release version reaches the diagnostic header');
  const startMarker = '/* Session-only save diagnostics. No storage, payloads, raw errors or telemetry. */';
  const endMarker = '/* Little Leaf authoritative Web storage. Never mounts or writes Godot IDBFS. */';
  for (const shell of ['little_leaf_shell.html', 'little_leaf_crazygames_shell.html']) {
    const embedded = fs.readFileSync(path.join(root, 'web', shell), 'utf8');
    const start = embedded.indexOf(startMarker), end = embedded.indexOf(endMarker, start);
    check(start >= 0 && end > start && embedded.slice(start, end).trim() === source.trim(), shell + ' embeds the exact standalone diagnostic source bytes');
  }
  const { api, effects } = load();
  check(api.snapshot().length === 0, 'Logger begins empty without startup writes');
  api.setVersion('0.1.8-alpha');
  const id = 'abcdef01-2345-4000-8000-123456789abc';
  api.record('save_requested', { layer: 'vault', source: 'authority', profileId: id, revision: 4, payload: 'PRIVATE_PAYLOAD', message: 'PRIVATE_MESSAGE', stack: 'PRIVATE_STACK', digest: 'PRIVATE_DIGEST', path: 'PRIVATE_FILE', error: new Error('PRIVATE_ERROR') });
  api.record('save_failure', { layer: 'PRIVATE_LAYER', source: 'PRIVATE_SOURCE', profileId: id, revision: -1, code: 'PRIVATE_CODE' });
  api.record('PRIVATE_EVENT', { payload: 'PRIVATE_EXTRA' });
  api.record('save_failure', { code: 'QuotaExceededError' });
  const initial = api.snapshot();
  check(initial.length === 3, 'Unknown events are rejected');
  check(initial[0].profile === initial[1].profile && /^[a-f0-9]{8}$/.test(initial[0].profile), 'Only a stable short profile fingerprint is retained');
  check(initial[0].revision === 4 && !('revision' in initial[1]), 'Revision accepts only a non-negative safe integer');
  check(initial[1].code === 'STORAGE_ERROR' && initial[2].code === 'QuotaExceededError', 'Unknown error codes are reduced to a fixed safe code');
  check(!('layer' in initial[1]) && !('source' in initial[1]), 'Unknown layer and source strings are discarded');
  const allowedKeys = new Set(['sequence', 'timestamp', 'event', 'layer', 'source', 'profile', 'revision', 'code', 'stage', 'connectionGeneration']);
  check(initial.every(entry => Object.keys(entry).every(key => allowedKeys.has(key))), 'Entries contain only documented allowlisted fields');
  const text = api.text();
  check(text.includes('app 0.1.8-alpha') && text.includes('origin=https://example.test') && text.includes('referrerOrigin=https://refer.example.test') && text.includes('browser=Safari 18.3') && text.includes('frame=top-level'), 'Context retains version, origins, browser family/version and frame status');
  check(!text.includes('PRIVATE_') && !text.includes(id), 'Rendered log excludes credentials, paths, query/fragment, raw UA, save data, errors and complete IDs');
  check(!JSON.stringify(initial).includes('PRIVATE_') && !JSON.stringify(initial).includes(id), 'Snapshot has the same privacy boundary');
  api.record('connection_opened', { stage: 'reopen_existing', connectionGeneration: 2, message: 'PRIVATE_MESSAGE', stack: 'PRIVATE_STACK' });
  check(api.snapshot().at(-1).stage === 'reopen_existing' && api.snapshot().at(-1).connectionGeneration === 2, 'connection diagnostics accept only explicit static stage and valid generation');
  for (const connectionGeneration of [0, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1, '2']) {
    api.record('connection_closed', { stage: 'PRIVATE_STAGE', connectionGeneration });
    const row = api.snapshot().at(-1);
    check(!('stage' in row) && !('connectionGeneration' in row), 'unsafe stage or connection generation cannot enter diagnostics');
  }
  check(!api.text().includes('PRIVATE_'), 'new connection diagnostics never include raw messages, stacks or arbitrary stage strings');
  initial[0].event = 'PRIVATE_MUTATION'; initial.push({ event: 'PRIVATE_MUTATION' });
  check(!api.text().includes('PRIVATE_MUTATION') && api.snapshot().length === 11, 'Snapshot callers cannot mutate the stored events');
  for (const fields of [null, new Proxy({}, { get() { throw new Error('PRIVATE_GETTER'); } })]) {
    assert.doesNotThrow(() => api.record('save_failure', fields));
  }
  for (const revision of [Infinity, NaN, 1.5, Number.MAX_SAFE_INTEGER + 1, '5']) {
    api.record('save_requested', { revision });
    check(!('revision' in api.snapshot().at(-1)), 'Invalid revision ' + String(revision) + ' is omitted');
  }
  api.setVersion('PRIVATE_VERSION?token=PRIVATE_TOKEN');
  check(api.text().includes('app 0.1.8-alpha'), 'Unsafe version strings cannot enter the header');
  api.record('read_result', { layer: 'vault', source: 'legacy-v13', profileId: id, revision: 0, payload: 'PRIVATE_RETAINED_PAYLOAD' });
  api.record('read_accepted', { layer: 'controller', source: 'authority', profileId: id, revision: 7, error: 'PRIVATE_RETAINED_ERROR' });
  const latestRead = api.snapshot().at(-1);
  for (let i = 0; i < 1000; i++) api.record('save_requested', { layer: 'vault', revision: i });
  const bounded = api.snapshot();
  check(bounded.length === 240 && bounded[0].revision === 760 && bounded.at(-1).revision === 999, 'Ring retains exactly the newest 240 events');
  check(!bounded.some(entry => entry.event.startsWith('read_')) && api.text().includes('Latest read=' + JSON.stringify(latestRead)), 'Latest accepted read survives ring rollover in the header');
  check(!api.text().includes('PRIVATE_') && !api.text().includes(id), 'Retained read header contains only sanitized fields and the fingerprint');
  check(api.text().includes('Events retained=240/240') && /older events dropped=[1-9][0-9]*/.test(api.text()), 'Dropped-event count is visible');
  check(effects.storage === 0 && effects.network === 0 && effects.copies.length === 0, 'Reading and recording logs performs no storage, network or clipboard I/O');
  check(load().api.snapshot().length === 0, 'A new page instance retains no events from the prior session');
  check(load({ href: 'file:///PRIVATE_LOCAL_FILE' }).api.text().includes('origin=unknown'), 'Non-web origins are not exposed');
  const expected = api.text(); api.copy(); await new Promise(resolve => setImmediate(resolve));
  check(api.copyStatus === 'copied' && effects.copies.length === 1 && effects.copies[0] === expected, 'Explicit copy sends exactly the visible sanitized text');
  const rejected = load({ rejectClipboard: true, fallbackWorks: true }); rejected.api.copy(); await new Promise(resolve => setImmediate(resolve));
  check(rejected.api.copyStatus === 'copied' && rejected.effects.removed === 1 && rejected.effects.focused === 1, 'Clipboard rejection uses the legacy fallback and removes its temporary element');
  const unavailable = load({ rejectClipboard: true }); unavailable.api.copy(); await new Promise(resolve => setImmediate(resolve));
  check(unavailable.api.copyStatus === 'unavailable' && unavailable.effects.removed === 1, 'Unavailable copy reports failure and removes its temporary element');
  report.passed = true; report.total_checks = report.checks.length;
  if (process.env.SAVE_LOG_PRIVACY_REPORT) fs.writeFileSync(process.env.SAVE_LOG_PRIVACY_REPORT, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
