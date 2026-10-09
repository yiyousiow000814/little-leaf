'use strict';
// Scheduling/loader timings of the exact checked ordinary-Web export.
// No screenshots or audio reads during timing. This is not device FPS proof.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const {verifyExport, hash} = require('./wall_compatibility_helpers');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const args = process.argv.slice(2), value = name => args[args.indexOf(name)+1];
const web = path.resolve(value('--web-build')), output = path.resolve(value('--output'));
const manifest = JSON.parse(fs.readFileSync(path.join(web,'release-manifest.json')));
const root=args.includes('--source-root')?path.resolve(value('--source-root')):path.resolve(__dirname,'..');
const expected=cp.execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
const names=cp.execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0').filter(n=>['project.godot','main.tscn','export_presets.cfg'].includes(n)||['assets','data','scripts','shaders','web'].includes(n.split('/')[0]));
const sourceHashes=Object.fromEntries(names.map(n=>[n,hash(fs.readFileSync(path.join(root,n)))]));
assert.deepEqual(sourceHashes,manifest.production_sha256,'Complete exported source map must match this checkout');
verifyExport(web,expected,sourceHashes);
fs.mkdirSync(output,{recursive:true});
const report = {source_commit:manifest.source_commit,manifest_sha256:hash(fs.readFileSync(path.join(web,'release-manifest.json'))),trials:[],scope:'Browser rAF scheduling and loader visibility; fresh disposable origin, no input/audio claim; HTTP-cache warmth is separate from newly created atlas objects.'};
function summarize(rows) {
 const v=rows.slice().sort((a,b)=>a-b);return {samples:v.length,p50_ms:v[Math.floor((v.length-1)*.5)],p95_ms:v[Math.floor((v.length-1)*.95)],max_ms:v.at(-1),over50:v.filter(x=>x>50).length,over100:v.filter(x=>x>100).length};
}
async function ownedProcessMemory(session) {
 const result={scope:'Linux RSS and per-process lifetime high-water RSS for processes reported by this disposable browser. Shared pages prevent summing these into a unique total.',processes:[]};
 try {
  const info=await session.send('SystemInfo.getProcessInfo');
  for(const process of info.processInfo) {
   if(!Number.isSafeInteger(process.id)||process.id<=0)continue;
   try {
    const status=fs.readFileSync('/proc/'+process.id+'/status','utf8');
    const bytes=name=>{const match=status.match(new RegExp('^'+name+':\\s+(\\d+) kB','m'));return match?Number(match[1])*1024:null;};
    result.processes.push({id:process.id,type:process.type,rss_bytes:bytes('VmRSS'),peak_rss_bytes:bytes('VmHWM')});
   } catch(error) {result.processes.push({id:process.id,type:process.type,unavailable:String(error)});}
  }
 } catch(error) {result.unavailable=String(error);}
 return result;
}
(async()=>{
 let server,browser;
 try {
  server=http.createServer((req,res)=>{
   const file=path.resolve(web,'.'+new URL(req.url,'http://localhost').pathname);
   if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}
   res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');
   res.setHeader('Cache-Control','public, max-age=3600');res.end(fs.readFileSync(file));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||'chrome'});
  report.browser={version:browser.version(),sandbox:true};
  const browserSession=await browser.newBrowserCDPSession();
  report.gpu=await browserSession.send('SystemInfo.getInfo');
  report.graphics_flags=(await browserSession.send('Browser.getBrowserCommandLine')).arguments.filter(x=>/gpu|angle|gl=|vulkan|swiftshader|sandbox/.test(x));
  const context=await browser.newContext({viewport:{width:1360,height:880}});
  await context.addInitScript(()=>{
   const p=window.startupTiming={frames:[],callbacks:[],longTasks:[],firstVisible:null,loader_removed_at:null,started:performance.now()};
   let hadStatus=false;
   const observer=new MutationObserver(()=>{const status=document.getElementById('status');if(status)hadStatus=true;if(hadStatus&&!status&&p.loader_removed_at===null)p.loader_removed_at=performance.now();});
   observer.observe(document,{subtree:true,childList:true});
   try{new PerformanceObserver(list=>{for(const e of list.getEntries())p.longTasks.push({at:e.startTime,duration:e.duration});}).observe({type:'longtask',buffered:true});}catch{}
   function frame(now){
    const status=document.getElementById('status');if(status)hadStatus=true;
    if(p.firstVisible===null&&hadStatus&&!status)p.firstVisible=now;
    p.frames.push(now);p.callbacks.push({frame:now,executed:performance.now(),loader_present:!!status});if(!p.stop)requestAnimationFrame(frame);
   }
   requestAnimationFrame(frame);
  });
  const page=await context.newPage();const url='http://127.0.0.1:'+server.address().port+'/index.html';
  for(const name of ['cold_http','warm_http']) {
   const errors=[];const onError=e=>errors.push(String(e));page.on('pageerror',onError);
   await page.goto(url,{waitUntil:'domcontentloaded'});
   await page.waitForFunction(()=>typeof window.startupTiming?.firstVisible==='number',null,{timeout:90000});
   await page.waitForTimeout(10000);
   const timing=await page.evaluate(()=>{startupTiming.stop=true;return {...startupTiming,resources:performance.getEntriesByType('resource').map(r=>({name:new URL(r.name).pathname,transferSize:r.transferSize,encodedBodySize:r.encodedBodySize,decodedBodySize:r.decodedBodySize,duration:r.duration})),heap:performance.memory?{used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize,limit:performance.memory.jsHeapSizeLimit}:null};});
   assert.equal(errors.length,0,errors.join('\n'));assert(timing.frames.length>10&&timing.firstVisible>0);
   assert.equal(await page.evaluate(()=>JSON.parse(window.__littleLeafVault.bootJson).source),'fresh','Each HTTP-cache trial must use a fresh disposable cafe');
   const bins={first_visible_second:[],next_5_5_seconds:[],settled_window:[]};
   for(let i=1;i<timing.frames.length;i++){
    const at=timing.frames[i]-timing.firstVisible,gap=timing.frames[i]-timing.frames[i-1];
    if(at<0)continue;
    bins[at<1000?'first_visible_second':at<6500?'next_5_5_seconds':'settled_window'].push(gap);
   }
   report.trials.push({name,first_visible_ms:timing.firstVisible,summary:Object.fromEntries(Object.entries(bins).map(([k,v])=>[k,summarize(v)])),raw:timing,process_memory:await ownedProcessMemory(browserSession),errors});
   page.off('pageerror',onError);
   // Clear only this disposable origin's generated storage, retaining HTTP cache.
   // This keeps the warm HTTP comparison a fresh generated cafe rather than a save-load test.
   await page.goto('about:blank');
   const session=await context.newCDPSession(page);
   await session.send('Storage.clearDataForOrigin',{origin:new URL(url).origin,storageTypes:'indexeddb,local_storage'});
   await session.detach();
  }
  report.status='passed';
 } catch(error){report.status='failed';report.error=String(error);process.exitCode=1;}
 finally {fs.writeFileSync(path.join(output,'startup-browser.json'),JSON.stringify(report,null,2));if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));}
})();
