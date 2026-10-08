'use strict';
// Fast, browser-free contract checks. Actual rendered gameplay is a separate CI gate.
const assert = require('node:assert/strict');
const {validateLayout, validateBinding, summarize, validateProgress} = require('./fresh_tutorial_browser');
const {hash, canonical} = require('./wall_compatibility_helpers');
const stages = Object.fromEntries(Object.entries({open: 0, staff: 1, staff_done: 2, decorate: 3, return: 4, order: 5, complete: 7})
  .map(([name, step]) => [name, {step, text: name, point: [100, 150], guide: [50, 100, 200, 64]}]));
const receipt = {checks: 10, failures: [], player_save_used: false,
  web_layout: {viewport: [1360, 880], initial_coins: 1200, meal_payment: 200, stages}};
const layout = validateLayout(receipt);
for (const mutate of [
  r => r.failures.push('failed engine test'),
  r => r.player_save_used = true,
  r => r.web_layout.viewport[0] = 390,
  r => r.web_layout.stages.open.point[0] = -1,
  r => r.web_layout.stages.staff.guide[2] = 1400,
  r => r.web_layout.stages.complete.step = 6,
  r => delete r.web_layout.stages.return,
]) {
  const bad = structuredClone(receipt); mutate(bad);
  assert.throws(() => validateLayout(bad));
}
const payload = {coins: 1200, served: 0, total_earned: 0, total_wages_paid: 0, operating_open: false,
  tutorial: {format: 1, status: 'active', step: 0, baseline_served: 0}, first_guest_pending: true,
  items: [{id: 1, kind: 'table'}], runtime: {customers: [], service: {records: []}}};
const ack = {ok: true, revision: 1, payload: JSON.stringify(payload), inbox: {paid: []}};
const initial = summarize(ack);
assert.equal(initial.items_sha256, hash(canonical(payload.items)));
assert.equal(summarize({ok: true, payload: null}), null);
assert.equal(summarize({ok: false}), null);
validateProgress(initial, layout);
const ordered = {...initial, open: true, tutorial: {...initial.tutorial, step: 6},
  guests: [{id: 1, seated: true, phase: 'cooking'}], orders: [1]};
validateProgress(ordered, layout, initial);
const paid = {...ordered, served: 1, earned: 200, coins: 1350, wages: 50, tutorial: {...ordered.tutorial, step: 7}};
validateProgress(paid, layout, initial);
validateProgress({...paid, tutorial: {...paid.tutorial, status: 'completed'}}, layout, initial);
for (const mutate of [
  s => s.coins += 1000,
  s => s.earned += 200,
  s => s.served = 0,
  s => s.tutorial.baseline_served = 1,
  s => s.tutorial.status = 'skipped',
  s => s.items_sha256 = 'changed layout',
  s => s.paid_campaigns.push({coins: 1000}),
]) {
  const bad = structuredClone(paid); mutate(bad);
  assert.throws(() => validateProgress(bad, layout, initial));
}
assert.throws(() => validateProgress({...initial, tutorial: {...initial.tutorial, step: 7}}, layout, initial));
assert.throws(() => validateProgress({...initial, tutorial: {...initial.tutorial, status: 'completed'}}, layout, initial));
const orderAck = structuredClone(ack), orderPayload = structuredClone(payload);
orderPayload.runtime.customers = [{id: 1, phase: 'cooking', seated: true}];
orderPayload.runtime.service.records = [{guest_id: 1, order_done: true}, {guest_id: 2, order_done: false}];
orderAck.payload = JSON.stringify(orderPayload);
assert.deepEqual(summarize(orderAck).orders, [1]);
assert.deepEqual(summarize(orderAck).guests, [{id: 1, phase: 'cooking', seated: true}]);
// Exercise the exact production binding function against disposable fake
// export/report receipts. Only git's readonly answers are stubbed; source files
// are genuinely hashed and are never changed by this test.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '..'), temp = fs.mkdtempSync(path.join(os.tmpdir(), 'fresh-tutorial-binding-'));
const exec = cp.execFileSync;
let dirty = false;
try {
  const commit = 'a'.repeat(40);
  cp.execFileSync = (command, args) => {
    assert.equal(command, 'git');
    return args[0] === 'rev-parse' ? commit : dirty ? ' M tests/fresh_tutorial_browser.js' : '';
  };
  const sourceNames = ['tests/test_interactive_tutorial.gd', 'tests/run_integration_candidate.py', 'tests/fresh_tutorial_browser.js', 'tests/wall_compatibility_helpers.js', 'project.godot'];
  const engine = {source_commit: commit, status: 'passed', source_sha256: Object.fromEntries(sourceNames.map(name => [name, hash(fs.readFileSync(path.join(root, name)))])),
    records: [{test: 'test_interactive_tutorial', exit_code: 0, failures: [], result_sha256: hash(JSON.stringify(receipt))}]};
  const production = {'project.godot': engine.source_sha256['project.godot']};
  const manifest = {source_commit: commit, toolchain_verification: 'checksum-pinned-official-archives', packed_smoke: 'passed', production_sha256: production};
  const layoutFile = path.join(temp, 'layout.json'), engineFile = path.join(temp, 'engine.json');
  const write = (mutateEngine = () => {}, html = '<title>Ordinary Web</title>') => {
    fs.writeFileSync(layoutFile, JSON.stringify(receipt));
    const current = structuredClone(engine); mutateEngine(current);
    fs.writeFileSync(engineFile, JSON.stringify(current));
    fs.writeFileSync(path.join(temp, 'index.html'), html);
    fs.writeFileSync(path.join(temp, 'release-manifest.json'), JSON.stringify({...manifest,
      test_report_sha256: hash(fs.readFileSync(engineFile)), files: {'index.html': {bytes: Buffer.byteLength(html), sha256: hash(html)}}}));
  };
  const verify = () => validateBinding(temp, layoutFile, engineFile);
  write(); assert.equal(verify().source_commit, commit);
  fs.appendFileSync(layoutFile, ' '); assert.throws(verify, /Coordinate receipt/);
  write(); fs.appendFileSync(engineFile, ' '); assert.throws(verify, /Exact full engine report/);
  write(e => {e.source_commit = 'b'.repeat(40);}); assert.throws(verify);
  write(e => {e.records[0].result_sha256 = 'c'.repeat(64);}); assert.throws(verify, /Coordinate receipt/);
  write(e => {e.records.push(structuredClone(e.records[0]));}); assert.throws(verify);
  write(e => {e.records[0].failures.push('fixture failed');}); assert.throws(verify);
  write(e => {e.source_sha256['tests/fresh_tutorial_browser.js'] = 'd'.repeat(64);}); assert.throws(verify, /Exact tested harness/);
  write(e => {e.source_sha256['project.godot'] = 'e'.repeat(64);}); assert.throws(verify, /Production source passed/);
  write(() => {}, '<script>LittleLeafPlatform</script>'); assert.throws(verify, /Ordinary Web export/);
  write(); fs.appendFileSync(path.join(temp, 'index.html'), '!'); assert.throws(verify, /size/);
  write(); dirty = true; assert.throws(verify, /Clean tracked source/);
} finally {
  cp.execFileSync = exec;
  fs.rmSync(temp, {recursive: true, force: true});
}
console.log('Fresh tutorial browser contract and source-binding checks passed (browser runtime not exercised)');
