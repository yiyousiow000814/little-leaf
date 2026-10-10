'use strict';
const {sourcePath}=require('./source_paths.js');
// Fast, browser-free contract checks. Actual rendered gameplay is a separate CI gate.
const assert = require('node:assert/strict');
const {validateLayout, validateBinding, summarize, validateProgress, validateNaturalPayment, recognizeCue, completionButtonRegion, cuePixelScale, flowBudget, matchesCue} = require('./fresh_tutorial_browser');
const {hash, canonical} = require('./wall_compatibility_helpers');
const stages = Object.fromEntries(Object.entries({open: 0, staff: 1, staff_done: 2, decorate: 3, return: 4, order: 5, payment: 6, complete: 7})
  .map(([name, step]) => [name, {step, text: name, point: [100, 150], guide: [50, 100, 200, 64]}]));
const receipt = {checks: 10, failures: [], player_save_used: false,
  web_layout: {viewport: [1360, 880], initial_coins: 1200, meal_payment: 200, stages}};
const layout = validateLayout(receipt);
for (const mutate of [
  r => r.failures.push('failed engine test'),
  r => r.player_save_used = true,
  r => r.web_layout.viewport[0] = 390,
  r => r.web_layout.stages.open.point[0] = -1,
  r => r.web_layout.stages.staff.guide[2] = 1400,
  r => r.web_layout.stages.complete.step = 6,
  r => delete r.web_layout.stages.return,
]) {
  const bad = structuredClone(receipt); mutate(bad);
  assert.throws(() => validateLayout(bad));
}
const payload = {coins: 1200, served: 0, total_earned: 0, total_wages_paid: 0, operating_open: false,
  tutorial: {format: 1, status: 'active', step: 0, baseline_served: 0}, first_guest_pending: true,
  items: [{id: 1, kind: 'table'}], runtime: {customers: [], service: {records: []}}};
const ack = {ok: true, revision: 1, payload: JSON.stringify(payload), inbox: {paid: []}};
const initial = summarize(ack);
assert.equal(initial.items_sha256, hash(canonical(payload.items)));
assert.equal(summarize({ok: true, payload: null}), null);
assert.equal(summarize({ok: false}), null);
validateProgress(initial, layout);
const ordered = {...initial, open: true, tutorial: {...initial.tutorial, step: 6},
  guests: [{id: 1, seated: true, phase: 'cooking'}], orders: [1]};
validateProgress(ordered, layout, initial);
const paid = {...ordered, served: 1, earned: 200, coins: 1350, wages: 50, tutorial: {...ordered.tutorial, step: 7}};
validateProgress(paid, layout, initial);
validateProgress({...paid, tutorial: {...paid.tutorial, status: 'completed'}}, layout, initial);
for (const mutate of [
  s => s.coins += 1000,
  s => s.earned += 200,
  s => s.served = 0,
  s => s.tutorial.baseline_served = 1,
  s => s.tutorial.status = 'skipped',
  s => s.items_sha256 = 'changed layout',
  s => s.paid_campaigns.push({coins: 1000}),
]) {
  const bad = structuredClone(paid); mutate(bad);
  assert.throws(() => validateProgress(bad, layout, initial));
}
validateProgress({...initial, tutorial: {...initial.tutorial, step: 7}}, layout, initial);
const explained = {...initial, tutorial: {...initial.tutorial, status: 'completed', step: 7}};
validateProgress(explained, layout, initial); // Done is independent of any order/payment.
const actualOrder = {...ordered, tutorial: explained.tutorial};
validateNaturalPayment({...paid, tutorial: explained.tutorial}, actualOrder, layout, initial);
assert.throws(() => validateNaturalPayment(explained, actualOrder, layout, initial), /genuine payment/);
assert.throws(() => validateNaturalPayment({...paid, tutorial: explained.tutorial}, {...actualOrder, orders: []}, layout, initial), /actual seated order/);
assert.throws(() => validateNaturalPayment({...paid, tutorial: explained.tutorial}, {...actualOrder, guests: []}, layout, initial), /actual seated order/);
assert.throws(() => validateNaturalPayment({...paid, tutorial: explained.tutorial}, {...actualOrder, guests: [{id: 2, seated: true}]}, layout, initial), /actual seated order/);
assert.throws(() => validateProgress({...initial, tutorial: {...initial.tutorial, status: 'completed'}}, layout, initial));
const orderAck = structuredClone(ack), orderPayload = structuredClone(payload);
orderPayload.runtime.customers = [{id: 1, phase: 'cooking', seated: true}];
orderPayload.runtime.service.records = [{guest_id: 1, order_done: true}, {guest_id: 2, order_done: false}];
orderAck.payload = JSON.stringify(orderPayload);
assert.deepEqual(summarize(orderAck).orders, [1]);
assert.deepEqual(summarize(orderAck).guests, [{id: 1, phase: 'cooking', seated: true}]);
// Exercise the exact production binding function against disposable fake
// export/report receipts. Only git's readonly answers are stubbed; source files
// are genuinely hashed and are never changed by this test.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '..'), temp = fs.mkdtempSync(path.join(os.tmpdir(), 'fresh-tutorial-binding-'));
const exec = cp.execFileSync;
// Exercise the same phase/step budget and exact OCR used by the browser with a
// deterministic clock. Synthetic recognition proves timing, not real gameplay.
const realNow = Date.now;
try {
  const started = 100000;
  let now = started;
  Date.now = () => now;
  const budget = flowBudget(started);
  const natural = flowBudget(started + 120000, () => now, started + 300000);
  assert.equal(natural.deadline(999999), started + 300000, 'Independent service cannot extend the whole-run cap');
  assert.equal(budget.deadline(25000), started + 25000, 'Opening cue retains its own limit');
  assert.equal(budget.deadline(30000), started + 30000, 'Saved-state waits retain their own limit');
  now = started + 80759;
  assert.equal(budget.deadline(45000), now + 45000, 'Arrival/order allowance is unchanged');
  assert.equal(budget.deadline(20000), now + 20000, 'Meal cue allowance is unchanged');
  const paymentDeadline = budget.deadline(150000);
  assert.equal(paymentDeadline, started + 220000, 'Payment cannot borrow completion time');
  now = started + 211731; // Exact late-but-valid payment time in failed CI #157.
  assert.equal(budget.remaining(paymentDeadline), 8269);
  const completionDeadline = budget.startCompletion();
  assert.equal(completionDeadline, now + 25000 + 25000 + 30000);
  let calls = 0;
  cp.execFileSync = () => {calls++; return 'First order complete!';};
  assert(recognizeCue('completion-title.png', ['First order complete!'], 'tesseract', budget.deadline(25000)).matched);
  now += 12000; // Title/evidence work has crossed the old 220-second ceiling.
  const doneDeadline = budget.deadline(25000);
  assert.equal(doneDeadline, now + 25000, 'Done receives its bounded OCR window after late payment');
  cp.execFileSync = () => {calls++; return 'Done\n';};
  const done = recognizeCue('completion-action-2x.png', ['Done'], 'tesseract', doneDeadline, true);
  assert(done.matched && done.attempts.length > 0, 'Late valid payment must permit actual exact Done OCR attempts');
  assert.equal(calls, 2);
  budget.remaining(); // The real click is allowed only inside completion time.
  now += 5000;
  const saveDeadline = budget.deadline(30000);
  now += 20000;
  assert(budget.remaining(saveDeadline) > 0, 'A normal completed autosave fits after the final click');
  assert.throws(() => budget.startCompletion(), /cannot be restarted/);
  now = completionDeadline;
  assert.throws(() => budget.remaining(), /completion.*deadline exceeded/);

  for (const overdue of [220000, 220001, 299999]) {
    now = started + overdue;
    const expiredService = flowBudget(started);
    assert.throws(() => expiredService.remaining(paymentDeadline), /service.*deadline exceeded/);
    assert.throws(() => expiredService.startCompletion(), /service.*deadline exceeded/,
      'An expired payment observation cannot unlock completion grace');
  }
  now = started + 100000;
  const stepLimited = flowBudget(started), stepDeadline = stepLimited.deadline(30000);
  now = stepDeadline;
  assert.throws(() => stepLimited.remaining(stepDeadline), /service.*deadline exceeded/,
    'A matching save observed after its local wait expired must also fail');

  for (const phrase of ['First order complete!', 'Done']) {
    now = started + 219999;
    const missing = flowBudget(started), end = missing.startCompletion();
    assert.equal(end, started + 299999, 'Even the latest valid payment stays below the fixed 300s cap');
    const cueDeadline = missing.deadline(25000);
    cp.execFileSync = () => {now += 5000; return 'Unrelated scene text';};
    while (now < cueDeadline) {
      assert(!recognizeCue('missing-completion.png', [phrase], 'tesseract', cueDeadline, phrase === 'Done').matched,
        'Missing completion content cannot pass within the extra allowance');
    }
    assert.throws(() => missing.remaining(cueDeadline), /completion.*deadline exceeded/);
    now = started + 300000;
    assert.throws(() => missing.remaining(), /completion.*deadline exceeded/);
    assert.throws(() => missing.startCompletion(), /cannot be restarted/);
    calls = 0;
    cp.execFileSync = () => {calls++; return phrase;};
    assert(!recognizeCue('too-late.png', [phrase], 'tesseract', missing.deadline(25000), phrase === 'Done').matched);
    assert.equal(calls, 0, 'Missing completion cannot cause OCR to run beyond the overall cap');
  }
} finally {Date.now = realNow; cp.execFileSync = exec;}
let dirty = false;
try {
  const commit = 'a'.repeat(40);
  cp.execFileSync = (command, args) => {
    assert.equal(command, 'git');
    return args[0] === 'rev-parse' ? commit : dirty ? ' M tests/fresh_tutorial_browser.js' : '';
  };
  const sourceNames = ['tests/test_interactive_tutorial.gd', 'tests/run_integration_candidate.py', 'tests/fresh_tutorial_browser.js', 'tests/wall_compatibility_helpers.js', 'project.godot'];
  const engine = {source_commit: commit, status: 'passed', source_sha256: Object.fromEntries(sourceNames.map(name => [name, hash(fs.readFileSync(sourcePath(root,name)))])),
    records: [{test: 'test_interactive_tutorial', exit_code: 0, failures: [], result_sha256: hash(JSON.stringify(receipt))}]};
  const production = {'project.godot': engine.source_sha256['project.godot']};
  const manifest = {source_commit: commit, toolchain_verification: 'checksum-pinned-official-archives', packed_smoke: 'passed', production_sha256: production};
  const layoutFile = path.join(temp, 'layout.json'), engineFile = path.join(temp, 'engine.json');
  const write = (mutateEngine = () => {}, html = '<title>Ordinary Web</title>') => {
    fs.writeFileSync(layoutFile, JSON.stringify(receipt));
    const current = structuredClone(engine); mutateEngine(current);
    fs.writeFileSync(engineFile, JSON.stringify(current));
    fs.writeFileSync(path.join(temp, 'index.html'), html);
    fs.writeFileSync(path.join(temp, 'release-manifest.json'), JSON.stringify({...manifest,
      test_report_sha256: hash(fs.readFileSync(engineFile)), files: {'index.html': {bytes: Buffer.byteLength(html), sha256: hash(html)}}}));
  };
  const verify = () => validateBinding(temp, layoutFile, engineFile);
  write(); assert.equal(verify().source_commit, commit);
  fs.appendFileSync(layoutFile, ' '); assert.throws(verify, /Coordinate receipt/);
  write(); fs.appendFileSync(engineFile, ' '); assert.throws(verify, /Exact full engine report/);
  write(e => {e.source_commit = 'b'.repeat(40);}); assert.throws(verify);
  write(e => {e.records[0].result_sha256 = 'c'.repeat(64);}); assert.throws(verify, /Coordinate receipt/);
  write(e => {e.records.push(structuredClone(e.records[0]));}); assert.throws(verify);
  write(e => {e.records[0].failures.push('fixture failed');}); assert.throws(verify);
  write(e => {e.source_sha256['tests/fresh_tutorial_browser.js'] = 'd'.repeat(64);}); assert.throws(verify, /Exact tested harness/);
  write(e => {e.source_sha256['project.godot'] = 'e'.repeat(64);}); assert.throws(verify, /Production source passed/);
  write(() => {}, '<script>LittleLeafPlatform</script>'); assert.throws(verify, /Ordinary Web export/);
  write(); fs.appendFileSync(path.join(temp, 'index.html'), '!'); assert.throws(verify, /size/);
  write(); dirty = true; assert.throws(verify, /Clean tracked source/);
} finally {
  cp.execFileSync = exec;
  fs.rmSync(temp, {recursive: true, force: true});
}
// The fallback must inspect the same image and retain the same exact phrases.
try {
  const calls = [];
  cp.execFileSync = (command, args) => {
    calls.push(args);
    assert.equal(command, 'tesseract');
    assert.equal(args[0], 'same-captured-frame.png');
    assert.equal(args[args.indexOf('--psm') + 1], '11');
    return args.includes('thresholding_method=2') ? 'Tap to open\nSkip & open\n' : 'Unrelated scene text';
  };
  const result = recognizeCue('same-captured-frame.png', ['Tap to open', 'Skip'], 'tesseract', Date.now() + 10000);
  assert(result.matched);
  assert.deepEqual(result.attempts.map(a => a.mode), ['sparse', 'sparse-sauvola']);
  assert.equal(calls.length, 2);
  const absent = recognizeCue('same-captured-frame.png', ['First order complete'], 'tesseract', Date.now() + 10000);
  assert(!absent.matched, 'Fallback must not loosen the requested visible text');
  calls.length = 0;
  assert(!recognizeCue('same-captured-frame.png', ['Tap'], 'tesseract', Date.now() + 500).matched);
  assert.equal(calls.length, 0, 'Do not start OCR with a subsecond remaining budget');
  for (const wrong of ['Dor', 'Dene', 'Undone', 'Done later', 'First order complete!']) {
    cp.execFileSync = () => wrong;
    assert(!recognizeCue('same-captured-frame.png', ['Done'], 'tesseract', Date.now() + 10000, true).matched,
      'Exact button label rejects ' + wrong);
  }
  for (const wrong of ['Mealontheway', 'Meal on the wax', 'Meal on the wayward', 'Premeal on the way', 'Meal on way', 'Meals on the way']) {
    cp.execFileSync = () => wrong;
    assert(!recognizeCue('same-captured-frame.png', ['Meal on the way'], 'tesseract', Date.now() + 10000).matched,
      'Exact spaced cue rejects ' + wrong);
  }
  for (const correct of ['Meal on the way', 'Meal\non the way', '5/6\nMeal on the way.\nSkip']) {
    cp.execFileSync = () => correct;
    assert(recognizeCue('same-captured-frame.png', ['Meal on the way'], 'tesseract', Date.now() + 10000).matched);
  }
  for (const phrase of ['Your team cooks and serves meals.', 'Guests pay at checkout.', 'Next']) {
    cp.execFileSync = () => phrase;
    assert(recognizeCue('same-captured-frame.png', [phrase], 'tesseract', Date.now() + 10000, phrase === 'Next').matched);
  }
  cp.execFileSync = () => 'Done\n';
  assert(recognizeCue('same-captured-frame.png', ['Done'], 'tesseract', Date.now() + 10000, true).matched);
  cp.execFileSync = () => {throw Object.assign(new Error('Synthetic OCR timeout'), {code: 'ETIMEDOUT'});};
  assert.throws(() => recognizeCue('same-captured-frame.png', ['Tap'], 'tesseract', Date.now() + 10000),
    error => error.ocr_evidence.attempts[0].mode === 'sparse' && /timeout/.test(error.ocr_evidence.attempts[0].error));
} finally {cp.execFileSync = exec;}
assert.equal(cuePixelScale(null), 2, 'Every moving full-frame cue receives exact 2x pixels');
assert.equal(cuePixelScale(undefined), 2);
assert.equal(cuePixelScale([10, 10, 100, 64]), 1, 'Existing native-bound card evidence remains unchanged');
assert.equal(cuePixelScale([10, 10, 44, 44], 2), 2, 'Done uses the same nearest-neighbor scaling');
assert.throws(() => cuePixelScale(null, 3), /exact 2x/);
const browserSource = fs.readFileSync(path.join(__dirname, 'fresh_tutorial_browser.js'), 'utf8');
assert(browserSource.includes('const pixelScale = cuePixelScale(region, options.pixelScale ?? 1)'));
assert(browserSource.includes('if (pixelScale === 2)'));
assert(browserSource.includes('context.imageSmoothingEnabled = false'));
assert(browserSource.includes('new OffscreenCanvas(bitmap.width * 2, bitmap.height * 2)'));
assert(browserSource.indexOf("await click('complete')") < browserSource.indexOf("await waitState('natural-payment'"),
  'Tutorial Done is tested before the independent natural payment wait');
assert(!browserSource.includes('observeMovingCues'), 'No moving guest cue can delay Next');
for (const name of ['service-next-button', 'checkout-next-button']) {
  assert(browserSource.includes("await visible('" + name + "', ['Next'], completionButtonRegion"),
    'Each Next button has its own exact-label 2x OCR gate');
}
for (const guard of [
  'Browser profile and origin contain no existing saves or seeded fixtures',
  'Independent natural-service gate requires a new genuine payment',
  'Completed tutorial leaves the cafe open for ordinary play',
  "await click('order')", "await click('payment')", "await click('complete')",
  "await waitState('natural-payment'", 'validateNaturalPayment(paid, order, layout, initial)',
  'Exact tested harness source ', 'Exact exported production source ',
]) assert(browserSource.includes(guard), 'Preserve short tutorial, genuine service and source binding: ' + guard);

// New regression PNGs contain only RGB pixels and dimensions, without metadata.
// Keep the raw capture and verify that the distinct OCR input duplicates every
// pixel exactly, matching the detached browser canvas with smoothing disabled.
function retainedRgb(file) {
  const bytes = fs.readFileSync(file), data = [];
  assert(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])));
  let offset = 8, width, height;
  while (offset < bytes.length) {
    const length = bytes.readUInt32BE(offset), kind = bytes.toString('ascii', offset + 4, offset + 8);
    assert(offset + length + 12 <= bytes.length);
    const body = bytes.subarray(offset + 8, offset + 8 + length);
    assert(['IHDR', 'IDAT', 'IEND'].includes(kind), 'No retained-image metadata');
    if (kind === 'IHDR') {
      width = body.readUInt32BE(0); height = body.readUInt32BE(4);
      assert.deepEqual([...body.subarray(8)], [8, 2, 0, 0, 0]);
    } else if (kind === 'IDAT') data.push(body);
    offset += length + 12;
  }
  const stride = width * 3, scanlines = require('node:zlib').inflateSync(Buffer.concat(data));
  assert.equal(scanlines.length, (stride + 1) * height);
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    assert.equal(scanlines[y * (stride + 1)], 0);
    scanlines.copy(pixels, y * stride, y * (stride + 1) + 1, (y + 1) * (stride + 1));
  }
  return {width, height, pixels};
}
const retainedFolder = path.join(__dirname, 'fixtures/tutorial-ocr');
for (const name of ['opening-card-compact', 'staff-card', 'staff-done-card', 'decorate-card', 'return-card', 'completion-title']) {
  retainedRgb(path.join(retainedFolder, name + '.png'));
}
for (const name of ['arrival-frame', 'meal-frame', 'arrival-frame-alternate', 'meal-frame-alternate', 'completion-action']) {
  const raw = retainedRgb(path.join(retainedFolder, name + '.png'));
  const scaled = retainedRgb(path.join(retainedFolder, name + '-2x.png'));
  assert.deepEqual([scaled.width, scaled.height], [raw.width * 2, raw.height * 2]);
  assert.deepEqual([raw.width, raw.height], name === 'completion-action' ? [45, 45] : [1360, 880]);
  for (let y = 0; y < raw.height; y++) {
    const repeated = Buffer.alloc(raw.width * 6);
    for (let x = 0; x < raw.width; x++) {
      const pixel = raw.pixels.subarray((y * raw.width + x) * 3, (y * raw.width + x + 1) * 3);
      pixel.copy(repeated, x * 6); pixel.copy(repeated, x * 6 + 3);
    }
    for (const row of [2 * y, 2 * y + 1]) {
      assert(scaled.pixels.subarray(row * scaled.width * 3, (row + 1) * scaled.width * 3).equals(repeated),
        name + ' OCR input contains only exact 2x repeated source pixels');
    }
  }
}
const completeTarget = {point: [765.5, 145.1084], guide: [558.5, 113.1084, 243, 64]};
completionButtonRegion(completeTarget).forEach((value, index) =>
  assert(Math.abs(value - [743.5, 123.1084, 44, 44][index]) < 1e-8));
assert.throws(() => completionButtonRegion({...completeTarget, point: [550, 145]}), /fully within/);
assert.throws(() => completionButtonRegion({...completeTarget, point: [765.5, 113]}), /fully within/);
if (process.argv.includes('--ocr-fixtures')) {
  const folder = path.join(__dirname, 'fixtures/tutorial-ocr');
  const fixtures = JSON.parse(fs.readFileSync(path.join(folder, 'provenance.json'), 'utf8'));
  // Retain the existing provenance-bound fixtures; append the new generic pixel cases.
  fixtures.images.push(
    {file: 'opening-card-compact.png', phrases: ['Tap to open', 'Skip']},
    {file: 'staff-card.png', phrases: ['Meet your team']},
    {file: 'staff-done-card.png', phrases: ['Ready? Tap Done']},
    {file: 'decorate-card.png', phrases: ['Try Decorate']},
    {file: 'return-card.png', phrases: ['Back to café']},
    {file: 'arrival-frame-2x.png', raw_fixture: 'arrival-frame.png', phrases: ['Your waiter takes the order']},
    {file: 'meal-frame-2x.png', raw_fixture: 'meal-frame.png', phrases: ['Meal on the way']},
    {file: 'arrival-frame-alternate-2x.png', raw_fixture: 'arrival-frame-alternate.png', phrases: ['Your waiter takes the order']},
    {file: 'meal-frame-alternate-2x.png', raw_fixture: 'meal-frame-alternate.png', phrases: ['Meal on the way']},
    {file: 'completion-title.png', phrases: ['First order complete!']},
    {file: 'completion-action-2x.png', raw_fixture: 'completion-action.png', phrases: ['Done'], exact_label: true},
    {file: 'arrival-frame-2x.png', phrases: ['Meal on the way'], expected_match: false},
    {file: 'meal-frame-2x.png', phrases: ['Your waiter takes the order'], expected_match: false},
    {file: 'staff-card.png', phrases: ['Try Decorate'], expected_match: false},
    {file: 'decorate-card.png', phrases: ['Back to café'], expected_match: false},
    {file: 'return-card.png', phrases: ['First order complete!'], expected_match: false},
    {file: 'completion-title.png', phrases: ['Done'], exact_label: true, expected_match: false},
    {file: 'completion-action-2x.png', phrases: ['Skip'], exact_label: true, expected_match: false},
  );
  const tesseract = process.env.TESSERACT_BIN || 'tesseract';
  const results = fixtures.images.map(fixture => {
    const file = path.join(folder, fixture.file);
    const before = hash(fs.readFileSync(file));
    const rawFile = fixture.raw_fixture && path.join(folder, fixture.raw_fixture);
    const rawBefore = rawFile && hash(fs.readFileSync(rawFile));
    if (fixture.sha256) assert.equal(before, fixture.sha256, 'Captured OCR fixture bytes are unchanged');
    if (fixture.raw_sha256) assert.equal(rawBefore, fixture.raw_sha256,
      'Enlarged OCR input retains its unmodified raw screenshot');
    const result = recognizeCue(file, fixture.phrases, tesseract, Date.now() + 15000, fixture.exact_label === true);
    assert.equal(hash(fs.readFileSync(file)), before, 'OCR never mutates its input');
    if (rawFile) assert.equal(hash(fs.readFileSync(rawFile)), rawBefore, 'Raw regression frame remains untouched');
    assert.equal(result.matched, fixture.expected_match !== false,
      fixture.file + ' must preserve the positive/negative visible label expectation: ' + JSON.stringify(result));
    return {file: fixture.file, ...result};
  });
  console.log(JSON.stringify({ocr_fixture_checks: 'passed', images_unmodified: true, browser_runtime_exercised: false,
    tesseract: cp.execFileSync(tesseract, ['--version'], {encoding: 'utf8'}).split('\n')[0], results}, null, 2));
}
console.log('Fresh tutorial browser contract and source-binding checks passed (browser runtime not exercised)');
