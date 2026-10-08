'use strict';
// Exact shell presentation and startup JS in a synthetic DOM. No player profile,
// actual network, engine, SDK or storage is opened by these contract checks.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const root = path.resolve(__dirname, '..');
let checks = 0;
function check(condition, message) { assert(condition, message); checks++; }
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return {promise, resolve, reject}; }
const flush = async () => { for (let n = 0; n < 10; n++) await Promise.resolve(); };
function element(id) {
  return {id, dataset: {}, attrs: {}, listeners: {}, hidden: false, complete: false, naturalWidth: 783,
    setAttribute(k, v) { this.attrs[k] = v; },
    removeAttribute(k) { delete this[k]; delete this.attrs[k]; },
    addEventListener(k, fn) { this.listeners[k] = fn; },
    remove() { this.removals = (this.removals || 0) + 1; },
    focus() { this.focused = true; }};
}
function harness(html, options = {}) {
  const scripts = Array.from(html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g), m => m[1]);
  const presentation = scripts.find(s => s.includes('/* Little Leaf boot presentation only.'));
  const startup = scripts.find(s => s.includes('const GODOT_CONFIG = $GODOT_CONFIG;'));
  const ids = ['status', 'status-label', 'status-progress', 'status-splash', 'status-brand-fallback', 'canvas', 'status-error', 'status-retry'];
  const dom = Object.fromEntries(ids.map(id => [id, element(id)]));
  const events = [], timers = new Map(), game = deferred(); let nextTimer = 0;
  const document = {visibilityState: 'visible', listeners: {}, getElementById: id => dom[id],
    addEventListener(k, f) { this.listeners[k] = f; }, removeEventListener(k) { delete this.listeners[k]; }};
  const engine = {startGame(config) { events.push('engine'); engine.options = config; if (options.throwStart) throw Error('Engine failure'); return game.promise; },
    installServiceWorker: () => Promise.reject(Error('Service worker failed'))};
  function Engine(config) { if (options.throwConstructor) throw Error('Constructor failure'); events.push('construct'); check(config.persistentPaths.length === 0, 'IDBFS remains disabled'); return engine; }
  Engine.getMissingFeatures = () => { if (options.throwFeatures) throw Error('Feature detection failure'); return options.missing || []; };
  const context = {document, console: {error() {}}, Error, Number, Promise, navigator: {},
    location: {reload() { events.push('reload'); }},
    setTimeout(f, ms) { const id = ++nextTimer; timers.set(id, {f, ms}); return id; }, clearTimeout(id) {timers.delete(id);},
    __littleLeafVault: {boot() { events.push('vault'); return Promise.resolve(options.vault || {ok: true}); }},
    __littleLeafPreferences: {boot() { events.push('preferences'); return Promise.resolve(options.preferences || {ok: true}); }}};
  if (!options.noEngine) context.Engine = Engine;
  context.window = context;
  vm.createContext(context); vm.runInContext(presentation, context);
  return {context, dom, document, events, timers, engine, game, boot: context.LittleLeafBoot,
    start() {vm.runInContext(startup.replace('$GODOT_CONFIG', '{}').replace('$GODOT_THREADS_ENABLED', 'false'), context);}};
}
(async () => {
  for (const file of ['little_leaf_shell.html', 'little_leaf_crazygames_shell.html']) {
    const html = fs.readFileSync(path.join(root, 'web', file), 'utf8');
    check(html.includes('background: #cce3e8;') && !html.includes('background-color: black'), file + ': branded initial background');
    check(!/#status\s*\{[^}]*visibility:\s*hidden/.test(html) && html.includes('alt="Little Leaf"'), file + ': branded loader visible before scripts');
    check(html.includes('src="$GODOT_SPLASH"') && html.includes('role="alert"') && html.includes('<noscript>'), file + ': exported art, error and no-JS fallback');
    check(!html.includes('animation:') && !html.includes('transition:') && html.includes('(prefers-reduced-motion: reduce)'), file + ': no decorative motion, reduced-motion fallback');
    if (file.includes('crazygames')) check(html.indexOf('id="status"') < html.indexOf('sdk.crazygames.com'), 'CrazyGames SDK does not block branded markup');
    for (const frameFirst of [true, false]) {
      const h = harness(html); h.start(); await flush();
      check(h.events.join(',') === 'construct,vault,preferences,engine', file + ': unchanged vault/preference/engine order');
      check(!h.dom.status.removals, 'startup begins covered');
      if (frameFirst) h.boot.firstFrameReady(); else {h.game.resolve(); await flush();}
      check(!h.dom.status.removals, 'one readiness event cannot uncover engine splash');
      if (frameFirst) {h.game.resolve(); await flush();} else h.boot.firstFrameReady();
      check(h.dom.status.removals === 1 && h.dom.canvas.attrs['aria-busy'] === 'false', 'both readiness orders reveal first rendered game');
      h.boot.firstFrameReady(); h.boot.engineReady(); h.boot.fail('late');
      check(h.dom.status.removals === 1 && !h.dom['status-error'].textContent && !h.timers.size, 'duplicate/late events harmless; no pending loader timer');
    }
    {
      const h = harness(html);
      h.boot.onProgress(0, 200); check(h.dom['status-progress'].value === 0 && h.dom['status-progress'].max === 200, 'zero-byte known total honest');
      h.boot.onProgress(50, 200); check(h.dom['status-progress'].value === 50, 'engine byte progress passed through');
      h.boot.onProgress(200, 200); check(h.dom['status-label'].textContent === 'Opening your café…' && !h.dom.status.removals, '100% download still waits for scene');
      for (const [a, b] of [[0, 0], [NaN, 2], [-1, 3], [4, 3], [1, Infinity]]) {
        h.boot.onProgress(a, b); check(!Object.hasOwn(h.dom['status-progress'], 'value'), 'invalid/unknown total stays indeterminate');
      }
      h.dom['status-splash'].listeners.error(); check(h.dom['status-splash'].hidden && !h.dom['status-brand-fallback'].hidden, 'failed logo retains Little Leaf text');
      h.boot.fail('<b>literal error</b>'); h.boot.engineReady(); h.boot.firstFrameReady();
      check(!h.dom.status.removals && h.dom.status.dataset.mode === 'notice', 'error cannot be hidden by late readiness');
      check(h.dom['status-error'].textContent === '<b>literal error</b>' && h.dom['status-retry'].focused, 'errors are safe text and keyboard reachable');
      h.dom['status-retry'].listeners.click(); check(h.events.join(',') === 'reload', 'retry only reloads');
    }
    {
      const h = harness(html); h.boot.engineReady();
      check(h.timers.size === 1 && [...h.timers.values()][0].ms === 45000, 'stalled first frame has diagnostic, not a timed reveal');
      h.document.visibilityState = 'hidden'; h.document.listeners.visibilitychange(); check(h.timers.size === 0, 'hidden tab does not time out');
      h.document.visibilityState = 'visible'; h.document.listeners.visibilitychange(); check(h.timers.size === 1, 'visible tab gets fresh first-frame window');
      [...h.timers.values()][0].f(); check(h.dom.status.dataset.mode === 'notice' && !h.dom.status.removals, 'stalled render shows actionable error instead of blank canvas');
    }
    for (const options of [{noEngine: true}, {missing: ['WebGL2']}, {throwConstructor: true}, {throwFeatures: true}, {throwStart: true}]) {
      const h = harness(html, options); h.start(); await flush();
      check(h.dom.status.dataset.mode === 'notice' && !h.dom.status.removals, 'engine/feature/startup failure retains branded error');
    }
    for (const which of ['vault', 'preferences']) {
      const h = harness(html, {[which]: {ok: false, error: 'Synthetic storage failure'}}); h.start(); await flush();
      if (file.includes('crazygames')) check(!h.events.includes('engine') && h.dom.status.dataset.mode === 'notice', 'CrazyGames bad ' + which + ' still blocks engine without fallback');
      else check(h.events.includes('engine'), 'ordinary Web retains in-game recovery for bad ' + which);
    }
  }
  const project = fs.readFileSync(path.join(root, 'project.godot'), 'utf8');
  check(project.includes('boot_splash/image="res://assets/branding/little_leaf_approved_v3.png"'), 'native/export use approved source PNG');
  check(project.includes('boot_splash/minimum_display_time=0') && project.includes('boot_splash/bg_color=Color(0.8, 0.89, 0.91, 1)'), 'native splash is sky colored with no minimum delay');
  console.log(JSON.stringify({passed: true, checks, scope: 'Exact shell startup/presentation code in synthetic DOM; no real browser, native render or player storage claim.'}, null, 2));
})().catch(error => {console.error(error); process.exitCode = 1;});
