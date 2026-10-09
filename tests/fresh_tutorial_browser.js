'use strict';
// Short interactive guide, then an independent natural-service regression.
// Empty origin, normal wall time, real input throughout.
// No fixtures, runtime hooks, launch flags, artificial guests, ticks or rewards.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const {hash, canonical, verifyExport, normalizedText} = require('./wall_compatibility_helpers');
const root = path.resolve(__dirname, '..');
const VIEWPORT = {width: 1360, height: 880};
const SERVICE_MS = 220000, CUE_MS = 25000, SAVE_MS = 30000;
const COMPLETION_MS = CUE_MS * 2 + SAVE_MS;

function flowBudget(started, now = Date.now, hardDeadline = Infinity) {
  const serviceDeadline = Math.min(started + SERVICE_MS, hardDeadline);
  const overallDeadline = Math.min(started + SERVICE_MS + COMPLETION_MS, hardDeadline);
  let phaseDeadline = serviceDeadline, completing = false;
  const budget = {
    deadline: limit => Math.min(phaseDeadline, overallDeadline, now() + limit),
    remaining(deadline = phaseDeadline) {
      const left = Math.min(deadline, phaseDeadline, overallDeadline) - now();
      assert(left > 0, 'Fresh tutorial ' + (completing ? 'completion' : 'service') + ' deadline exceeded');
      return left;
    },
    startCompletion() {
      assert(!completing, 'Completion allowance cannot be restarted');
      budget.remaining(); // The initial observation phase must finish within its fixed cap.
      completing = true;
      phaseDeadline = Math.min(overallDeadline, now() + COMPLETION_MS);
      return phaseDeadline;
    },
  };
  return budget;
}

function matchesCue(observed, phrases, exactLabel = false) {
  return exactLabel ? normalizedText(observed) === normalizedText(phrases[0])
    : phrases.every(text => (' ' + normalizedText(observed) + ' ').includes(' ' + normalizedText(text) + ' '));
}

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
      result.matched = matchesCue(result.observed, phrases, exactLabel);
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
  const expected = {open: 0, staff: 1, staff_done: 2, decorate: 3, return: 4, order: 5, payment: 6, complete: 7};
  for (const [name, step] of Object.entries(expected)) {
    const stage = layout.stages?.[name];
    assert.equal(stage?.step, step, 'Engine-derived tutorial step ' + name);
    assert(typeof stage.text === 'string' && stage.text.length > 0);
    const r = stage.guide;
    assert(Array.isArray(r) && r.length === 4 && r.every(Number.isFinite));
    assert(r[0] >= 0 && r[1] >= 0 && r[2] > 0 && r[3] > 0 && r[0] + r[2] <= VIEWPORT.width && r[1] + r[3] <= VIEWPORT.height);
    {
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
  assert(Number.isInteger(state.tutorial.step) && state.tutorial.step >= 0 && state.tutorial.step <= 7, 'Known tutorial step');
  if (state.tutorial.status === 'completed') assert.equal(state.tutorial.step, 7, 'Done belongs to the final explanation');
  if (initial) assert.equal(state.items_sha256, initial.items_sha256, 'Tutorial does not buy, move or create furniture');
}

function hasSeatedOrder(state) {
  return state.guests.some(g => g.seated && state.orders.includes(g.id));
}
function validateNaturalPayment(state, order, layout, initial) {
  validateProgress(order, layout, initial); validateProgress(state, layout, initial);
  assert.equal(order.tutorial.status, 'completed', 'Natural-service regression follows tutorial completion');
  assert(hasSeatedOrder(order), 'An actual seated order precedes payment');
  assert(state.served > order.served, 'Independent natural-service gate requires a new genuine payment');
  assert.equal(state.earned - order.earned, (state.served - order.served) * layout.meal_payment,
    'Natural payment earns exactly the real meal value');
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
  let browser, server, page, started, budget;
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
    started = Date.now(); budget = flowBudget(started);
    report.budget_ms = {service: SERVICE_MS, completion: COMPLETION_MS, overall: SERVICE_MS + COMPLETION_MS};
    await page.goto(url + '/index.html');
    await page.waitForFunction(() => !document.getElementById('status') && window.__littleLeafVault?.bootJson, null, {timeout: 60000});
    const boot = await page.evaluate(() => JSON.parse(window.__littleLeafVault.bootJson));
    check(boot.ok && boot.source === 'fresh' && boot.revision === 0 && boot.payload === null, 'Unmodified exported shell boots a genuinely fresh ordinary-Web profile');
    check(await page.evaluate(() => window.LittleLeafCloudSettings === undefined) && report.errors.length === 0, 'Ordinary Web starts without a Firebase bridge or missing-interface engine errors');
    let initial, lastRevision = -1;
    const snapshot = async signal => {
      const ack = await page.evaluate(() => JSON.parse(window.__littleLeafVault.bootJson));
      signal?.throwIfAborted();
      const state = summarize(ack);
      if (state) {
        validateProgress(state, layout, initial);
        if (state.revision !== lastRevision) {lastRevision = state.revision; report.snapshots.push({wall_seconds: elapsed(), ...state});}
      }
      assert(report.errors.length === 0, 'Exported game raised a script/browser error');
      return state;
    };
    const waitState = async (name, predicate, limit = SAVE_MS) => {
      report.stage = name;
      const deadline = budget.deadline(limit);
      while (Date.now() < deadline) {
        const state = await snapshot();
        budget.remaining(deadline);
        if (state && predicate(state)) return state;
        await page.waitForTimeout(250);
      }
      throw Error(name + ' did not reach the required genuine saved state within its bounded wait; last=' + JSON.stringify(report.snapshots.at(-1)));
    };
    const scalePixels = png => page.evaluate(async base64 => {
      const raw = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
      const bitmap = await createImageBitmap(new Blob([raw], {type: 'image/png'}));
      const canvas = new OffscreenCanvas(bitmap.width * 2, bitmap.height * 2);
      const context = canvas.getContext('2d'); context.imageSmoothingEnabled = false;
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height); bitmap.close();
      return Array.from(new Uint8Array(await (await canvas.convertToBlob({type: 'image/png'})).arrayBuffer()));
    }, png.toString('base64'));
    const visible = async (name, phrases, region, limit = CUE_MS, options = {}) => {
      report.stage = name;
      const deadline = budget.deadline(limit);
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
            const bytes = await scalePixels(png);
            input = path.join(output, name + '-ocr-input.png'); fs.writeFileSync(input, Buffer.from(bytes));
            evidence.pixel_scale = 2; evidence.ocr_input = input;
          }
          const ocr = recognizeCue(input, phrases, tesseract, deadline, options.exactLabel === true);
          if (ocr.attempts.length === 0) {evidence.ocr_budget_exhausted = true; break;}
          Object.assign(evidence, {observed: ocr.observed, matched: ocr.matched, ocr_attempts: ocr.attempts, wall_seconds: elapsed()});
          fs.writeFileSync(path.join(output, name + '.txt'), evidence.observed);
          if (evidence.matched) {
            await page.screenshot({path: path.join(output, name + '.png'), timeout: Math.max(1, Math.min(10000, deadline - Date.now()))});
            budget.remaining(deadline);
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
      if (evidence.ocr_attempts.length === 0 && deadline - Date.now() < 1000) evidence.ocr_budget_exhausted = true;
      const failure = evidence.ocr_budget_exhausted ? 'OCR budget exhausted for ' : 'Required rendered text was not detected for ';
      throw Error(failure + name + ': ' + phrases.join(', ') + '; OCR attempts=' + evidence.ocr_attempts.length + '; last OCR=' + JSON.stringify(evidence.observed) + (evidence.last_attempt_error ? '; last operation=' + evidence.last_attempt_error : ''));
    };
    const stage = name => layout.stages[name];
    const click = async name => {
      budget.remaining();
      report.stage = 'click-' + name;
      await page.mouse.click(...stage(name).point);
      budget.remaining();
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
    await visible('service-explanation', [stage('order').text], stage('order').guide);
    await visible('service-next-button', ['Next'], completionButtonRegion(stage('order')), CUE_MS,
      {pixelScale: 2, exactLabel: true});
    await waitState('service-explanation-saved', s => s.tutorial.step === 5);
    await click('order');
    await visible('checkout-explanation', [stage('payment').text], stage('payment').guide);
    await visible('checkout-next-button', ['Next'], completionButtonRegion(stage('payment')), CUE_MS,
      {pixelScale: 2, exactLabel: true});
    await waitState('checkout-explanation-saved', s => s.tutorial.step === 6);
    await click('payment');
    await waitState('guide-ready', s => s.tutorial.step === 7);
    report.completion_deadline_seconds = (budget.startCompletion() - started) / 1000;
    await visible('guide-ready-to-play', [stage('complete').text], stage('complete').guide);
    await visible('completion-done-button', ['Done'], completionButtonRegion(stage('complete')), CUE_MS,
      {pixelScale: 2, exactLabel: true});
    await click('complete');
    const finished = await waitState('tutorial-completed', s => s.tutorial.status === 'completed' && s.tutorial.step === 7);
    // Background service may run while the guide is read. Economic reconciliation
    // rejects any extra tutorial reward without pretending genuine meals freeze.
    validateProgress(finished, layout, initial);
    check(finished.open, 'Completed tutorial leaves the cafe open for ordinary play');
    report.tutorial_completed_seconds = elapsed();
    report.tutorial_completion = {requires_order: false, requires_payment: false, served: finished.served};
    await page.screenshot({path: path.join(output, 'tutorial-completed.png'), timeout: Math.min(10000, budget.remaining())});
    budget.remaining();

    // This separate test must still witness a real seated order and subsequent
    // checkout. It cannot delay the player's Next/Done or synthesize any work.
    const naturalStarted = Date.now();
    // Separate service evidence never extends the original five-minute cap.
    budget = flowBudget(naturalStarted, Date.now, started + SERVICE_MS + COMPLETION_MS);
    const order = await waitState('independent-natural-order', s => hasSeatedOrder(s), 90000);
    check(order.tutorial.status === 'completed', 'Natural-service observation starts after the tutorial is dismissed');
    await page.screenshot({path: path.join(output, 'natural-order-after-tutorial.png'), timeout: Math.min(10000, budget.remaining())});
    const paid = await waitState('natural-payment', s => s.served > order.served, 150000);
    validateNaturalPayment(paid, order, layout, initial);
    check(true, 'Independent natural-service gate observed an actual order and genuine payment');
    report.natural_service = {status: 'passed', seconds: (Date.now() - naturalStarted) / 1000,
      ordered_served: order.served, paid_served: paid.served, earned_delta: paid.earned - order.earned};
    report.first_payment_seconds = elapsed();
    await page.screenshot({path: path.join(output, 'natural-payment-after-tutorial.png'), timeout: Math.min(10000, budget.remaining())});
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
module.exports = {validateLayout, validateBinding, summarize, validateProgress, validateNaturalPayment, recognizeCue, completionButtonRegion, cuePixelScale, flowBudget, matchesCue};
