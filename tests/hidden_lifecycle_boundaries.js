'use strict';
// Deterministic permutations of actual embedded DOM code; no browser/FPS claim.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../scripts/cafe_web_lifecycle.gd'), 'utf8').split('const DOM_SOURCE = """')[1].split('"""')[0];
let checks = 0;
function equal(actual, expected, label) { assert.deepEqual(actual, expected, label); checks++; }
class Target {
  constructor() { this.handlers = {}; }
  addEventListener(type, fn) { (this.handlers[type] ??= new Set()).add(fn); }
  removeEventListener(type, fn) { this.handlers[type]?.delete(fn); }
  fire(type, persisted = false) { for (const fn of this.handlers[type] || []) fn({ target: this, persisted }); }
}
function fixture(initial = 'visible') {
  const window = new Target(), document = new Target(), events = [];
  document.visibilityState = initial;
  document.getElementById = () => ({ tagName: 'CANVAS' });
  vm.runInNewContext(source, { window, document, Set, Array, JSON });
  const registration = window.__littleLeafLifecycleV1.install((reason, save) => events.push([reason, save]));
  return { window, document, events, registration,
    visibility(state) { document.visibilityState = state; document.fire('visibilitychange'); },
    saves() { return events.filter(e => e[1]).length; },
    returns() { return events.filter(e => e[0] === 'visible').length; }
  };
}
for (const persisted of [false, true]) {
  const f = fixture();
  f.visibility('hidden'); f.visibility('hidden');
  f.window.fire('pagehide', persisted); f.window.fire('pagehide', persisted);
  f.window.fire('pageshow', persisted); f.window.fire('pageshow', persisted);
  f.visibility('hidden');
  equal(f.saves(), 1, 'hidden pageshow keeps the single-save latch');
  equal(f.returns(), 0, 'hidden restoration never resumes');
  f.visibility('visible');
  equal(f.returns(), 1, 'visibility after background restoration resumes');
  f.visibility('hidden');
  equal(f.saves(), 2, 'a new visible-to-hidden episode saves once');
}
for (const returnOrder of ['visible-first', 'pageshow-first']) {
  const f = fixture();
  f.visibility('hidden'); f.window.fire('pagehide', true);
  if (returnOrder === 'visible-first') {
    f.visibility('visible');
    equal(f.returns(), 0, 'pagehide fence survives an early visibility event');
    f.window.fire('pageshow', true);
  } else {
    f.window.fire('pageshow', true);
    equal(f.returns(), 0, 'pageshow in the background keeps suspension');
    f.visibility('visible');
  }
  equal(f.returns(), 1, returnOrder + ' produces a visible return');
  equal(f.saves(), 1, returnOrder + ' does not request another save');
}
const initial = fixture('hidden');
initial.window.fire('pageshow', true); initial.visibility('hidden');
equal(initial.events, [['hidden', true], ['hidden', false]], 'initial hidden and pageshow are one save episode');
initial.registration.dispose(); initial.visibility('visible'); initial.window.fire('pageshow', true);
equal(initial.returns(), 0, 'disposed listener cannot resume an old runtime');
const blurred = fixture();
blurred.window.fire('blur');
equal(blurred.events, [['blur', false]], 'blur cancels input without hiding, saving or pausing');
const pagehideOnly = fixture();
pagehideOnly.window.fire('pagehide', true); pagehideOnly.visibility('visible');
equal(pagehideOnly.events, [['pagehide', true]], 'pagehide-only episode requires restoration before return');
pagehideOnly.window.fire('pageshow', true);
equal(pagehideOnly.returns(), 1, 'pagehide-only restoration returns once');
console.log(JSON.stringify({ checks, failures: [], scope: 'actual embedded lifecycle event-order permutations; synthetic DOM only' }));
