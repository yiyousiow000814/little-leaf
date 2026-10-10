'use strict';
// Hosted CI only. Actual exported Godot/Game/JavaScriptBridge/vault in disposable
// HTTPS contexts. The sole injected failure closes a captured native IDB handle.
// No client.close(), seeded save, fake callback/log entry, or simulation speedup.
//
// Inputs are the candidate ci/build_web.py export and its native test evidence.
// Preflight needs only Node (no Playwright import or browser launch):
//   node tests/connection_recovery_browser.js --check-inputs --web-build WEB \
//     --engine-report ENGINE/summary.json --layout-report ENGINE/test_save_log-result.json
// Hosted invocation, separately for RUNTIME_BROWSER=webkit and chromium:
//   RUNTIME_BROWSER=webkit PLAYWRIGHT_MODULE=/tools/node_modules/playwright \
//     xvfb-run -a node tests/connection_recovery_browser.js --run-hosted \
//     --web-build WEB --engine-report ENGINE/summary.json \
//     --layout-report ENGINE/test_save_log-result.json --output EVIDENCE/webkit
// CI=true is required to launch. Chromium defaults to installed official Chrome
// with its sandbox enabled. This script installs nothing and never publishes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {installEngineLaunchHook} = require('./engine_launch_hook');
const root = path.resolve(__dirname, '..');
const GAME = 'https://game.little-leaf-recovery.test';
const HOST = 'https://embed-host-recovery.test';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const option = (name, required = true) => {
  const at = process.argv.indexOf(name);
  if (at < 0 && !required) return null;
  assert(at >= 0 && process.argv[at + 1] && !process.argv[at + 1].startsWith('--'), name + ' is required');
  return path.resolve(process.argv[at + 1]);
};

function inputs() {
  const web = option('--web-build'), enginePath = option('--engine-report');
  const layoutPath = option('--layout-report');
  const manifestBytes = fs.readFileSync(path.join(web, 'release-manifest.json'));
  const manifest = JSON.parse(manifestBytes), engineBytes = fs.readFileSync(enginePath);
  const engine = JSON.parse(engineBytes), layoutBytes = fs.readFileSync(layoutPath);
  const layout = JSON.parse(layoutBytes);
  assert.equal(manifest.schema_version, 1);
  assert(/^[0-9a-f]{40}$/.test(manifest.source_commit));
  assert(/^[0-9a-f]{40}$/.test(manifest.source_tree));
  assert.equal(manifest.packed_smoke, 'passed');
  assert.equal(manifest.toolchain_verification, 'checksum-pinned-official-archives');
  assert.equal(sha(engineBytes), manifest.test_report_sha256, 'native report is bound to this candidate export');
  assert.equal(engine.source_commit, manifest.source_commit);
  assert.equal(engine.status, 'passed');
  assert(engine.total_checks > 0);
  const native = engine.records.filter(item => item.test === 'test_save_log');
  assert.equal(native.length, 1, 'exactly one paired native input fixture');
  assert.equal(native[0].exit_code, 0);
  assert.deepEqual(native[0].failures, []);
  assert.deepEqual(native[0].diagnostics, []);
  assert.equal(native[0].checks, layout.checks);
  assert.deepEqual(layout.failures, []);
  assert.deepEqual(layout.web_viewport, {width: 1360, height: 880});
  for (const name of ['settings', 'help', 'log', 'pause']) {
    const point = layout.web_input_points[name];
    assert(Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
    assert(point[0] >= 0 && point[0] < 1360 && point[1] >= 0 && point[1] < 880);
  }
  // The native summary predates result-file hashes. Bind the supplied points to
  // its named native log, current exact fixture source, and exported production.
  assert.equal(native[0].log, 'test_save_log.log');
  const layoutLogBytes = fs.readFileSync(path.join(path.dirname(enginePath), native[0].log));
  const nativeResults = layoutLogBytes.toString('utf8').split(/\r?\n/)
    .filter(line => line.startsWith('SAVE_LOG_RESULT ')).map(line => JSON.parse(line.slice(16)));
  assert.equal(nativeResults.length, 1);
  assert.deepEqual(nativeResults[0], layout, 'pointer coordinates match the paired native result');
  assert.equal(engine.source_sha256['tests/test_save_log.gd'], sha(fs.readFileSync(path.join(root, 'tests/test_save_log.gd'))));
  const requiredSources = ['project.godot', 'main.tscn', 'scripts/main.gd', 'scripts/cafe_web_save.gd',
    'scripts/cafe_web_lifecycle.gd', 'scripts/cafe_save_log.gd', 'scripts/cafe_save_log_panel.gd',
    'web/little_leaf_shell.html', 'web/little_leaf_vault.js', 'web/little_leaf_save_log.js',
    'web/little_leaf_inbox.js', 'web/little_leaf_preferences.js'];
  for (const name of requiredSources) assert(Object.hasOwn(manifest.production_sha256, name), 'manifest source: ' + name);
  // Dynamic candidate binding, deliberately no alpha version/tree/run constants.
  for (const [name, digest] of Object.entries(manifest.production_sha256)) {
    const source = path.resolve(root, name);
    assert(source.startsWith(root + path.sep) && !fs.lstatSync(source).isSymbolicLink());
    assert.equal(sha(fs.readFileSync(source)), digest, 'candidate/current production hash: ' + name);
    assert.equal(engine.source_sha256[name], digest, 'candidate/native source hash: ' + name);
  }
  const fileBytes = new Map();
  for (const [name, record] of Object.entries(manifest.files)) {
    assert(name && path.basename(name) === name && !name.includes('\\') && name !== 'release-manifest.json');
    assert(!fs.lstatSync(path.join(web, name)).isSymbolicLink());
    const bytes = fs.readFileSync(path.join(web, name));
    assert.equal(bytes.length, record.bytes, name + ' length');
    assert.equal(sha(bytes), record.sha256, name + ' export digest');
    fileBytes.set(name, bytes);
  }
  for (const name of ['index.html', 'index.js', 'index.wasm', 'index.pck']) assert(fileBytes.has(name));
  const html = fileBytes.get('index.html').toString('utf8');
  const version = /config\/version="([^"]+)"/.exec(fs.readFileSync(path.join(root, 'project.godot'), 'utf8'))?.[1];
  assert.equal(manifest.version, version);
  for (const name of ['web/little_leaf_vault.js', 'web/little_leaf_save_log.js',
    'web/little_leaf_inbox.js', 'web/little_leaf_preferences.js']) {
    assert(html.includes(fs.readFileSync(path.join(root, name), 'utf8').trim()), 'HTML embeds exact ' + name);
  }
  const match = /const GODOT_CONFIG\s*=\s*(\{.*?\});/.exec(html);
  assert(match, 'export contains the actual Godot configuration');
  const config = JSON.parse(match[1]);
  assert(!config.serviceWorker, 'service worker is disabled in this candidate');
  assert(html.includes('GODOT_CONFIG.persistentPaths = [];'), 'legacy IDBFS remains unmounted');
  for (const [name, bytes] of Object.entries(config.fileSizes)) assert.equal(fileBytes.get(name)?.length, bytes);
  assert.equal(fileBytes.get('index.wasm').subarray(0, 4).toString('hex'), '0061736d');
  assert.equal(fileBytes.get('index.pck').subarray(0, 4).toString('ascii'), 'GDPC');
  return {web, manifest, layout, fileBytes, binding: {
    source_commit: manifest.source_commit, source_tree: manifest.source_tree, app_version: version,
    export_manifest_sha256: sha(manifestBytes), native_report_sha256: sha(engineBytes),
    native_layout_sha256: sha(layoutBytes), native_layout_log_sha256: sha(layoutLogBytes),
    browser_harness_sha256: sha(fs.readFileSync(__filename)),
    launch_hook_sha256: sha(fs.readFileSync(path.join(__dirname, 'engine_launch_hook.js'))),
    export_files: Object.fromEntries(['index.html', 'index.js', 'index.wasm', 'index.pck'].map(name => [name, manifest.files[name]]))
  }};
}

// Installed before the real shell boots. All wrappers return the original native
// return value and rethrow the original error. Native event handlers, callback
// arguments, log records, transactions and their ordering are never replaced.
function observeNativeStorage({gameOrigin}) {
  if (location.origin !== gameOrigin) return;
  const DB = 'little-leaf.authoritative.v1';
  const nativeOpen = IDBFactory.prototype.open;
  const nativeTransaction = IDBDatabase.prototype.transaction;
  const nativePut = IDBObjectStore.prototype.put;
  const handles = [], ids = new WeakMap(), txIds = new WeakMap();
  const state = {opens: [], transactions: [], puts: [], submissions: [], arm: null};
  let serial = 0;
  const stamp = () => ({order: ++serial, logSequence: globalThis.LittleLeafSaveLog?.snapshot().at(-1)?.sequence || 0});
  IDBFactory.prototype.open = function (...args) {
    const request = Reflect.apply(nativeOpen, this, args);
    if (args[0] !== DB) return request;
    const item = {...stamp(), suppliedVersion: args.length > 1 ? args[1] : null, upgrades: 0, success: false};
    state.opens.push(item);
    request.addEventListener('upgradeneeded', () => {item.upgrades++;});
    request.addEventListener('error', () => {item.error = request.error?.name || 'unknown';});
    request.addEventListener('success', () => {
      const db = request.result;
      item.success = true; item.connection = handles.push(db); ids.set(db, item.connection);
      item.version = db.version; item.successOrder = ++serial;
    });
    return request;
  };
  IDBDatabase.prototype.transaction = function (...args) {
    const connection = ids.get(this);
    if (!connection) return Reflect.apply(nativeTransaction, this, args);
    const item = {...stamp(), connection, mode: args[1] || 'readonly',
      requestedDurability: args[2]?.durability || null, created: false, completed: false, aborted: false};
    state.transactions.push(item);
    try {
      const tx = Reflect.apply(nativeTransaction, this, args);
      item.created = true; item.effectiveDurability = tx.durability || null; txIds.set(tx, item.order);
      tx.addEventListener('complete', () => {item.completed = true; item.completeOrder = ++serial;});
      tx.addEventListener('abort', () => {item.aborted = true; item.error = tx.error?.name || 'unknown';});
      return tx;
    } catch (error) {item.error = error.name; throw error;}
  };
  IDBObjectStore.prototype.put = function (...args) {
    const connection = ids.get(this.transaction.db);
    if (connection && this.name === 'profiles' && args[1] === 'active') {
      // Only the synthetic candidate is retained inside this disposable page.
      state.puts.push({...stamp(), connection, transactionOrder: txIds.get(this.transaction),
        value: JSON.parse(JSON.stringify(args[0]))});
    }
    return Reflect.apply(nativePut, this, args);
  };
  state.readAuthority = async () => {
    // Bypass capture for the independent observer. Abort on missing database:
    // observation must never create a replacement authority or change a row.
    const db = await new Promise((resolve, reject) => {
      const request = Reflect.apply(nativeOpen, indexedDB, [DB]);
      request.onupgradeneeded = () => request.transaction.abort();
      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);
    });
    try {
      return await new Promise((resolve, reject) => {
        const tx = Reflect.apply(nativeTransaction, db, ['profiles', 'readonly']);
        const active = tx.objectStore('profiles').get('active'), identity = tx.objectStore('profiles').get('identity');
        tx.oncomplete = () => resolve({active: active.result, identity: identity.result});
        tx.onabort = () => reject(tx.error);
      });
    } finally {db.close();}
  };
  state.closeAcceptedHandle = expected => {
    const list = LittleLeafSaveLog.snapshot();
    const read = list.find(event => event.event === 'read_accepted' && event.layer === 'controller');
    const boot = JSON.parse(__littleLeafVault.bootJson);
    if (state.arm || !read || read.revision !== expected.revision || read.profile !== expected.profile ||
        !boot.ok || boot.revision !== expected.revision || handles.length !== 1 ||
        list.some(event => event.event === 'save_requested')) throw Error('Close injection requires an accepted boot before its first save');
    const client = __littleLeafVault, commit = client.commit;
    client.commit = function (...args) {
      state.submissions.push({...stamp(), payload: args[0], revision: args[1], profileId: args[2]});
      // Observe the real bridge path without touching the returned Promise or the
      // real controller callback. The unchanged original commit performs all I/O.
      return Reflect.apply(commit, this, args);
    };
    handles[0].close(); // Deliberately NOT __littleLeafVault.close(), which faults the client.
    state.arm = {...stamp(), revision: boot.revision, profileId: boot.profileId,
      priorPayload: boot.payload, connection: 1, readSequence: read.sequence};
    return {revision: boot.revision, readSequence: read.sequence, closedConnection: 1};
  };
  state.snapshot = () => ({opens: state.opens, transactions: state.transactions, puts: state.puts,
    submissions: state.submissions, arm: state.arm});
  globalThis.__connectionRecoveryProbe = state;
}

function safeEvents(list) {
  if (!list?.length) return list || [];
  const base = Date.parse(list[0].timestamp), synthetic = Date.parse('2000-01-01T00:00:00.000Z');
  return list.map(event => ({...event, timestamp: new Date(synthetic + Math.max(0, Date.parse(event.timestamp) - base)).toISOString()}));
}
function publicProbe(probe) {
  // Never serialize raw profile IDs, payloads, save timestamps or wallet values.
  const candidate = value => ({revision: value.revision, digest: value.digest,
    profile_sha256: sha(value.profileId), payload_sha256: sha(value.payload)});
  return {
    opens: probe.opens, transactions: probe.transactions,
    puts: probe.puts.map(({value, ...item}) => ({...item, candidate: candidate(value)})),
    submissions: probe.submissions.map(({payload, profileId, ...item}) => ({...item,
      profile_sha256: sha(profileId), payload_sha256: sha(payload)})),
    arm: {...probe.arm, profileId: undefined, priorPayload: undefined,
      profile_sha256: sha(probe.arm.profileId), prior_payload_sha256: probe.arm.priorPayload === null ? null : sha(probe.arm.priorPayload)}
  };
}
async function gameFrame(page, embedded) {
  if (!embedded) return page.mainFrame();
  await page.locator('#game').waitFor();
  const element = await page.locator('#game').elementHandle();
  const frame = await element.contentFrame();
  assert(frame, 'synthetic cross-site iframe exists');
  await frame.waitForURL(GAME + '/index.html');
  return frame;
}
const events = frame => frame.evaluate(() => LittleLeafSaveLog.snapshot());

async function main() {
  const input = inputs(), {layout, manifest, fileBytes} = input;
  const browserName = process.env.RUNTIME_BROWSER || 'webkit';
  assert(['webkit', 'chromium'].includes(browserName));
  if (process.argv.includes('--check-inputs')) {
    console.log(JSON.stringify({inputs_verified: true, ...input.binding}));
    return;
  }
  assert(process.argv.includes('--run-hosted') && process.env.CI === 'true', 'Browser execution requires --run-hosted in CI=true; local preflight is --check-inputs');
  const output = option('--output');
  fs.mkdirSync(output, {recursive: true});
  const report = {...input.binding, synthetic_only: true, actual_exported_game: true, engine: browserName,
    browser_sandbox: true, external_requests_allowed: false, physical_ipad_safari: false,
    actual_itch_embed: false, os_forced_termination_tested: false, browser_process_restart_tested: false,
    private_mode_detection: false, clipboard_content_verified: false, log_ui_pixels_verified: false,
    timestamps: 'Synthetic 2000-01-01 anchor; relative order and interval retained',
    scope: 'Captured native IDBDatabase.close after accepted boot, natural normal-speed save, one existing-only recovery, then real reload; repeated for fresh and saved authority in top-level and cross-site frames. Native Pause keeps the wallet stable while the normal autosave timer continues. One completed lifecycle save before reload makes the exact revision/payload comparison deterministic.',
    checks: [], scenarios: []};
  const check = (ok, label) => {assert(ok, label); report.checks.push(label);};
  const failAs = (outcome, message) => {throw Object.assign(new Error(message), {outcome});};
  async function ready(frame, record) {
    try {
      await frame.waitForFunction(() => globalThis.LittleLeafSaveLog?.snapshot().some(event => event.event === 'read_accepted' && event.layer === 'controller'), null, {timeout: 90000});
      await frame.waitForFunction(() => !document.getElementById('status'), null, {timeout: 30000});
    } catch (error) {
      const startup = await frame.evaluate(() => ({notice: document.getElementById('status-notice')?.textContent || '',
        features: typeof Engine === 'function' ? Engine.getMissingFeatures({threads: false}) : null,
        events: globalThis.LittleLeafSaveLog?.snapshot() || []})).catch(() => null);
      record.startup = startup && {...startup, events: safeEvents(startup.events)};
      const graphics = /webgl|opengl|gpu|rendering context/i.test((startup?.notice || '') + ' ' + record.browser_errors.join(' '));
      error.outcome = startup?.features?.length ? 'runtime_feature_unsupported' :
        startup?.events.some(event => event.event === 'read_failure') ? 'storage_or_validation_startup_failed' :
          graphics ? 'runtime_graphics_unsupported' : 'engine_startup_failed';
      throw error;
    }
    check(await frame.evaluate(() => __connectionRecoveryLaunch.launchCalls === 1 &&
      JSON.stringify(__connectionRecoveryLaunch.launchArgs) === '["--","--skip-intro"]'), 'actual Engine runs at normal simulation speed');
    const read = (await events(frame)).find(event => event.event === 'read_accepted' && event.layer === 'controller');
    check(read && /^[a-f0-9]{8}$/.test(read.profile), 'actual controller accepted a synthetic profile');
    return read;
  }
  async function inspectLog(page, frame, label, record) {
    const pointerInputs = [];
    const offset = frame === page.mainFrame() ? {x: 0, y: 0} : await page.locator('#game').boundingBox();
    assert(offset);
    for (const name of ['settings', 'help', 'log']) {
      const [x, y] = layout.web_input_points[name];
      await page.mouse.click(x + offset.x, y + offset.y); pointerInputs.push(name);
      await page.waitForTimeout(300);
    }
    const text = await frame.evaluate(() => LittleLeafSaveLog.text());
    check(text.startsWith('Little Leaf save log | app ' + manifest.version + '\n'), 'Log uses candidate app version');
    check(text.includes('origin=' + GAME + ' | frame=' + (frame === page.mainFrame() ? 'top-level' : 'embedded')), 'Log identifies actual synthetic frame context');
    check(text.includes('connection_reopen_requested') && text.includes('connectionGeneration=2') && text.includes('save_accepted'), 'actual Log retains the recovery and controller acceptance');
    const screenshot = label + '-synthetic-log.png';
    await page.screenshot({path: path.join(output, screenshot)});
    record.log_inspection = {native_pointer_inputs: pointerInputs, screenshot, pixel_assertion: false};
    await page.keyboard.press('Escape');
  }
  async function recoveredSave(page, frame, read, label, record) {
    // Native Pause freezes gameplay and wallet changes while the production
    // autosave timer keeps its normal 15-second cadence. No model/test API call.
    const offset = frame === page.mainFrame() ? {x: 0, y: 0} : await page.locator('#game').boundingBox();
    assert(offset);
    const [pauseX, pauseY] = layout.web_input_points.pause;
    await page.mouse.click(pauseX + offset.x, pauseY + offset.y);
    const baseline = await frame.evaluate(() => __connectionRecoveryProbe.readAuthority());
    check(baseline.active.revision === read.revision && baseline.identity.profileId === baseline.active.profileId && baseline.identity.createdAt === baseline.active.createdAt, label + ': boot agrees with independent authority and identity');
    record.close = await frame.evaluate(expected => __connectionRecoveryProbe.closeAcceptedHandle(expected), read);
    record.native_pause_pointer_activation = true;
    record.stage = 'wait_for_natural_autosave';
    await frame.waitForFunction(revision => LittleLeafSaveLog.snapshot().some(event =>
      event.layer === 'controller' && ((event.event === 'save_accepted' && event.revision === revision + 1) || event.event === 'save_failure')),
    read.revision, {timeout: 60000});
    const list = await events(frame), probe = await frame.evaluate(() => __connectionRecoveryProbe.snapshot());
    record.events = safeEvents(list); record.native_observations = publicProbe(probe);
    const failures = list.filter(event => ['save_failure', 'read_failure'].includes(event.event));
    check(failures.length === 0, label + ': real closed-handle save has no controller/vault failure');
    const next = read.revision + 1;
    const findOne = (event, layer, revision) => {
      const matches = list.filter(item => item.event === event && item.layer === layer && item.revision === revision);
      check(matches.length === 1, label + ': one ' + layer + ' ' + event + ' revision ' + revision);
      return matches[0];
    };
    const chain = [findOne('save_requested', 'controller', read.revision), findOne('save_validated', 'controller', read.revision),
      findOne('save_submitted', 'controller', read.revision), findOne('save_submitted', 'vault', next),
      findOne('save_confirmed', 'vault', next), findOne('save_accepted', 'controller', next)];
    check(chain.every((event, index) => event.profile === read.profile && (!index || chain[index - 1].sequence < event.sequence)), label + ': real request/validation/submission/IDB confirmation/controller acceptance ordered for one profile');
    const reopen = list.filter(event => event.event === 'connection_reopen_requested');
    const opened = list.filter(event => event.event === 'connection_opened');
    check(reopen.length === 1 && reopen[0].code === 'InvalidStateError' && reopen[0].stage === 'transaction_create' &&
      reopen[0].connectionGeneration === 1 && chain[2].sequence < reopen[0].sequence && reopen[0].sequence < chain[3].sequence,
    label + ': exactly one reconnect follows the real controller submission');
    check(opened.length === 2 && opened[0].stage === 'boot_open' && opened[0].connectionGeneration === 1 &&
      opened[1].stage === 'reopen_existing' && opened[1].connectionGeneration === 2 &&
      reopen[0].sequence < opened[1].sequence && opened[1].sequence < chain[3].sequence && chain[3].connectionGeneration === 2,
    label + ': retry installs and uses connectionGeneration 2');
    check(probe.opens.length === 2 && probe.opens.every(item => item.success && !item.error) &&
      probe.opens[0].suppliedVersion === 1 && probe.opens[1].suppliedVersion === null && probe.opens[1].upgrades === 0,
    label + ': captured native open proves one existing-only reopen without schema upgrade');
    const writes = probe.transactions.filter(item => item.mode === 'readwrite');
    if (writes.some(item => item.error === 'TypeError' || (item.created && item.effectiveDurability !== 'strict'))) {
      failAs('storage_durability_unsupported', 'Browser did not expose a successful strict durability transaction; no strict-durability pass claimed');
    }
    check(writes.length === 2 && writes.every(item => item.requestedDurability === 'strict'), label + ': both native write attempts request strict durability');
    check(writes[0].connection === 1 && !writes[0].created && writes[0].error === 'InvalidStateError' &&
      writes[1].connection === 2 && writes[1].created && writes[1].completed && !writes[1].aborted &&
      writes[1].effectiveDurability === 'strict', label + ': closed-handle transaction never begins and the one retried strict transaction completes');
    check(probe.transactions.some(item => item.mode === 'readonly' && item.connection === 2 && item.completed && item.order < writes[1].order), label + ': reopened authority is read before the retry write');
    check(probe.submissions.length === 1 && probe.puts.length === 1, label + ': actual controller submits once and native authority put occurs once');
    const submission = probe.submissions[0], put = probe.puts[0];
    check(submission.order > probe.arm.order && submission.revision === read.revision && submission.profileId === baseline.active.profileId &&
      put.value.profileId === submission.profileId && put.value.revision === next && put.value.payload === submission.payload &&
      put.transactionOrder === writes[1].order && put.order < writes[1].completeOrder,
    label + ': retry preserves actual pending controller payload, expected revision and identity');
    const stored = await frame.evaluate(() => __connectionRecoveryProbe.readAuthority());
    check(stored.active.profileId === baseline.active.profileId && stored.active.revision === next &&
      stored.active.payload === submission.payload && stored.active.digest === put.value.digest &&
      JSON.stringify(stored.identity) === JSON.stringify(baseline.identity), label + ': independent native read matches the accepted exact payload and permanent identity');
    const stablePayload = JSON.parse(stored.active.payload);
    check(stablePayload.wall_format === 2 && stablePayload.runtime?.service?.version === 5,
      label + ': recovered actual controller save retains current wall format 2 and service version 5');
    if (read.revision > 0) check(stored.active.previous?.digest === baseline.active.digest &&
      stored.active.previous?.payload === baseline.active.payload, label + ': saved-authority retry retains the previous committed snapshot');
    record.accepted = {revision: next, profile: read.profile, digest: stored.active.digest, payload_sha256: sha(stored.active.payload)};
    record.stage = 'inspect_recovery_log'; await inspectLog(page, frame, label, record);
    return stored;
  }
  async function scenario(browser, embedded) {
    const record = {name: embedded ? 'cross-site' : 'top-level', frame: embedded ? 'cross-site' : 'top-level',
      stage: 'create_context', browser_errors: [], external_origins: [], rounds: []};
    report.scenarios.push(record);
    const context = await browser.newContext({viewport: layout.web_viewport, serviceWorkers: 'block'});
    let page, frame;
    try {
      await context.route('**/*', route => {
        const url = new URL(route.request().url());
        if (![GAME, HOST].includes(url.origin)) {record.external_origins.push(url.origin); return route.abort();}
        if (url.origin === HOST) return route.fulfill({contentType: 'text/html', headers: {'Cache-Control': 'no-store'},
          body: '<!doctype html><title>Synthetic cross-site recovery host</title><style>html,body{margin:0;width:100%;height:100%}iframe{display:block;border:0;width:100%;height:100%}</style><iframe id="game" src="' + GAME + '/index.html"></iframe>'});
        const name = decodeURIComponent(url.pathname).slice(1);
        if (!fileBytes.has(name)) return route.fulfill({status: 404, body: ''});
        return route.fulfill({body: fileBytes.get(name), headers: {'Cache-Control': 'no-store'}, contentType:
          ({'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png'})[path.extname(name)] || 'application/octet-stream'});
      });
      await context.addInitScript(installEngineLaunchHook, {args: ['--', '--skip-intro'], reportKey: '__connectionRecoveryLaunch'});
      await context.addInitScript(observeNativeStorage, {gameOrigin: GAME});
      page = await context.newPage();
      page.on('pageerror', error => record.browser_errors.push(String(error)));
      page.on('console', message => {if (message.text().includes('SCRIPT ERROR')) record.browser_errors.push(message.text());});
      record.stage = 'actual_game_startup';
      await page.goto(embedded ? HOST + '/' : GAME + '/index.html');
      frame = await gameFrame(page, embedded);
      let read = await ready(frame, record);
      const originalProfile = read.profile;
      check(read.source === 'fresh' && read.revision === 0, record.name + ': actual fresh controller boot, with no seeded save');
      for (const roundName of ['fresh-first-save', 'saved-authority-save']) {
        const round = {name: roundName, boot_read: safeEvents([read])[0]}; record.rounds.push(round);
        record.stage = roundName;
        const recovered = await recoveredSave(page, frame, read, record.name + '-' + roundName, round);
        // Complete the actual lifecycle handler once before navigation. Its
        // savedForHide guard then prevents an unobserved additional unload save.
        // The closed-handle recovery above was driven solely by normal autosave.
        await frame.evaluate(() => window.dispatchEvent(new Event('pagehide')));
        await frame.waitForFunction(revision => LittleLeafSaveLog.snapshot().some(event => event.event === 'save_accepted' && event.layer === 'controller' && event.revision === revision), recovered.active.revision + 1, {timeout: 30000});
        const stored = await frame.evaluate(() => __connectionRecoveryProbe.readAuthority());
        check(stored.active.revision === recovered.active.revision + 1 && stored.active.profileId === recovered.active.profileId && JSON.parse(stored.active.payload).coins === JSON.parse(recovered.active.payload).coins, record.name + ': completed real lifecycle save preserves recovered identity and wallet');
        round.reload_baseline = {revision: stored.active.revision, digest: stored.active.digest, payload_sha256: sha(stored.active.payload)};
        record.stage = 'actual_parent_reload_after_' + roundName;
        await page.reload(); frame = await gameFrame(page, embedded); read = await ready(frame, record);
        round.reload_read = safeEvents([read])[0];
        const restored = await frame.evaluate(async () => ({stored: await __connectionRecoveryProbe.readAuthority(), boot: JSON.parse(__littleLeafVault.bootJson)}));
        check(read.source === 'authority' && read.profile === originalProfile && read.revision === stored.active.revision &&
          restored.boot.profileId === stored.active.profileId && restored.stored.active.profileId === stored.active.profileId &&
          restored.stored.active.revision === read.revision && restored.boot.revision === read.revision &&
          restored.boot.payload === stored.active.payload && restored.stored.active.payload === stored.active.payload &&
          restored.stored.active.digest === stored.active.digest &&
          JSON.parse(restored.boot.payload).coins === JSON.parse(stored.active.payload).coins &&
          JSON.stringify(restored.stored.identity) === JSON.stringify(stored.identity),
        record.name + ' ' + roundName + ': real reload validates the exact durable identity, revision, wallet and payload');
        const restoredPayload = JSON.parse(restored.boot.payload);
        check(restoredPayload.wall_format === 2 && restoredPayload.runtime?.service?.version === 5,
          record.name + ' ' + roundName + ': real reload accepts current wall format 2 and service version 5');
        check(!(await events(frame)).some(event => ['read_failure', 'save_failure'].includes(event.event)), record.name + ': reload has no storage or validation failure');
      }
      check(record.external_origins.length === 0, record.name + ': no external network requests');
      check(record.browser_errors.length === 0, record.name + ': no JavaScript or Godot script exceptions');
      record.outcome = 'passed'; record.stage = 'complete';
    } catch (error) {
      record.outcome = error.outcome || (/startup/.test(record.stage) ? 'engine_startup_failed' : 'storage_recovery_failed');
      record.error = String(error.stack || error);
      record.failure_events = frame ? safeEvents(await events(frame).catch(() => null)) : null;
      if (frame) {
        const probe = await frame.evaluate(() => globalThis.__connectionRecoveryProbe?.snapshot()).catch(() => null);
        if (probe?.arm) record.failure_native_observations = publicProbe(probe);
      }
      if (page) await page.screenshot({path: path.join(output, record.name + '-synthetic-failure.png')}).catch(() => {});
    } finally {await context.close();}
  }
  let browser;
  try {
    const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
    browser = await playwright[browserName].launch(browserName === 'chromium' ?
      {headless: false, chromiumSandbox: true, channel: process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || 'chrome'} : {headless: false});
    report.browser_version = browser.version();
    await scenario(browser, false); await scenario(browser, true);
    report.passed = report.scenarios.length === 2 && report.scenarios.every(item => item.outcome === 'passed');
  } catch (error) {
    report.passed = false; report.outcome = 'browser_launch_or_runner_failed'; report.error = String(error.stack || error);
  } finally {
    if (browser) await browser.close();
    fs.writeFileSync(path.join(output, 'connection-recovery-browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({passed: report.passed, engine: browserName, browser_version: report.browser_version,
      checks: report.checks.length, outcomes: report.scenarios.map(({name, outcome, stage}) => ({name, outcome, stage}))}));
    if (!report.passed) process.exitCode = 1;
  }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
