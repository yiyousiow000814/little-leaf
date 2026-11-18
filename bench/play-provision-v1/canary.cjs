const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
(async () => {
  assert.equal(require(process.env.PLAYWRIGHT_MODULE + '/package.json').version, '1.63.0');
  const browser = await chromium.launch({headless:false, chromiumSandbox:true, channel:'chrome', timeout:15000});
  try {
    assert.equal(browser.version(), '154.0.8037.97');
    const page = await browser.newPage({viewport:{width:1360,height:880}});
    await page.setContent('<canvas></canvas><body>Little Leaf / Play A/B</body>');
    assert(await page.locator('body').innerText() === 'Little Leaf / Play A/B');
    const png = await page.screenshot({timeout:10000});
    assert(png.length > 0);
    console.log(JSON.stringify({driver:'1.63.0',browser:browser.version(),headed:true,chromiumSandbox:true,
      screenshotSha256:crypto.createHash('sha256').update(png).digest('hex')}));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode=1; });
