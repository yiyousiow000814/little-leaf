'use strict';
// Offline native-geometry and retained-pixel regressions. No browser or player data.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), zlib = require('node:zlib');
const {hash, requireWallBackText, requireVisibleText, verifyLayout} = require('./wall_compatibility_helpers');
const root = path.resolve(__dirname, '..'), folder = path.join(__dirname, 'fixtures/wall-ocr');
let checks = 0;
function check(label, fn) {fn(); checks++; console.log('PASS ' + label);}
const layoutSource = fs.readFileSync(path.join(__dirname, 'wall_compatibility_layout.gd'), 'utf8');
const shopSource = fs.readFileSync(path.join(root, 'scripts/cafe_shop_ui.gd'), 'utf8');
const browserSource = fs.readFileSync(path.join(__dirname, 'wall_compatibility_browser.js'), 'utf8');
const workflow = fs.readFileSync(path.join(root, '.github/workflows/build-web.yml'), 'utf8');
const size = shopSource.match(/_put\(tiles_back,Rect2\(category_margin,header_y,(\d+),(\d+)\)\)/);
check('fixture geometry is read from the real back-button layout', () => assert(size));
check('only wall_back uses complete native Button bounds with single-line 3x OCR', () => {
  assert.match(layoutSource, /result\.regions\.wall_back=region\(shop\.tiles_back\)\s+result\.regions\.wall_back\.psm=7\s+result\.regions\.wall_back\.scale=3/);
  assert(!layoutSource.includes('wall_back=text_region('));
  assert.match(layoutSource, /func region\(control:Control\)->Dictionary:\s+var rect=control\.get_global_rect\(\)/);
  assert(layoutSource.includes('"bounded visible OCR region "'));
  assert(shopSource.includes('style.content_margin_left=30;style.content_margin_right=10'));
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
  assert(workflow.includes('node tests/wall_compatibility_ocr_test.js\n'));
  const ocr = workflow.indexOf('node tests/wall_compatibility_ocr_test.js --ocr-fixtures');
  assert(ocr > workflow.indexOf('sudo apt-get install -y --no-install-recommends tesseract-ocr'));
  assert(ocr < workflow.indexOf('xvfb-run -a node tests/wall_compatibility_browser.js'));
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
const layoutIndex = process.argv.indexOf('--layout-file');
if (layoutIndex >= 0) {
  const layout = JSON.parse(fs.readFileSync(process.argv[layoutIndex + 1]));
  check('new native receipt validates and supplies full bounded button geometry', () => {
    verifyLayout(layout, 'new');
    const back = layout.regions.wall_back, catalog = layout.regions.catalog;
    assert.deepEqual([back.width, back.height], size.slice(1).map(Number));
    assert.equal(back.psm, 7); assert.equal(back.scale, 3);
    assert(back.x >= catalog.x && back.y >= catalog.y);
    assert(back.x + back.width <= catalog.x + catalog.width);
    assert(back.y + back.height <= catalog.y + catalog.height);
  });
}
if (process.argv.includes('--ocr-fixtures')) {
  const tesseract = process.env.TESSERACT_BIN || 'tesseract';
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
  console.log(JSON.stringify({ocr_fixture_checks: 'passed', results,
    tesseract: cp.execFileSync(tesseract, ['--version'], {encoding: 'utf8'}).split('\n')[0]}));
}
console.log(JSON.stringify({passed: true, checks, browser_runtime_exercised: false,
  method: 'native-source geometry and lossless retained-pixel guards'}));
