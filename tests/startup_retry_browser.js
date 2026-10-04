'use strict';
// Only disposable headless contexts and synthetic saves are used.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/little_leaf_vault.js'), 'utf8');
const payload = fs.readFileSync(path.join(__dirname, 'fixtures/startup-retry-v15.json'), 'utf8');
const option = name => {
  const index = process.argv.indexOf(name);
  return index < 0 ? null : path.resolve(process.argv[index + 1]);
};
const web = option('--web-build');
const report = { synthetic_only: true, checks: [], engine: web ? {} : null };
function check(condition, name) {
  assert(condition, name);
  report.checks.push({ name, pass: true });
}
const digest = data => crypto.createHash('sha256').update(data).digest('hex');

async function records(page) {
  return page.evaluate(async () => {
    const request = indexedDB.open(LittleLeafVault.DB_NAME);
    const db = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction('profiles', 'readonly');
        const entries = tx.objectStore('profiles').getAll();
        tx.oncomplete = () => resolve(JSON.stringify(entries.result));
        tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  });
}

async function seed(page) {
  await page.addScriptTag({ content: source });
  return page.evaluate(async text => {
    const boot = await __littleLeafVault.boot();
    return __littleLeafVault.commit(text, boot.revision, boot.profileId);
  }, payload);
}

async function clientChecks(browser, url) {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await page.goto(url + '/empty');
    const saved = await seed(page);
    check(saved.ok && saved.durable, 'Synthetic authority seeded durably');
    const before = await records(page);
    const failure = await page.evaluate(async () => {
      __littleLeafVault.close();
      const original = indexedDB.open;
      indexedDB.open = () => { throw new DOMException('Synthetic denial', 'SecurityError'); };
      __littleLeafVault = LittleLeafVault.createClient();
      try { return await __littleLeafVault.boot(); }
      finally { indexedDB.open = original; }
    });
    check(!failure.ok && failure.code === 'SecurityError', 'Transient boot failure reproduced');
    const cached = await page.evaluate(() => __littleLeafVault.boot());
    check(!cached.ok, 'Old client retains failed boot after storage recovers');
    const recovered = await page.evaluate(() => new Promise(resolve => LittleLeafVault.retry(text => resolve(JSON.parse(text)))));
    check(recovered.ok && recovered.source === 'authority', 'Fresh-client retry opens existing authority');
    check(recovered.profileId === saved.profileId && recovered.revision === saved.revision, 'Retry preserves loaded identity and revision');
    check(JSON.parse(recovered.payload).coins === 42000, 'Retry returns original synthetic wallet');
    check(await records(page) === before, 'Retry leaves every existing authority record byte-identical');

    const stale = await page.evaluate(async text => {
      const old = LittleLeafVault.createClient();
      const boot = await old.boot();
      const saved = await __littleLeafVault.commit(text, boot.revision, boot.profileId);
      const conflict = await old.commit(text, boot.revision, boot.profileId);
      old.close();
      return { saved, conflict };
    }, payload);
    check(stale.saved.ok && !stale.conflict.ok && stale.conflict.code === 'REVISION_CONFLICT', 'Existing compare-and-swap ownership remains authoritative');

    await page.evaluate(() => new Promise((resolve, reject) => {
      const request = indexedDB.open(LittleLeafVault.DB_NAME);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const tx = db.transaction('profiles', 'readwrite');
        const store = tx.objectStore('profiles');
        const active = store.get('active');
        active.onsuccess = () => { active.result.digest = 'synthetic-damaged-checksum'; store.put(active.result, 'active'); };
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onabort = () => reject(tx.error);
      };
    }));
    const damaged = await records(page);
    const rejected = await page.evaluate(() => new Promise(resolve => LittleLeafVault.retry(text => resolve(JSON.parse(text)))));
    check(!rejected.ok && rejected.code === 'CORRUPT_AUTHORITY', 'Retry rejects damaged authority');
    check(await records(page) === damaged, 'Rejected retry cannot overwrite damaged records');
    report.authority_before_retry_sha256 = digest(before);
  } finally { await context.close(); }
}

async function engineChecks(browser, url) {
  const context = await browser.newContext({ viewport: { width: 1360, height: 880 } });
  try {
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => {
      if (message.type() === 'error' || message.text().includes('SCRIPT ERROR')) errors.push(message.text());
    });
    await page.addInitScript(() => {
      window.qa = { saves: [], acknowledgements: [] };
      let api;
      Object.defineProperty(window, '__littleLeafVault', {
        configurable: true,
        get() { return api; },
        set(value) {
          api = value;
          const save = value.save;
          value.save = function (text, revision, profile, callback) {
            qa.saves.push(JSON.parse(text));
            return save.call(this, text, revision, profile, result => {
              qa.acknowledgements.push(JSON.parse(result));
              callback(result);
            });
          };
        }
      });
      const open = indexedDB.open.bind(indexedDB);
      indexedDB.open = function (name, ...args) {
        if (name === 'little-leaf.authoritative.v1' && sessionStorage.getItem('syntheticBootFailure')) {
          sessionStorage.removeItem('syntheticBootFailure');
          throw new DOMException('Synthetic once-only storage denial', 'SecurityError');
        }
        return open(name, ...args);
      };
    });
    await page.goto(url + '/empty');
    const saved = await seed(page);
    check(saved.ok, 'Engine fixture seeded');
    const before = await records(page);
    await page.evaluate(() => { __littleLeafVault.close(); sessionStorage.setItem('syntheticBootFailure', '1'); });
    await page.goto(url + '/index.html');
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 45000 });
    await page.waitForTimeout(800);
    check(!(await page.evaluate(() => JSON.parse(__littleLeafVault.bootJson))).ok, 'Actual engine starts with protected loading failure');
    await page.keyboard.press('Enter'); // Retry receives keyboard focus in Help.
    await page.waitForFunction(() => JSON.parse(__littleLeafVault.bootJson).ok);
    await page.waitForTimeout(1000);
    const loaded = await page.evaluate(() => JSON.parse(__littleLeafVault.bootJson));
    check(loaded.profileId === saved.profileId && JSON.parse(loaded.payload).coins === 42000, 'Actual engine retry restores same authority');
    check(await records(page) === before, 'Actual engine retry leaves stored bytes unchanged');
    await page.mouse.click(905, 55);
    await page.waitForTimeout(300);
    await page.mouse.move(568, 316);
    await page.mouse.down();
    await page.mouse.move(568, 430, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(1200);
    await page.mouse.click(875, 55);
    await page.waitForFunction(() => qa.saves.length > 0 && qa.saves.length === qa.acknowledgements.length && qa.acknowledgements.at(-1).ok && qa.acknowledgements.at(-1).durable);
    const result = await page.evaluate(() => qa);
    const latest = result.saves.at(-1);
    check(JSON.stringify(latest.items) !== JSON.stringify(JSON.parse(payload).items), 'Actual furniture input changes the model');
    await page.reload();
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 45000 });
    const reloaded = await page.evaluate(() => JSON.parse(__littleLeafVault.bootJson));
    check(reloaded.profileId === saved.profileId && reloaded.revision === result.acknowledgements.at(-1).revision, 'Reload retains same identity and latest durable revision');
    check(JSON.stringify(JSON.parse(reloaded.payload)) === JSON.stringify(latest), 'Reload agrees exactly with saved payload');
    check(errors.length === 0, 'Actual engine has no browser or script errors');
    report.engine = { same_profile: true, exact_payload_reload: true, coins: latest.coins, durable_revisions: result.acknowledgements.map(x => x.revision) };
  } finally { await context.close(); }
}

(async () => {
  let browser;
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (pathname === '/empty') { response.setHeader('Content-Type', 'text/html'); return response.end('<title>Synthetic isolated test</title>'); }
    if (pathname === '/favicon.ico') { response.writeHead(204); return response.end(); }
    const filename = web && path.resolve(web, '.' + pathname);
    if (!filename || !filename.startsWith(web + path.sep) || !fs.existsSync(filename)) { response.writeHead(404); return response.end(); }
    response.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' })[path.extname(filename)] || 'application/octet-stream');
    response.end(fs.readFileSync(filename));
  });
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const options = { headless: true, chromiumSandbox: true, args: ['--mute-audio', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] };
    if (process.env.CHROMIUM_PATH) options.executablePath = process.env.CHROMIUM_PATH;
    browser = await chromium.launch(options);
    const url = 'http://127.0.0.1:' + server.address().port;
    await clientChecks(browser, url);
    if (web) await engineChecks(browser, url);
    report.passed = true;
  } catch (error) {
    report.passed = false;
    report.error = error.message;
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    const directory = path.join(root, 'qa-project/results');
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, 'startup-retry-browser.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  }
})();
