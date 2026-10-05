'use strict';
// Real browser storage, synthetic origins and generated profiles only.
// Linux Playwright WebKit is NOT physical iPad Safari or the real itch embed.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const engine = process.env.STORAGE_BROWSER || 'webkit';
assert(['webkit', 'chromium'].includes(engine), 'Supported engine required');
const output = path.resolve(process.env.STORAGE_REPORT || 'storage-browser-report.json');
const sources = {
  live_018: fs.readFileSync(path.join(__dirname, 'fixtures/inbox-vault-018.js'), 'utf8'),
  candidate: fs.readFileSync(path.join(root, 'web/little_leaf_vault.js'), 'utf8')
};
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
assert.equal(digest(sources.live_018), 'ce050fe7e4ba6e56086f8d2c976d04cf14976128523871d933200c4b8def716d');
assert(fs.readFileSync(path.join(root, 'web/little_leaf_shell.html'), 'utf8').includes(sources.candidate.trim()), 'Candidate shell and vault agree');
const payload = fs.readFileSync(path.join(__dirname, 'fixtures/startup-retry-v15.json'), 'utf8');
const report = {
  synthetic_only: true, engine, platform: process.platform,
  physical_ipad_safari: false, actual_game_engine: false,
  actual_itch_origin: false, security_flags_disabled: false,
  live_commit: '9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc',
  source_sha256: Object.fromEntries(Object.entries(sources).map(([key, source]) => [key, digest(source)])),
  checks: [], contexts: [], partitions: []
};
function check(condition, label) {
  assert(condition, label);
  report.checks.push({ label, passed: true });
}
const GAME = 'https://game.little-leaf-test.test';
const HOST_A = 'https://embed-host-a.test';
const HOST_B = 'https://embed-host-b.test';
async function contextFor(browser, source) {
  const context = await browser.newContext();
  context.setDefaultTimeout(15000);
  // Every request is fulfilled locally by Playwright. No DNS, credential,
  // external website, storage-access exception, or TLS bypass is involved.
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (![GAME, HOST_A, HOST_B].includes(url.origin)) return route.abort();
    if (url.pathname === '/vault.js') return route.fulfill({ contentType: 'text/javascript', body: source });
    const body = url.pathname === '/host'
      ? '<iframe id="game" src="' + GAME + '/game"></iframe>'
      : '<script src="/vault.js"></script><script>window.storageBoot = __littleLeafVault.boot();</script>';
    return route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Synthetic storage test</title>' + body });
  });
  return context;
}
async function target(page) {
  if (!page.url().endsWith('/host')) return page.mainFrame();
  await page.locator('#game').waitFor();
  const frame = await page.locator('#game').elementHandle().then(element => element.contentFrame());
  await frame.waitForURL(GAME + '/game');
  return frame;
}
async function boot(frame) {
  await frame.waitForFunction(() => !!window.storageBoot);
  return frame.evaluate(() => window.storageBoot);
}
async function records(frame) {
  return frame.evaluate(async () => {
    const request = indexedDB.open(LittleLeafVault.DB_NAME);
    const db = await new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction('profiles', 'readonly'), values = tx.objectStore('profiles').getAll();
        tx.oncomplete = () => resolve(JSON.stringify(values.result)); tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  });
}
async function commit(frame, text = payload) {
  return frame.evaluate(async text => {
    const state = await storageBoot;
    return __littleLeafVault.commit(text, JSON.parse(__littleLeafVault.bootJson).revision, state.profileId);
  }, text);
}
function retained(state, saved, label, required) {
  const same = state.ok && state.source === 'authority' && state.profileId === saved.profileId && state.revision === saved.revision && state.payload === payload;
  if (required) check(same, label);
  else check(same || (state.ok && state.source === 'fresh' && state.revision === 0) || !state.ok, label + ': result classified without guessing');
  return { label, retained: !!same, ok: state.ok, source: state.source || null, code: state.code || null, profileId: state.profileId || null, revision: state.revision ?? null };
}
async function retentionChecks(browser, key, source) {
  for (const [name, url] of [['top_level', GAME + '/game'], ['same_origin_iframe', GAME + '/host'], ['cross_site_iframe', HOST_A + '/host']]) {
    const context = await contextFor(browser, source);
    try {
      let page = await context.newPage(); await page.goto(url);
      let frame = await target(page), initial = await boot(frame);
      if (!initial.ok && name === 'cross_site_iframe') {
        report.contexts.push({ source: key, context: name, boot_blocked: true, code: initial.code, checks: [] });
        check(!initial.source, key + '/' + name + ': blocked storage is not reported as fresh');
        continue;
      }
      check(initial.ok && initial.source === 'fresh', key + '/' + name + ': fresh synthetic profile opens');
      const saved = await commit(frame);
      check(saved.ok && saved.durable && saved.revision === 1, key + '/' + name + ': IDB transaction completes');
      const entry = { source: key, context: name, profileId: saved.profileId, checks: [] };
      // Refresh the game document, then refresh its enclosing document.
      await frame.goto(GAME + '/game');
      entry.checks.push(retained(await boot(frame), saved, 'game document reload', name !== 'cross_site_iframe'));
      await page.reload(); frame = await target(page);
      entry.checks.push(retained(await boot(frame), saved, 'top document reload', name !== 'cross_site_iframe'));
      await page.close(); page = await context.newPage(); await page.goto(url); frame = await target(page);
      entry.checks.push(retained(await boot(frame), saved, 'new page, same browser context', name !== 'cross_site_iframe'));
      report.contexts.push(entry);
    } finally { await context.close(); }
  }
  const context = await contextFor(browser, source);
  try {
    const observed = [];
    for (const url of [GAME + '/game', HOST_A + '/host', HOST_B + '/host']) {
      const page = await context.newPage(); await page.goto(url); const state = await boot(await target(page));
      check(state.ok || (!state.source && url !== GAME + '/game'), key + ': partition result is readable or explicitly blocked');
      observed.push({ topOrigin: new URL(url).origin, ok: state.ok, code: state.code || null, profileId: state.profileId || null, source: state.source || null });
    }
    report.partitions.push({ source: key, observed, distinct: new Set(observed.filter(value => value.ok).map(value => value.profileId)).size });
  } finally { await context.close(); }
}
async function failureChecks(browser, key, source) {
  const context = await contextFor(browser, source);
  try {
    const page = await context.newPage(); await page.goto(GAME + '/game'); await boot(page);
    check((await commit(page)).ok, key + ': failure fixture committed');
    const before = await records(page);
    for (const failure of ['open_denied', 'read_abort']) {
      const result = await page.evaluate(async failure => {
        const open = indexedDB.open, get = IDBObjectStore.prototype.get;
        if (failure === 'open_denied') indexedDB.open = () => { throw new DOMException('Synthetic open denial', 'SecurityError'); };
        else IDBObjectStore.prototype.get = function (...args) {
          const request = get.apply(this, args);
          if (args[0] === 'active') request.addEventListener('success', () => this.transaction.abort());
          return request;
        };
        const client = LittleLeafVault.createClient();
        try { const state = await client.boot(); return { state, subsequent: await client.commit('invalid', 0, '') }; }
        finally { indexedDB.open = open; IDBObjectStore.prototype.get = get; client.close(); }
      }, failure);
      check(!result.state.ok && !result.state.source && !result.subsequent.ok && result.subsequent.code === 'NOT_READY', key + '/' + failure + ': cannot become a writable fresh profile');
      check(await records(page) === before, key + '/' + failure + ': all authority bytes unchanged');
    }
    for (const failure of ['write_abort', 'quota']) {
      const result = await page.evaluate(async ({ failure, payload }) => {
        const put = IDBObjectStore.prototype.put;
        IDBObjectStore.prototype.put = function (...args) {
          if (failure === 'quota') throw new DOMException('Synthetic quota failure', 'QuotaExceededError');
          const request = put.apply(this, args); request.addEventListener('success', () => this.transaction.abort()); return request;
        };
        try { const state = JSON.parse(__littleLeafVault.bootJson); return await __littleLeafVault.commit(payload, state.revision, state.profileId); }
        finally { IDBObjectStore.prototype.put = put; }
      }, { failure, payload: JSON.stringify({ ...JSON.parse(payload), coins: 98765 }) });
      check(!result.ok && !result.durable, key + '/' + failure + ': no successful durable acknowledgement');
      check(await records(page) === before, key + '/' + failure + ': previous profile is byte-identical');
    }
    // Hold the real transaction-completion callback. Request success must not
    // become a durable acknowledgement while the transaction is still pending.
    const delayed = await page.evaluate(async payload => {
      const original = IDBDatabase.prototype.transaction;
      let release, settled = false;
      IDBDatabase.prototype.transaction = function (...args) {
        const tx = original.apply(this, args);
        if (args[1] === 'readwrite') Object.defineProperty(tx, 'oncomplete', { configurable: true, set(callback) {
          tx.addEventListener('complete', event => { release = () => callback(event); });
        } });
        return tx;
      };
      try {
        const state = JSON.parse(__littleLeafVault.bootJson);
        const pending = __littleLeafVault.commit(payload, state.revision, state.profileId).then(result => { settled = true; return result; });
        const deadline = performance.now() + 5000;
        while (!release && performance.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
        if (!release) throw Error('Synthetic delayed completion was not reached');
        const settledBeforeCompletion = settled; release();
        return { settledBeforeCompletion, result: await pending };
      } finally { IDBDatabase.prototype.transaction = original; }
    }, payload);
    check(!delayed.settledBeforeCompletion && delayed.result.ok && delayed.result.durable, key + ': acknowledgement waits for transaction completion');
    await page.reload();
    check((await boot(page)).revision === delayed.result.revision, key + ': completed revision survives reload');
  } finally { await context.close(); }
  // A first write can fail while boot itself succeeded. Reload then sees the
  // same revision-zero profile, not a denied read or a replaced identity.
  const freshContext = await contextFor(browser, source);
  try {
    const page = await freshContext.newPage(); await page.goto(GAME + '/game');
    const initial = await boot(page);
    const firstFailure = await page.evaluate(async payload => {
      const put = IDBObjectStore.prototype.put;
      IDBObjectStore.prototype.put = () => { throw new DOMException('Synthetic quota failure', 'QuotaExceededError'); };
      try { const state = await storageBoot; return await __littleLeafVault.commit(payload, state.revision, state.profileId); }
      finally { IDBObjectStore.prototype.put = put; }
    }, payload);
    check(!firstFailure.ok && firstFailure.code === 'QuotaExceededError', key + ': initial write can fail after successful fresh boot');
    await page.reload(); const state = await boot(page);
    check(state.ok && state.source === 'fresh' && state.revision === 0 && state.profileId === initial.profileId, key + ': failed first commit reloads as fresh with the same identity');
  } finally { await freshContext.close(); }
}
async function main() {
  const options = engine === 'chromium' ? { headless: true, chromiumSandbox: true, ...(process.env.PLAYWRIGHT_CHROMIUM_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHROMIUM_CHANNEL } : {}) } : { headless: true };
  const browser = await playwright[engine].launch(options);
  report.browser_version = browser.version();
  try {
    for (const [key, source] of Object.entries(sources)) {
      await retentionChecks(browser, key, source);
      await failureChecks(browser, key, source);
    }
    report.passed = true;
    report.cross_site_reload_loss_observed = report.contexts.filter(value => value.context === 'cross_site_iframe').some(value => value.checks.some(item => !item.retained));
    report.cross_site_boot_blocked = report.contexts.some(value => value.boot_blocked);
  } finally { await browser.close(); }
}
main().catch(error => { report.passed = false; report.error = String(error.stack || error); process.exitCode = 1; }).finally(() => {
  fs.mkdirSync(path.dirname(output), { recursive: true }); fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ report: output, passed: report.passed, checks: report.checks.length, cross_site_reload_loss_observed: report.cross_site_reload_loss_observed }));
});
