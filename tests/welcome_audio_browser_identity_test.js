'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const {systemChromeVersion, browserIdentity, splitCommandLine, browserCommandLine, verifyIdentity,
  SYSTEM_CHROME_EXECUTABLE} = require('./welcome_audio_browser_identity');
let checks = 0;
async function test(name, fn) {await fn(); checks++; console.log('ok ' + name);}
(async () => {
  await test('only explicit official Chrome154 versions accepted', () => {
    assert.equal(systemChromeVersion('Google Chrome 154.0.1234.5'), '154.0.1234.5');
    for (const text of ['Chromium 154.0.1234.5', 'Google Chrome 153.0.1234.5', 'Google Chrome 155.0.1234.5', 'Google Chrome 154', 'Google Chrome 154.0.1.2 extra']) assert.throws(() => systemChromeVersion(text));
  });
  await test('explicit system channel retains sandbox, unmutes only default driver mute, adds no flags', () => {
    const old = [fs.statSync, fs.readFileSync, cp.execFileSync];
    try {
      fs.statSync = name => {assert.equal(name, SYSTEM_CHROME_EXECUTABLE); return {isFile: () => true};};
      fs.readFileSync = name => {assert.equal(name, SYSTEM_CHROME_EXECUTABLE); return Buffer.from('synthetic binary');};
      cp.execFileSync = (name, args) => {assert.equal(name, SYSTEM_CHROME_EXECUTABLE); assert.deepEqual(args, ['--version']); return 'Google Chrome 154.0.1234.5\n';};
      const identity = browserIdentity(null, null, 'system-chrome');
      assert.deepEqual(identity.options, {headless: false, chromiumSandbox: true, ignoreDefaultArgs: ['--mute-audio'], channel: 'chrome'});
      assert.equal(identity.expected_version, '154.0.1234.5'); assert.equal(identity.executable_sha256.length, 64);
    } finally {[fs.statSync, fs.readFileSync, cp.execFileSync] = old;}
  });
  await test('unsupported selection cannot choose a fallback', () => assert.throws(() => browserIdentity(null, null, 'automatic')));
  await test('command-line parser preserves quoted and escaped fields', () => {
    assert.deepEqual(splitCommandLine('"/opt/google/chrome/chrome" --user-data-dir="/tmp/profile with spaces" --flag=two\\ words'), [SYSTEM_CHROME_EXECUTABLE, '--user-data-dir=/tmp/profile with spaces', '--flag=two words']);
    for (const raw of ['', '"unterminated', '/opt/chrome trailing\\']) assert.throws(() => splitCommandLine(raw));
  });
  await test('Browser command-line response is used without extra CDP calls', async () => {
    const calls = []; const result = await browserCommandLine({send: async method => {calls.push(method); return {arguments: [SYSTEM_CHROME_EXECUTABLE]};}});
    assert.deepEqual(calls, ['Browser.getBrowserCommandLine']); assert.equal(result.method, 'Browser.getBrowserCommandLine');
  });
  await test('missing automation uses passive SystemInfo fallback without launch changes', async () => {
    const calls = []; const result = await browserCommandLine({send: async method => {
      calls.push(method); if (method === 'Browser.getBrowserCommandLine') throw Error('Command line not returned because --enable-automation is not set');
      return {commandLine: SYSTEM_CHROME_EXECUTABLE + ' --user-data-dir=/tmp/synthetic'};
    }});
    assert.deepEqual(calls, ['Browser.getBrowserCommandLine', 'SystemInfo.getInfo']);
    assert.equal(result.method, 'SystemInfo.getInfo'); assert.equal(result.arguments[0], SYSTEM_CHROME_EXECUTABLE);
  });
  await test('unrelated CDP errors do not silently fallback', async () => {
    const calls = []; await assert.rejects(browserCommandLine({send: async method => {calls.push(method); throw Error('Target closed');}}), /Target closed/);
    assert.deepEqual(calls, ['Browser.getBrowserCommandLine']);
  });
  await test('missing fallback command-line identity fails closed', async () => {
    await assert.rejects(browserCommandLine({send: async method => {if (method === 'Browser.getBrowserCommandLine') throw Error('--enable-automation missing'); return {};}}), /command line/);
  });
  const identity = {expected_version: '154.0.1234.5', executable: SYSTEM_CHROME_EXECUTABLE};
  await test('exact launch identity required', () => {
    verifyIdentity(identity, identity.expected_version, {arguments: [SYSTEM_CHROME_EXECUTABLE]});
    assert.throws(() => verifyIdentity(identity, '154.0.1234.6', {arguments: [SYSTEM_CHROME_EXECUTABLE]}));
    assert.throws(() => verifyIdentity(identity, identity.expected_version, {arguments: ['/unreviewed/chrome']}));
  });
  await test('sandbox mute and autoplay bypass flags rejected from either CDP route', () => {
    for (const flag of ['--no-sandbox', '--disable-setuid-sandbox', '--mute-audio', '--autoplay-policy=no-user-gesture-required', '--disable-features=AutoplayIgnoreWebAudio', '--media-engagement=high']) {
      assert.throws(() => verifyIdentity(identity, identity.expected_version, {arguments: splitCommandLine(SYSTEM_CHROME_EXECUTABLE + ' "' + flag + '"')}));
    }
  });
  console.log(JSON.stringify({checks, failures: [], scope: 'Offline browser identity/command-line mocks only; no browser launch'}));
})().catch(error => {console.error(error); process.exitCode = 1;});
