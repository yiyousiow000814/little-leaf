'use strict';
// Separate attribution run: tracing/profiling overhead is excluded from timing acceptance.
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
const report = {source_commit:manifest.source_commit,manifest_sha256:hash(fs.readFileSync(path.join(web,'release-manifest.json'))),trials:[],diagnostic_only:true,scope:'Browser rAF scheduling and loader visibility; fresh disposable origin, no input/audio claim; HTTP-cache warmth is separate from newly created atlas objects.'};
function summarize(rows) {
 const v=rows.slice().sort((a,b)=>a-b);return {samples:v.length,p50_ms:v[Math.floor((v.length-1)*.5)],p95_ms:v[Math.floor((v.length-1)*.95)],max_ms:v.at(-1),over50:v.filter(x=>x>50).length,over100:v.filter(x=>x>100).length};
}
(async()=>{
 let server,browser,session;
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
  // SystemInfo already includes the launch command. Browser.getBrowserCommandLine
  // requires --enable-automation, which the ordinary Chrome launcher may omit.
  report.graphics_flags=(report.gpu.commandLine || '').match(/--[^\s]*(?:gpu|angle|gl=|vulkan|swiftshader|sandbox)[^\s]*/g) || [];
  const context=await browser.newContext({viewport:{width:1360,height:880}});
  await context.addInitScript(()=>{
   const p=window.startupTiming={frames:[],callbacks:[],marks:[],webgl_calls:{},webgl_long_calls:[],longTasks:[],firstVisible:null,loader_removed_at:null,started:performance.now()};
   function mark(name,detail){const at=performance.now();p.marks.push({name,at,detail});performance.mark('little-leaf:'+name);}
   const observe=new MutationObserver(()=>{const status=document.getElementById('status');if(status)hadStatus=true;if(hadStatus&&!status&&p.loader_removed_at===null){p.loader_removed_at=performance.now();mark('loader-removed');}});
   observe.observe(document,{subtree:true,childList:true});
   for(const name of ['__littleLeafVault','__littleLeafPreferences']){
    let current;Object.defineProperty(window,name,{configurable:true,get:()=>current,set(value){
     current=value;const boot=value.boot;if(typeof boot==='function')value.boot=function(...args){mark(name+':boot:start');return Reflect.apply(boot,this,args).then(result=>{mark(name+':boot:end',{source:result?.source});return result;});};
    }});
   }
   let bootApi;Object.defineProperty(window,'LittleLeafBoot',{configurable:true,get:()=>bootApi,set(value){
    const copy={...value};for(const name of ['engineReady','firstFrameReady','artWarmup'])if(typeof value[name]==='function')copy[name]=function(...args){mark('boot:'+name+':start',args);try{return Reflect.apply(value[name],value,args);}finally{mark('boot:'+name+':end');}};
    bootApi=Object.freeze(copy);
   }});
   for(const name of ['compile','compileStreaming','instantiate','instantiateStreaming'])if(typeof WebAssembly[name]==='function'){
    const original=WebAssembly[name];WebAssembly[name]=function(...args){mark('wasm:'+name+':start');return Reflect.apply(original,WebAssembly,args).then(result=>{mark('wasm:'+name+':end');return result;});};
   }
   for(const Type of [window.WebGLRenderingContext,window.WebGL2RenderingContext])if(Type){
    for(const name of ['compileShader','linkProgram','texImage2D','texSubImage2D','readPixels','finish']){
     const original=Type.prototype[name];if(typeof original!=='function')continue;
     Type.prototype[name]=function(...args){const start=performance.now();try{return Reflect.apply(original,this,args);}finally{
      const duration=performance.now()-start;const row=p.webgl_calls[name]||{count:0,total_ms:0,max_ms:0};row.count++;row.total_ms+=duration;row.max_ms=Math.max(row.max_ms,duration);p.webgl_calls[name]=row;
      if(duration>=10&&p.webgl_long_calls.length<1000){p.webgl_long_calls.push({name,start,duration});mark('webgl:'+name+':slow',{duration});}
     }};
    }
   }
   let hadStatus=false;
   try{new PerformanceObserver(list=>{for(const e of list.getEntries())p.longTasks.push({at:e.startTime,duration:e.duration});}).observe({type:'longtask',buffered:true});}catch{}
   function frame(now){
    const status=document.getElementById('status');if(status)hadStatus=true;
    if(p.firstVisible===null&&hadStatus&&!status)p.firstVisible=now;
    p.frames.push(now);p.callbacks.push({frame:now,executed:performance.now(),loader_present:!!status});if(!p.stop)requestAnimationFrame(frame);
   }
   requestAnimationFrame(frame);
  });
  const page=await context.newPage();report.requests=[];page.on('request',request=>report.requests.push({url:request.url(),type:request.resourceType()}));const url='http://127.0.0.1:'+server.address().port+'/index.html';
  for(const name of ['cold_trace']) {
   session=await context.newCDPSession(page);
   await session.send('Profiler.enable');await session.send('Profiler.setSamplingInterval',{interval:1000});await session.send('Profiler.start');
   await session.send('Tracing.start',{categories:'devtools.timeline,v8,blink.user_timing,gpu,disabled-by-default-devtools.timeline',transferMode:'ReturnAsStream'});
   const errors=[];const onError=e=>errors.push(String(e));page.on('pageerror',onError);
   await page.goto(url,{waitUntil:'domcontentloaded'});
   await page.waitForFunction(()=>typeof window.startupTiming?.firstVisible==='number',null,{timeout:90000});
   await page.waitForTimeout(10000);
   const cpu=await session.send('Profiler.stop');fs.writeFileSync(path.join(output,'startup.cpuprofile'),JSON.stringify(cpu.profile));
   const completed=new Promise(resolve=>session.once('Tracing.tracingComplete',resolve));await session.send('Tracing.end');const trace=await completed;
   const chunks=[];while(true){const part=await session.send('IO.read',{handle:trace.stream});chunks.push(Buffer.from(part.data,part.base64Encoded?'base64':'utf8'));if(part.eof)break;}await session.send('IO.close',{handle:trace.stream});fs.writeFileSync(path.join(output,'startup-trace.json'),Buffer.concat(chunks));
   const timing=await page.evaluate(()=>{startupTiming.stop=true;return {...startupTiming,resources:performance.getEntriesByType('resource').map(r=>({name:new URL(r.name).pathname,transferSize:r.transferSize,encodedBodySize:r.encodedBodySize,decodedBodySize:r.decodedBodySize,duration:r.duration})),hardware:{concurrency:navigator.hardwareConcurrency,memory:navigator.deviceMemory,userAgent:navigator.userAgent},webgl:(()=>{const gl=document.getElementById('canvas').getContext('webgl2');if(!gl)return null;const ext=gl.getExtension('WEBGL_debug_renderer_info');return {version:gl.getParameter(gl.VERSION),vendor:gl.getParameter(ext?ext.UNMASKED_VENDOR_WEBGL:gl.VENDOR),renderer:gl.getParameter(ext?ext.UNMASKED_RENDERER_WEBGL:gl.RENDERER)};})(),heap:performance.memory?{used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize,limit:performance.memory.jsHeapSizeLimit}:null};});
   assert.equal(errors.length,0,errors.join('\n'));assert(timing.frames.length>10&&timing.firstVisible>0);
   assert.equal(await page.evaluate(()=>JSON.parse(window.__littleLeafVault.bootJson).source),'fresh','Each HTTP-cache trial must use a fresh disposable cafe');
   const bins={first_visible_second:[],next_5_5_seconds:[],settled_window:[]};
   for(let i=1;i<timing.frames.length;i++){
    const at=timing.frames[i]-timing.firstVisible,gap=timing.frames[i]-timing.frames[i-1];
    if(at<0)continue;
    bins[at<1000?'first_visible_second':at<6500?'next_5_5_seconds':'settled_window'].push(gap);
   }
   assert(report.requests.every(request=>request.url.startsWith(new URL(url).origin+'/')||request.url.startsWith('data:')||request.url.startsWith('blob:')),'Unexpected external request in local-only startup fixture');
   report.trials.push({name,first_visible_ms:timing.firstVisible,summary:Object.fromEntries(Object.entries(bins).map(([k,v])=>[k,summarize(v)])),raw:timing,errors});
   page.off('pageerror',onError);
   // Clear only this disposable origin's generated storage, retaining HTTP cache.
   // This keeps the warm HTTP comparison a fresh generated cafe rather than a save-load test.
   await page.goto('about:blank');
   await session.send('Storage.clearDataForOrigin',{origin:new URL(url).origin,storageTypes:'indexeddb,local_storage'});
   await session.detach();
  }
  report.status='passed';
 } catch(error){report.status='failed';report.error=String(error);process.exitCode=1;}
 finally {fs.writeFileSync(path.join(output,'startup-attribution.json'),JSON.stringify(report,null,2));if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));}
})();
