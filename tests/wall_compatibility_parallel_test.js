'use strict';
const assert = require('node:assert/strict');
const {mergeCases} = require('./wall_compatibility_parallel');
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
console.log('wall compatibility parallel aggregation: 10 checks passed');
