'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const {mergeCases, mergeFromFolder} = require('./wall_compatibility_parallel');
function fixture(name) {
  return {status: 'passed', browser_verified: true, synthetic_only: true,
    inputs: {preflight_sha256: 'same', export_files: {old: 'old', new: 'new'}},
    browser: {sandbox: true, version: 'same'}, ocr: {version: 'same'}, errors: [],
    checks: [name], cases: {[name]: {reload: {revision_after: 3}}},
    ...(name === 'already_open_old' ? {new_ui_edit: {revision_before: 1, revision_after: 2}} : {})};
}
const good = () => [fixture('old_opened_after_new'), fixture('already_open_old')];
assert.equal(Object.keys(mergeCases(good()).cases).length, 2);
assert.throws(() => mergeCases(good().slice(0, 1)));
assert.throws(() => mergeCases([fixture('old_opened_after_new'), fixture('old_opened_after_new')]));
for (const mutate of [r => r.status = 'failed', r => r.browser_verified = false,
  r => r.errors.push('script error'), r => r.inputs.preflight_sha256 = 'other',
  r => r.browser.sandbox = false, r => delete r.cases.already_open_old.reload,
  r => r.new_ui_edit.revision_after = 9]) {
  const reports = good(); mutate(reports[1]); assert.throws(() => mergeCases(reports));
}
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'leaf-case-aggregate-'));
const originalExec = cp.execFileSync;
const originalLog = console.log;
try {
  const reports = good();
  for (const report of reports) report.inputs.new_commit = 'synthetic-source';
  cp.execFileSync = () => 'synthetic-source\n';
  console.log = () => {};
  for (const report of reports) {
    const folder = path.join(output, Object.keys(report.cases)[0]);
    fs.mkdirSync(folder);
    fs.writeFileSync(path.join(folder, 'wall-compatibility-browser.json'), JSON.stringify(report));
  }
  mergeFromFolder(output);
  mergeFromFolder(output); // Existing staging receipt must match exactly.
  const file = path.join(output, 'wall-compatibility-browser.json');
  const saved = JSON.parse(fs.readFileSync(file)); saved.inputs.new_commit = 'other';
  fs.writeFileSync(file, JSON.stringify(saved));
  assert.throws(() => mergeFromFolder(output));
  cp.execFileSync = () => 'other-source\n';
  assert.throws(() => mergeFromFolder(output));
} finally {
  cp.execFileSync = originalExec; console.log = originalLog;
  fs.rmSync(output, {recursive: true, force: true});
}
console.log('wall compatibility parallel aggregation: 14 checks passed');
