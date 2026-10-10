'use strict';
// Runs the actual private legacy-read functions against an in-memory read-only
// IDB fixture. No browser profile, player save, engine mount or external I/O.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { webcrypto, createHash } = require('node:crypto');
const root = path.resolve(process.env.LITTLE_LEAF_SOURCE_ROOT || path.join(__dirname, '..'));
const shell = fs.readFileSync(path.join(root, 'platform/web/little_leaf_shell.html'), 'utf8');
const report = { synthetic_only: true, scope: 'Actual legacy readers with read-only IDB fixture; no rendered-browser claim', checks: [] };
const check = (condition, name) => { assert(condition, name); report.checks.push(name); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const payload = JSON.stringify({ schema: 'little_leaf_reconstructed_cafe', version: 13, new_reconstruction: true, checkout_format: 'little_leaf.checkout.v1', coins: 42000, synthetic_marker: 'é中文' });
const settings = '[display]\nzoom=1.0\nsynthetic_marker="é中文"\n';
const profilePath = '/userfs/synthetic/little_leaf_cafe_v13.json';
const settingsPath = '/userfs/synthetic/little_leaf_settings.cfg';
const encode = text => new TextEncoder().encode(text);
function loadReader(filename, marker) {
  const source = fs.readFileSync(path.join(root, 'platform/web', filename), 'utf8');
  check(shell.includes(source.trim()), filename + ' exactly matches embedded shell');
  check(source.split(marker).length === 2, filename + ' instrumentation target is unique');
  const context = vm.createContext({ Uint8Array, Int8Array, TextEncoder, TextDecoder, crypto: webcrypto, setTimeout, clearTimeout });
  vm.runInContext(source.replace(marker, 'root.__readLegacyForTest=readLegacy;\n  ' + marker), context);
  return context.__readLegacyForTest;
}
// Transactions expose only the methods used by the production reader. Any
// readwrite request or unexpected mutation is a test failure.
function fixture(entries, options = {}) {
  const record = { modes: [], opened: [], closed: 0 };
  const snapshot = () => entries.map(([key, value]) => ({ key, mode: value && value.mode, timestamp: value && value.timestamp && value.timestamp.getTime(), tag: Object.prototype.toString.call(value && value.contents), bytes: value && ArrayBuffer.isView(value.contents) ? hash(Buffer.from(value.contents.buffer, value.contents.byteOffset, value.contents.byteLength)) : JSON.stringify(value && value.contents) }));
  const before = JSON.stringify(snapshot());
  const db = { objectStoreNames: { contains: name => name === 'FILE_DATA' && !options.unknownStore }, close: () => record.closed++, transaction(name, mode) {
    assert.equal(name, 'FILE_DATA'); assert.equal(mode, 'readonly'); record.modes.push(mode);
    const tx = { objectStore(storeName) {
      assert.equal(storeName, 'FILE_DATA');
      return { openCursor() {
        const request = {}; let index = 0;
        function next() { queueMicrotask(() => {
          const cursor = index < entries.length ? { key: entries[index][0], value: entries[index++][1], continue: next } : null;
          request.onsuccess({ target: { result: cursor } });
          if (!cursor) queueMicrotask(() => tx.oncomplete());
        }); }
        next(); return request;
      }, put() { throw Error('Unexpected legacy write'); }, delete() { throw Error('Unexpected legacy delete'); } };
    }}; return tx;
  }};
  return { factory: { open(name, version) { assert.equal(name, '/userfs'); assert.equal(version, undefined); record.opened.push(name); const request = {}; queueMicrotask(() => { request.result = db; request.onsuccess(); }); return request; } }, record, unchanged: () => before === JSON.stringify(snapshot()) };
}
function entry(contents) { return { timestamp: new Date(0), mode: 33188, contents }; }
function subview(bytes, Type) {
  const backing = new Uint8Array(bytes.length + 7); backing.fill(0xff); backing.set(bytes, 3);
  return new Type(backing.buffer, 3, bytes.length);
}
async function runRead(read, entries, name, expected, options) {
  const test = fixture(entries, options); let value, error;
  try { value = await read(test.factory); } catch (caught) { error = caught; }
  if (expected.error) check(error && (expected.code ? error.code === expected.code : expected.error.test(error.message)), name + ' rejects as expected');
  else { check(!error, name + ' succeeds'); expected.accept(value); }
  check(test.unchanged(), name + ' leaves all fixture bytes and metadata unchanged');
  check(test.record.modes.every(mode => mode === 'readonly'), name + ' requests no legacy write transaction');
  check(test.record.closed === 1, name + ' closes the database');
}
(async () => {
  const vault = loadReader('little_leaf_vault.js', 'root.LittleLeafVault =');
  const prefs = loadReader('little_leaf_preferences.js', 'root.LittleLeafPreferences=');
  for (const [name, Type] of [['unsigned', Uint8Array], ['signed', Int8Array]]) {
    for (const offset of [false, true]) {
      const data = encode(payload), cfg = encode(settings);
      const bytes = offset ? subview(data, Type) : new Type(data.buffer);
      const cfgBytes = offset ? subview(cfg, Type) : new Type(cfg.buffer);
      const label = name + (offset ? ' subview with nonzero offset' : ' whole view');
      await runRead(vault, [[profilePath, entry(bytes)]], 'vault ' + label, { accept: result => {
        check(result.payload === payload, label + ' preserves exact UTF-8 payload');
        check(result.path === profilePath && result.digest === hash(data), label + ' preserves path and payload checksum');
      }});
      await runRead(prefs, [[profilePath, entry(bytes)], [settingsPath, entry(cfgBytes)]], 'preferences ' + label, { accept: result => check(result === settings, label + ' preserves exact UTF-8 preferences') });
    }
    // Every byte through 0xff is preserved; malformed UTF-8 must not be repaired.
    for (const [reader, filename, limit, key] of [[vault, 'vault', 1048576, profilePath], [prefs, 'preferences', 65536, settingsPath]]) {
      await runRead(reader, [[key, entry(new Type(limit + 1))]], filename + ' oversize ' + name, { error: /unreadable or too large/ });
      await runRead(reader, [[key, entry(new Type([0xc3, 0x28]))]], filename + ' malformed UTF-8 ' + name, { error: /encoding|encoded/, ...(filename === 'vault' ? { code: 'INVALID_SAVE' } : {}) });
    }
  }
  for (const [name, contents] of [['ArrayBuffer', encode(payload).buffer], ['Uint16Array', new Uint16Array([123, 125])], ['DataView', new DataView(encode(payload).buffer)], ['Uint8ClampedArray', new Uint8ClampedArray(encode(payload))], ['plain Array', Array.from(encode(payload))], ['missing contents', undefined], ['string', payload]]) {
    await runRead(vault, [[profilePath, entry(contents)]], 'vault unsupported ' + name, { error: /unreadable or too large/, code: 'LEGACY_UNREADABLE' });
    await runRead(prefs, [[settingsPath, entry(contents)]], 'preferences unsupported ' + name, { error: /unreadable or too large/ });
  }
  await runRead(vault, [[profilePath, entry(encode('not JSON'))]], 'vault invalid JSON', { error: /Invalid save JSON/, code: 'INVALID_SAVE' });
  await runRead(vault, [[profilePath, entry(encode(payload.replace('"version":13', '"version":15')))]], 'vault foreign save version', { error: /Unsupported save format/, code: 'INVALID_SAVE' });
  await runRead(vault, [], 'vault absent legacy', { accept: result => check(result === null, 'no legacy returns null') });
  await runRead(prefs, [], 'preferences absent legacy', { accept: result => check(result === null, 'no preferences returns null') });
  await runRead(vault, [[profilePath, entry(encode(payload))], ['/userfs/other/little_leaf_cafe_v13.json', entry(encode(payload))]], 'vault ambiguous legacy', { error: /Several legacy/, code: 'AMBIGUOUS_LEGACY' });
  await runRead(prefs, [[settingsPath, entry(encode(settings))], ['/userfs/other/little_leaf_settings.cfg', entry(encode(settings))]], 'preferences ambiguous legacy', { error: /Several legacy/ });
  const boundaryPayload = payload + ' '.repeat(1048576 - encode(payload).length);
  await runRead(vault, [[profilePath, entry(subview(encode(boundaryPayload), Int8Array))]], 'vault exact size boundary', { accept: result => check(result.payload === boundaryPayload, '1 MiB remains accepted') });
  const boundarySettings = settings + ' '.repeat(65536 - encode(settings).length);
  await runRead(prefs, [[settingsPath, entry(subview(encode(boundarySettings), Int8Array))]], 'preferences exact size boundary', { accept: result => check(result === boundarySettings, '64 KiB remains accepted') });
  report.passed = true; report.total_checks = report.checks.length;
  console.log(JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
