'use strict';
// CI-only actual-browser acceptance. Never run via an alternate access route
// after a local browser URL-policy denial. See welcome_audio_qa.md.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const {hash, requireVisibleText, normalizedText} = require('./wall_compatibility_helpers');
const {installWelcomeAudioObserver} = require('./welcome_audio_observer');
const {PLAYWRIGHT_VERSION, PREFERENCE_KEY, MODES, GESTURES, preferences,
  verifySource, gestureTime, sustainedSignal, compareTrials} = require('./welcome_audio_helpers');
const {browserIdentity, browserCommandLine, verifyIdentity} = require('./welcome_audio_browser_identity');
async function main() {
  const args = process.argv.slice(2);
  function option(name, fallback) {
    const index = args.indexOf(name);
    assert(index < 0 || args[index + 1] && !args[index + 1].startsWith('--'), 'Value required for ' + name);
    const value = index < 0 ? fallback : args[index + 1];
    assert(value, 'Required argument ' + name); return path.resolve(value);
  }
  const web = option('--web-build'), output = option('--output');
  const source = option('--source-root', path.resolve(__dirname, '..'));
  assert(!fs.existsSync(output), 'Fresh evidence directory required');
  fs.mkdirSync(output, {recursive: true});
  const report = {status: 'not-run', trials: [], errors: [], stream_identity: 'unproven',
    scope: 'Destination-bound WebAudio samples, context state and isolated BGM controls after trusted input. No speaker recording, human listening, MP3 reference match or device acceptance.',
    instrumentation: 'Parallel unconnected AnalyserNode taps only. Existing graph routes, gain, playback, context state and autoplay policy are not changed.',
    qa_source_commit: cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: __dirname, encoding: 'utf8'}).trim(),
    qa_sha256: Object.fromEntries(['welcome_audio_browser.js', 'welcome_audio_helpers.js', 'welcome_audio_observer.js', 'welcome_audio_browser_identity.js']
      .map(name => [name, hash(fs.readFileSync(path.join(__dirname, name)))]))};
  let server, browser;
  const persist = () => fs.writeFileSync(path.join(output, 'welcome-audio-browser.json'), JSON.stringify(report, null, 2));
  try {
    Object.assign(report, verifySource(web, source));
    // Do not include the large manifest twice; its bytes and complete map were checked above.
    delete report.manifest;
    const moduleName = process.env.PLAYWRIGHT_MODULE || 'playwright';
    const playwright = require(moduleName), moduleDir = path.dirname(require.resolve(moduleName));
    assert.equal(require(path.join(moduleDir, 'package.json')).version, PLAYWRIGHT_VERSION, 'Pinned Playwright package required');
    const identity = browserIdentity(playwright, moduleDir, process.env.WELCOME_AUDIO_BROWSER || 'bundled-chromium');
    server = http.createServer((req, res) => {
      const pathname = new URL(req.url, 'http://localhost').pathname;
      if (pathname === '/empty') {res.setHeader('Content-Type', 'text/html'); return res.end('<title>Disposable audio QA origin</title>');}
      const file = path.resolve(web, '.' + pathname);
      if (!file.startsWith(web + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404); return res.end();}
      res.setHeader('Content-Type', ({'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png'})[path.extname(file)] || 'application/octet-stream');
      res.setHeader('Cache-Control', 'no-store'); res.end(fs.readFileSync(file));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = 'http://127.0.0.1:' + server.address().port;
    report.browser_request = identity;
    browser = await playwright.chromium.launch(identity.options);
    const session = await browser.newBrowserCDPSession();
    let command;
    try {command = await browserCommandLine(session);} finally {await session.detach();}
    verifyIdentity(identity, browser.version(), command);
    report.browser = {playwright: PLAYWRIGHT_VERSION, ...identity,
      version: browser.version(), sandbox: true, ...command};
    for (const gesture of GESTURES) {
      for (const mode of MODES) {
        const context = await browser.newContext({viewport: {width: 1360, height: 880}, deviceScaleFactor: 1, hasTouch: gesture === 'touch'});
        const trial = {gesture, mode, preferences: preferences(mode), errors: [], blocked_requests: [], screenshots: []};
        report.trials.push(trial);
        let page;
        try {
          await context.route('**/*', route => {
            if (new URL(route.request().url()).origin === origin) return route.continue();
            trial.blocked_requests.push(route.request().url()); return route.abort();
          });
          page = await context.newPage();
          page.on('pageerror', error => trial.errors.push(String(error)));
          page.on('console', message => {if (/SCRIPT ERROR|ERROR:/.test(message.text())) trial.errors.push(message.text());});
          await page.goto(origin + '/empty');
          const empty = await page.evaluate(async () => ({databases: await indexedDB.databases(), local: localStorage.length, session: sessionStorage.length}));
          assert.deepEqual(empty, {databases: [], local: 0, session: 0}, 'Every trial starts in a new empty disposable profile');
          // Exact real preference envelope; no cafe/save/player fixture is seeded.
          await page.evaluate(({key, value}) => localStorage.setItem(key, JSON.stringify(value)), {key: PREFERENCE_KEY, value: trial.preferences});
          await context.addInitScript(installWelcomeAudioObserver);
          await page.goto(origin + '/index.html', {waitUntil: 'domcontentloaded'});
          await page.waitForFunction(() => {
            const raw = window.__welcomeAudioQA;
            return raw && raw.firstVisible !== null && raw.samples.some(row => row.at >= raw.firstVisible);
          }, null, {timeout: 90000});
          const read = () => page.evaluate(() => window.__welcomeAudioQA);
          async function screenshot(name) {
            const file = gesture.toLowerCase() + '-' + mode + '-' + name + '.png';
            const before = await page.evaluate(() => performance.now());
            await page.screenshot({path: path.join(output, file), animations: 'allow'});
            const after = await page.evaluate(() => performance.now());
            trial.screenshots.push({name, file, before, after, sha256: hash(fs.readFileSync(path.join(output, file)))});
          }
          trial.initial_boot = await page.evaluate(() => JSON.parse(window.__littleLeafVault.bootJson));
          assert.equal(trial.initial_boot.source, 'fresh');
          assert.equal(trial.initial_boot.payload, null);
          await screenshot('before-gesture');
          // Focus does not activate audio. Never click merely to focus for Enter.
          if (gesture === 'Enter') await page.locator('#canvas').focus();
          if (gesture === 'click') await page.mouse.click(680, 440);
          else if (gesture === 'touch') await page.touchscreen.tap(680, 440);
          else await page.keyboard.press('Enter');
          const at = gestureTime(await read(), gesture);
          if (mode === 'enabled') {
            let raw;
            do {
              await page.waitForTimeout(25); raw = await read();
              if (sustainedSignal(raw.samples, at + 50, at + 2200)) break;
            } while (await page.evaluate(() => performance.now()) < at + 2200);
          } else await page.waitForTimeout(700);
          await screenshot('early-welcome');
          const waitUntil = async time => {
            const now = await page.evaluate(() => performance.now());
            if (time > now) await page.waitForTimeout(time - now);
          };
          await waitUntil(at + 3000); await screenshot('during-descent');
          await waitUntil(at + 6500); await screenshot('after-normal-descent');
          trial.raw = await page.evaluate(() => {window.__welcomeAudioQA.stopped = true; return window.__welcomeAudioQA;});
          trial.boot = await page.evaluate(() => ({vault: JSON.parse(window.__littleLeafVault.bootJson), preferences: JSON.parse(window.__littleLeafPreferences.bootJson), cloud: typeof window.LittleLeafCloudSettings}));
          assert.equal(trial.boot.cloud, 'undefined', 'Ordinary Web only, no Firebase bridge');
          assert.equal(trial.boot.preferences.ok, true);
          assert.equal(trial.boot.preferences.source, 'preferences');
          // Godot may serialize CFG whitespace/numbers, so compare actual values.
          for (const [key, expected] of [['bgm_enabled', mode !== 'disabled'], ['sfx_enabled', false], ['bgm_volume', mode === 'zero' ? 0 : 70], ['sfx_volume', 0]]) {
            const match = trial.boot.preferences.text.match(new RegExp('^' + key + '\\s*=\\s*([^\\r\\n]+)', 'm'));
            assert(match, 'Loaded preference ' + key);
            assert.equal(typeof expected === 'boolean' ? match[1].trim() === 'true' : Number(match[1]), expected, 'Loaded preference value ' + key);
          }
          assert.deepEqual(trial.errors, []); assert.deepEqual(trial.blocked_requests, []);
          // OCR is deferred until after the real-time audio/visual capture.
          for (const name of ['before-gesture', 'early-welcome']) {
            const shot = trial.screenshots.find(row => row.name === name);
            const text = cp.execFileSync(process.env.TESSERACT_BIN || 'tesseract', [path.join(output, shot.file), 'stdout', '-l', 'eng', '--psm', '11'],
              {encoding: 'utf8', timeout: 10000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
            shot.ocr = text;
            requireVisibleText(text, name === 'early-welcome' ? ['Welcome to', 'Tap again'] : ['Welcome to', 'Esc to skip']);
          }
          const last = trial.screenshots.find(row => row.name === 'after-normal-descent');
          last.ocr = cp.execFileSync(process.env.TESSERACT_BIN || 'tesseract', [path.join(output, last.file), 'stdout', '-l', 'eng', '--psm', '11'],
            {encoding: 'utf8', timeout: 10000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
          assert(!normalizedText(last.ocr).includes('welcome to'), 'Welcome title must no longer appear after the normal descent');
          trial.status = 'captured';
        } catch (error) {
          trial.status = 'failed'; trial.error = String(error);
          if (page) trial.raw = await page.evaluate(() => {if (window.__welcomeAudioQA) window.__welcomeAudioQA.stopped = true; return window.__welcomeAudioQA;}).catch(() => null);
          throw error;
        } finally {await context.close(); persist();}
      }
    }
    report.comparisons = compareTrials(report.trials);
    report.status = 'passed-bgm-correlated-signal';
    report.visual_review = 'Screenshots retained; early welcome OCR checked. Human motion/appearance acceptance is separate.';
  } catch (error) {report.status = 'failed'; report.errors.push(String(error)); process.exitCode = 1;}
  finally {persist(); if (browser) await browser.close(); if (server) await new Promise(resolve => server.close(resolve));}
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {main};
