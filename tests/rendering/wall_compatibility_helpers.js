'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const {sourcePath} = require('../tooling/source_paths');

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
    assert.equal(hash(fs.readFileSync(within(source, path.relative(source, sourcePath(source, name))))), digest, 'Checked-out source must match preflight: ' + name);
  }
}
function verifyCandidateSources(production, historicalRequired) {
  // The pinned fixture contract retains its historical namespace.
  for (const historical of historicalRequired) {
    const name = historical.replace('scripts/cafe_web_save.gd', 'scripts/persistence/cafe_web_save.gd')
      .replace('scripts/cafe_model.gd', 'scripts/core/cafe_model.gd')
      .replace('scripts/cafe_shell_segments.gd', 'scripts/gameplay/cafe_shell_segments.gd');
    assert(Object.hasOwn(production, name), 'Missing required candidate source ' + name);
  }
}
function normalizedText(text) {
  return text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}
function requireVisibleText(text, phrases) {
  const normalized = normalizedText(text);
  for (const phrase of phrases) assert(normalized.includes(normalizedText(phrase)), 'OCR inconclusive: required rendered text not found: ' + phrase);
}
// The back-button crop must contain the complete label as its own token.
// Arrow punctuation is harmless; clipped "Buil", "Builder" and "Rebuild" are not.
function requireWallBackText(text) {
  assert(normalizedText(text).split(' ').includes('build'), 'OCR inconclusive: required complete back-button label not found: Build');
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
    for (const name of ['build', 'wall', 'wall_next', 'wall_style', 'segment', 'confirm', 'apply']) point(name);
    if (Object.hasOwn(layout.points, 'build_next')) {
      point('build_next');
      for (const name of ['category_ready', 'build_category']) region(layout.regions?.[name], name);
    }
    for (const name of ['catalog', 'wall_heading', 'wall_back', 'style_name', 'style_height', 'style_price', 'selected_height', 'selected_price', 'review', 'review_heading', 'review_text']) region(layout.regions?.[name], name);
    assert.equal(layout.expected_cost, 35, 'Unchanged half-wall purchase price');
    assert.equal(layout.expected_segment?.height, 'half', 'Exact requested height');
    assert.equal(layout.expected_segment?.material, 'sage_panels', 'Exact requested finish');
    assert.equal(layout.expected_target, 'x:2:0', 'Exact grid-edge target');
    assert.equal(layout.expected_segment?.id, 'shell:back#2', 'Imported wall identity survives replacement');
    assert.deepEqual([layout.expected_segment?.axis, layout.expected_segment?.x, layout.expected_segment?.z], ['x', 2, 0], 'Exact one-tile grid geometry');
    assert.equal(layout.expected_segment?.paid_cost, 35, 'Exact wall payment');
    assert.equal(layout.expected_segment?.refund_credit, 17, 'Exact wall refund ownership');
  }
}

// The actual browser calls this same route. It only prepares the review;
// payment and all storage/transaction assertions remain in the browser gate.
async function selectWallReplacement(click, screenUiText, categoryPage = false) {
  // The source-bound native recipe records this only when Build is off the rail.
  await click('decorate', 0);
  if (categoryPage) {
    // Observe the settled initial rail before its one real paging input. Then
    // require Build at its fully exposed native position before selecting it.
    await screenUiText('case-b-category-ready', 'category_ready', ['Tables']);
    await click('build_next', 0);
    await screenUiText('case-b-build-exposed', 'build_category', ['Build']);
  }
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
// Preserve both representations exactly. Conversion is permitted only against a
// projection emitted by the candidate's real native codec and bound to the
// fixed fixture, source, export and layout hashes before any browser is opened.
const buildingFields = ['building_format', 'wall_format', 'built_walls', 'shell_material',
  'shell_products', 'shell_segment_format', 'shell_segment_products', 'wall_attachment_format',
  'wall_attachments', 'next_wall_id', 'next_attachment_id', 'starter_geometry_version',
  'floor_style', 'floor_finishes', 'owned_parcels'];
function building(payload) {
  return Object.fromEntries(buildingFields.filter(key => Object.hasOwn(payload, key)).map(key => [key, payload[key]]));
}
function ownership(record) {
  return {profileId: record.profileId, origin: record.origin, campaigns: record.campaigns};
}
function progress(record) {
  const payload = JSON.parse(record.payload);
  return {...ownership(record), coins: payload.coins, ...building(payload)};
}
function assertPreserved(before, after) {
  assert.equal(canonical(progress(after)), canonical(progress(before)), 'Wall products, openings, wallet, identity, provenance and receipts must survive');
}
function verifyCodecProjection(projection, fixture) {
  assert(projection && typeof projection.converted_payload === 'string', 'Native converted bytes are mandatory');
  assert.equal(projection.source_sha256, hash(fixture), 'Native projection binds the exact preserved fixture');
  assert.equal(projection.original_backup_sha256, hash(fixture), 'Native recovery copy retains the exact input');
  assert.equal(projection.converted_sha256, hash(projection.converted_payload), 'Native converted bytes match their receipt');
  const payload = JSON.parse(projection.converted_payload);
  assert.equal(payload.building_format, 'little_leaf.grid_building.v2', 'Native codec must emit centered grid building');
  assert.equal(payload.wall_format, 4, 'Native codec must emit wall format 4');
  assert.equal(payload.wall_attachment_format, 2, 'Native codec must emit grid attachment ownership');
  for (const obsolete of ['shell_products', 'shell_segment_products', 'shell_segment_format', 'shell_material']) {
    assert(!Object.hasOwn(payload, obsolete), 'Converted projection has no obsolete ' + obsolete);
  }
  assert(Array.isArray(payload.built_walls) && payload.built_walls.length > 0, 'Native grid walls are mandatory');
  assert(Array.isArray(payload.wall_attachments) && payload.wall_attachments.length > 0, 'Native paid opening is mandatory');
  return payload;
}
function assertImported(before, after, fixture, projection, cost = 0) {
  const original = JSON.parse(fixture), baseline = JSON.parse(before.payload), actual = JSON.parse(after.payload);
  const converted = verifyCodecProjection(projection, fixture);
  assert.equal(canonical(building(baseline)), canonical(building(original)), 'Import baseline must match the fixed historical geometry and payment identity');
  assert.equal(canonical(building(actual)), canonical(building(converted)), 'Imported grid geometry, paid openings, IDs, receipts and floor ownership match the exact native codec');
  assert.equal(canonical(ownership(after)), canonical(ownership(before)), 'Import preserves profile identity, provenance and compensation receipts');
  assert.equal(actual.coins, baseline.coins - cost, 'Import preserves wallet except the single authorized wall charge');
  assert.equal(converted.coins, original.coins - cost, 'Native projection charges only the expected wall cost');
}
const archiveRows = snapshot => snapshot.authority.filter(([key]) => typeof key === 'string' && key.startsWith('pre-grid-v1/'));
function assertOriginalArchived(before, after) {
  const original = before.authority.find(([key]) => key === 'active')[1];
  const key = 'pre-grid-v1/' + original.profileId;
  const previous = before.authority.find(([name]) => name === key);
  const row = after.authority.find(([name]) => name === key);
  assert(row && typeof row[1] === 'string', 'Migration must durably retain its original authority archive');
  const archives = JSON.parse(row[1]), prior = previous ? JSON.parse(previous[1]) : [];
  assert.equal(archives.length, prior.length + 1, 'Exactly one original authority is archived for this transition');
  assert.equal(canonical(archives.slice(0, -1)), canonical(prior), 'Previous recovery entries remain unchanged');
  const entry = archives.at(-1), {archiveDigest, ...body} = entry;
  assert.equal(archiveDigest, hash(JSON.stringify(body)), 'Archive checksum');
  assert.equal(entry.format, 'little-leaf.pre-grid.v1', 'Exact recovery archive format');
  assert.equal(entry.profileId, original.profileId, 'Archived profile identity');
  assert.equal(entry.revision, original.revision, 'Archived revision');
  assert.equal(entry.digest, original.digest, 'Archived authority digest');
  assert.equal(entry.legacyDigest, null, 'Archive is the acknowledged authority, not a substituted legacy file');
  assert.equal(entry.payload, original.payload, 'Original authority payload bytes retained exactly');
  assert.equal(entry.payloadDigest, hash(original.payload), 'Original payload checksum');
  assert.equal(canonical(JSON.parse(entry.recordText)), canonical(original), 'Original authority, identity, receipts and previous record retained exactly');
  assert.equal(canonical(after.legacy), canonical(before.legacy), 'Migration leaves original legacy bytes unchanged');
  assert.equal(canonical(archiveRows(after).filter(([name]) => name !== key)), canonical(archiveRows(before).filter(([name]) => name !== key)), 'Unrelated archives remain unchanged');
}
module.exports = {hash, canonical, within, verifyExport, verifyPreflightBinding, verifyCandidateSources, normalizedText, requireVisibleText, requireWallBackText, verifyLayout, selectWallReplacement, progress, assertPreserved, building, verifyCodecProjection, assertImported, archiveRows, assertOriginalArchived};
