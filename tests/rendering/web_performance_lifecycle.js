'use strict';
// Exact embedded production DOM code, with event targets only. No browser/thermal claim.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../../game/scripts/platform/cafe_web_lifecycle.gd'), 'utf8').split('const DOM_SOURCE = """')[1].split('"""')[0];
class Target {
  constructor() { this.handlers = {}; }
  addEventListener(type, handler) { (this.handlers[type] ??= new Set()).add(handler); }
  removeEventListener(type, handler) { this.handlers[type]?.delete(handler); }
  fire(type) { for (const handler of this.handlers[type] || []) handler({ target: this }); }
  count() { return Object.values(this.handlers).reduce((sum, handlers) => sum + handlers.size, 0); }
}
const window = new Target(), document = new Target();
const canvas = { tagName: 'CANVAS' };
document.getElementById = () => canvas;
document.visibilityState = 'visible';
vm.runInNewContext(source, { window, document, Set, Array, JSON });
const events = [];
let registration;
for (let n = 0; n < 100; n++) registration = window.__littleLeafLifecycleV1.install((reason, save) => events.push([reason, save]));
assert.equal(window.count() + document.count(), 7);
document.visibilityState = 'hidden'; document.fire('visibilitychange'); window.fire('pagehide');
document.visibilityState = 'visible'; document.fire('visibilitychange'); window.fire('pageshow');
assert.deepEqual(events, [['hidden', true], ['pagehide', false], ['visible', false], ['visible', false]]);
registration.dispose();
assert.equal(window.count() + document.count(), 0);
document.visibilityState = 'hidden';
window.__littleLeafLifecycleV1.install((reason, save) => events.push([reason, save]));
assert.deepEqual(events.at(-1), ['hidden', true]);
console.log(JSON.stringify({ checks: 4, failures: [], scope: 'mock DOM lifecycle; repeated install/dispose and initial hidden tab' }));
// The hosted Log fixture saves through pagehide, then returns before GUI input.
// A hidden page must not receive a premature resume or another hide-save.
document.visibilityState = 'visible';
const returnEvents = [];
window.__littleLeafLifecycleV1.install((reason, save) => returnEvents.push([reason, save]));
window.fire('pagehide');
assert.deepEqual(returnEvents, [['pagehide', true]], 'pagehide alone must not emit a resume');
window.fire('pagehide');
assert.deepEqual(returnEvents.at(-1), ['pagehide', false], 'repeated hide must not request another save');
document.visibilityState = 'hidden';
window.fire('pageshow');
assert.equal(returnEvents.length, 2, 'pageshow while still hidden must not resume GUI processing');
document.visibilityState = 'visible';
window.fire('pageshow');
assert.deepEqual(returnEvents.at(-1), ['visible', false], 'foreground return resumes without an extra save');
window.__littleLeafLifecycleV1.current.dispose();
console.log(JSON.stringify({ checks: 4, failures: [], scope: 'pagehide/foreground-return order and negative hidden resume' }));
(async () => {
  const preferences = fs.readFileSync(path.join(__dirname, '../../platform/web/little_leaf_preferences.js'), 'utf8');
  const oldText = '[audio]\nbgm_enabled=false\nbgm_volume=37\n[play]\nspeed=2\n';
  const saved = new Map([['little-leaf.preferences.v1', JSON.stringify({ format: 1, text: oldText })]]);
  const storage = { getItem: key => saved.get(key) ?? null, setItem: (key, value) => saved.set(key, value) };
  const context = { TextEncoder, TextDecoder, setTimeout, clearTimeout };
  vm.runInNewContext(preferences, context);
  const client = context.LittleLeafPreferences.createClient({ localStorage: storage, indexedDB: {} });
  assert.equal((await client.boot()).text, oldText);
  const nextText = oldText + '[display]\nframe_rate=120\n';
  assert.equal(client.writeText(nextText), true);
  const reloaded = context.LittleLeafPreferences.createClient({ localStorage: storage, indexedDB: {} });
  assert.equal((await reloaded.boot()).text, nextText);
  assert.equal(JSON.parse(saved.get('little-leaf.preferences.v1')).format, 1);
  console.log(JSON.stringify({ checks: 4, failures: [], scope: 'exact preference adapter mock-storage round-trip; old CFG and new display key retained' }));
})().catch(error => { console.error(error); process.exitCode = 1; });

// Exact opt-in Main bridge source. It has no storage/network/DOM dependency.
// The actual Godot callback/WebGL runtime still requires browser qualification.
{
  const main = fs.readFileSync(path.join(__dirname, '../../game/scripts/main.gd'), 'utf8');
  const bridge = main.split('const FLOOR_DIAGNOSTIC_WEB_SOURCE = """')[1].split('"""')[0];
  const scopedWindow = {};
  const context = {window: scopedWindow};
  let calls = 0;
  let previous;
  for (let n = 0; n < 100; n++) {
    vm.runInNewContext(bridge, context);
    const current = scopedWindow.LittleLeafFloorDiagnostics;
    current.callback = () => calls++;
    current.latest_json = '{"floor":{"current":{},"previous":{}}}';
    if (previous) {
      assert.equal(previous.callback, null, 'old callback detached');
      assert.equal(previous.latest_json, '', 'old packet released');
      previous.capture();
      previous.dispose();
      assert.equal(scopedWindow.LittleLeafFloorDiagnostics, current, 'old owner cannot remove successor');
    }
    current.capture();
    previous = current;
  }
  assert.equal(calls, 100, 'one current callback per explicit request');
  assert.deepEqual(Object.keys(scopedWindow), ['LittleLeafFloorDiagnostics'], 'single bounded opt-in global');
  previous.dispose();
  previous.capture();
  assert.equal(calls, 100, 'detached callback cannot fire');
  assert.deepEqual(Object.keys(scopedWindow), [], 'shutdown removes exact registration');
  console.log(JSON.stringify({checks: 4 + 99 * 3, failures: [], scope: 'exact developer floor bridge source;100 install/dispose cycles, no browser/Godot/storage execution'}));
}
