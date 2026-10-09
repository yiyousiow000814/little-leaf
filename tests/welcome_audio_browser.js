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
  verifySource, classifyActivation, activationCoverage, compareTrials} = require('./welcome_audio_helpers');
const {capturePhases, captureReadyBaseline} = require('./welcome_audio_capture');
const {passiveReader, waitForPassive, failureKind, recordPageLogs} = require('./welcome_audio_driver');
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
  const report = {status: 'not-run', trials: [], visual_trials: [], errors: [], stream_identity: 'unproven',
    scope: 'Destination-bound WebAudio samples, context state and isolated BGM controls after trusted input. Early pixels are captured in separate source-bound visual-only profiles: no same-profile early image/audio proof. No speaker recording, human listening, MP3 reference match or device acceptance.',
    instrumentation: 'Parallel unconnected AnalyserNode taps only. Existing graph routes, gain, playback, context state and autoplay policy are not changed.',
    qa_source_commit: cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: __dirname, encoding: 'utf8'}).trim(),
    qa_sha256: Object.fromEntries(['welcome_audio_browser.js', 'welcome_audio_helpers.js', 'welcome_audio_observer.js', 'welcome_audio_browser_identity.js', 'welcome_audio_capture.js', 'welcome_audio_driver.js', 'welcome_audio_ocr.py']
      .map(name => [name, hash(fs.readFileSync(path.join(__dirname, name)))]))};
  let server, browser, phase;
  const log = row => fs.appendFileSync(path.join(output, 'browser-events.jsonl'), JSON.stringify({utc: new Date().toISOString(), ...row}) + '\n');
  const stage = (name, trial) => {phase = name; report.phase = name; if (trial) trial.phase = name; log({kind: 'phase', phase: name, profile_kind: trial?.profile_kind, gesture: trial?.gesture, mode: trial?.mode});};
  const persist = () => fs.writeFileSync(path.join(output, 'welcome-audio-browser.json'), JSON.stringify(report, null, 2));
  try {
    stage('source-verification');
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
    stage('browser-launch');
    browser = await playwright.chromium.launch(identity.options);
    stage('browser-identity');
    const session = await browser.newBrowserCDPSession();
    let command;
    try {command = await browserCommandLine(session);} finally {await session.detach();}
    verifyIdentity(identity, browser.version(), command);
    report.browser = {playwright: PLAYWRIGHT_VERSION, ...identity,
      version: browser.version(), sandbox: true, ...command};
    for (const profile_kind of ['audio-measurement', 'visual-only']) {
      for (const gesture of GESTURES) {
        for (const mode of MODES) {
          const context = await browser.newContext({viewport: {width: 1360, height: 880}, deviceScaleFactor: 1, hasTouch: gesture === 'touch'});
          const trial = {profile_kind, gesture, mode, preferences: preferences(mode), errors: [], blocked_requests: [], screenshots: []};
          (profile_kind === 'audio-measurement' ? report.trials : report.visual_trials).push(trial);
          let page, observe, pageSession;
          try {
            await context.route('**/*', route => {
              if (new URL(route.request().url()).origin === origin) return route.continue();
              trial.blocked_requests.push(route.request().url()); return route.abort();
            });
            page = await context.newPage();
            recordPageLogs(page, row => log({profile_kind, gesture, mode, ...row}), trial.errors);
            pageSession = await context.newCDPSession(page);
            observe = passiveReader(pageSession);
            stage('fresh-profile', trial);
            await page.goto(origin + '/empty');
            const empty = await observe(async () => ({databases: await indexedDB.databases(), local: localStorage.length, session: sessionStorage.length}));
            assert.deepEqual(empty, {databases: [], local: 0, session: 0}, 'Every trial starts in a new empty disposable profile');
            // Exact real preference envelope; no cafe/save/player fixture is seeded.
            await observe(({key, value}) => localStorage.setItem(key, JSON.stringify(value)), {key: PREFERENCE_KEY, value: trial.preferences});
            await context.addInitScript(installWelcomeAudioObserver);
            await page.goto(origin + '/index.html', {waitUntil: 'domcontentloaded'});
            // Focus before readiness, never by clicking or inside the timed phase.
            if (gesture === 'Enter') await page.locator('#canvas').focus();
            stage('readiness', trial);
            await waitForPassive(observe, captureReadyBaseline);
            const read = () => observe(() => window.__welcomeAudioQA);
            async function screenshot(name) {
              const file = profile_kind + '-' + gesture.toLowerCase() + '-' + mode + '-' + name + '.png';
              const before = await observe(() => performance.now());
              await page.screenshot({path: path.join(output, file), animations: 'allow'});
              const after = await observe(() => performance.now());
              trial.screenshots.push({profile_kind, name, file, before, after, sha256: hash(fs.readFileSync(path.join(output, file)))});
            }
            stage('gesture-capture', trial);
            await capturePhases(trial, {
              now: () => observe(() => performance.now()),
              wait: ms => page.waitForTimeout(ms), read, shot: screenshot,
              press: async input => {
                if (input === 'click') await page.mouse.click(680, 440);
                else if (input === 'touch') await page.touchscreen.tap(680, 440);
                else await page.keyboard.press('Enter');
              },
              stopAndRead: () => observe(() => {
                const raw = window.__welcomeAudioQA;
                raw.stopped = true; raw.stoppedAt = performance.now(); return raw;
              }),
            });
            if (profile_kind === 'audio-measurement')
              trial.activation = classifyActivation(trial.raw, trial.phase_timestamps.gesture);
            trial.phase_timestamps.initial_boot_capture = trial.raw.initial_boot_snapshot.at;
            assert(trial.phase_timestamps.initial_boot_capture <= trial.phase_timestamps.gesture, 'Fresh boot evidence must precede input');
            trial.initial_boot = trial.raw.initial_boot_snapshot.value;
            trial.phase_timestamps.final_boot_read = await observe(() => performance.now());
            assert.equal(trial.initial_boot.source, 'fresh');
            assert.equal(trial.initial_boot.payload, null);
            trial.boot = await observe(() => ({vault: JSON.parse(window.__littleLeafVault.bootJson), preferences: JSON.parse(window.__littleLeafPreferences.bootJson), cloud: typeof window.LittleLeafCloudSettings}));
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
            stage('visual-ocr', trial);
            for (const name of profile_kind === 'visual-only' ? ['before-gesture', 'early-welcome'] : []) {
              const shot = trial.screenshots.find(row => row.name === name);
              const text = cp.execFileSync(process.env.TESSERACT_BIN || 'tesseract', [path.join(output, shot.file), 'stdout', '-l', 'eng', '--psm', '11'],
                {encoding: 'utf8', timeout: 10000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
              shot.ocr = text;
              requireVisibleText(text, ['Welcome to']);
              // Whole-screen sparse OCR misses the small bottom hint next to
              // the large illustrated logo. Read its exact-pixel crop instead.
              const hintFile = shot.file.replace(/\.png$/, '-hint.png');
              shot.hint_crop = JSON.parse(cp.execFileSync(process.env.PYTHON_BIN || 'python3',
                [path.join(__dirname, 'welcome_audio_ocr.py'), path.join(output, shot.file), path.join(output, hintFile)], {encoding: 'utf8', timeout: 10000}));
              shot.hint_ocr = cp.execFileSync(process.env.TESSERACT_BIN || 'tesseract',
                [path.join(output, hintFile), 'stdout', '-l', 'eng', '--psm', '7'],
                {encoding: 'utf8', timeout: 10000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
              requireVisibleText(shot.hint_ocr, name === 'early-welcome' ? ['Tap again', 'Esc to skip'] : ['Tap or press Enter to enter', 'Esc to skip']);
            }
            if (profile_kind === 'audio-measurement') {
              const last = trial.screenshots.find(row => row.name === 'after-normal-descent');
              last.ocr = cp.execFileSync(process.env.TESSERACT_BIN || 'tesseract', [path.join(output, last.file), 'stdout', '-l', 'eng', '--psm', '11'],
                {encoding: 'utf8', timeout: 10000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
              assert(!normalizedText(last.ocr).includes('welcome to'), 'Welcome title must no longer appear after the normal descent');
            }
            trial.status = 'captured';
          } catch (error) {
            trial.status = 'failed'; trial.error = String(error); trial.failure_kind = failureKind(error, phase); trial.stack = error.stack;
            log({kind: 'trial-failure', profile_kind, gesture, mode, phase, failure_kind: trial.failure_kind, error: String(error), stack: error.stack});
            if (observe && !trial.raw) trial.raw = await observe(() => {
              if (window.__welcomeAudioQA) {window.__welcomeAudioQA.stopped = true; window.__welcomeAudioQA.stoppedAt = performance.now();}
              return window.__welcomeAudioQA;
            }).catch(() => null);
            throw error;
          } finally {persist(); await context.close(); persist();}
        }
      }
    }
    stage('audio-comparison');
    report.comparisons = compareTrials(report.trials);
    report.activation_coverage = activationCoverage(report.comparisons);
    assert.equal(report.visual_trials.filter(row => row.status === 'captured').length, GESTURES.length * MODES.length, 'All independent visual profiles required');
    report.status = report.activation_coverage.observed_path === 'gesture-unlocked'
      ? 'passed-gesture-unlocked-signal-settings' : 'passed-default-autoplay-signal-settings';
    report.visual_review = 'Early welcome/hint OCR checked only in independent visual-only profiles. Later descent images belong to measured profiles after measurement stopped. No same-profile early image/audio proof; human motion/appearance acceptance is separate.';
  } catch (error) {report.status = 'failed'; report.failure_kind = failureKind(error, phase); report.errors.push(String(error)); report.stack = error.stack; log({kind: 'failure', phase, failure_kind: report.failure_kind, error: String(error), stack: error.stack}); console.error(error.stack || String(error)); process.exitCode = 1;}
  finally {persist(); try {if (browser) await browser.close();} finally {if (server) await new Promise(resolve => server.close(resolve)); report.cleanup = {browser_closed: !browser || !browser.isConnected(), server_closed: !server || !server.listening}; persist();}}
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {main};
