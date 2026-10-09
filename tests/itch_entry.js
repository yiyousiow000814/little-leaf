'use strict';
// Exact shell entry/startup scripts in a disposable DOM; no service or player data.
const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm');
const html = fs.readFileSync('web/little_leaf_shell.html', 'utf8');
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x => x[1]);
const entry = scripts.find(x => x.includes('/* Little Leaf itch entry only.'));
const startup = scripts.find(x => x.includes('const GODOT_CONFIG = $GODOT_CONFIG;'))
  .replace('$GODOT_CONFIG', '{}').replace('$GODOT_THREADS_ENABLED', 'false');
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
function fixture(hostname) {
  const nodes = Object.fromEntries(['itch-entry','itch-local','canvas','status'].map(id => [id, {
    hidden: true, listeners: {}, addEventListener(type, fn) { this.listeners[type] = fn; }, focus() { this.focused = true; }
  }]));
  const calls = [];
  const context = {Promise, console, location: {hostname}, document: {getElementById: id => nodes[id]},
    __littleLeafVault: {boot() { calls.push('vault'); return Promise.resolve(); }},
    __littleLeafPreferences: {boot() { calls.push('preferences'); return Promise.resolve(); }},
    LittleLeafBoot: {engineReady() {calls.push('ready');}, fail(error) {throw error;}}};
  context.Engine = function () { return {startGame() {calls.push('engine'); return Promise.resolve();}}; };
  context.Engine.getMissingFeatures = () => [];
  context.window = context;
  for (const key of ['indexedDB','localStorage','sessionStorage','fetch','open']) {
    Object.defineProperty(context, key, {get() {throw Error('Entry touched forbidden boundary: ' + key);}});
  }
  vm.createContext(context);
  vm.runInContext(entry, context);
  vm.runInContext(startup, context);
  return {nodes, calls, context};
}
(async () => {
  assert(entry && startup);
  assert.match(html, /id="itch-account" href="https:\/\/little-leaf-41e5d\.firebaseapp\.com\/" target="_blank" rel="noopener noreferrer"/);
  assert.match(html, /Play with Google &mdash; opens a new tab/);
  assert.match(html, /Account progress is separate: your existing itch progress does not transfer automatically/);
  assert.match(html, /Continue local play on itch/);
  assert(!html.includes('little_leaf_firebase_boot.mjs'), 'ordinary shell must not initialize Firebase');
  assert(!entry.includes('itch-account'), 'account link uses native user navigation without a script handler');
  assert.equal((html.match(/window\.__littleLeafVault\.boot\(\)/g) || []).length, 1, 'Firebase staging marker retained');
  for (const host of ['html-classic.itch.zone', 'itch.io', 'little-leaf.itch.io', 'itch.zone']) {
    const f = fixture(host); await flush();
    assert.equal(f.nodes['itch-entry'].hidden, false);
    assert.equal(f.nodes.canvas.hidden, true);
    assert.deepEqual(f.calls, [], 'no local-save boot before explicit local choice');
    // Account navigation has no handler: it cannot resolve local boot or change this page.
    f.nodes['itch-local'].listeners.click(); await flush();
    assert.equal(f.nodes['itch-entry'].hidden, true);
    assert.equal(f.nodes.canvas.hidden, false);
    assert.equal(f.nodes.status.hidden, false);
    assert(f.nodes.canvas.focused);
    assert.deepEqual(f.calls, ['vault','preferences','engine','ready']);
  }
  for (const host of ['localhost','little-leaf-41e5d.firebaseapp.com','evilitch.zone','itch.zone.evil.test','']) {
    const f = fixture(host); await flush();
    assert.equal(f.nodes['itch-entry'].hidden, true);
    assert.deepEqual(f.calls, ['vault','preferences','engine','ready'], 'non-itch launch remains automatic');
  }
  console.log('itch entry: exact shell isolation, hostname boundaries, explicit local boot and new-tab contract passed');
})().catch(error => {console.error(error); process.exitCode = 1;});
