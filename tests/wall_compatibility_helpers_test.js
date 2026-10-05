'use strict';
// Pure, offline gate guards. This test never imports Playwright or opens IDB.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {hash, canonical, within, verifyExport, verifyPreflightBinding, requireVisibleText, assertPreserved} = require('./wall_compatibility_helpers');
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
console.log(JSON.stringify({passed: true, checks, browser_verified: false, method: 'pure offline gate guards'}));
