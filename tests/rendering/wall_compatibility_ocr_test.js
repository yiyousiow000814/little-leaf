'use strict';
// Offline native-geometry and retained-pixel regressions. No browser or player data.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), zlib = require('node:zlib');
const {hash, requireWallBackText, requireVisibleText, verifyLayout, selectWallReplacement} = require('./wall_compatibility_helpers');
const root = path.resolve(__dirname, '../..'), folder = path.join(__dirname, '../fixtures/wall-ocr');
let checks = 0;
function check(label, fn) {fn(); checks++; console.log('PASS ' + label);}
const layoutSource = fs.readFileSync(path.join(__dirname, '../fixtures/wall_compatibility_layout.gd'), 'utf8');
const shopSource = fs.readFileSync(path.join(root, 'game/scripts/ui/cafe_shop_ui.gd'), 'utf8');
const compactSource = fs.readFileSync(path.join(root, 'game/scripts/ui/cafe_compact_ui.gd'), 'utf8');
const browserSource = fs.readFileSync(path.join(__dirname, 'wall_compatibility_browser.js'), 'utf8');
const workflow = fs.readFileSync(path.join(root, '.github/workflows/build-web.yml'), 'utf8');
const literalSize = shopSource.match(/_put\(tiles_back,Rect2\(category_margin,header_y,(\d+),(\d+)\)\)/);
const responsiveSize = shopSource.match(/_put\(tiles_back,Rect2\(category_margin,header_y,back_width,(\d+)\)\)/);
// The 80px branch applies only to tiny Tiles inspection with a repair button.
// Walls retains the default width: bind it to the real source expression.
const responsiveWidth = shopSource.match(/var back_width=(\d+(?:\.\d+)?) if tiny and tiles_active\(\) and repair_width>0 else (\d+(?:\.\d+)?)/);
const size = literalSize || (responsiveSize && responsiveWidth
  ? [responsiveSize[0], responsiveWidth[2], responsiveSize[1]] : null);
check('responsive width reduction is Tiles-only and leaves full Walls bounds', () => {
  if (!literalSize) assert(responsiveSize && responsiveWidth);
});
check('fixture geometry is read from the real back-button layout', () => assert(size));
check('only wall_back uses complete native Button bounds with single-line 3x OCR', () => {
  assert.match(layoutSource, /result\.regions\.wall_back=region\(shop\.tiles_back\)\s+result\.regions\.wall_back\.psm=7\s+result\.regions\.wall_back\.scale=3/);
  assert(!layoutSource.includes('wall_back=text_region('));
  assert.match(layoutSource, /func region\(control:Control\)->Dictionary:\s+var rect=control\.get_global_rect\(\)/);
  assert(layoutSource.includes('"bounded visible OCR region "'));
  assert(shopSource.includes('style.content_margin_left=30;style.content_margin_right=10'));
});
check('catalog retains complete native bounds with lossless 3x OCR', () => {
  assert.match(layoutSource, /result\.regions\.catalog=region\(game\.tray\)[\s\S]*?result\.regions\.catalog\.scale=3/);
  requireVisibleText('Wall Door Window Tiles', ['Wall','Door','Window']);
  assert.throws(() => requireVisibleText('Wall Deen Window', ['Wall','Door','Window']));
});
check('actual browser requires the complete label from its own back-button crop', () => {
  assert(browserSource.includes("regions.findIndex(spec => spec.key === 'wall_back')"));
  assert(browserSource.includes('requireWallBackText(texts[backIndex])'));
  assert(browserSource.includes('requireVisibleText(text, phrases)'));
  assert(browserSource.includes('context.imageSmoothingEnabled = false'));
  assert(browserSource.includes("String(spec.psm || 6)"));
  assert(browserSource.includes("spec.key === 'wall_back' ? ['-c', 'thresholding_method=2'] : []"));
  assert(browserSource.includes("thresholding_mode: 'sauvola'"));
});
check('actual Case B payment, conflict, preservation and reload assertions remain', () => {
  for (const guard of [
    'Normal new UI edit commits exactly R+1',
    'Real new UI charges the expected wall price once',
    'Real new UI retains paid wide door geometry and ownership',
    'New commit retains compensation receipt without a second grant',
    'Actual new controller receives durable R+1 acknowledgement',
    'Actual stale old UI save receives REVISION_CONFLICT from real IndexedDB CAS',
    'Repeated old UI/lifecycle attempts are suppressed by the faulted controller',
    "await assertUnchanged(oldPage, reloadBaseline, 'Case B old reload')",
    "await verifyNewReload(context, reloadBaseline, 'case-b-new-restored')",
  ]) assert(browserSource.includes(guard), guard);
});
check('workflow runs fast guards and retained OCR before the unchanged browser gate', () => {
  assert(workflow.includes('run: python3 tools/ci/preflight.py\n'));
  const fastGuard = fs.readFileSync(path.join(root, 'tools/ci/preflight.py'), 'utf8');
  assert(fastGuard.includes('"tests/rendering/wall_compatibility_ocr_test.js",'));
  const ocr = workflow.indexOf('node tests/rendering/wall_compatibility_ocr_test.js --ocr-fixtures');
  assert(ocr > workflow.indexOf('sudo apt-get install -y --no-install-recommends tesseract-ocr'));
  assert(ocr < workflow.indexOf('xvfb-run -a node tests/rendering/wall_compatibility_browser.js --case'));
});
for (const text of ['Build', '< Build', '‹ BUILD ›', '\nBuild\n']) {
  check('complete label accepts harmless arrow punctuation: ' + JSON.stringify(text), () => requireWallBackText(text));
}
for (const text of ['Buil', 'Buid', 'Builder', 'Rebuild', 'Wall', 'Replace wall', 'Buildable', '']) {
  check('complete label rejects wrong/clipped text: ' + JSON.stringify(text), () => assert.throws(() => requireWallBackText(text)));
}
check('Wall title and clipped Build cannot satisfy the combined tray requirement', () => {
  requireVisibleText('Wall\nBuild', ['Wall', 'Build']);
  assert.throws(() => requireVisibleText('Wall\nBuil', ['Wall', 'Build']));
});

// These RGB fixtures intentionally contain only lossless pixels, dimensions and
// PNG framing. No historical run IDs, source receipts or screenshot metadata.
function pixels(file) {
  const bytes = fs.readFileSync(file), chunks = [], compressed = [];
  assert(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])));
  let offset = 8, width, height;
  while (offset < bytes.length) {
    const length = bytes.readUInt32BE(offset), kind = bytes.toString('ascii', offset + 4, offset + 8);
    assert(offset + 12 + length <= bytes.length);
    const body = bytes.subarray(offset + 8, offset + 8 + length); chunks.push(kind);
    assert(['IHDR', 'IDAT', 'IEND'].includes(kind), 'No ancillary fixture metadata');
    if (kind === 'IHDR') {
      width = body.readUInt32BE(0); height = body.readUInt32BE(4);
      assert.deepEqual([...body.subarray(8)], [8, 2, 0, 0, 0], 'Plain RGB8 noninterlaced PNG');
    } else if (kind === 'IDAT') compressed.push(body);
    offset += length + 12;
  }
  assert.equal(chunks[0], 'IHDR'); assert.equal(chunks.at(-1), 'IEND');
  const stride = width * 3, raw = zlib.inflateSync(Buffer.concat(compressed));
  assert.equal(raw.length, (stride + 1) * height);
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y++) {
    assert.equal(raw[y * (stride + 1)], 0, 'Unfiltered retained pixels');
    raw.copy(data, y * stride, y * (stride + 1) + 1, (y + 1) * (stride + 1));
  }
  return {width, height, data};
}
const fixtures = [
  {name: 'build-button', matched: true},
  {name: 'build-clipped', matched: false},
  {name: 'wall-title-negative', matched: false},
  {name: 'review-title-negative', matched: false},
];
for (const fixture of fixtures) {
  const raw = pixels(path.join(folder, fixture.name + '.png'));
  const scaled = pixels(path.join(folder, fixture.name + '-3x.png'));
  check(fixture.name + ': 3x input repeats every retained pixel exactly', () => {
    assert.equal(scaled.width, raw.width * 3); assert.equal(scaled.height, raw.height * 3);
    for (let y = 0; y < scaled.height; y++) for (let x = 0; x < scaled.width; x++) {
      const source = (Math.floor(y / 3) * raw.width + Math.floor(x / 3)) * 3;
      const target = (y * scaled.width + x) * 3;
      assert(scaled.data.subarray(target, target + 3).equals(raw.data.subarray(source, source + 3)));
    }
  });
  if (fixture.matched) check('complete Build fixture matches the source-derived button size', () => {
    assert.deepEqual([raw.width, raw.height], size.slice(1).map(Number));
  });
}
const categoryRaw = pixels(path.join(folder, 'category-tables-button.png'));
const categoryContent = pixels(path.join(folder, 'category-tables-content-3x.png'));
check('category crop uses actual asymmetric style content margins, not the icon/frame', () => {
  assert(shopSource.includes('style.content_margin_left=36;style.content_margin_right=9'));
  assert.match(layoutSource, /func category_text_region\(button:Button\)->Dictionary:[\s\S]*?var value=region\(button\);var style=button.get_theme_stylebox\("normal"\)/);
  assert(layoutSource.includes('ceilf(style.get_margin(SIDE_LEFT))'));
  assert(layoutSource.includes('ceilf(style.get_margin(SIDE_RIGHT))'));
  assert(layoutSource.includes('value.x+=left;value.width-=left+right'));
  assert(layoutSource.includes('value.psm=7;value.scale=3'));
  assert(layoutSource.includes('result.regions.category_ready=category_text_region(first)'));
  assert(layoutSource.includes('result.regions.build_category=category_text_region(build)'));
});
check('category OCR repeats only the complete native content pixels without alteration', () => {
  assert.deepEqual([categoryRaw.width, categoryRaw.height], [113, 44]);
  assert.deepEqual([categoryContent.width, categoryContent.height], [(categoryRaw.width-36-9)*3, categoryRaw.height*3]);
  for (let y=0; y<categoryContent.height; y++) for (let x=0; x<categoryContent.width; x++) {
    const source=(Math.floor(y/3)*categoryRaw.width+36+Math.floor(x/3))*3;
    const target=(y*categoryContent.width+x)*3;
    assert(categoryContent.data.subarray(target,target+3).equals(categoryRaw.data.subarray(source,source+3)));
  }
});
check('category readiness never accepts the observed OCR error or a clipped/wrong label', () => {
  for (const text of ['taies', 'Tabl', 'Kitchen', '']) assert.throws(() => requireVisibleText(text, ['Tables']));
  requireVisibleText('Tables', ['Tables']);
});
const layoutIndex = process.argv.indexOf('--layout-file');
if (layoutIndex >= 0) {
  const layout = JSON.parse(fs.readFileSync(process.argv[layoutIndex + 1]));
  check('new native receipt validates and supplies full bounded button geometry', () => {
    verifyLayout(layout, 'new');
    const back = layout.regions.wall_back, catalog = layout.regions.catalog;
    assert.deepEqual([back.width, back.height], size.slice(1).map(Number));
    assert.equal(back.psm, 7); assert.equal(back.scale, 3);
    assert.equal(catalog.scale, 3);
    assert(back.x >= catalog.x && back.y >= catalog.y);
    assert(back.x + back.width <= catalog.x + catalog.width);
    assert(back.y + back.height <= catalog.y + catalog.height);
  });
}
if (process.argv.includes('--ocr-fixtures')) {
  const tesseract = process.env.TESSERACT_BIN || 'tesseract';
  const categoryFile=path.join(folder,'category-tables-content-3x.png');
  const categoryBefore=hash(fs.readFileSync(categoryFile));
  const categoryText=cp.execFileSync(tesseract,[categoryFile,'stdout','-l','eng','--psm','7'],
    {encoding:'utf8',timeout:15000,env:{...process.env,OMP_THREAD_LIMIT:'1'}});
  check('actual retained category-content OCR requires the complete Tables label', () => {
    assert.equal(hash(fs.readFileSync(categoryFile)),categoryBefore);
    requireVisibleText(categoryText,['Tables']);
  });
  const results = fixtures.map(fixture => {
    const file = path.join(folder, fixture.name + '-3x.png'), before = hash(fs.readFileSync(file));
    const text = cp.execFileSync(tesseract, [file, 'stdout', '-l', 'eng', '--psm', '7', '-c', 'thresholding_method=2'],
      {encoding: 'utf8', timeout: 15000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
    let matched = true;
    try {requireWallBackText(text);} catch (_) {matched = false;}
    check(fixture.name + ': actual retained-pixel OCR positive/negative expectation', () => {
      assert.equal(hash(fs.readFileSync(file)), before, 'OCR never mutates its input');
      assert.equal(matched, fixture.matched, JSON.stringify({text, matched}));
    });
    return {file: fixture.name + '-3x.png', psm: 7, scale: 3, thresholding_mode: 'sauvola', thresholding_method: 2, text, matched};
  });
  console.log(JSON.stringify({ocr_fixture_checks: 'passed', category_text: categoryText, results,
    tesseract: cp.execFileSync(tesseract, ['--version'], {encoding: 'utf8'}).split('\n')[0]}));
}
async function verifyConfirmFailureEvidence() {
  // Execute the actual boundary/collector source with synthetic read-only pages.
  // This checks diagnostics and unchanged input order, not browser qualification.
  const start = browserSource.indexOf('        const captureConfirmFailure = ');
  const end = browserSource.indexOf('        check(canonical(await readSnapshot(fixture))', start);
  assert(start > 0 && end > start, 'Actual confirmation boundary is present');
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const run = new AsyncFunction('observation', 'check', 'click', 'idle', 'newPage', 'oldPage',
    'fixture', 'report', 'baseline', 'layouts', 'readSnapshot', 'path', 'output', browserSource.slice(start, end));
  const beforeMessage = 'New tray/product/target actions cause no save before the verified wall confirmation';
  const afterMessage = 'Wall Confirm changes only the Decorate draft before Apply';
  for (const [beforeCount, afterCount, failReads, acknowledged] of [
    [0, 0, false, true], [1, 0, false, true], [1, 0, false, false],
    [1, 0, true, true], [0, 1, false, true], [0, 1, true, true],
  ]) {
    const calls = [], report = {}, baseline = {authority: 'synthetic baseline'};
    const acknowledgement = {ok: true, durable: true, revision: 9, creditedCoins: 0};
    const observed = count => ({saveStarts: count, saves: count && acknowledged ? [acknowledgement] : []});
    const boundary = observed(beforeCount), successor = observed(afterCount);
    let observations = 0;
    const page = label => ({
      evaluate: async callback => {
        calls.push(label + ' read');
        if (failReads) throw Error('synthetic diagnostic failure');
        return require('node:vm').runInNewContext('(' + callback.toString() + ')()', {
          structuredClone, __wallCompatibility: observed(beforeCount || afterCount),
          LittleLeafSaveLog: {snapshot: () => [{event: 'save_confirmed', timestamp: '2026-01-01T00:00:00.000Z'}]},
          document: {visibilityState: 'visible', hasFocus: () => true}, Date,
        });
      },
      screenshot: async options => {
        calls.push(path.basename(options.path));
        if (failReads) throw Error('synthetic screenshot failure');
      },
    });
    const promise = run(async () => {calls.push('observe'); return observations++ ? successor : boundary;},
      assert, async () => {calls.push('confirm');}, async () => {calls.push('idle');},
      page('new'), page('old'), {}, report, baseline, {new: {points: {confirm: [12, 34]}}},
      async () => {calls.push('authority read'); if (failReads) throw Error('synthetic authority failure'); return {authority: 'synthetic after'};},
      path, '/unused-synthetic-output');
    if (!beforeCount && !afterCount) {
      await promise;
      check('successful confirmation performs no diagnostic reads or extra input', () => {
        assert.deepEqual(calls, ['observe', 'confirm', 'idle', 'observe']);
        assert.deepEqual(report, {});
      });
      continue;
    }
    await assert.rejects(promise, {name: 'AssertionError', message: beforeCount ? beforeMessage : afterMessage});
    check(`confirmation failure evidence: before=${beforeCount}, read errors=${failReads}, acknowledged=${acknowledged}`, () => {
      const evidence = beforeCount ? report.pre_confirm_failure : report.confirm_failure;
      assert.equal(evidence.before, boundary, 'Frozen original observation is retained');
      assert.deepEqual(evidence.before.saves, boundary.saves, 'Pending versus acknowledged save is not invented');
      assert.equal(evidence.authority_before, baseline);
      assert.equal(evidence.synthetic_only, true);
      assert(!Number.isNaN(Date.parse(evidence.started_at)));
      assert(!Number.isNaN(Date.parse(beforeCount ? evidence.observed_at : evidence.finished_at)));
      assert.deepEqual(beforeCount ? evidence.pending_confirm_point : evidence.derived_point, [12, 34]);
      assert.equal(calls.filter(value => value === 'confirm').length, beforeCount ? 0 : 1);
      assert.equal(calls.filter(value => value === 'idle').length, beforeCount ? 0 : 1);
      assert.equal(calls.at(-1), beforeCount ? 'case-b-before-confirm-failure.png' : 'case-b-confirm-failure.png');
      if (!beforeCount) assert.equal(evidence.after, successor);
      if (failReads) {
        for (const key of ['authority_read_error', 'old_diagnostic_error', 'new_diagnostic_error', 'screenshot_error']) assert(evidence[key], key);
      } else {
        assert.equal(evidence.authority_after.authority, 'synthetic after');
        assert.equal(evidence.new_diagnostics.observation.saveStarts, beforeCount || afterCount);
        assert.equal(evidence.new_diagnostics.save_log[0].event, 'save_confirmed');
        assert.equal(evidence.old_diagnostics.visibility, 'visible');
        assert.equal(evidence.new_diagnostics.focused, true);
        assert(!Number.isNaN(Date.parse(evidence.new_diagnostics.timestamp)));
      }
    });
  }
}
async function verifyClockWindow() {
  const {freezeCaseBClock, settleInput, resumeCaseBClock, clickCaseBWallStep} = require('./wall_compatibility_browser');
  const trayOpenSource = compactSource.split('func set_tray_open(opened:bool):')[1].split('func _set_tray_reveal')[0];
  check('rendered Tables label is not permission to click while the tray opens', () => {
    assert.match(trayOpenSource, /mouse_behavior_recursive=Control.MOUSE_BEHAVIOR_DISABLED[\s\S]*?\.20\*absf\(target-tray_reveal\)[\s\S]*?tween_callback[\s\S]*?mouse_behavior_recursive=Control.MOUSE_BEHAVIOR_INHERITED if opened/);
    assert.match(browserSource, /await click\(page, 'new', name, delay\);\s*if \(name === 'decorate'\) await settleCaseBTrayOpening\(page\);/);
    assert.match(browserSource, /await selectWallReplacement\(\s*\(name, delay\) => clickCaseBWallStep\(newPage, click, name, delay\),/);
  });
  let elapsed = 1300, paused = false, fixed = false;
  const newWall = 1767225600000, oldWall = newWall + 1200;
  const wallTimes = [newWall, oldWall], transitions = [], advances = [], realWaits = [];
  const frames = wallTimes.map((_, index) => ({evaluate: async () => wallTimes[index]}));
  const page = {
    context: () => ({pages: () => frames.map(frame => ({frames: () => [frame]}))}),
    evaluate: async () => elapsed,
    waitForTimeout: async ms => {realWaits.push(ms);},
    clock: {
      setFixedTime: async ticks => {assert(!paused); fixed = true; wallTimes.fill(ticks); transitions.push(['fix', ticks]);},
      pauseAt: async ticks => {
        // Model both a skewed old document and 800ms dispatch lag. The legacy
        // sampling-plus-250ms implementation fails this exact condition.
        elapsed += 800;
        if (!fixed) for (const index of wallTimes.keys()) wallTimes[index] += 800;
        assert(wallTimes.every(now => now <= ticks), 'Cannot fast-forward to the past');
        paused = true; transitions.push(['pause', ticks]);
      },
      setSystemTime: async ticks => {assert(paused && fixed); fixed = false; wallTimes.fill(ticks); transitions.push(['unfix', ticks]);},
      runFor: async ms => {
        assert(paused && !fixed); advances.push(['run', ms]); elapsed += ms;
        for (const index of wallTimes.keys()) wallTimes[index] += ms;
      },
      fastForward: async ms => {
        assert(paused && !fixed); advances.push(['coalesce', ms]); elapsed += ms;
        for (const index of wallTimes.keys()) wallTimes[index] += ms;
      },
      resume: async () => {assert(paused && !fixed); paused = false;},
    },
  };
  await settleInput(page, 9);
  await freezeCaseBClock(page);
  const routeInputs = [], routeOcr = [];
  const routeStart = elapsed;
  const emit = async (target, label, name, delay) => {
    assert.equal(target, page);
    assert.equal(label, 'new');
    routeInputs.push(name);
    if (name === 'decorate') await settleInput(page, delay, true);
    if (name === 'build_next') assert(elapsed - routeStart >= 2500, 'Arrow input must be after the full opening window');
  };
  await selectWallReplacement(
    (name, delay) => clickCaseBWallStep(page, emit, name, delay),
    async (name, _region, phrases) => {routeOcr.push([name, phrases]);}, true);
  await settleInput(page, 400);
  await settleInput(page, 250, true);
  elapsed = 39900;
  await assert.rejects(settleInput(page, 400), /exhausted its controlled pre-autosave time/);
  await resumeCaseBClock(page);
  await settleInput(page, 11);
  check('Case B bounds simulation on real input only and restores lifecycle clock', () => {
    assert.deepEqual(transitions, [['fix', oldWall], ['pause', oldWall], ['unfix', oldWall]]);
    assert.deepEqual(wallTimes, [oldWall + 3184, oldWall + 3184]);
    assert.deepEqual(advances, [['run', 34], ...Array.from({length: 29}, () => ['coalesce', 100]),
      ['run', 34], ['coalesce', 100], ['coalesce', 100], ['coalesce', 16]]);
    assert.deepEqual(realWaits, [9, 11]);
    assert.deepEqual(routeInputs, ['decorate', 'build_next', 'wall', 'wall_next', 'wall_style', 'segment']);
    assert.deepEqual(routeOcr[0], ['case-b-category-ready', ['Tables']]);
    assert.deepEqual(routeOcr[1], ['case-b-build-exposed', ['Build']]);
    assert.equal(paused, false);
  });
}
async function verifyPhaseDeadlines() {
  const {createPhaseRunner} = require('./wall_compatibility_browser');
  const entries = [], timers = [], cleared = [];
  const run = createPhaseRunner(event => entries.push(event), (cb, ms) => {
    const timer = {cb, ms}; timers.push(timer); return timer;
  }, timer => cleared.push(timer));
  const timedOut = run('clock: pause without jump', 8000, () => new Promise(() => {}));
  assert.deepEqual(entries.map(e => [e.name, e.state]), [['clock: pause without jump', 'started']]);
  assert.equal(timers[0].ms, 8000);
  timers[0].cb();
  await assert.rejects(timedOut, /Case B host deadline: clock: pause without jump/);
  await assert.rejects(run('OCR: crop', 10000, () => {throw Error('screenshot exception');}), /screenshot exception/);
  assert.equal(await run('Apply: durable acknowledgement', 17000, () => 'opaque signal'), 'opaque signal');
  check('host phase journal distinguishes cancelled waits from real completion and errors', () => {
    assert.deepEqual(cleared, timers);
    assert.deepEqual(entries.map(e => [e.id, e.state, e.deadline_ms]),
      [[1, 'started', 8000], [1, 'timed-out', 8000], [2, 'started', 10000], [2, 'failed', 10000],
       [3, 'started', 17000], [3, 'completed', 17000]]);
    assert(entries.every(e => Number.isFinite(e.elapsed_ms) && e.elapsed_ms >= 0 && Number.isFinite(Date.parse(e.at))));
  });
}
verifyConfirmFailureEvidence().then(verifyClockWindow).then(verifyPhaseDeadlines).then(() => console.log(JSON.stringify({passed: true, checks,
  browser_runtime_exercised: false,
  method: 'native-source geometry, retained-pixel and failure-only boundary guards'})))
  .catch(error => {console.error(error); process.exitCode = 1;});
