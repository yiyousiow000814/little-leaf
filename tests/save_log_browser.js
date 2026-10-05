'use strict';
// Hosted CI only: real exported Wasm/controller, sandboxed Chromium, disposable
// localhost origin. No player profile, mocked acknowledgements or injected log events.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const crypto = require('node:crypto');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {installEngineLaunchHook} = require('./engine_launch_hook');
const root = path.resolve(__dirname, '..');
const option = name => {
  const index = process.argv.indexOf(name);
  assert(index >= 0 && process.argv[index + 1], name + ' is required');
  return path.resolve(process.argv[index + 1]);
};
const web = option('--web-build'), output = option('--output');
const layout = JSON.parse(fs.readFileSync(option('--layout-report'), 'utf8'));
assert.deepEqual(layout.failures, []);
assert.deepEqual(layout.web_viewport, {width: 1360, height: 880});
const version = /config\/version="([^"]+)"/.exec(fs.readFileSync(path.join(root, 'project.godot'), 'utf8'))[1];
const logger = fs.readFileSync(path.join(root, 'web/little_leaf_save_log.js'), 'utf8');
const vault = fs.readFileSync(path.join(root, 'web/little_leaf_vault.js'), 'utf8');
const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
assert(html.includes(logger.trim()) && html.includes(vault.trim()), 'export embeds the exact diagnostic and vault sources');
const payload = fs.readFileSync(path.join(__dirname, 'fixtures/startup-retry-v15.json'), 'utf8');
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const report = {synthetic_only: true, browser_sandbox: true, checks: [], app_version: version, export_sha256: {},
  ui_scope: 'Native-derived pointer input and actual clipboard contents; frozen simulation also freezes the timed Copying label refresh. Native UI tests cover feedback labels.'};
for (const file of ['index.html', 'index.js', 'index.wasm', 'index.pck']) report.export_sha256[file] = digest(fs.readFileSync(path.join(web, file)));
function check(ok, label) {assert(ok, label); report.checks.push(label);}

async function main() {
  let browser, server, context, page;
  fs.mkdirSync(output, {recursive: true});
  try {
    server = http.createServer((request, response) => {
      const pathname = new URL(request.url, 'http://localhost').pathname;
      if (pathname === '/fixture') {
        response.setHeader('Content-Type', 'text/html');
        return response.end('<title>Disposable save log fixture</title>');
      }
      const file = path.resolve(web, '.' + pathname);
      if (!file.startsWith(web + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
        response.writeHead(404); return response.end();
      }
      response.setHeader('Content-Type', ({'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png'})[path.extname(file)] || 'application/octet-stream');
      response.end(fs.readFileSync(file));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = 'http://127.0.0.1:' + server.address().port;
    browser = await chromium.launch({headless: false, chromiumSandbox: true, channel: process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || undefined});
    report.browser_version = browser.version();
    context = await browser.newContext({viewport: layout.web_viewport, serviceWorkers: 'block'});
    const external = [];
    await context.route('**/*', route => {
      if (new URL(route.request().url()).origin === origin) return route.continue();
      external.push(route.request().url()); return route.abort();
    });
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], {origin});
    page = await context.newPage();
    const errors = [];
    report.browser_errors = errors;
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => {if (message.text().includes('SCRIPT ERROR')) errors.push(message.text());});
    await page.goto(origin + '/fixture');
    await page.addScriptTag({content: vault});
    const seeded = await page.evaluate(async text => {
      const boot = await __littleLeafVault.boot();
      const saved = await __littleLeafVault.commit(text, boot.revision, boot.profileId);
      __littleLeafVault.close(); return saved;
    }, payload);
    check(seeded.ok && seeded.durable, 'valid synthetic authority seeded only in the disposable origin');
    // Skip the welcome animation and stop simulation time, using only official
    // Engine launch options. GUI processing and the real save lifecycle still run.
    await page.addInitScript(installEngineLaunchHook, {
      args: ['--time-scale', '0', '--', '--skip-intro'], reportKey: '__saveLogBrowser'
    });
    await page.goto(origin + '/index.html?PRIVATE_QUERY_SENTINEL#PRIVATE_FRAGMENT_SENTINEL', {
      referer: origin + '/PRIVATE_REFERRER_SENTINEL?token=PRIVATE_TOKEN_SENTINEL'
    });
    await page.waitForFunction(() => !document.getElementById('status'), null, {timeout: 60000});
    await page.waitForFunction(() => globalThis.LittleLeafSaveLog?.snapshot().some(event => event.event === 'read_accepted' && event.layer === 'controller'), null, {timeout: 30000});
    check(await page.evaluate(() => __saveLogBrowser.launchCalls === 1 && JSON.stringify(__saveLogBrowser.launchArgs) === '["--time-scale","0","--","--skip-intro"]'), 'the actual exported Engine instance receives controlled launch arguments');
    const read = await page.evaluate(() => LittleLeafSaveLog.snapshot().find(event => event.event === 'read_accepted' && event.layer === 'controller'));
    check(read.source === 'authority' && read.revision === seeded.revision && /^[0-9a-f]{8}$/.test(read.profile), 'real game controller validates and accepts the seeded authority');
    // Exercise the exported game's installed DOM lifecycle listener. No direct
    // vault commit, fake controller, callback replacement or logger.record call.
    await page.waitForFunction(() => globalThis.__littleLeafLifecycleV1?.current, null, {timeout: 10000});
    await page.evaluate(() => window.dispatchEvent(new Event('pagehide')));
    await page.waitForFunction(revision => LittleLeafSaveLog.snapshot().some(event => event.event === 'save_accepted' && event.layer === 'controller' && event.revision === revision), seeded.revision + 1, {timeout: 30000});
    const events = await page.evaluate(() => LittleLeafSaveLog.snapshot());
    report.events = events;
    const requested = events.find(event => event.event === 'save_requested' && event.layer === 'controller');
    const validated = events.find(event => event.event === 'save_validated' && event.layer === 'controller');
    const submitted = events.find(event => event.event === 'save_submitted' && event.layer === 'controller');
    const confirmed = events.find(event => event.event === 'save_confirmed' && event.layer === 'vault');
    const accepted = events.find(event => event.event === 'save_accepted' && event.layer === 'controller');
    check(requested && validated && submitted && confirmed && accepted && requested.sequence < validated.sequence && validated.sequence < submitted.sequence && submitted.sequence < confirmed.sequence && confirmed.sequence < accepted.sequence, 'actual lifecycle save logs request, validation, submission, durable confirmation, then controller acceptance');
    check(accepted.revision === seeded.revision + 1 && confirmed.revision === accepted.revision && accepted.profile === read.profile, 'accepted revision and opaque profile agree across controller and vault');
    check(!events.some(event => ['save_failure', 'read_failure'].includes(event.event)), 'real exported read and save have no diagnostic failure');
    const stored = await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open(LittleLeafVault.DB_NAME);
        request.onerror = () => reject(request.error); request.onsuccess = () => resolve(request.result);
      });
      try {return await new Promise((resolve, reject) => {
        const tx = db.transaction('profiles', 'readonly'), request = tx.objectStore('profiles').get('active');
        tx.oncomplete = () => resolve({revision: request.result.revision, profileId: request.result.profileId, payload: request.result.payload});
        tx.onabort = () => reject(tx.error);
      });} finally {db.close();}
    });
    check(stored.revision === accepted.revision && stored.profileId === seeded.profileId, 'independent IndexedDB read confirms the revision the real controller accepted');
    await page.evaluate(() => navigator.clipboard.writeText('UNTOUCHED_CLIPBOARD_SENTINEL'));
    const click = async name => {
      const point = layout.web_input_points[name];
      assert(Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
      await page.mouse.click(...point); await page.waitForTimeout(250);
    };
    await page.waitForTimeout(500);
    await click('settings'); await click('log');
    await page.screenshot({path: path.join(output, 'exported-save-log-open.png')});
    check(await page.evaluate(() => navigator.clipboard.readText()) === 'UNTOUCHED_CLIPBOARD_SENTINEL', 'opening Settings and Log does not copy automatically');
    await click('copy');
    await page.waitForFunction(() => LittleLeafSaveLog.copyStatus === 'copied', null, {timeout: 10000});
    const copied = await page.evaluate(() => navigator.clipboard.readText());
    const current = await page.evaluate(() => LittleLeafSaveLog.text());
    check(copied === current && copied.startsWith('Little Leaf save log | app ' + version + '\n'), 'native-derived Settings → Log → Copy clicks copy the exact current versioned snapshot');
    check(copied.includes('origin=' + origin + ' | frame=top-level | referrerOrigin=' + origin + ' | browser=Chrome '), 'copied snapshot contains origin-only browser context');
    check(copied.includes('Latest read=') && copied.includes('read_accepted') && copied.includes('save_accepted'), 'copied snapshot retains the actual controller read and accepted save');
    for (const secret of [seeded.profileId, payload, stored.payload, 'PRIVATE_QUERY_SENTINEL', 'PRIVATE_FRAGMENT_SENTINEL', 'PRIVATE_REFERRER_SENTINEL', 'PRIVATE_TOKEN_SENTINEL', '"coins"', 'coins=', '42000']) check(!copied.includes(secret), 'snapshot omits synthetic private value ' + (secret.length > 40 ? '(payload)' : secret.startsWith('PRIVATE_') ? secret : '(identity/wallet)'));
    const allowed = new Set(['sequence', 'timestamp', 'event', 'layer', 'source', 'profile', 'revision', 'code', 'stage', 'connectionGeneration']);
    const allowedStages = new Set(['boot_open', 'transaction_create', 'object_store', 'get_identity', 'get_active', 'active_result', 'identity_result', 'compare_authority', 'put', 'transaction_complete', 'reopen_existing', 'versionchange', 'forced_close', 'save_prepare']);
    check(events.every(event => Object.keys(event).every(key => allowed.has(key))), 'actual controller events contain only approved diagnostic fields');
    check(events.every(event => !Object.hasOwn(event, 'stage') || allowedStages.has(event.stage)), 'connection stages use only the explicit sanitized stage allowlist');
    check(events.every(event => !Object.hasOwn(event, 'connectionGeneration') || (Number.isSafeInteger(event.connectionGeneration) && event.connectionGeneration > 0)), 'connection generations are positive safe integers');
    await page.keyboard.press('Escape');
    await page.evaluate(() => navigator.clipboard.writeText('SECOND_COPY_SENTINEL'));
    await click('settings'); await click('log'); await click('copy');
    await page.waitForFunction(() => LittleLeafSaveLog.copyStatus === 'copied', null, {timeout: 10000});
    check(await page.evaluate(() => navigator.clipboard.readText()) === copied, 'Escape and repeated Settings → Log → Copy remain usable without adding save events');
    check(external.length === 0, 'exported diagnostic issues no off-origin requests');
    check(errors.length === 0, 'exported game runs without browser or Godot script exceptions');
    report.snapshot_sha256 = digest(copied); report.events = events;
    fs.writeFileSync(path.join(output, 'copied-save-log.txt'), copied + '\n');
    await page.screenshot({path: path.join(output, 'exported-save-log-copied.png')});
    report.passed = true;
  } catch (error) {
    report.passed = false; report.error = error.stack; process.exitCode = 1;
    if (page) {
      report.failure_events = await page.evaluate(() => globalThis.LittleLeafSaveLog?.snapshot()).catch(() => null);
      await page.screenshot({path: path.join(output, 'exported-save-log-failure.png')}).catch(() => {});
    }
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
    fs.writeFileSync(path.join(output, 'save-log-browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
