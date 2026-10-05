'use strict';
// CI-only real Chromium + exported Web check under Xvfb. Every browser context is fresh,
// localhost-only, synthetic, and discarded. No security flags are disabled.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const {installEngineLaunchHook}=require('./engine_launch_hook');
const root=path.resolve(__dirname,'..');
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:path.resolve(process.argv[i+1]);};
const web=arg('--web-build'),output=arg('--output'),layoutFile=arg('--layout-report');
if(!web||!output||!layoutFile)throw Error('--web-build, --output and --layout-report are required');
fs.mkdirSync(output,{recursive:true});
const layout=JSON.parse(fs.readFileSync(layoutFile,'utf8'));assert(!layout.failures.length);const points=layout.web_input_points;
const report={synthetic_only:true,checks:[],source_sha256:{}};
report.export_js_sha256=crypto.createHash('sha256').update(fs.readFileSync(path.join(web,'index.js'))).digest('hex');
report.web_template_sha256=JSON.parse(fs.readFileSync(path.join(web,'release-manifest.json'),'utf8')).web_template_sha256;
report.launch_hook_scope='Pass through the original feature check; wrap only the actual shell instance startup with official clock arguments';
report.source_sha256['tests/engine_launch_hook.js']=crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'engine_launch_hook.js'))).digest('hex');
const sources={};for(const [key,file] of Object.entries({old:'tests/fixtures/inbox-vault-018.js',vault:'web/little_leaf_vault.js',markers:'web/little_leaf_inbox.js',suite:'tests/compensation_inbox_suite.js'})){sources[key]=fs.readFileSync(path.join(root,file),'utf8');report.source_sha256[file]=crypto.createHash('sha256').update(sources[key]).digest('hex');}
const check=(ok,name)=>{assert(ok,name);report.checks.push(name);};
(async()=>{
 let browser,server;
 try{
  server=http.createServer((req,res)=>{const pathname=new URL(req.url,'http://localhost').pathname;if(pathname==='/fixture'){res.setHeader('Content-Type','text/html');return res.end('<title>Disposable Inbox storage test</title>');}const file=path.resolve(web,'.'+pathname);if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){res.writeHead(404);return res.end();}res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');res.end(fs.readFileSync(file));});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const channel=process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||undefined;
  browser=await chromium.launch({headless:false,chromiumSandbox:true,channel});
  report.browser={channel:channel||'bundled Chromium',version:browser.version(),playwright:require(path.join(process.env.PLAYWRIGHT_MODULE||'playwright','package.json')).version,sandbox:true};
  const context=await browser.newContext({viewport:{width:1360,height:880}}),page=await context.newPage(),url='http://127.0.0.1:'+server.address().port;
  await page.goto(url+'/fixture');
  await page.addScriptTag({content:sources.old});await page.evaluate(()=>window.oldVault=LittleLeafVault);
  for(const key of ['vault','markers','suite'])await page.addScriptTag({content:sources[key]});
  report.storage=await page.evaluate(async()=>runInboxSuite({vault:LittleLeafVault,oldVault,factory:indexedDB,storePrototype:IDBObjectStore.prototype,markers:LittleLeafInbox,storage:localStorage,runId:crypto.randomUUID()}));
  check(report.storage.passed,'real IndexedDB/localStorage regression suite passes');
  // Seed the production namespace only inside this disposable test origin.
  // Use a real engine-loadable fixture with a verified synthetic legacy origin.
  const payload=fs.readFileSync(path.join(__dirname,'fixtures/startup-retry-v15.json'),'utf8');
  const seeded=await page.evaluate(async text=>{
   const raw=JSON.parse(text),old={...raw,version:13};delete old.layout_motion_format;
   await new Promise((resolve,reject)=>{const q=indexedDB.open('/userfs',21);q.onupgradeneeded=()=>q.result.createObjectStore('FILE_DATA');q.onsuccess=()=>{const db=q.result,tx=db.transaction('FILE_DATA','readwrite');tx.objectStore('FILE_DATA').put({contents:new Int8Array(new TextEncoder().encode(JSON.stringify(old)).buffer),mode:33188,timestamp:new Date(1000)},'/userfs/synthetic/little_leaf_cafe_v13.json');tx.oncomplete=()=>{db.close();resolve();};tx.onabort=()=>reject(tx.error);};q.onerror=()=>reject(q.error);});
   const client=LittleLeafVault.createClient();const boot=await client.boot();const saved=await client.commit(text,boot.revision,boot.profileId);client.close();return saved;
  },payload);
  check(seeded.ok&&seeded.creditedCoins===1000,'exported engine scenario starts with durable historical receipt');
  // Capture authority state before the actual UI opens any Inbox message.
  const readRecords=()=>page.evaluate(async()=>new Promise((resolve,reject)=>{const q=indexedDB.open('little-leaf.authoritative.v1');q.onsuccess=()=>{const db=q.result,tx=db.transaction('profiles','readonly'),r=tx.objectStore('profiles').getAll();tx.oncomplete=()=>{db.close();resolve(JSON.stringify(r.result));};tx.onabort=()=>reject(tx.error);};q.onerror=()=>reject(q.error);}));
  const before=await readRecords(),errors=[];
  page.on('pageerror',error=>errors.push(String(error)));page.on('console',message=>{if(message.text().includes('SCRIPT ERROR'))errors.push(message.text());});
  // Supply an official runtime launch argument through the exported Engine
  // API. Zero simulation delta removes slow-CI autosave timing races while
  // keeping native GUI input, rendering, vault commits and read markers real.
  await page.addInitScript(installEngineLaunchHook,{args:['--time-scale','0'],reportKey:'inboxTestLaunch'});
  await page.goto(url+'/index.html');await page.waitForFunction(()=>!document.getElementById('status'),null,{timeout:60000});await page.waitForTimeout(1500);
  report.launch_hook=await page.evaluate(()=>window.inboxTestLaunch);
  check(report.launch_hook?.launchCalls===1&&JSON.stringify(report.launch_hook.launchArgs)==='[\"--time-scale\",\"0\"]','exported Engine accepts controlled test clock arguments');
  check(await page.evaluate(()=>JSON.parse(__littleLeafVault.snapshotJson()).paid.length===1),'actual exported shell retains historical snapshot on reload');
  const click=async name=>{assert(points[name]&&points[name].length===2);await page.mouse.click(...points[name]);await page.waitForTimeout(150);};
  await click('settings');await click('inbox');
  check(await page.evaluate(()=>{const s=JSON.parse(__littleLeafVault.snapshotJson()),r=s.paid[0];return !__littleLeafInbox.isRead(s.profileId,r.id,r.revision);}), 'opening actual Inbox list does not consume unread receipt');
  await page.screenshot({path:path.join(output,'exported-inbox-history.png')});
  await click('first_message');
  check(await page.evaluate(()=>{const s=JSON.parse(__littleLeafVault.snapshotJson()),r=s.paid[0];return __littleLeafInbox.isRead(s.profileId,r.id,r.revision);}), 'opening actual message detail acknowledges its paid receipt');
  await page.screenshot({path:path.join(output,'exported-inbox-detail.png')});
  await page.keyboard.press('Escape');
  await click('settings');await click('inbox');await page.keyboard.press('Escape');
  check(await readRecords()===before,'actual Inbox open/read/reopen/Escape leaves authority byte-identical');
  report.authority_after_inbox_sha256=crypto.createHash('sha256').update(await readRecords()).digest('hex');
  await page.reload();await page.waitForFunction(()=>!document.getElementById('status'),null,{timeout:60000});
  check(await page.evaluate(()=>{const s=JSON.parse(__littleLeafVault.snapshotJson()),r=s.paid[0];return __littleLeafInbox.isRead(s.profileId,r.id,r.revision);}), 'embedded read sidecar survives real exported-Web reload');
  report.authority_before_sha256=crypto.createHash('sha256').update(before).digest('hex');
  report.authority_after_sha256=crypto.createHash('sha256').update(await readRecords()).digest('hex');
  const afterReload=JSON.parse(await readRecords()).find(row=>row.payload);
  const beforeRecord=JSON.parse(before).find(row=>row.payload);
  check(JSON.parse(afterReload.payload).coins===JSON.parse(beforeRecord.payload).coins&&JSON.stringify(afterReload.campaigns)===JSON.stringify(beforeRecord.campaigns),'reload retains wallet and immutable receipt; normal lifecycle save may advance revision');
  check(errors.length===0,'exported engine runs without script/browser exceptions');
  await page.screenshot({path:path.join(output,'exported-inbox-startup.png')});
  await context.close();report.passed=true;
 }catch(error){report.passed=false;report.error=error.stack;process.exitCode=1;}
 finally{if(browser)await browser.close();if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'compensation-inbox-browser.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));}
})();
