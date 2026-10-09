'use strict';
const assert = require('node:assert/strict');

// Playwright evaluate() requests userGesture:true. Observation must never unlock
// audio, set user activation, or invoke the production resume/playback path.
function passiveReader(session) {
  return async (fn, argument) => {
    assert.equal(typeof fn, 'function');
    const value = argument === undefined ? 'undefined' : JSON.stringify(argument);
    const response = await session.send('Runtime.evaluate', {
      expression: '(' + fn.toString() + ')(' + value + ')',
      awaitPromise: true, returnByValue: true, userGesture: false,
    });
    if (response.exceptionDetails) throw new Error('Passive observation failed: ' + JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
}
async function waitForPassive(read, fn, timeout = 90000, wait = ms => new Promise(resolve => setTimeout(resolve, ms))) {
  const deadline = Date.now() + timeout;
  do {
    if (await read(fn)) return;
    await wait(25);
  } while (Date.now() < deadline);
  throw new Error('Passive readiness timed out after ' + timeout + ' ms');
}
function failureKind(error, phase) {
  const text = String(error);
  if (phase === 'browser-launch' || /No usable sandbox|Chromium sandboxing failed/.test(text)) return 'browser-infrastructure';
  if (/OCR inconclusive/.test(text) || phase === 'visual-ocr') return 'visual-evidence';
  if (/Passive observation failed|Passive readiness timed out/.test(text)) return 'observation';
  return 'acceptance-or-runtime';
}
function recordPageLogs(page, write, errors) {
  page.on('console', message => {
    const text = message.text();
    write({kind: 'console', level: message.type(), text, location: message.location()});
    if (/SCRIPT ERROR|ERROR:/.test(text)) errors.push(text);
  });
  page.on('pageerror', error => {errors.push(String(error)); write({kind: 'pageerror', error: String(error), stack: error.stack});});
  page.on('requestfailed', request => write({kind: 'requestfailed', url: request.url(), failure: request.failure()}));
  page.on('response', response => write({kind: 'response', url: response.url(), status: response.status()}));
  page.on('crash', () => {errors.push('Browser page crashed'); write({kind: 'crash'});});
}
module.exports = {passiveReader, waitForPassive, failureKind, recordPageLogs};
