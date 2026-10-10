'use strict';
// Pure, offline gate guards. This test never imports Playwright or opens IDB.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {hash, canonical, within, verifyExport, verifyPreflightBinding, requireVisibleText, verifyLayout, selectWallReplacement, assertPreserved} = require('./wall_compatibility_helpers');
let checks = 0;
function check(label, fn) {fn(); checks++; console.log('PASS ' + label);}
const fixtures = path.join(__dirname, 'fixtures/wall-compatibility');
const contract = JSON.parse(fs.readFileSync(path.join(fixtures, 'contract.json')));
for (const [name, digest] of Object.entries(contract.fixture_sha256)) check('exact fixture ' + name, () => assert.equal(hash(fs.readFileSync(path.join(fixtures, name))), digest));
check('candidate sources are required without redundant static hashes', () => {assert(contract.candidate_required_sources.includes('web/little_leaf_vault.js')); assert(!Object.hasOwn(contract, 'candidate_production_sha256'));});
check('canonical snapshots preserve payload bytes', () => assert.notEqual(canonical({payload: '{"coins":1}'}), canonical({payload: '{ "coins":1}'})));
check('canonical snapshots disregard only object key enumeration', () => assert.equal(canonical({z: [2, 1], a: 'x'}), canonical({a: 'x', z: [2, 1]})));
check('snapshot order remains significant for lists', () => assert.notEqual(canonical([1, 2]), canonical([2, 1])));
check('OCR accepts line wraps, accents and typographic punctuation', () => requireVisibleText('Saved café\nOriginal progress is unchanged.\nInvalid saved wall or finish data', ['original progress is unchanged', 'Invalid saved wall or finish data']));
check('OCR cannot silently pass missing recovery evidence', () => assert.throws(() => requireVisibleText('Loading game', ['Saving is paused to protect your progress'])));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'wall-compatibility-helpers-'));
try {
  const payload = Buffer.from('synthetic packed bytes');
  fs.writeFileSync(path.join(temporary, 'index.pck'), payload);
  fs.mkdirSync(path.join(temporary, 'web'));
  fs.writeFileSync(path.join(temporary, 'web/vault.js'), 'synthetic source');
  const manifest = {source_commit: 'a'.repeat(40), toolchain_verification: 'checksum-pinned-official-archives', packed_smoke: 'passed', production_sha256: {'web/vault.js': hash('synthetic source')}, files: {'index.pck': {bytes: payload.length, sha256: hash(payload)}}};
  fs.writeFileSync(path.join(temporary, 'release-manifest.json'), JSON.stringify(manifest));
  const manifestDigest = hash(fs.readFileSync(path.join(temporary, 'release-manifest.json')));
  check('matching export hashes verify', () => assert.equal(verifyExport(temporary, manifest.source_commit, manifest.production_sha256).source_commit, manifest.source_commit));
  check('fresh candidate production map binds to exact preflight', () => verifyPreflightBinding(temporary, temporary, manifest, manifest.production_sha256, manifestDigest));
  check('preflight cannot omit production entries', () => assert.throws(() => verifyPreflightBinding(temporary, temporary, manifest, {}, manifestDigest)));
  check('replaced manifest is rejected even with matching sources', () => assert.throws(() => verifyPreflightBinding(temporary, temporary, manifest, manifest.production_sha256, 'e'.repeat(64))));
  check('changed checked-out source is rejected', () => {
    fs.writeFileSync(path.join(temporary, 'web/vault.js'), 'different source');
    assert.throws(() => verifyPreflightBinding(temporary, temporary, manifest, manifest.production_sha256, manifestDigest));
  });
  check('relocated current sources bind without changing historical manifest labels', () => {
    const current = path.join(temporary, 'current');
    fs.mkdirSync(path.join(current, 'game/assets/audio'), {recursive: true});
    fs.mkdirSync(path.join(current, 'platform/web'), {recursive: true});
    fs.writeFileSync(path.join(current, 'game/project.godot'), 'synthetic project');
    fs.writeFileSync(path.join(current, 'game/assets/audio/license.txt'), 'synthetic license');
    fs.writeFileSync(path.join(current, 'platform/web/vault.js'), 'synthetic source');
    const relocated = {...manifest, production_sha256: {...manifest.production_sha256, 'assets/audio/license.txt': hash('synthetic license')}};
    const bytes = JSON.stringify(relocated);
    fs.writeFileSync(path.join(temporary, 'release-manifest.json'), bytes);
    verifyPreflightBinding(temporary, current, relocated, relocated.production_sha256, hash(bytes));
    fs.writeFileSync(path.join(current, 'game/assets/audio/license.txt'), 'changed license');
    assert.throws(() => verifyPreflightBinding(temporary, current, relocated, relocated.production_sha256, hash(bytes)));
    fs.writeFileSync(path.join(temporary, 'release-manifest.json'), JSON.stringify(manifest));
  });
  check('wrong source commit is blocked', () => assert.throws(() => verifyExport(temporary, 'c'.repeat(40), manifest.production_sha256)));
  check('changed source after preflight is blocked', () => assert.throws(() => verifyExport(temporary, manifest.source_commit, {'web/vault.js': 'd'.repeat(64)})));
  check('changed packed bytes are blocked', () => {fs.appendFileSync(path.join(temporary, 'index.pck'), '!'); assert.throws(() => verifyExport(temporary, manifest.source_commit, manifest.production_sha256));});
  check('export route refuses parent traversal', () => assert.throws(() => within(temporary, '../index.pck')));
} finally {fs.rmSync(temporary, {recursive: true, force: true});}
const record = {profileId: 'synthetic', origin: {source: 'legacy-v13'}, campaigns: {grant: {coins: 1000}}, payload: fs.readFileSync(path.join(fixtures, 'new-format2.json'), 'utf8')};
check('legitimate lifecycle revision may advance', () => assertPreserved(record, {...record, revision: 300}));
for (const [name, mutate] of [
  ['wallet', value => {value.coins++;}],
  ['door geometry', value => {value.wall_attachments[0].width = 1;}],
  ['segment height', value => {value.shell_segment_products['shell:back#2'].height = 'full';}]
]) check('reload guard catches changed ' + name, () => {
  const value = JSON.parse(record.payload); mutate(value);
  assert.throws(() => assertPreserved(record, {...record, payload: JSON.stringify(value)}));
});
check('reload guard catches a second receipt', () => assert.throws(() => assertPreserved(record, {...record, campaigns: {...record.campaigns, extra: {coins: 1000}}})));
// Synthetic receipts test the consumer contract, separately from native output.
const region = {x: 10, y: 10, width: 100, height: 30};
const oldLayout = {viewport: [1360, 880], checks: 9, failures: [], ui_route: 'historical-recovery',
  points: Object.fromEntries(['business', 'decorate', 'settings', 'retry'].map(name => [name, [100, 100]])), help_rect: region};
const newLayout = structuredClone(oldLayout);
newLayout.ui_route = 'wall-bottom-tray'; newLayout.checks = 53;
for (const name of ['build', 'wall', 'wall_next', 'wall_style', 'segment', 'confirm']) newLayout.points[name] = [100, 100];
newLayout.regions = Object.fromEntries(['catalog', 'wall_heading', 'wall_back', 'style_name', 'style_height', 'style_price', 'selected_height', 'selected_price', 'review', 'review_heading', 'review_text'].map(name => [name, {...region}]));
newLayout.expected_cost = 35; newLayout.expected_segment = {height: 'half', material: 'sage_panels', paid_cost: 35, refund_credit: 17};
check('historical recovery layout needs no current Wall tray controls', () => verifyLayout(oldLayout, 'old'));
check('current bottom Wall tray coordinates and OCR regions bind', () => verifyLayout(newLayout, 'new'));
for (const [label, mutate] of [
  ['old floating-picker route', layout => {layout.ui_route = 'floating-wall-picker';}],
  ['absent product paging target', layout => {delete layout.points.wall_next;}],
  ['absent real wall card target', layout => {delete layout.points.wall_style;}],
  ['non-finite pointer', layout => {layout.points.wall_style[0] = NaN;}],
  ['offscreen pointer', layout => {layout.points.wall_style[0] = 1360;}],
  ['offscreen card OCR', layout => {layout.regions.style_name.x = 1300;}],
  ['missing selected product OCR', layout => {delete layout.regions.selected_height;}],
  ['empty native result', layout => {layout.checks = 0;}],
  ['failed native result', layout => {layout.failures = ['not visible'];}],
  ['changed price', layout => {layout.expected_cost = 55;}],
  ['wrong wall height', layout => {layout.expected_segment.height = 'full';}],
  ['wrong wall material', layout => {layout.expected_segment.material = 'cream_stripe';}]
]) check('layout contract rejects ' + label, () => {
  const changed = structuredClone(newLayout); mutate(changed);
  assert.throws(() => verifyLayout(changed, 'new'));
});

(async () => {
  const calls = [];
  await selectWallReplacement(async (name, delay) => {
    assert(newLayout.points[name], 'Every browser action consumes a derived current-layout point');
    calls.push(['click', name, delay]);
  }, async (name, regions, phrases, retryTarget) => {
    for (const key of Array.isArray(regions) ? regions : [regions]) assert(newLayout.regions[key], 'Every OCR guard consumes a derived visible region');
    if (retryTarget) assert(newLayout.points[retryTarget]);
    calls.push(['ocr', name, phrases, retryTarget]);
  });
  check('browser route pages before selecting the real card and opens review without paying', () => {
    assert.deepEqual(calls.filter(call => call[0] === 'click').map(call => call[1]), ['decorate', 'wall', 'wall_next', 'wall_style', 'segment']);
    assert.deepEqual(calls.map(call => call[0]), ['click', 'ocr', 'click', 'ocr', 'click', 'ocr', 'click', 'ocr', 'click', 'ocr']);
    assert.deepEqual(calls.filter(call => call[0] === 'ocr').map(call => call[3]).filter(Boolean), ['build'], 'Only idempotent Build navigation is retried');
    assert(calls.at(-1)[2].includes('You pay 35 coins'));
  });
  const stopped = [];
  await assert.rejects(() => selectWallReplacement(async name => {stopped.push(name);}, async name => {
    if (name === 'case-b-wall-product') throw Error('Missing visible half-wall product');
  }), /Missing visible half-wall product/);
  check('failed product visibility blocks selection, target and payment', () => assert.deepEqual(stopped, ['decorate', 'wall', 'wall_next']));
  console.log(JSON.stringify({passed: true, checks, browser_verified: false, method: 'pure offline gate guards'}));
})().catch(error => {console.error(error); process.exitCode = 1;});
