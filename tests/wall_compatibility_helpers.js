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
module.exports = {hash, canonical, within, verifyExport, verifyPreflightBinding, normalizedText, requireVisibleText, progress, assertPreserved};
