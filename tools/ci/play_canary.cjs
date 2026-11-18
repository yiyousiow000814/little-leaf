const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
(async () => {
  assert.equal(require(process.env.PLAYWRIGHT_MODULE + '/package.json').version, '1.63.0');
  const browser = await chromium.launch({headless:false, chromiumSandbox:true, channel:'chrome', timeout:15000});
  try {
    assert.equal(browser.version(), '154.0.8037.97');
    const page = await browser.newPage({viewport:{width:1360,height:880}});
    await page.setContent('<canvas></canvas><body>Little Leaf / Play A/B</body>');
    assert(await page.locator('body').innerText() === 'Little Leaf / Play A/B');
    // Rendering/OCR screenshots belong to the unchanged ordinary-Web gate, not this setup canary.
    console.log(JSON.stringify({driver:'1.63.0',browser:browser.version(),headed:true,chromiumSandbox:true,domVerified:true}));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode=1; });
