'use strict';
// Pure, offline gate guards. This test never imports Playwright or opens IDB.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {hash, canonical, within, verifyExport, verifyPreflightBinding, verifyCandidateSources, requireVisibleText, verifyLayout, selectWallReplacement, assertPreserved, building, verifyCodecProjection, assertImported, archiveRows, assertOriginalArchived} = require('./wall_compatibility_helpers');
let checks = 0;
function check(label, fn) {fn(); checks++; console.log('PASS ' + label);}
const fixtures = path.join(__dirname, '../fixtures/wall-compatibility');
const contract = JSON.parse(fs.readFileSync(path.join(fixtures, 'contract.json')));
for (const [name, digest] of Object.entries(contract.fixture_sha256)) check('exact fixture ' + name, () => assert.equal(hash(fs.readFileSync(path.join(fixtures, name))), digest));
check('candidate sources are required without redundant static hashes', () => {assert(contract.candidate_required_sources.includes('web/little_leaf_vault.js')); assert(!Object.hasOwn(contract, 'candidate_production_sha256'));});
const currentCandidateSources = {
  'web/little_leaf_vault.js': 'synthetic-vault',
  'web/little_leaf_shell.html': 'synthetic-shell',
  'scripts/persistence/cafe_web_save.gd': 'synthetic-save',
  'scripts/core/cafe_model.gd': 'synthetic-model',
  'scripts/gameplay/cafe_shell_segments.gd': 'synthetic-segments'
};
check('current candidate binds mapped resources without rewriting the pinned contract', () => {
  const original = JSON.stringify(contract);
  verifyCandidateSources(currentCandidateSources, contract.candidate_required_sources);
  assert.equal(JSON.stringify(contract), original);
});
for (const name of Object.keys(currentCandidateSources)) check('missing current candidate source rejected: ' + name, () => {
  const incomplete = {...currentCandidateSources}; delete incomplete[name];
  assert.throws(() => verifyCandidateSources(incomplete, contract.candidate_required_sources));
});
check('historical resource labels cannot qualify a current candidate', () => {
  const historical = Object.fromEntries(contract.candidate_required_sources.map(name => [name, 'synthetic-old']));
  assert.throws(() => verifyCandidateSources(historical, contract.candidate_required_sources));
});
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
// Synthetic codec receipts exercise validation only. Production conversions are
// emitted by model.load_save/model.save in the source-bound native preflight.
const sourceFixture = fs.readFileSync(path.join(fixtures, 'old-format1.json'), 'utf8');
const sourcePayload = JSON.parse(sourceFixture);
const importedPayload = {...sourcePayload, building_format: 'little_leaf.grid_building.v2', wall_format: 4,
  wall_attachment_format: 2, built_walls: [
    {id: 'shell:back#2', axis: 'x', x: 2, z: 0, height: 'full', material: 'original', paid_cost: 0, refund_credit: 0},
    {id: 'shell:west#5', axis: 'z', x: 0, z: 5, height: 'full', material: 'cream_stripe', paid_cost: 55, refund_credit: 27}],
  wall_attachments: [{id: 77, kind: 'door', wall_ids: ['shell:west#5'], offset: .5, width: 1.5, paid_cost: 40}]};
for (const key of ['shell_material', 'shell_products', 'shell_segment_format', 'shell_segment_products']) delete importedPayload[key];
const receipt = value => ({source_sha256: hash(sourceFixture), converted_payload: JSON.stringify(value),
  converted_sha256: hash(JSON.stringify(value)), original_backup_sha256: hash(sourceFixture)});
const native = receipt(importedPayload);
const sourceRecord = {...record, revision: 3, digest: 'synthetic-authority-digest', payload: sourceFixture};
const importedRecord = {...sourceRecord, revision: 4, payload: native.converted_payload};
check('native codec projection binds exact original and converted bytes', () => verifyCodecProjection(native, sourceFixture));
check('source-bound conversion preserves geometry and ownership with a revision advance', () => assertImported(sourceRecord, importedRecord, sourceFixture, native));
check('compensation wallet is retained rather than overwritten with fixture coins', () => {
  const before = {...sourceRecord, payload: JSON.stringify({...sourcePayload, coins: sourcePayload.coins + 1000})};
  const after = {...importedRecord, payload: JSON.stringify({...importedPayload, coins: importedPayload.coins + 1000})};
  assertImported(before, after, sourceFixture, native);
});
const editedPayload = structuredClone(importedPayload);
editedPayload.coins -= 35; Object.assign(editedPayload.built_walls[0], {height: 'half', material: 'sage_panels', paid_cost: 35, refund_credit: 17});
check('only exact source-bound single wall charge is accepted', () => assertImported(sourceRecord, {...importedRecord, payload: JSON.stringify(editedPayload)}, sourceFixture, receipt(editedPayload), 35));
for (const [label, mutate] of [
  ['wrong original fixture', value => {value.source_sha256 = 'a'.repeat(64);}],
  ['missing original backup', value => {delete value.original_backup_sha256;}],
  ['changed converted bytes', value => {value.converted_payload += ' ';}],
  ['missing converted bytes', value => {delete value.converted_payload;}]
]) check('codec receipt rejects ' + label, () => {const value = structuredClone(native); mutate(value); assert.throws(() => verifyCodecProjection(value, sourceFixture));});
for (const [label, mutate] of [
  ['obsolete wall format', value => {value.wall_format = 2;}],
  ['previous grid format', value => {value.building_format = 'little_leaf.grid_building.v1'; value.wall_format = 3;}],
  ['legacy attachments', value => {value.wall_attachment_format = 1;}],
  ['obsolete shell fields', value => {value.shell_products = {};}],
  ['missing walls', value => {value.built_walls = [];}],
  ['missing openings', value => {value.wall_attachments = [];}]
]) check('codec projection rejects ' + label, () => {const value = structuredClone(importedPayload); mutate(value); assert.throws(() => verifyCodecProjection(receipt(value), sourceFixture));});
for (const [label, mutate] of [
  ['wall identity', value => {value.built_walls[0].id = 'wall:9';}],
  ['wall geometry', value => {value.built_walls[0].x++;}],
  ['wall receipt', value => {value.built_walls[1].refund_credit++;}],
  ['door supports', value => {value.wall_attachments[0].wall_ids = ['shell:back#2'];}],
  ['door width', value => {value.wall_attachments[0].width = 1;}],
  ['door ownership', value => {value.wall_attachments[0].paid_cost = 0;}],
  ['next wall identity', value => {value.next_wall_id++;}],
  ['next opening identity', value => {value.next_attachment_id++;}],
  ['floor ownership', value => {delete value.floor_finishes['0,0'];}],
  ['parcel ownership', value => {value.owned_parcels = ['different'];}],
  ['wallet', value => {value.coins++;}]
]) check('import and modern reload both reject changed ' + label, () => {
  const value = structuredClone(importedPayload); mutate(value);
  const changed = {...importedRecord, payload: JSON.stringify(value)};
  assert.throws(() => assertImported(sourceRecord, changed, sourceFixture, native));
  assert.throws(() => assertPreserved(importedRecord, changed));
});
for (const [label, mutate] of [
  ['profile identity', value => {value.profileId += '-other';}],
  ['provenance', value => {value.origin.source = 'fresh';}],
  ['second compensation receipt', value => {value.campaigns.extra = {coins: 1000};}]
]) check('import rejects changed ' + label, () => {const value = structuredClone(importedRecord); mutate(value); assert.throws(() => assertImported(sourceRecord, value, sourceFixture, native));});
check('conversion cannot normalize an unrelated historical payload', () => {
  const other = structuredClone(sourcePayload); other.wall_attachments[0].width = 1;
  assert.throws(() => assertImported({...sourceRecord, payload: JSON.stringify(other)}, importedRecord, sourceFixture, native));
});
check('migration charge cannot be omitted or repeated', () => {
  assert.throws(() => assertImported(sourceRecord, importedRecord, sourceFixture, native, 35));
  const extra = {...editedPayload, coins: editedPayload.coins - 35};
  assert.throws(() => assertImported(sourceRecord, {...importedRecord, payload: JSON.stringify(extra)}, sourceFixture, receipt(editedPayload), 35));
});
function archiveEntry(original) {
  const body = {format: 'little-leaf.pre-grid.v1', profileId: original.profileId, revision: original.revision,
    digest: original.digest, legacyDigest: null, recordText: JSON.stringify(original), payload: original.payload, payloadDigest: hash(original.payload)};
  return {...body, archiveDigest: hash(JSON.stringify(body))};
}
const beforeArchive = {authority: [['active', sourceRecord]], legacy: [['synthetic-file', {bytes: [1, 2, 3]}]]};
const archived = archiveEntry(sourceRecord);
const afterArchive = {authority: [['active', importedRecord], ['pre-grid-v1/' + sourceRecord.profileId, JSON.stringify([archived])]], legacy: structuredClone(beforeArchive.legacy)};
check('migration requires exact original authority and legacy bytes', () => assertOriginalArchived(beforeArchive, afterArchive));
check('missing archive cannot pass a successful model conversion', () => assert.throws(() => assertOriginalArchived(beforeArchive, {...afterArchive, authority: [['active', importedRecord]]})));
for (const [label, mutate] of [
  ['original payload bytes', value => {value.payload += ' ';}],
  ['profile identity', value => {value.profileId += '-other';}],
  ['source revision', value => {value.revision++;}],
  ['authority digest', value => {value.digest = 'other';}],
  ['original receipt', value => {const r = JSON.parse(value.recordText); r.campaigns = {}; value.recordText = JSON.stringify(r);}],
  ['archive checksum', value => {value.archiveDigest = 'a'.repeat(64);}]
]) check('archive guard rejects changed ' + label, () => {
  const value = structuredClone(archived); mutate(value);
  const altered = structuredClone(afterArchive); altered.authority[1][1] = JSON.stringify([value]);
  assert.throws(() => assertOriginalArchived(beforeArchive, altered));
});
check('archive guard rejects changed legacy bytes', () => {
  const altered = structuredClone(afterArchive); altered.legacy[0][1].bytes[0]++;
  assert.throws(() => assertOriginalArchived(beforeArchive, altered));
});
check('archive extraction retains original archive strings byte-for-byte', () => assert.deepEqual(archiveRows(afterArchive), [afterArchive.authority[1]]));
// Synthetic receipts test the consumer contract, separately from native output.
const region = {x: 10, y: 10, width: 100, height: 30};
const oldLayout = {viewport: [1360, 880], checks: 9, failures: [], ui_route: 'historical-recovery',
  points: Object.fromEntries(['business', 'decorate', 'settings', 'retry'].map(name => [name, [100, 100]])), help_rect: region};
const newLayout = structuredClone(oldLayout);
newLayout.ui_route = 'wall-bottom-tray'; newLayout.checks = 53;
for (const name of ['build', 'wall', 'wall_next', 'wall_style', 'segment', 'confirm', 'apply']) newLayout.points[name] = [100, 100];
newLayout.regions = Object.fromEntries(['catalog', 'wall_heading', 'wall_back', 'style_name', 'style_height', 'style_price', 'selected_height', 'selected_price', 'review', 'review_heading', 'review_text'].map(name => [name, {...region}]));
newLayout.expected_cost = 35; newLayout.expected_target = 'x:2:0';
newLayout.expected_segment = {id: 'shell:back#2', axis: 'x', x: 2, z: 0, height: 'half', material: 'sage_panels', paid_cost: 35, refund_credit: 17};
check('historical recovery layout needs no current Wall tray controls', () => verifyLayout(oldLayout, 'old'));
check('current bottom Wall tray coordinates and OCR regions bind', () => verifyLayout(newLayout, 'new'));
const pagedLayout = structuredClone(newLayout); pagedLayout.points.build_next = [400, 700];
pagedLayout.regions.category_ready = {...region}; pagedLayout.regions.build_category = {...region};
for (const name of ['category_ready', 'build_category']) check('category navigation requires observed region ' + name, () => {
  const changed = structuredClone(pagedLayout); delete changed.regions[name];
  assert.throws(() => verifyLayout(changed, 'new'));
});
check('derived category page point binds before Build', () => verifyLayout(pagedLayout, 'new'));
for (const bad of [[1360, 700], [400, NaN], [400]]) check('invalid category page point is rejected ' + String(bad), () => {
  const changed = structuredClone(pagedLayout); changed.points.build_next = bad;
  assert.throws(() => verifyLayout(changed, 'new'));
});
for (const [label, mutate] of [
  ['old floating-picker route', layout => {layout.ui_route = 'floating-wall-picker';}],
  ['absent product paging target', layout => {delete layout.points.wall_next;}],
  ['absent real wall card target', layout => {delete layout.points.wall_style;}],
  ['absent session Apply target', layout => {delete layout.points.apply;}],
  ['non-finite pointer', layout => {layout.points.wall_style[0] = NaN;}],
  ['offscreen pointer', layout => {layout.points.wall_style[0] = 1360;}],
  ['offscreen card OCR', layout => {layout.regions.style_name.x = 1300;}],
  ['missing selected product OCR', layout => {delete layout.regions.selected_height;}],
  ['empty native result', layout => {layout.checks = 0;}],
  ['failed native result', layout => {layout.failures = ['not visible'];}],
  ['changed price', layout => {layout.expected_cost = 55;}],
  ['wrong wall height', layout => {layout.expected_segment.height = 'full';}],
  ['wrong wall material', layout => {layout.expected_segment.material = 'cream_stripe';}],
  ['obsolete segment target', layout => {layout.expected_target = 'shell:back#2';}],
  ['changed imported identity', layout => {layout.expected_segment.id = 'wall:1';}],
  ['shifted grid geometry', layout => {layout.expected_segment.x = 3;}],
  ['missing purchase receipt', layout => {delete layout.expected_segment.paid_cost;}],
  ['changed refund receipt', layout => {layout.expected_segment.refund_credit = 18;}]
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
  const paged = [];
  await selectWallReplacement(async (name, delay) => {
    assert(pagedLayout.points[name]); paged.push(['click', name, delay]);
  }, async (name, regions, phrases, retryTarget) => {
    for (const key of Array.isArray(regions) ? regions : [regions]) assert(pagedLayout.regions[key]);
    if (retryTarget) assert(pagedLayout.points[retryTarget]);
    paged.push(['ocr', name, phrases, retryTarget]);
  }, true);
  check('paged category route exposes Build before unchanged Wall selection', () => {
    assert.deepEqual(paged.filter(call => call[0] === 'click').map(call => call[1]), ['decorate', 'build_next', 'wall', 'wall_next', 'wall_style', 'segment']);
    assert.deepEqual(paged.slice(0, 4).map(call => call.slice(0, 2)), [['click', 'decorate'], ['ocr', 'case-b-category-ready'], ['click', 'build_next'], ['ocr', 'case-b-build-exposed']]);
    assert.equal(paged[1][3], undefined, 'Readiness observes without unbounded input retries');
    assert.equal(paged[3][3], undefined, 'Exposure is required without repeating category paging');
    assert.equal(paged[4][3], 'build', 'Build remains actual idempotent pointer navigation after observed exposure');
    assert.deepEqual(paged.slice(4), calls.slice(1), 'Wall/OCR/review route remains byte-for-byte equivalent');
  });
  let releaseReady;
  const ready = new Promise(resolve => {releaseReady = resolve;});
  const delayed = [];
  const delayedNavigation = selectWallReplacement(async name => {delayed.push(name);}, async name => {
    if (name === 'case-b-category-ready') await ready;
  }, true);
  await Promise.resolve();
  check('delayed rendered readiness blocks the category arrow', () => assert.deepEqual(delayed, ['decorate']));
  releaseReady(); await delayedNavigation;
  check('observed readiness permits exactly one category page', () => assert.equal(delayed.filter(name => name === 'build_next').length, 1));
  const ignored = [];
  await assert.rejects(() => selectWallReplacement(async name => {ignored.push(['click', name]);}, async (name, regions, phrases, retryTarget) => {
    ignored.push(['ocr', name, retryTarget]);
    if (name === 'case-b-build-exposed') throw Error('Page click ignored: Build not exposed');
  }, true), /Build not exposed/);
  check('ignored category page blocks Build selection, product actions and payment', () => {
    assert.deepEqual(ignored.filter(call => call[0] === 'click').map(call => call[1]), ['decorate', 'build_next']);
    assert.equal(ignored.some(call => call[2]), false, 'No retry target can click the wrong category');
  });
  const stopped = [];
  await assert.rejects(() => selectWallReplacement(async name => {stopped.push(name);}, async name => {
    if (name === 'case-b-wall-product') throw Error('Missing visible half-wall product');
  }), /Missing visible half-wall product/);
  check('failed product visibility blocks selection, target and payment', () => assert.deepEqual(stopped, ['decorate', 'wall', 'wall_next']));
  console.log(JSON.stringify({passed: true, checks, browser_verified: false, method: 'pure offline gate guards'}));
})().catch(error => {console.error(error); process.exitCode = 1;});
