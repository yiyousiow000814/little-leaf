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
const SERVICE_MS = 220000, CUE_MS = 25000, SAVE_MS = 30000;
const COMPLETION_MS = CUE_MS * 2 + SAVE_MS;

function flowBudget(started, now = Date.now) {
  const serviceDeadline = started + SERVICE_MS;
  const overallDeadline = serviceDeadline + COMPLETION_MS;
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
      budget.remaining(); // Payment must arrive within the unchanged service cap.
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

// One OCR process at a time, outside the capture loop. Both exact moving labels
// are inspected on the same immutable frame; neither can stand in for the other.
const MOVING_PHRASES = ['Your waiter takes the order', 'Meal on the way'];
async function recognizeMovingFrame(file, tesseract, deadline, signal) {
  const result = {observed: '', matches: [], attempts: []};
  for (const mode of ['sparse', 'sparse-sauvola']) {
    signal?.throwIfAborted();
    if (deadline - Date.now() < 1000) break;
    const args = [file, 'stdout', '-l', 'eng', '--psm', '11'];
    if (mode === 'sparse-sauvola') args.push('-c', 'thresholding_method=2');
    try {
      result.observed = await new Promise((resolve, reject) => cp.execFile(tesseract, args,
        {encoding: 'utf8', timeout: Math.min(5000, deadline - Date.now()),
          env: {...process.env, OMP_THREAD_LIMIT: '1'}, maxBuffer: 1024 * 1024, signal},
        (error, stdout) => error ? reject(error) : resolve(stdout)));
      result.attempts.push({mode, observed: result.observed});
      result.matches = MOVING_PHRASES.filter(text => matchesCue(result.observed, [text]));
      if (result.matches.length) break;
    } catch (error) {
      result.attempts.push({mode, error: String(error)});
      error.ocr_evidence = result;
      signal?.throwIfAborted();
      // Preserve this uniquely captured frame after a recoverable first-mode
      // timeout: the same pixels still get their bounded adaptive attempt.
      if (error.name !== 'TimeoutError' && error.code !== 'ETIMEDOUT' && !error.killed) throw error;
    }
  }
  return result;
}

async function observeMovingCues({budget, binding, capture, recognize, snapshot, sleep,
  evidence, now = Date.now}) {
  const began = now(), arrivalDeadline = budget.deadline(45000), returnDeadline = budget.deadline(SAVE_MS);
  const bindingHash = hash(canonical(binding));
  assert(/^[a-f0-9]{40}$/.test(binding.source_commit), 'Moving frames require the verified source binding');
  for (const name of ['engine_report_sha256', 'layout_sha256', 'export_manifest_sha256'])
    assert(/^[a-f0-9]{64}$/.test(binding[name]), 'Moving frames require verified ' + name);
  // Worst case: arrival45s + order45s + meal20s, still inside service220s.
  // PNGs live on disk; retain every capture, with only one OCR process in flight.
  Object.assign(evidence, {binding_sha256: bindingHash, capture_interval_ms: 500,
    max_frames: 220, max_bytes: 128 * 1024 * 1024, bytes: 0, frames: [], cues: {}});
  let returned, order, orderDeadline, mealDeadline, replayThrough, stopped = false, failure;
  const cancellation = new AbortController();
  const observedAll = Error('Moving cue observations complete');
  // page.evaluate has no Playwright operation timeout. Bound every asynchronous
  // adapter as well as the subprocess; abort a peer immediately on failure.
  const bounded = (operation, end) => new Promise((resolve, reject) => {
    const signal = cancellation.signal;
    let timer;
    const cleanup = () => {clearTimeout(timer); signal.removeEventListener('abort', abort);};
    const abort = () => {cleanup(); reject(signal.reason);};
    if (signal.aborted) {abort(); return;}
    signal.addEventListener('abort', abort, {once: true});
    timer = setTimeout(() => {cleanup(); reject(Error('Moving cue operation deadline exceeded'));}, budget.remaining(end));
    Promise.resolve().then(() => operation(signal)).then(value => {cleanup(); resolve(value);},
      error => {cleanup(); reject(error);});
  });
  const complete = () => returned && order && MOVING_PHRASES.every(text => evidence.cues[text]);
  const limits = () => [!returned && returnDeadline, !evidence.cues[MOVING_PHRASES[0]] && arrivalDeadline,
    !order && orderDeadline, order && !evidence.cues[MOVING_PHRASES[1]] && mealDeadline].filter(Number.isFinite);
  const deadline = () => Math.min(budget.deadline(110000), ...limits());
  const enforce = () => {
    budget.remaining();
    for (const end of limits()) budget.remaining(end);
  };
  const remember = state => {
    if (!state) return;
    if (!returned && state.tutorial.step === 5) {
      budget.remaining(returnDeadline); returned = state;
      evidence.returned_to_service_ms = now() - began;
    }
    if (!order && state.tutorial.step === 6 && state.orders.length > 0 && state.guests.some(g => g.seated)) {
      if (orderDeadline) budget.remaining(orderDeadline);
      order = state; mealDeadline = budget.deadline(20000);
      replayThrough = evidence.frames.length;
      evidence.first_order_ms = now() - began;
    }
  };
  const verifyFrame = frame => {
    assert.equal(frame.binding_sha256, bindingHash, 'Captured frame belongs to this exact source/export');
    assert.equal(hash(fs.readFileSync(frame.file)), frame.sha256, 'Retained raw frame bytes are unchanged');
  };
  const captureLoop = async () => {
    while (!stopped && !complete()) {
      enforce();
      assert(evidence.frames.length < evidence.max_frames, 'Moving cue frame limit exceeded');
      const before = await bounded(snapshot, deadline()); remember(before); enforce();
      if (complete()) break;
      const index = evidence.frames.length + 1, captureStarted = now();
      const captureDeadline = deadline();
      const frame = await bounded(signal => capture(index, captureDeadline, signal), captureDeadline);
      enforce();
      Object.assign(frame, {index, binding_sha256: bindingHash, capture_started_ms: captureStarted - began,
        captured_ms: now() - began, before_revision: before?.revision ?? null});
      verifyFrame(frame);
      evidence.bytes += fs.statSync(frame.file).size;
      assert(evidence.bytes <= evidence.max_bytes, 'Moving cue evidence byte limit exceeded');
      evidence.frames.push(frame);
      const after = await bounded(snapshot, deadline()); frame.after_revision = after?.revision ?? null; remember(after); enforce();
      if (!complete()) await bounded(() => sleep(Math.min(evidence.capture_interval_ms, budget.remaining(deadline()))), deadline());
    }
  };
  const recognizeLoop = async () => {
    while (!stopped && !complete()) {
      enforce();
      if (MOVING_PHRASES.every(text => evidence.cues[text])) {await bounded(() => sleep(25), deadline()); continue;}
      const pending = evidence.frames.filter(frame => !frame.ocr);
      // Once the ordinary acknowledged order arrives, revisit preceding frames
      // newest first. Slow OCR must not discard a short cue it did not yet read.
      const frame = (!evidence.cues[MOVING_PHRASES[0]] && replayThrough !== undefined
        ? pending.filter(item => item.index <= replayThrough).at(-1) : null) || pending.at(-1);
      if (!frame) {await bounded(() => sleep(25), deadline()); continue;}
      verifyFrame(frame);
      const recognitionDeadline = deadline();
      try {
        frame.ocr = await bounded(signal => recognize(frame, recognitionDeadline, signal), recognitionDeadline);
      } catch (error) {
        if (error === observedAll) throw error;
        frame.ocr = error.ocr_evidence || {attempts: []};
        frame.ocr.error = String(error);
        if (error.name !== 'TimeoutError' && error.code !== 'ETIMEDOUT' && !error.killed) throw error;
      }
      frame.recognized_ms = now() - began;
      verifyFrame(frame);
      if (frame.ocr_input) {
        assert.equal(hash(fs.readFileSync(frame.ocr_input)), frame.ocr_input_sha256, 'OCR input bytes are unchanged');
        evidence.bytes += fs.statSync(frame.ocr_input).size;
        assert(evidence.bytes <= evidence.max_bytes, 'Moving cue evidence byte limit exceeded');
      }
      enforce(); // Late recognition cannot unlock a new allowance.
      for (const phrase of MOVING_PHRASES) {
        // Inspect the retained OCR text ourselves, never trust a callback's flag.
        const attempt = frame.ocr.attempts.find(item => typeof item.observed === 'string' && matchesCue(item.observed, [phrase]));
        if (!attempt || evidence.cues[phrase]) continue;
        evidence.cues[phrase] = {frame: frame.index, file: frame.file, sha256: frame.sha256,
          captured_ms: frame.captured_ms, recognized_ms: frame.recognized_ms, observed: attempt.observed};
        if (phrase === MOVING_PHRASES[0]) orderDeadline = budget.deadline(45000);
      }
    }
  };
  const guarded = async fn => {
    try {await fn();} catch (error) {
      if (error !== observedAll) {failure ||= error; cancellation.abort(failure);}
    } finally {
      stopped = true;
      if (complete() && !failure) cancellation.abort(observedAll);
    }
  };
  await Promise.all([guarded(captureLoop), guarded(recognizeLoop)]);
  evidence.duration_ms = now() - began;
  if (failure) throw failure;
  enforce();
  assert(complete(), 'Both exact moving cues and genuine returned/order saves are required');
  assert(evidence.cues[MOVING_PHRASES[0]].frame < evidence.cues[MOVING_PHRASES[1]].frame,
    'The waiter cue must precede the independent meal frame');
  return {returned, order};
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
    // Capture immediately after the real return click, before waiting for its
    // acknowledged save. OCR runs concurrently; gameplay is never suspended.
    report.stage = 'natural-moving-cues';
    const moving = report.moving_cues = {};
    const movingStarted = elapsed();
    const {order} = await observeMovingCues({budget, binding, snapshot,
      evidence: moving, sleep: ms => page.waitForTimeout(ms),
      capture: async (index, deadline, signal) => {
        const file = path.join(output, 'moving-' + String(index).padStart(3, '0') + '.png');
        const bytes = await page.screenshot({timeout: Math.min(10000, budget.remaining(deadline))});
        signal.throwIfAborted();
        fs.writeFileSync(file, bytes);
        return {file, sha256: hash(bytes)};
      },
      recognize: async (frame, deadline, signal) => {
        const bytes = await scalePixels(fs.readFileSync(frame.file));
        signal.throwIfAborted();
        frame.ocr_input = frame.file.replace(/\.png$/, '-2x.png');
        fs.writeFileSync(frame.ocr_input, Buffer.from(bytes));
        frame.ocr_input_sha256 = hash(Buffer.from(bytes));
        return recognizeMovingFrame(frame.ocr_input, tesseract, deadline, signal);
      },
    });
    for (const [index, name] of ['natural-arrival', 'natural-meal'].entries()) {
      const phrase = MOVING_PHRASES[index], cue = moving.cues[phrase];
      const frame = moving.frames.find(item => item.index === cue.frame);
      report.rendered_stages[name] = {...cue, phrases: [phrase], matched: true,
        pixel_scale: 2, ocr_input: frame.ocr_input, ocr_input_sha256: frame.ocr_input_sha256,
        ocr_attempts: frame.ocr.attempts, wall_seconds: movingStarted + cue.captured_ms / 1000};
      // These aliases copy the matched frame, never a later screenshot.
      fs.copyFileSync(frame.file, path.join(output, name + '-text.png'));
      fs.copyFileSync(frame.ocr_input, path.join(output, name + '-ocr-input.png'));
      fs.writeFileSync(path.join(output, name + '.txt'), cue.observed);
      check(true, 'Actual rendered pixels show ' + name);
    }
    check(order.served === 0 && order.earned === 0 && order.tutorial.status === 'active', 'A naturally seated guest has a genuine order, with no premature payment or tutorial completion');
    report.first_order_seconds = movingStarted + moving.first_order_ms / 1000;
    const paid = await waitState('natural-payment', s => s.served > 0 && s.tutorial.step === 7, 150000);
    report.first_payment_seconds = elapsed();
    check(paid.tutorial.status === 'active', 'Genuine payment unlocks completion but does not dismiss the guide');
    // Separate verification time from natural gameplay. Title, exact Done OCR,
    // real click and saved completion share their existing 25s + 25s + 30s cap.
    report.completion_deadline_seconds = (budget.startCompletion() - started) / 1000;
    await visible('first-order-complete', [stage('complete').text], stage('complete').guide);
    await visible('completion-done-button', ['Done'], completionButtonRegion(stage('complete')), CUE_MS,
      {pixelScale: 2, exactLabel: true});
    await click('complete');
    const finished = await waitState('tutorial-completed', s => s.tutorial.status === 'completed' && s.tutorial.step === 7);
    check(finished.served === paid.served && finished.earned === paid.earned && finished.coins + finished.wages === paid.coins + paid.wages, 'Real final Done completes tutorial without an extra reward');
    check(finished.open, 'Completed tutorial leaves the cafe open for ordinary play');
    await page.screenshot({path: path.join(output, 'tutorial-completed.png'), timeout: Math.min(10000, budget.remaining())});
    budget.remaining();
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
module.exports = {validateLayout, validateBinding, summarize, validateProgress, recognizeCue, completionButtonRegion, cuePixelScale, flowBudget, matchesCue, recognizeMovingFrame, observeMovingCues};
