'use strict';
// One ordinary exported-Web journey. Empty origin, natural wall time, real input.
// No fixtures, runtime hooks, launch flags, artificial guests, ticks or rewards.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const {hash, canonical, verifyExport, normalizedText} = require('./wall_compatibility_helpers');
const root = path.resolve(__dirname, '..');
const VIEWPORT = {width: 1360, height: 880};
const FLOW_MS = 220000;

function recognizeCue(file, phrases, tesseract, deadline, exactLabel = false) {
  assert(!exactLabel || phrases.length === 1, 'Exact button OCR requires one label');
  const result = {observed: '', matched: false, attempts: []};
  // Compact cards mix a main cue, small progress and an action label. Sparse
  // segmentation keeps those separate; block mode merged them in CI #100.
  // The fallback reads the SAME captured pixels with adaptive thresholding.
  for (const mode of ['sparse', 'sparse-sauvola']) {
    if (deadline - Date.now() < 1000) break;
    const args = [file, 'stdout', '-l', 'eng', '--psm', '11'];
    if (mode === 'sparse-sauvola') args.push('-c', 'thresholding_method=2');
    try {
      result.observed = cp.execFileSync(tesseract, args, {encoding: 'utf8',
        timeout: Math.min(5000, deadline - Date.now()), env: {...process.env, OMP_THREAD_LIMIT: '1'}, stdio: ['ignore', 'pipe', 'pipe']});
      result.attempts.push({mode, observed: result.observed});
      result.matched = exactLabel ? normalizedText(result.observed) === normalizedText(phrases[0])
        : phrases.every(text => (' ' + normalizedText(result.observed) + ' ').includes(' ' + normalizedText(text) + ' '));
      if (result.matched) break;
    } catch (error) {
      result.attempts.push({mode, error: String(error)});
      error.ocr_evidence = result;
      throw error;
    }
  }
  return result;
}

function cuePixelScale(region, requested = 1) {
  assert(requested === 1 || requested === 2, 'Only unchanged or exact 2x evidence pixels');
  // Moving actor cues require full-frame OCR. Apply one policy to every such
  // cue, while keeping native-bound static cards and the explicit Done crop.
  return region ? requested : 2;
}

function completionButtonRegion(stage) {
  const [x, y] = stage.point, [left, top, width, height] = stage.guide;
  // The existing native fixture verifies the active action is at least44×44.
  // Read only that centered target, inside the source-bound completion card.
  assert(x - 22 >= left && y - 22 >= top && x + 22 <= left + width && y + 22 <= top + height,
    'Completion action target must lie fully within its source-bound guide');
  return [x - 22, y - 22, 44, 44];
}

function validateLayout(result) {
  assert(result.checks > 0 && result.player_save_used === false);
  assert.deepEqual(result.failures, [], 'Engine tutorial fixture passed');
  const layout = result.web_layout;
  assert.deepEqual(layout?.viewport, [VIEWPORT.width, VIEWPORT.height]);
  assert(Number.isSafeInteger(layout.initial_coins) && layout.initial_coins > 0);
  assert(Number.isSafeInteger(layout.meal_payment) && layout.meal_payment > 0);
  const expected = {open: 0, staff: 1, staff_done: 2, decorate: 3, return: 4, order: 5, complete: 7};
  for (const [name, step] of Object.entries(expected)) {
    const stage = layout.stages?.[name];
    assert.equal(stage?.step, step, 'Engine-derived tutorial step ' + name);
    assert(typeof stage.text === 'string' && stage.text.length > 0);
    const r = stage.guide;
    assert(Array.isArray(r) && r.length === 4 && r.every(Number.isFinite));
    assert(r[0] >= 0 && r[1] >= 0 && r[2] > 0 && r[3] > 0 && r[0] + r[2] <= VIEWPORT.width && r[1] + r[3] <= VIEWPORT.height);
    if (name !== 'order') {
      const p = stage.point;
      assert(Array.isArray(p) && p.length === 2 && p.every(Number.isFinite));
      assert(p[0] >= 0 && p[0] < VIEWPORT.width && p[1] >= 0 && p[1] < VIEWPORT.height);
    }
  }
  return layout;
}

function validateBinding(web, resultFile, engineFile) {
  const commit = cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(cp.execFileSync('git', ['status', '--porcelain', '--untracked-files=no'], {cwd: root, encoding: 'utf8'}).trim(), '', 'Clean tracked source required');
  const engineBytes = fs.readFileSync(engineFile), engine = JSON.parse(engineBytes);
  const manifest = verifyExport(web, commit, {});
  assert.equal(manifest.test_report_sha256, hash(engineBytes), 'Exact full engine report bound by export');
  assert.equal(engine.source_commit, commit);
  assert.equal(engine.status, 'passed');
  const record = engine.records.filter(row => row.test === 'test_interactive_tutorial');
  assert.equal(record.length, 1);
  assert.equal(record[0].exit_code, 0);
  assert.deepEqual(record[0].failures, []);
  const resultBytes = fs.readFileSync(resultFile);
  assert.equal(record[0].result_sha256, hash(resultBytes), 'Coordinate receipt bound through engine aggregate and export');
  for (const name of ['tests/test_interactive_tutorial.gd', 'tests/run_integration_candidate.py', 'tests/fresh_tutorial_browser.js', 'tests/wall_compatibility_helpers.js']) {
    assert.equal(hash(fs.readFileSync(path.join(root, name))), engine.source_sha256[name], 'Exact tested harness source ' + name);
  }
  assert(Object.keys(manifest.production_sha256).length > 0);
  for (const [name, digest] of Object.entries(manifest.production_sha256)) {
    assert.equal(hash(fs.readFileSync(path.join(root, name))), digest, 'Exact exported production source ' + name);
    assert.equal(engine.source_sha256[name], digest, 'Production source passed engine aggregate ' + name);
  }
  const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
  assert(!html.includes('crazygames-sdk') && !html.includes('LittleLeafPlatform'), 'Ordinary Web export, not a platform variant');
  return {layout: validateLayout(JSON.parse(resultBytes)), source_commit: commit,
    engine_report_sha256: hash(engineBytes), layout_sha256: hash(resultBytes),
    export_manifest_sha256: hash(fs.readFileSync(path.join(web, 'release-manifest.json')))};
}

function summarize(ack) {
  if (!ack?.ok || typeof ack.payload !== 'string') return null;
  assert(Array.isArray(ack.inbox?.paid), 'Acknowledged save includes campaign receipt state');
  const saved = JSON.parse(ack.payload);
  return {revision: ack.revision, coins: saved.coins, served: saved.served, earned: saved.total_earned,
    wages: saved.total_wages_paid, open: saved.operating_open, tutorial: saved.tutorial,
    first_guest_pending: saved.first_guest_pending === true, items_sha256: hash(canonical(saved.items)),
    guests: saved.runtime.customers.map(g => ({id: g.id, phase: g.phase, seated: g.seated})),
    orders: saved.runtime.service.records.filter(r => r.order_done).map(r => r.guest_id),
    paid_campaigns: ack.inbox.paid};
}
function validateProgress(state, layout, initial) {
  assert.equal(state.earned, state.served * layout.meal_payment, 'Only genuine meal earnings');
  assert.equal(state.coins + state.wages, layout.initial_coins + state.earned, 'Wallet reconciles with genuine meals and normal wages');
  assert.deepEqual(state.paid_campaigns, [], 'Fresh profile receives no historical compensation');
  assert.equal(state.tutorial?.baseline_served, 0);
  assert(['active', 'completed'].includes(state.tutorial.status), 'Tutorial was never skipped');
  if (state.tutorial.step >= 7 || state.tutorial.status === 'completed') assert(state.served > 0, 'Completion requires genuine payment');
  if (initial) assert.equal(state.items_sha256, initial.items_sha256, 'Tutorial does not buy, move or create furniture');
}

async function main() {
  const arg = name => {
    const index = process.argv.indexOf('--' + name);
    assert(index >= 0 && process.argv[index + 1], '--' + name + ' is required');
    return path.resolve(process.argv[index + 1]);
  };
  const web = arg('web-build'), output = arg('output'), layoutFile = arg('layout-report'), engineFile = arg('engine-report');
  fs.mkdirSync(output, {recursive: true});
  const report = {status: 'running', browser_verified: false, fresh_context: true, player_save_used: false,
    launch_arguments: [], manual_ticks: false, forced_guests: false, gameplay_state_mutated_by_harness: false,
    state_observation: 'Readonly copies of production vault bootJson, updated only by genuine acknowledged saves',
    checks: [], snapshots: [], rendered_stages: {}, errors: []};
  let browser, server, page, started, flowDeadline;
  const check = (ok, label) => {assert(ok, label); report.checks.push(label);};
  const elapsed = () => ((Date.now() - started) / 1000);
  try {
    const binding = validateBinding(web, layoutFile, engineFile), layout = binding.layout;
    report.binding = binding;
    const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
    const channel = process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || 'chrome';
    assert.equal(require(path.join(process.env.PLAYWRIGHT_MODULE || 'playwright', 'package.json')).version, '1.63.0', 'Shared pinned Playwright');
    const tesseract = process.env.TESSERACT_BIN || 'tesseract';
    report.ocr_version = cp.execFileSync(tesseract, ['--version'], {encoding: 'utf8', timeout: 5000}).split('\n')[0];
    server = http.createServer((req, res) => {
      const pathname = new URL(req.url, 'http://localhost').pathname;
      if (pathname === '/empty') {res.setHeader('Content-Type', 'text/html'); return res.end('<title>Fresh origin check</title>');}
      const file = path.resolve(web, '.' + pathname);
      if (!file.startsWith(web + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404); return res.end();}
      res.setHeader('Content-Type', ({'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png'})[path.extname(file)] || 'application/octet-stream');
      res.end(fs.readFileSync(file));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    browser = await chromium.launch({headless: false, chromiumSandbox: true, channel});
    report.browser = {channel, version: browser.version(), playwright: '1.63.0', sandbox: true};
    const context = await browser.newContext({viewport: VIEWPORT, deviceScaleFactor: 1});
    // Keep the entire scenario on one isolated, foreground, localhost origin.
    const url = 'http://127.0.0.1:' + server.address().port;
    await context.route('**/*', route => new URL(route.request().url()).origin === url ? route.continue() : route.abort());
    page = await context.newPage();
    page.setDefaultTimeout(15000);
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => {if (/SCRIPT ERROR|ERROR:/.test(message.text())) report.errors.push(message.text());});
    await page.goto(url + '/empty');
    const empty = await page.evaluate(async () => ({databases: await indexedDB.databases(), local: localStorage.length, session: sessionStorage.length}));
    check(empty.databases.length === 0 && empty.local === 0 && empty.session === 0, 'Browser profile and origin contain no existing saves or seeded fixtures');
    started = Date.now(); flowDeadline = started + FLOW_MS;
    await page.goto(url + '/index.html');
    await page.waitForFunction(() => !document.getElementById('status') && window.__littleLeafVault?.bootJson, null, {timeout: 60000});
    const boot = await page.evaluate(() => JSON.parse(window.__littleLeafVault.bootJson));
    check(boot.ok && boot.source === 'fresh' && boot.revision === 0 && boot.payload === null, 'Unmodified exported shell boots a genuinely fresh ordinary-Web profile');
    let initial, lastRevision = -1;
    const snapshot = async () => {
      const state = summarize(await page.evaluate(() => JSON.parse(window.__littleLeafVault.bootJson)));
      if (state) {
        validateProgress(state, layout, initial);
        if (state.revision !== lastRevision) {lastRevision = state.revision; report.snapshots.push({wall_seconds: elapsed(), ...state});}
      }
      assert(report.errors.length === 0, 'Exported game raised a script/browser error');
      return state;
    };
    const waitState = async (name, predicate, limit = 30000) => {
      report.stage = name;
      const deadline = Math.min(flowDeadline, Date.now() + limit);
      do {
        const state = await snapshot();
        if (state && predicate(state)) return state;
        await page.waitForTimeout(250);
      } while (Date.now() < deadline);
      throw Error(name + ' did not reach the required genuine saved state within its bounded wait; last=' + JSON.stringify(report.snapshots.at(-1)));
    };
    const visible = async (name, phrases, region, limit = 25000, options = {}) => {
      report.stage = name;
      const deadline = Math.min(flowDeadline, Date.now() + limit);
      const clip = region ? {x: Math.floor(region[0]), y: Math.floor(region[1]), width: Math.min(VIEWPORT.width - Math.floor(region[0]), Math.ceil(region[2]) + 1), height: Math.min(VIEWPORT.height - Math.floor(region[1]), Math.ceil(region[3]) + 1)} : {x: 0, y: 0, ...VIEWPORT};
      const pixelScale = cuePixelScale(region, options.pixelScale ?? 1);
      const file = path.join(output, name + '-text.png');
      const evidence = report.rendered_stages[name] = {phrases, observed: '', attempts: 0, clip, ocr_attempts: [], matched: false, pixel_scale: pixelScale};
      do {
        // Preserve the last useful OCR result instead of beginning a capture
        // with only a few hundred milliseconds left and masking the cause.
        if (deadline - Date.now() < 1000) break;
        evidence.attempts++;
        await snapshot();
        if (deadline - Date.now() < 1000) break;
        try {
          const png = await page.screenshot({path: file, clip, timeout: Math.min(10000, deadline - Date.now())});
          let input = file;
          if (pixelScale === 2) {
            // Preserve the raw crop. Repeat each pixel in a detached canvas;
            // never alter the live game, its canvas, model or storage.
            const bytes = await page.evaluate(async base64 => {
              const raw = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
              const bitmap = await createImageBitmap(new Blob([raw], {type: 'image/png'}));
              const canvas = new OffscreenCanvas(bitmap.width * 2, bitmap.height * 2);
              const context = canvas.getContext('2d'); context.imageSmoothingEnabled = false;
              context.drawImage(bitmap, 0, 0, canvas.width, canvas.height); bitmap.close();
              return Array.from(new Uint8Array(await (await canvas.convertToBlob({type: 'image/png'})).arrayBuffer()));
            }, png.toString('base64'));
            input = path.join(output, name + '-ocr-input.png'); fs.writeFileSync(input, Buffer.from(bytes));
            evidence.pixel_scale = 2; evidence.ocr_input = input;
          }
          const ocr = recognizeCue(input, phrases, tesseract, deadline, options.exactLabel === true);
          if (ocr.attempts.length === 0) {evidence.ocr_budget_exhausted = true; break;}
          Object.assign(evidence, {observed: ocr.observed, matched: ocr.matched, ocr_attempts: ocr.attempts, wall_seconds: elapsed()});
          fs.writeFileSync(path.join(output, name + '.txt'), evidence.observed);
          if (evidence.matched) {
            await page.screenshot({path: path.join(output, name + '.png'), timeout: Math.max(1, Math.min(10000, deadline - Date.now()))});
            check(true, 'Actual rendered pixels show ' + name);
            return;
          }
        } catch (error) {
          if (error.ocr_evidence) Object.assign(evidence, {observed: error.ocr_evidence.observed, ocr_attempts: error.ocr_evidence.attempts});
          evidence.last_attempt_error = String(error);
          if (evidence.matched || (error.name !== 'TimeoutError' && error.code !== 'ETIMEDOUT')) throw error;
        }
        await page.waitForTimeout(150);
      } while (Date.now() < deadline);
      throw Error('Required rendered text was not detected for ' + name + ': ' + phrases.join(', ') + '; last OCR=' + JSON.stringify(evidence.observed) + (evidence.last_attempt_error ? '; last operation=' + evidence.last_attempt_error : ''));
    };
    const stage = name => layout.stages[name];
    const click = async name => {
      assert(Date.now() < flowDeadline, 'Whole fresh flow exceeded 220 seconds');
      report.stage = 'click-' + name;
      await page.mouse.click(...stage(name).point);
    };
    // Wait for the unskipped intro and the ordinary first autosave while CLOSED.
    await visible('fresh-closed', ['Tap to open', 'Skip'], stage('open').guide);
    initial = await waitState('first-closed-autosave', s => s.tutorial.step === 0);
    check(!initial.open && initial.served === 0 && initial.earned === 0 && initial.guests.length === 0 && initial.first_guest_pending, 'Fresh tutorial starts closed with no guests, orders or payment');
    await click('open');
    await visible('meet-team', [stage('staff').text], stage('staff').guide);
    await waitState('opened', s => s.open && s.tutorial.step === 1);
    await click('staff');
    await visible('staff-done', [stage('staff_done').text], stage('staff_done').guide);
    await waitState('staff-open', s => s.tutorial.step === 2);
    await click('staff_done');
    await visible('try-decorate', [stage('decorate').text], stage('decorate').guide);
    await waitState('staff-closed', s => s.tutorial.step === 3);
    await click('decorate');
    await visible('return-to-cafe', [stage('return').text], stage('return').guide);
    await waitState('decorating', s => s.tutorial.step === 4);
    await click('return');
    await waitState('returned-to-service', s => s.tutorial.step === 5);
    // The guest-following guide moves with the actual actor, so OCR the canvas
    // rather than guessing a fixed position or reading inaccessible engine state.
    // Both moving cues use the same lossless 2x evidence scaling as Done; the
    // untouched full frame remains alongside each separate OCR input.
    await visible('natural-arrival', ['Your waiter takes the order'], null, 45000);
    const order = await waitState('natural-order', s => s.tutorial.step === 6 && s.orders.length > 0 && s.guests.some(g => g.seated), 45000);
    check(order.served === 0 && order.earned === 0 && order.tutorial.status === 'active', 'A naturally seated guest has a genuine order, with no premature payment or tutorial completion');
    report.first_order_seconds = elapsed();
    await visible('natural-meal', ['Meal on the way'], null, 20000);
    const paid = await waitState('natural-payment', s => s.served > 0 && s.tutorial.step === 7, 150000);
    report.first_payment_seconds = elapsed();
    check(paid.tutorial.status === 'active', 'Genuine payment unlocks completion but does not dismiss the guide');
    await visible('first-order-complete', [stage('complete').text], stage('complete').guide);
    await visible('completion-done-button', ['Done'], completionButtonRegion(stage('complete')), 25000,
      {pixelScale: 2, exactLabel: true});
    await click('complete');
    const finished = await waitState('tutorial-completed', s => s.tutorial.status === 'completed' && s.tutorial.step === 7);
    check(finished.served === paid.served && finished.earned === paid.earned && finished.coins + finished.wages === paid.coins + paid.wages, 'Real final Done completes tutorial without an extra reward');
    check(finished.open, 'Completed tutorial leaves the cafe open for ordinary play');
    await page.screenshot({path: path.join(output, 'tutorial-completed.png')});
    check(report.errors.length === 0, 'No exported engine or browser errors');
    report.duration_seconds = elapsed(); report.status = 'passed'; report.browser_verified = true;
    await context.close();
  } catch (error) {
    report.status = 'failed'; report.error = error.stack; process.exitCode = 1;
    if (page && !page.isClosed()) try {await page.screenshot({path: path.join(output, 'failure-state.png'), timeout: 10000});} catch (captureError) {report.failure_capture_error = String(captureError);}
  } finally {
    if (browser) await browser.close();
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
    fs.writeFileSync(path.join(output, 'fresh-tutorial-browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
}
if (require.main === module) main();
module.exports = {validateLayout, validateBinding, summarize, validateProgress, recognizeCue, completionButtonRegion, cuePixelScale};
