'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {hash} = require('./wall_compatibility_helpers');
const {launchOptions, verifyBrowserArguments} = require('./welcome_audio_helpers');
const SYSTEM_CHROME_MAJOR = 154;
const SYSTEM_CHROME_EXECUTABLE = '/opt/google/chrome/chrome';
function systemChromeVersion(text) {
  const match = /^Google Chrome (154\.\d+\.\d+\.\d+)\s*$/.exec(text);
  assert(match, 'Official system Google Chrome major 154 required; no browser substitution');
  return match[1];
}
function browserIdentity(playwright, moduleDir, selection) {
  assert(['bundled-chromium', 'system-chrome'].includes(selection), 'Explicit supported browser selection required');
  if (selection === 'system-chrome') {
    assert(fs.statSync(SYSTEM_CHROME_EXECUTABLE).isFile(), 'Official system Chrome binary required');
    const installed = cp.execFileSync(SYSTEM_CHROME_EXECUTABLE, ['--version'], {encoding: 'utf8'}).trim();
    return {selection, channel: 'chrome', executable: SYSTEM_CHROME_EXECUTABLE,
      installed_version_text: installed, expected_version: systemChromeVersion(installed),
      executable_sha256: hash(fs.readFileSync(SYSTEM_CHROME_EXECUTABLE)),
      options: {...launchOptions(), channel: 'chrome'}};
  }
  const core = path.dirname(require.resolve('playwright-core/package.json', {paths: [moduleDir]}));
  const pin = JSON.parse(fs.readFileSync(path.join(core, 'browsers.json'))).browsers.find(row => row.name === 'chromium');
  assert(pin?.revision && pin.browserVersion, 'Pinned bundled Chromium metadata required');
  const executable = playwright.chromium.executablePath();
  assert(fs.existsSync(executable), 'Install the pinned bundled Chromium; no system browser fallback');
  return {selection, chromium_revision: pin.revision, executable, expected_version: pin.browserVersion, options: launchOptions()};
}
function splitCommandLine(text) {
  assert(typeof text === 'string' && text.trim(), 'Nonempty actual browser command line required');
  const args = []; let token = '', quote = null, escaped = false, started = false;
  for (const ch of text) {
    if (escaped) {token += ch; escaped = false; started = true; continue;}
    if (ch === '\\' && quote !== "'") {escaped = true; started = true; continue;}
    if (quote) {if (ch === quote) quote = null; else token += ch; started = true; continue;}
    if (ch === '"' || ch === "'") {quote = ch; started = true; continue;}
    if (/\s/.test(ch)) {if (started) args.push(token); token = ''; started = false; continue;}
    token += ch; started = true;
  }
  assert(!quote && !escaped, 'Unparseable actual browser command line');
  if (started) args.push(token);
  assert(args.length && args[0], 'Actual executable identity required');
  return args;
}
async function browserCommandLine(session) {
  try {
    const command = await session.send('Browser.getBrowserCommandLine');
    assert(Array.isArray(command.arguments) && command.arguments.length, 'Actual browser argument list required');
    return {method: 'Browser.getBrowserCommandLine', arguments: command.arguments};
  } catch (error) {
    if (!/enable-automation|command line.*not.*returned|method.*not found|wasn.t found|not supported/i.test(String(error))) throw error;
    const info = await session.send('SystemInfo.getInfo');
    return {method: 'SystemInfo.getInfo', arguments: splitCommandLine(info.commandLine),
      raw_command_line: info.commandLine, primary_error: String(error)};
  }
}
function verifyIdentity(identity, actualVersion, command) {
  assert.equal(actualVersion, identity.expected_version, 'Launched browser must match inspected exact installed version');
  assert.equal(command.arguments[0], identity.executable, 'Launched executable must match the explicitly inspected browser');
  verifyBrowserArguments(command.arguments);
}
module.exports = {SYSTEM_CHROME_MAJOR, SYSTEM_CHROME_EXECUTABLE, systemChromeVersion,
  browserIdentity, splitCommandLine, browserCommandLine, verifyIdentity};
