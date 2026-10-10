'use strict';
// Actual, unchanged old/new Web exports. CI only: fresh sandboxed context,
// one loopback origin, synthetic data. Never launch against a user profile.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const {installEngineLaunchHook} = require('./engine_launch_hook');
const {hash, canonical, within, verifyExport, verifyPreflightBinding, requireVisibleText, requireWallBackText, verifyLayout, selectWallReplacement, progress, assertPreserved} = require('./wall_compatibility_helpers');
const root = path.resolve(__dirname, '..');
const fixtureDir = path.join(__dirname, 'fixtures/wall-compatibility');
const contract = JSON.parse(fs.readFileSync(path.join(fixtureDir, 'contract.json')));

// Observation only. Every original storage method and save callback is invoked
// with its original receiver/arguments and its return value is preserved. No
// request, transaction, validator or acknowledgement is replaced or suppressed.
function observeOwnedTestPage() {
  const observation = window.__wallCompatibility = {saveStarts: 0, saves: [], clients: 0, writes: [], transactions: [], launchArgs: null};
  const relevant = name => name === 'little-leaf.authoritative.v1' || name === '/userfs';
  for (const method of ['add', 'put', 'delete', 'clear']) {
    const original = IDBObjectStore.prototype[method];
    IDBObjectStore.prototype[method] = function(...args) {
      if (relevant(this.transaction.db.name)) {
        const entry = {database: this.transaction.db.name, store: this.name, method, outcome: 'pending'};
        observation.writes.push(entry);
        this.transaction.addEventListener('complete', () => {entry.outcome = 'committed';}, {once: true});
        this.transaction.addEventListener('abort', () => {entry.outcome = 'aborted';}, {once: true});
      }
      return original.apply(this, args);
    };
  }
  for (const method of ['update', 'delete']) {
    const original = IDBCursor.prototype[method];
    IDBCursor.prototype[method] = function(...args) {
      const store = this.source.objectStore || this.source;
      if (relevant(store.transaction.db.name)) observation.writes.push({database: store.transaction.db.name, store: store.name, method: 'cursor.' + method});
      return original.apply(this, args);
    };
  }
  const transaction = IDBDatabase.prototype.transaction;
  IDBDatabase.prototype.transaction = function(...args) {
    const tx = transaction.apply(this, args);
    if (relevant(this.name) && tx.mode === 'readwrite') {
      const entry = {database: this.name, outcome: 'pending'};
      observation.transactions.push(entry);
      tx.addEventListener('complete', () => {entry.outcome = 'committed';}, {once: true});
      tx.addEventListener('abort', () => {entry.outcome = 'aborted';}, {once: true});
    }
    return tx;
  };
  const remove = IDBFactory.prototype.deleteDatabase;
  IDBFactory.prototype.deleteDatabase = function(name, ...args) {
    if (relevant(name)) observation.writes.push({database: name, method: 'deleteDatabase'});
    return remove.call(this, name, ...args);
  };
  let client;
  Object.defineProperty(window, '__littleLeafVault', {configurable: true, get: () => client, set(value) {
    client = value; observation.clients++;
    const save = value.save;
    value.save = function(payload, revision, profileId, callback) {
      observation.saveStarts++;
      return save.call(this, payload, revision, profileId, function(...args) {
        try {
          const result = JSON.parse(args[0]);
          observation.saves.push({ok: result.ok, code: result.code || null, revision: result.revision ?? null,
            durable: result.durable || false, creditedCoins: result.creditedCoins ?? null});
        } catch (_) {
          observation.saves.push({ok: false, observation_error: 'Malformed save acknowledgement'});
        }
        // Even malformed replies still reach the real controller unchanged.
        return callback(...args);
      });
    };
  }});

}

async function readSnapshot(page) {
  return page.evaluate(async () => {
    function encode(value) {
      if (value instanceof Date) return {date: value.toISOString()};
      if (ArrayBuffer.isView(value)) return {type: value.constructor.name, bytes: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength))};
      if (value instanceof ArrayBuffer) return {type: 'ArrayBuffer', bytes: Array.from(new Uint8Array(value))};
      if (Array.isArray(value)) return value.map(encode);
      if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, encode(value[key])]));
      return value;
    }
    async function rows(name, store) {
      const db = await new Promise((resolve, reject) => {
        const q = indexedDB.open(name); q.onerror = () => reject(q.error);
        q.onupgradeneeded = () => {q.transaction.abort(); reject(Error('Expected seeded database is absent'));};
        q.onsuccess = () => resolve(q.result);
      });
      try {
        return await new Promise((resolve, reject) => {
          const tx = db.transaction(store, 'readonly'), keys = tx.objectStore(store).getAllKeys(), values = tx.objectStore(store).getAll();
          tx.oncomplete = () => resolve(keys.result.map((key, i) => [key, encode(values.result[i])]));
          tx.onabort = () => reject(tx.error);
        });
      } finally {db.close();}
    }
    return {authority: await rows('little-leaf.authoritative.v1', 'profiles'), legacy: await rows('/userfs', 'FILE_DATA')};
  });
}
const active = snapshot => snapshot.authority.find(([key]) => key === 'active')[1];
async function observation(page) {return page.evaluate(() => structuredClone(__wallCompatibility));}
async function idle(page) {
  await page.waitForFunction(() => __wallCompatibility.saveStarts === __wallCompatibility.saves.length, null, {timeout: 15000});
}
async function stableSnapshot(page) {
  let previous = '', count = 0;
  for (let i = 0; i < 50; i++) {
    const snapshot = await readSnapshot(page), serialized = canonical(snapshot);
    count = serialized === previous ? count + 1 : 0; previous = serialized;
    if (count >= 5) return snapshot;
    await page.waitForTimeout(100);
  }
  throw Error('Authority never became quiescent for the boundary snapshot');
}
async function seed(page, oldSource, oldText, newSource, newText) {
  await page.addScriptTag({content: oldSource});
  const first = await page.evaluate(async text => {
    const legacy = JSON.parse(text); legacy.version = 13; delete legacy.layout_motion_format;
    await new Promise((resolve, reject) => {
      const q = indexedDB.open('/userfs', 21);
      q.onupgradeneeded = () => q.result.createObjectStore('FILE_DATA');
      q.onerror = () => reject(q.error);
      q.onsuccess = () => {
        const db = q.result, tx = db.transaction('FILE_DATA', 'readwrite');
        tx.objectStore('FILE_DATA').put({contents: new Int8Array(new TextEncoder().encode(JSON.stringify(legacy)).buffer), mode: 33188, timestamp: new Date(1000)}, '/userfs/synthetic/little_leaf_cafe_v13.json');
        tx.oncomplete = () => {db.close(); resolve();}; tx.onabort = () => {db.close(); reject(tx.error);};
      };
    });
    const client = LittleLeafVault.createClient(), boot = await client.boot();
    if (!boot.ok || boot.source !== 'legacy-v13') throw Error('Old vault must verify signed-byte synthetic legacy');
    const result = await client.commit(text, boot.revision, boot.profileId); client.close(); return result;
  }, oldText);
  assert(first.ok && first.durable && first.creditedCoins === 1000 && first.revision === 1, 'Exact old vault creates durable receipt');
  if (newText) {
    await page.addScriptTag({content: newSource});
    const committed = await page.evaluate(async text => {
      const payload = JSON.parse(text); payload.coins += 1000;
      const client = LittleLeafVault.createClient(), boot = await client.boot();
      const result = await client.commit(JSON.stringify(payload), boot.revision, boot.profileId); client.close(); return result;
    }, newText);
    assert(committed.ok && committed.durable && committed.revision === 2 && committed.creditedCoins === 0);
  }
  return readSnapshot(page);
}

async function main() {
  const argument = name => {const i = process.argv.indexOf('--' + name); assert(i >= 0 && process.argv[i + 1], '--' + name + ' is required'); return path.resolve(process.argv[i + 1]);};
  const oldWeb = argument('old-web'), newWeb = argument('new-web'), oldSourceRoot = argument('old-source');
  const layoutDir = argument('layout-dir'), output = argument('output');
  const tesseract = process.env.TESSERACT_BIN || 'tesseract';
  fs.mkdirSync(output, {recursive: true});
  const report = {status: 'running', browser_verified: false, synthetic_only: true, checks: [], cases: {}, errors: []};
  const check = (ok, label) => {assert(ok, label); report.checks.push(label);};
  let browser, server;
  try {
    const preflight = JSON.parse(fs.readFileSync(path.join(layoutDir, 'preflight.json')));
    assert.equal(preflight.status, 'passed');
    const newCommit = cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
    assert.equal(preflight.new_commit, newCommit); assert.equal(preflight.old_commit, contract.old_commit);
    const manifests = {
      old: verifyExport(oldWeb, contract.old_commit, {'web/little_leaf_vault.js': contract.old_vault_sha256}),
      new: verifyExport(newWeb, newCommit, preflight.production_sha256.new)
    };
    for (const [label, web, source] of [['old', oldWeb, oldSourceRoot], ['new', newWeb, root]]) {
      verifyPreflightBinding(web, source, manifests[label], preflight.production_sha256[label], preflight.export_manifest_sha256[label]);
    }
    for (const name of contract.candidate_required_sources) assert(Object.hasOwn(preflight.production_sha256.new, name), 'Missing required candidate source ' + name);
    assert.equal(canonical(manifests.old.toolchain_receipt), canonical(manifests.new.toolchain_receipt));
    const layouts = {};
    for (const label of ['old', 'new']) {
      const file = fs.readFileSync(path.join(layoutDir, label + '-layout.json'));
      assert.equal(hash(file), preflight.layouts[label].sha256);
      layouts[label] = JSON.parse(file); verifyLayout(layouts[label], label);
    }
    const fixtures = {};
    for (const [name, digest] of Object.entries(contract.fixture_sha256)) {
      const bytes = fs.readFileSync(path.join(fixtureDir, name)); assert.equal(hash(bytes), digest); fixtures[name] = bytes.toString('utf8');
    }
    const oldSource = fs.readFileSync(path.join(oldSourceRoot, 'web/little_leaf_vault.js'), 'utf8');
    const newSource = fs.readFileSync(path.join(root, 'platform/web/little_leaf_vault.js'), 'utf8');
    assert.equal(hash(oldSource), contract.old_vault_sha256);
    assert.equal(hash(newSource), preflight.production_sha256.new['web/little_leaf_vault.js']);
    report.inputs = {old_commit: contract.old_commit, new_commit: newCommit, fixture_sha256: contract.fixture_sha256,
      old_vault_sha256: hash(oldSource), new_vault_sha256: hash(newSource),
      export_files: {old: manifests.old.files, new: manifests.new.files}, preflight_sha256: hash(fs.readFileSync(path.join(layoutDir, 'preflight.json')))};
    report.ocr = {version: cp.execFileSync(tesseract, ['--version'], {encoding: 'utf8'}).split('\n')[0],
      wall_back: {psm: 7, scale: 3, thresholding_method: 2, thresholding_mode: 'sauvola'}};
    server = http.createServer((req, res) => {
      try {
        const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
        res.setHeader('Cache-Control', 'no-store');
        if (pathname === '/favicon.ico') {res.writeHead(204); return res.end();}
        if (pathname === '/fixture') {res.setHeader('Content-Type', 'text/html'); return res.end('<title>Disposable wall compatibility fixture</title>');}
        const label = pathname.split('/')[1]; assert(['old', 'new'].includes(label));
        const file = within(label === 'old' ? oldWeb : newWeb, pathname.slice(label.length + 2));
        assert(fs.statSync(file).isFile());
        res.setHeader('Content-Type', ({'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png'})[path.extname(file)] || 'application/octet-stream');
        res.end(fs.readFileSync(file));
      } catch (_) {res.writeHead(404); res.end();}
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = 'http://127.0.0.1:' + server.address().port;
    const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
    const channel = process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || undefined;
    browser = await chromium.launch({headless: false, chromiumSandbox: true, channel});
    report.browser = {channel: channel || 'bundled Chromium', version: browser.version(),
      playwright: require(path.join(process.env.PLAYWRIGHT_MODULE || 'playwright', 'package.json')).version, sandbox: true};
    const createPage = async (context, scale) => {
      const page = await context.newPage();
      await page.addInitScript(observeOwnedTestPage);
      await page.addInitScript(installEngineLaunchHook, {
        args: ['--time-scale', String(scale), '--', '--skip-intro'], reportKey: '__wallCompatibility'});
      page.on('pageerror', error => report.errors.push(String(error)));
      page.on('crash', () => report.errors.push('Exported game page crashed'));
      page.on('console', message => {if (message.type() === 'error' || /SCRIPT ERROR:|^ERROR:|Aborted\(|RuntimeError/.test(message.text())) report.errors.push(message.text());});
      return page;
    };
    const createContext = async () => {
      const context = await browser.newContext({viewport: {width: 1360, height: 880}, deviceScaleFactor: 1, serviceWorkers: 'block'});
      await context.route('**/*', route => {
        if (new URL(route.request().url()).origin === origin) return route.continue();
        report.errors.push('Unexpected non-loopback request blocked in disposable test context');
        return route.abort();
      });
      return context;
    };
    const boot = async (page, label, revision) => {
      await page.goto(origin + '/' + label + '/index.html');
      await page.waitForFunction(() => !document.getElementById('status'), null, {timeout: 90000});
      await page.waitForTimeout(500);
      const result = await page.evaluate(() => JSON.parse(__littleLeafVault.bootJson));
      check(result.ok && result.source === 'authority' && result.revision === revision, label + ' actual export reads the expected verified authority revision');
      check((await observation(page)).launchArgs !== null, label + ' accepts supported runtime launch arguments');
    };
    const click = async (page, label, name, delay = 250) => {
      const point = layouts[label].points[name]; assert(point && point.length === 2, 'Derived point ' + name);
      await page.mouse.click(...point); await page.waitForTimeout(delay);
    };
    const screenText = async (page, label, name, phrases) => {
      await page.waitForTimeout(200);
      const screenshot = path.join(output, name + '.png'); await page.screenshot({path: screenshot});
      const crop = path.join(output, name + '-help.png');
      await page.screenshot({path: crop, clip: layouts[label].help_rect});
      const text = cp.execFileSync(tesseract, [crop, 'stdout', '-l', 'eng', '--psm', '6'], {encoding: 'utf8', timeout: 30000, env: {...process.env, OMP_THREAD_LIMIT: '1'}});
      fs.writeFileSync(path.join(output, name + '-ocr.txt'), text);
      requireVisibleText(text, phrases);
      check(true, name + ' rendered Help text verified by local OCR');
    };
    const screenUiText = async (page, name, region, phrases, retryTarget = null) => {
      const regions = (Array.isArray(region) ? region : [region]).map(key => {
        const spec = layouts.new.regions?.[key];
        assert(spec && spec.width > 0 && spec.height > 0, 'Derived UI region ' + key);
        return {key, ...spec};
      });
      const deadline = Date.now() + 45000;
      let lastError;
      do {
        // Build category selection is idempotent. The real tray disables input
        // during its opening tween, so a slow exported frame may ignore the
        // first click even after a fixed wall-clock delay. Never retry payment.
        if (retryTarget) await click(page, 'new', retryTarget, 0);
        await page.waitForTimeout(400);
        await page.screenshot({path: path.join(output, name + '.png')});
        const texts = [];
        for (const spec of regions) {
          const {x, y, width, height} = spec;
          const crop = path.join(output, name + '-' + spec.key + '-crop.png');
          const png = await page.screenshot({path: crop, clip: {x, y, width, height}});
          let input = crop;
          if (spec.scale > 1) {
            // Preserve raw evidence. This separate OCR input repeats each
            // original pixel exactly, using an unattached canvas. It does not
            // change the game canvas, DOM, storage, or production code.
            const bytes = await page.evaluate(async ({base64, scale}) => {
              const raw = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
              const bitmap = await createImageBitmap(new Blob([raw], {type: 'image/png'}));
              const canvas = new OffscreenCanvas(bitmap.width * scale, bitmap.height * scale);
              const context = canvas.getContext('2d'); context.imageSmoothingEnabled = false;
              context.drawImage(bitmap, 0, 0, canvas.width, canvas.height); bitmap.close();
              const blob = await canvas.convertToBlob({type: 'image/png'});
              return Array.from(new Uint8Array(await blob.arrayBuffer()));
            }, {base64: png.toString('base64'), scale: spec.scale});
            input = path.join(output, name + '-' + spec.key + '-ocr-input.png');
            fs.writeFileSync(input, Buffer.from(bytes));
          }
          // The complete back button includes its illustrated border. Use a
          // fixed local threshold mode for that crop only, never looser text.
          const threshold = spec.key === 'wall_back' ? ['-c', 'thresholding_method=2'] : [];
          texts.push(cp.execFileSync(tesseract, [input, 'stdout', '-l', 'eng', '--psm', String(spec.psm || 6), ...threshold],
            {encoding: 'utf8', timeout: Math.max(1000, Math.min(30000, deadline - Date.now())),
              env: {...process.env, OMP_THREAD_LIMIT: '1'}}));
        }
        const text = texts.join('\n');
        fs.writeFileSync(path.join(output, name + '-ocr.txt'), text);
        try {
          const backIndex = regions.findIndex(spec => spec.key === 'wall_back');
          if (backIndex >= 0) requireWallBackText(texts[backIndex]);
          requireVisibleText(text, phrases);
          check(true, name + ' rendered UI state verified before the next action');
          return;
        } catch (error) {lastError = error;}
      } while (Date.now() < deadline);
      throw lastError;
    };
    const assertUnchanged = async (page, baseline, name) => {
      const after = await stableSnapshot(page);
      check(canonical(after) === canonical(baseline), name + ': all authority/identity/previous/receipt and legacy bytes unchanged');
      const observed = await observation(page);
      check(observed.writes.length === 0, name + ': zero old-client authority or legacy mutation calls');
      return {before_sha256: hash(canonical(baseline)), after_sha256: hash(canonical(after)), observation: observed};
    };
    const verifyNewReload = async (context, baseline, name) => {
      const page = await createPage(context, 0);
      await page.bringToFront();
      await boot(page, 'new', active(baseline).revision);
      const starts = (await observation(page)).saveStarts;
      await click(page, 'new', 'business'); await idle(page);
      const observed = await observation(page);
      check(observed.saveStarts === starts + 1 && observed.saves.at(-1).ok && observed.saves.at(-1).durable,
        name + ': actual reloaded new controller accepts model and completes a normal UI save');
      const after = await readSnapshot(page);
      assertPreserved(active(baseline), active(after));
      check(canonical(after.legacy) === canonical(baseline.legacy), name + ': legacy bytes retained');
      await page.screenshot({path: path.join(output, name + '.png')});
      // A normal operating-open toggle is deliberately not part of the preserved
      // wall/wallet/receipt projection. Lifecycle saves may advance revision.
      return {revision_before: active(baseline).revision, revision_after: active(after).revision,
        preserved_progress_sha256: hash(canonical(progress(active(after))))};
    };

    // Case A: real old engine rejects a format it cannot understand. Scale 1
    // allows a full >15-second autosave interval while recovery pauses service.
    {
      const context = await createContext();
      try {
        const fixture = await context.newPage(); await fixture.goto(origin + '/fixture');
        const baseline = await seed(fixture, oldSource, fixtures['old-format1.json'], newSource, fixtures['new-format2.json']);
        const page = await createPage(context, 1); await page.bringToFront(); await boot(page, 'old', active(baseline).revision);
        await screenText(page, 'old', 'case-a-old-recovery', ['Invalid saved wall or finish data', 'original progress is unchanged']);
        for (let i = 0; i < 2; i++) {
          const clients = (await observation(page)).clients;
          await click(page, 'old', 'retry');
          await page.waitForFunction(previous => __wallCompatibility.clients > previous, clients);
          await screenText(page, 'old', 'case-a-retry-' + (i + 1), ['Invalid saved wall or finish data']);
        }
        await page.keyboard.press('Escape');
        await click(page, 'old', 'business'); await click(page, 'old', 'decorate');
        await page.waitForTimeout(16500);
        await page.keyboard.press('F1');
        await screenText(page, 'old', 'case-a-after-autosave', ['Invalid saved wall or finish data', 'original progress is unchanged']);
        report.cases.old_opened_after_new = await assertUnchanged(page, baseline, 'Case A');
        report.cases.old_opened_after_new.reload = await verifyNewReload(context, baseline, 'case-a-new-restored');
      } finally {await context.close();}
    }
    // Case B: the old engine stays genuinely loaded throughout the real new UI
    // edit. Its scale 0 prevents unrelated old autosaves. New scale .1 keeps UI
    // tweens working and gives a 150-second autosave interval for this short edit.
    {
      const context = await createContext();
      try {
        const fixture = await context.newPage(); await fixture.goto(origin + '/fixture');
        const seeded = await seed(fixture, oldSource, fixtures['old-format1.json']);
        const oldPage = await createPage(context, 0), newPage = await createPage(context, .1);
        await oldPage.bringToFront(); await boot(oldPage, 'old', active(seeded).revision);
        // Prove the real old controller accepted its model, then restore the
        // operating state. A vault-only boot result is not engine acceptance.
        await click(oldPage, 'old', 'business'); await idle(oldPage);
        await click(oldPage, 'old', 'business'); await idle(oldPage);
        const acceptedOld = await observation(oldPage);
        check(acceptedOld.saves.length === 2 && acceptedOld.saves.every(result => result.ok && result.durable),
          'Actual old engine accepts format 1 and durably saves ordinary UI actions');
        // Let an ordinary page-hide save settle BEFORE the new engine loads R.
        await newPage.bringToFront(); await idle(oldPage);
        const baseline = await stableSnapshot(fixture), revision = active(baseline).revision;
        const oldBoot = await oldPage.evaluate(() => JSON.parse(__littleLeafVault.bootJson));
        check(oldBoot.revision === revision && JSON.parse(oldBoot.payload).wall_format === 1, 'Genuinely loaded old engine and authority share revision R');
        // Start observation at R, before the new engine opens. Never clear a
        // post-commit old mutation, even if it happened on a focus transition.
        await oldPage.evaluate(() => {__wallCompatibility.writes = []; __wallCompatibility.transactions = []; __wallCompatibility.saves = []; __wallCompatibility.saveStarts = 0;});
        await boot(newPage, 'new', revision);
        await selectWallReplacement(
          (name, delay) => click(newPage, 'new', name, delay),
          (name, region, phrases, retryTarget) => screenUiText(newPage, name, region, phrases, retryTarget));
        check((await observation(newPage)).saveStarts === 0, 'New tray/product/target actions cause no save before the verified wall confirmation');
        await click(newPage, 'new', 'confirm'); await idle(newPage);
        const committed = await readSnapshot(fixture), payload = JSON.parse(active(committed).payload);
        report.new_ui_edit = {revision_before: revision, revision_after: active(committed).revision,
          wall_format: payload.wall_format, target: 'shell:back#2', expected_segment: layouts.new.expected_segment,
          actual_segment: payload.shell_segment_products?.['shell:back#2'] || null};
        check(active(committed).revision === revision + 1, 'Normal new UI edit commits exactly R+1');
        check(payload.wall_format === 2 && canonical(payload.shell_segment_products['shell:back#2']) === canonical(layouts.new.expected_segment), 'Real new UI commits the expected one-tile wall format 2 edit');
        check(payload.coins === JSON.parse(active(baseline).payload).coins - layouts.new.expected_cost, 'Real new UI charges the expected wall price once');
        check(canonical(payload.wall_attachments) === canonical(JSON.parse(active(baseline).payload).wall_attachments), 'Real new UI retains paid wide door geometry and ownership');
        check(canonical(active(committed).campaigns) === canonical(active(baseline).campaigns), 'New commit retains compensation receipt without a second grant');
        check((await observation(newPage)).saves.some(result => result.ok && result.durable && result.revision === revision + 1 && result.creditedCoins === 0), 'Actual new controller receives durable R+1 acknowledgement');
        await newPage.screenshot({path: path.join(output, 'case-b-new-committed.png')});
        await oldPage.bringToFront(); await idle(newPage);
        // Settle and close the successful new writer before testing forbidden
        // old writes. Otherwise a later foreground switch can legitimately
        // trigger another new page-hide save and muddy the byte-equality check.
        await newPage.close();
        const protectedSnapshot = await stableSnapshot(fixture);
        assertPreserved(active(committed), active(protectedSnapshot));
        await click(oldPage, 'old', 'business'); await idle(oldPage);
        let observed = await observation(oldPage);
        check(observed.saves.length === 1 && observed.saves[0].ok === false && observed.saves[0].code === 'REVISION_CONFLICT', 'Actual stale old UI save receives REVISION_CONFLICT from real IndexedDB CAS');
        await oldPage.keyboard.press('F1');
        await screenText(oldPage, 'old', 'case-b-old-conflict', ['Saving is paused to protect your progress', 'Another tab saved newer progress']);
        await oldPage.keyboard.press('Escape');
        await click(oldPage, 'old', 'business'); await click(oldPage, 'old', 'decorate');
        // Normal visibility transitions also request save through the engine.
        await fixture.bringToFront(); await oldPage.bringToFront(); await idle(oldPage);
        observed = await observation(oldPage);
        check(observed.saves.length === 1 && observed.saveStarts === 1, 'Repeated old UI/lifecycle attempts are suppressed by the faulted controller');
        report.cases.already_open_old = await assertUnchanged(oldPage, protectedSnapshot, 'Case B');
        report.cases.already_open_old.revision_r = revision;
        report.cases.already_open_old.edit_revision = active(committed).revision;
        report.cases.already_open_old.lifecycle_revision = active(protectedSnapshot).revision;
        const reloadBaseline = await stableSnapshot(fixture);
        assertPreserved(active(protectedSnapshot), active(reloadBaseline));
        await boot(oldPage, 'old', active(reloadBaseline).revision);
        await screenText(oldPage, 'old', 'case-b-old-reloaded', ['Invalid saved wall or finish data', 'original progress is unchanged']);
        await assertUnchanged(oldPage, reloadBaseline, 'Case B old reload');
        report.cases.already_open_old.reload = await verifyNewReload(context, reloadBaseline, 'case-b-new-restored');
      } finally {await context.close();}
    }
    check(report.errors.length === 0, 'Both actual exports run without unexpected script/browser errors');
    report.status = 'passed'; report.browser_verified = true;
  } catch (error) {
    report.status = 'failed'; report.error = error.stack; process.exitCode = 1;
  } finally {
    if (browser) {
      try {await browser.close();} catch (error) {report.errors.push('Browser cleanup: ' + String(error)); report.status = 'failed'; report.browser_verified = false; process.exitCode = 1;}
    }
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
    fs.writeFileSync(path.join(output, 'wall-compatibility-browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {observeOwnedTestPage, readSnapshot};
