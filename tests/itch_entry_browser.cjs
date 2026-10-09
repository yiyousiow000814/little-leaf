'use strict';
// Offline shell-only browser check. All origins are routed; no real itch/account access.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {execFileSync} = require('node:child_process');
const out = path.resolve(process.env.ITCH_ENTRY_EVIDENCE || 'evidence/itch-entry');
const root = path.resolve(__dirname, '..');
const candidate = fs.readFileSync(path.join(root, 'web/little_leaf_shell.html'), 'utf8');
const baseline = execFileSync('git', ['show','f690cb7e0c7d1e04c64dc6a3cf6a8cfbb0b50473:web/little_leaf_shell.html'], {cwd: root, encoding:'utf8'});
const transform = html => html.replaceAll('$GODOT_PROJECT_NAME','Little Leaf').replaceAll('$GODOT_SPLASH','splash.png')
  .replaceAll('$GODOT_URL','index.js').replaceAll('$GODOT_CONFIG','{}').replaceAll('$GODOT_THREADS_ENABLED','false').replace('$GODOT_HEAD_INCLUDE','');
(async () => {
  fs.mkdirSync(out, {recursive:true});
  const browser = await chromium.launch({executablePath:process.env.CHROME_BIN, headless:true, chromiumSandbox:true});
  let context;
  const records = [];
  try {
    context = await browser.newContext();
    let source = candidate;
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.hostname === 'shell-fixture.test') return route.fulfill({contentType:'text/html',body:'<iframe title="Offline itch fixture" src="https://html-classic.itch.zone/offline-shell" style="width:100%;height:700px" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox"></iframe>'});
      if (url.hostname === 'little-leaf-41e5d.firebaseapp.com') return route.fulfill({contentType:'text/html', body:'<title>Offline account destination fixture</title>'});
      if (url.pathname === '/splash.png') return route.fulfill({contentType:'image/png',body:fs.readFileSync(path.join(root,'assets/branding/little_leaf_approved_v3.png'))});
      if (url.pathname === '/index.js') return route.fulfill({contentType:'text/javascript',body:"window.Engine = class {static getMissingFeatures(){return [];} startGame(){window.__entryCalls.push('engine');return Promise.resolve();}};"});
      if (url.hostname === 'html-classic.itch.zone') return route.fulfill({contentType:'text/html',body:transform(source)});
      throw Error('Unplanned request: ' + url.href);
    });
    await context.addInitScript(() => {
      window.__entryCalls = [];
      const original = indexedDB.open.bind(indexedDB);
      indexedDB.open = (...args) => {window.__entryCalls.push('indexedDB');return original(...args);};
    });
    const page = await context.newPage();
    source = baseline;
    await page.setViewportSize({width:1280,height:800});
    await page.goto('https://html-classic.itch.zone/offline-shell');
    await page.screenshot({path:path.join(out,'baseline-desktop.png')});
    source = candidate;
    for (const size of [{width:1280,height:800},{width:390,height:844},{width:568,height:320}]) {
      await page.setViewportSize(size);
      await page.goto('https://html-classic.itch.zone/offline-shell');
      await page.locator('#itch-entry').waitFor({state:'visible'});
      assert.deepEqual(await page.evaluate(() => window.__entryCalls), []);
      assert.equal(await page.locator('#canvas').isVisible(), false);
      assert.equal(await page.locator('#status').isVisible(), false);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      await page.screenshot({path:path.join(out,`candidate-${size.width}x${size.height}.png`)});
      await page.locator('#itch-local').evaluate(el => el.scrollIntoView({block:'center'}));
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const box = await page.locator('#itch-local').boundingBox();
      assert(box.height >= 44 && box.y >= 0 && box.y + box.height <= size.height);
      records.push({...size,noHorizontalOverflow:true,localTouchTargetReachable:true,noLocalBootBeforeChoice:true});
    }
    await page.setViewportSize({width:1280,height:800});
    await page.goto('https://html-classic.itch.zone/offline-shell');
    await page.keyboard.press('Tab');
    assert.equal(await page.evaluate(() => document.activeElement.id), 'itch-account');
    const popupPromise = page.waitForEvent('popup');
    await page.keyboard.press('Enter');
    const popup = await popupPromise;
    await popup.waitForLoadState();
    assert.equal(popup.url(),'https://little-leaf-41e5d.firebaseapp.com/');
    assert.equal(await popup.evaluate(() => window.opener), null);
    assert.equal(await page.locator('#itch-entry').isVisible(), true);
    assert.deepEqual(await page.evaluate(() => window.__entryCalls), []);
    await popup.close();
    await page.evaluate(() => {
      window.__littleLeafVault.boot = async () => {window.__entryCalls.push('vault');};
      window.__littleLeafPreferences.boot = async () => {window.__entryCalls.push('preferences');};
    });
    await page.locator('#itch-local').click();
    await page.waitForFunction(() => window.__entryCalls.includes('engine'));
    assert.deepEqual(await page.evaluate(() => window.__entryCalls), ['vault','preferences','engine']);
    assert.equal(await page.locator('#itch-entry').isVisible(), false);
    assert.equal(await page.locator('#status').isVisible(), true);
    await page.goto('https://shell-fixture.test/');
    const frame = page.frameLocator('iframe');
    await frame.locator('#itch-entry').waitFor({state:'visible'});
    const framedPopupPromise = page.waitForEvent('popup');
    await frame.locator('#itch-account').click();
    const framedPopup = await framedPopupPromise;
    await framedPopup.waitForLoadState();
    assert.equal(framedPopup.url(),'https://little-leaf-41e5d.firebaseapp.com/');
    assert.equal(await framedPopup.evaluate(() => window.top === window.self && window.opener === null), true);
    assert.equal(await frame.locator('#itch-entry').isVisible(), true);
    await framedPopup.close();
    await page.screenshot({path:path.join(out,'candidate-framed.png')});
    fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({passed:true,base:'f690cb7e0c7d1e04c64dc6a3cf6a8cfbb0b50473',browser:await browser.version(),scope:'offline exact shell with stub engine; no compiled game or real Google sign-in',realNetwork:false,playerSaveUsed:false,records,newTabDestination:true,openerIsolated:true,keyboardNavigation:true,localBootOrder:true,framedEntryOpensTopLevel:true},null,2));
    console.log('Offline itch shell browser checks passed: 3 sizes, keyboard, new tab, isolated opener and local boot order');
  } finally {
    if (context) await context.close();
    await browser.close();
    console.log('Owned disposable browser/context closed');
  }
})().catch(error => {console.error(error);process.exitCode=1;});
