'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
function within(root, relative) {
  const file = path.resolve(root, relative);
  assert(file.startsWith(path.resolve(root) + path.sep), 'File must stay inside the supplied export');
  return file;
}
function verifyExport(web, expectedCommit, critical) {
  const manifest = JSON.parse(fs.readFileSync(path.join(web, 'release-manifest.json')));
  assert.equal(manifest.source_commit, expectedCommit, 'Export must match the exact source commit');
  assert.equal(manifest.toolchain_verification, 'checksum-pinned-official-archives');
  assert.equal(manifest.packed_smoke, 'passed');
  for (const [name, digest] of Object.entries(critical)) assert.equal(manifest.production_sha256[name], digest, 'Source differs from verified preflight input: ' + name);
  for (const [name, file] of Object.entries(manifest.files)) {
    const bytes = fs.readFileSync(within(web, name));
    assert.equal(bytes.length, file.bytes, name + ' size');
    assert.equal(hash(bytes), file.sha256, name + ' digest');
  }
  return manifest;
}
function verifyPreflightBinding(web, source, manifest, production, manifestDigest) {
  assert.equal(hash(fs.readFileSync(path.join(web, 'release-manifest.json'))), manifestDigest, 'Exact export manifest must match preflight');
  assert.equal(canonical(manifest.production_sha256), canonical(production), 'Complete production hash map must match preflight');
  assert(Object.keys(production).length > 0, 'Empty production map is not evidence');
  for (const [name, digest] of Object.entries(production)) {
    assert.equal(hash(fs.readFileSync(within(source, name))), digest, 'Checked-out source must match preflight: ' + name);
  }
}
function normalizedText(text) {
  return text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}
function requireVisibleText(text, phrases) {
  const normalized = normalizedText(text);
  for (const phrase of phrases) assert(normalized.includes(normalizedText(phrase)), 'OCR inconclusive: required rendered text not found: ' + phrase);
}
// Fail before opening a browser if a receipt describes an obsolete/hidden UI
// route. The historical client only needs its unchanged recovery/toolbar path.
function verifyLayout(layout, label) {
  assert(['old', 'new'].includes(label), 'Known layout client');
  assert.deepEqual(layout.viewport, [1360, 880], 'Layout matches browser viewport');
  assert(Number.isInteger(layout.checks) && layout.checks > 0, 'Nonempty native layout checks');
  assert.deepEqual(layout.failures, [], 'Native layout passed');
  assert.equal(layout.ui_route, label === 'new' ? 'wall-bottom-tray' : 'historical-recovery', 'Exact supported UI route');
  function point(name) {
    const value = layout.points?.[name];
    assert(Array.isArray(value) && value.length === 2 && value.every(Number.isFinite), 'Derived point ' + name);
    assert(value[0] >= 0 && value[0] < 1360 && value[1] >= 0 && value[1] < 880, 'Bounded point ' + name);
  }
  function region(value, name) {
    assert(value && ['x', 'y', 'width', 'height'].every(key => Number.isFinite(value[key])), 'Derived region ' + name);
    assert(value.x >= 0 && value.y >= 0 && value.width > 0 && value.height > 0 && value.x + value.width <= 1360 && value.y + value.height <= 880, 'Bounded region ' + name);
  }
  for (const name of ['business', 'decorate', 'settings', 'retry']) point(name);
  region(layout.help_rect, 'Help');
  if (label === 'new') {
    for (const name of ['build', 'wall', 'wall_next', 'wall_style', 'segment', 'confirm']) point(name);
    for (const name of ['catalog', 'wall_heading', 'wall_back', 'style_name', 'style_height', 'style_price', 'selected_height', 'selected_price', 'review', 'review_heading', 'review_text']) region(layout.regions?.[name], name);
    assert.equal(layout.expected_cost, 35, 'Unchanged half-wall purchase price');
    assert.equal(layout.expected_segment?.height, 'half', 'Exact requested height');
    assert.equal(layout.expected_segment?.material, 'sage_panels', 'Exact requested finish');
  }
}

// The actual browser calls this same route. It only prepares the review;
// payment and all storage/transaction assertions remain in the browser gate.
async function selectWallReplacement(click, screenUiText) {
  await click('decorate', 0);
  await screenUiText('case-b-build-catalog', 'catalog', ['Wall', 'Door', 'Window'], 'build');
  await click('wall', 0);
  await screenUiText('case-b-wall-tray', ['wall_heading', 'wall_back'], ['Wall', 'Build']);
  await click('wall_next', 0);
  await screenUiText('case-b-wall-product', ['style_name', 'style_height', 'style_price'], ['Sage panels', 'Half wall', '35']);
  await click('wall_style', 0);
  await screenUiText('case-b-selected-wall', ['selected_height', 'selected_price', 'style_name'], ['Half wall', '35 / tile', 'Sage panels']);
  await click('segment');
  await screenUiText('case-b-new-confirmation', ['review_heading', 'review_text'],
    ['Replace wall', 'Selected one-tile wall', 'Half wall', 'Sage panels', 'You pay 35 coins']);
}
function progress(record) {
  const payload = JSON.parse(record.payload);
  return {profileId: record.profileId, origin: record.origin, campaigns: record.campaigns,
    coins: payload.coins, built_walls: payload.built_walls, wall_format: payload.wall_format,
    shell_products: payload.shell_products, shell_segment_format: payload.shell_segment_format,
    shell_segment_products: payload.shell_segment_products, wall_attachment_format: payload.wall_attachment_format,
    wall_attachments: payload.wall_attachments, next_attachment_id: payload.next_attachment_id};
}
function assertPreserved(before, after) {
  assert.equal(canonical(progress(after)), canonical(progress(before)), 'Wall products, openings, wallet, identity, provenance and receipts must survive');
}
module.exports = {hash, canonical, within, verifyExport, verifyPreflightBinding, normalizedText, requireVisibleText, verifyLayout, selectWallReplacement, progress, assertPreserved};
