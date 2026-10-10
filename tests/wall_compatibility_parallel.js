'use strict';
// Independent cases use different Chromium processes, X displays, loopback
// origins and synthetic contexts. Actions within each case remain sequential.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {canonical} = require('./wall_compatibility_helpers');
const CASES = ['old_opened_after_new', 'already_open_old'];

function mergeCases(reports) {
  assert.equal(reports.length, CASES.length, 'Both cases are mandatory');
  const cases = {}, checks = new Set();
  for (const report of reports) {
    assert.equal(report.status, 'passed');
    assert.equal(report.browser_verified, true);
    assert.equal(report.synthetic_only, true);
    assert.deepEqual(report.errors, []);
    assert(report.inputs && report.browser && report.ocr, 'Complete binding is mandatory');
    for (const field of ['inputs', 'browser', 'ocr']) {
      assert.equal(canonical(report[field]), canonical(reports[0][field]), field + ' differs between cases');
    }
    const names = Object.keys(report.cases);
    assert.equal(names.length, 1, 'One independent case per child');
    const name = names[0];
    assert(CASES.includes(name) && !Object.hasOwn(cases, name), 'Missing, duplicate or unexpected case');
    assert(report.cases[name].reload, 'Actual new-client reload is mandatory');
    cases[name] = report.cases[name];
    assert(Array.isArray(report.checks) && report.checks.length, 'Case assertions are mandatory');
    for (const check of report.checks) checks.add(check);
  }
  assert.deepEqual(Object.keys(cases).sort(), [...CASES].sort());
  const edit = reports.find(report => Object.hasOwn(report.cases, 'already_open_old')).new_ui_edit;
  assert(edit && edit.revision_after === edit.revision_before + 1, 'Real new UI commit is mandatory');
  return {...reports[0], cases, checks: [...checks], new_ui_edit: edit,
    execution: {mode: 'independent case processes', cases: CASES}, errors: []};
}

async function runParallel(args) {
  assert(!args.includes('--case'), 'Do not combine parallel and partial case modes');
  const index = args.indexOf('--output');
  assert(index >= 0 && args[index + 1], '--output is required');
  const output = path.resolve(args[index + 1]);
  fs.mkdirSync(output, {recursive: true});
  assert(!fs.existsSync(path.join(output, 'wall-compatibility-browser.json')), 'Preserve previous evidence');
  const started = Date.now();
  const children = CASES.map(name => {
    const childArgs = args.filter(arg => arg !== '--parallel-cases');
    childArgs[childArgs.indexOf('--output') + 1] = path.join(output, name);
    childArgs.push('--case', name);
    const log = fs.openSync(path.join(output, name + '.log'), 'wx');
    // A separate X display prevents foreground changes in the other case from
    // generating additional visibility saves. No writable profile is shared.
    return new Promise(resolve => {
      const child = cp.spawn('xvfb-run', ['-a', process.execPath,
        path.join(__dirname, 'wall_compatibility_browser.js'), ...childArgs],
      {env: process.env, stdio: ['ignore', log, log]});
      child.once('error', error => {fs.closeSync(log); resolve({name, error: String(error)});});
      child.once('exit', (code, signal) => {fs.closeSync(log); resolve({name, code, signal});});
    });
  });
  const results = await Promise.all(children);
  let report;
  try {
    assert(results.every(result => result.code === 0 && !result.signal && !result.error),
      'Both actual browser case processes must succeed: ' + JSON.stringify(results));
    report = mergeCases(CASES.map(name => JSON.parse(fs.readFileSync(
      path.join(output, name, 'wall-compatibility-browser.json'), 'utf8'))));
    report.execution.seconds = (Date.now() - started) / 1000;
  } catch (error) {
    report = {status: 'failed', browser_verified: false, synthetic_only: true,
      error: error.stack, children: results};
    process.exitCode = 1;
  }
  fs.writeFileSync(path.join(output, 'wall-compatibility-browser.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
}
module.exports = {mergeCases, runParallel};
