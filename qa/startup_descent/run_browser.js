'use strict';
// CI handoff only: run after browser access is authorized. Not run locally here.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
const os=require('node:os');
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

function postLoaderWindows(observed) {
  assert(Number.isFinite(observed.loaderRemovedMs),'Observed DOM removal is required');
  const windows=[[0,1000],[1000,6500],[6500,11000]],result={};
  // Assign each complete post-loader interval once by its ending callback.
  // Keep the preceding callback even when it belongs to an earlier window.
  for(const [start,end] of windows){const gaps=[];
    for(let i=1;i<observed.callbacks.length;i++){const a=observed.callbacks[i-1],b=observed.callbacks[i];
      if(!a.loaderPresent&&!b.loaderPresent&&a.executedMs>=observed.loaderRemovedMs&&b.executedMs>observed.loaderRemovedMs+start&&b.executedMs<=observed.loaderRemovedMs+end)gaps.push(b.executedMs-a.executedMs);
    }
    gaps.sort((a,b)=>a-b);result[start+'_'+end+'ms']={samples:gaps.length,p50_ms:gaps.length?gaps[Math.floor((gaps.length-1)*.5)]:null,p95_ms:gaps.length?gaps[Math.floor((gaps.length-1)*.95)]:null,max_ms:gaps.at(-1)??null,over50:gaps.filter(x=>x>50).length,over100:gaps.filter(x=>x>100).length};
  }return result;
}

async function main() {
  const args=process.argv.slice(2),value=name=>{assert(args.includes(name),'Missing '+name);return args[args.indexOf(name)+1];};
  const out=path.resolve(value('--output')),qa=path.resolve(value('--qa-tools'));
  const {verifyManifest,validatePacket,hash}=require(path.join(qa,'qa/startup_descent/validate'));
  const {installCollector}=require(path.join(qa,'qa/startup_descent/collector'));
  const pairs=Object.fromEntries(['baseline','candidate'].map(v=>[v,path.resolve(value('--'+v+'-pair'))]));
  const roots=Object.fromEntries(['baseline','candidate'].map(v=>[v,path.resolve(value('--'+v+'-root'))]));
  const manifests=Object.fromEntries(['baseline','candidate'].map(v=>[v,Object.fromEntries(['control','instrumented'].map(mode=>[mode,verifyManifest(path.join(pairs[v],mode,'web'),roots[v])]))]));
  for(const v of ['baseline','candidate'])assert.equal(manifests[v].control.pair_id,manifests[v].instrumented.pair_id,'Matched diagnostic pair required');
  assert(!fs.existsSync(out),'Use a new output directory');fs.mkdirSync(out,{recursive:true});
  const report={schema_version:1,diagnostic_only:true,release_qualified:false,
    sources:Object.fromEntries(Object.entries(manifests).map(([v,m])=>[v,{source_commit:m.control.source_commit,source_tree:m.control.source_tree,pair_id:m.control.pair_id}])),
    collector_sha256:hash(fs.readFileSync(path.join(qa,'qa/startup_descent/collector.js'))),runner_sha256:hash(fs.readFileSync(__filename)),
    exported_files:Object.fromEntries(Object.entries(manifests).map(([v,modes])=>[v,Object.fromEntries(Object.entries(modes).map(([mode,m])=>[mode,m.files]))])),
    browser_status:'running',trials:[],os:{platform:os.platform(),release:os.release(),arch:os.arch()},
    scope:'Symmetric same-run baseline/candidate fresh ordinary-Web diagnostic exports. Post-loader windows are callback-execution windows, not inferred gameplay phase or physical presentation. No release qualification, visual/audio acceptance or device FPS claim. Cold/warm refer only to HTTP cache; Godot process and atlases restart on navigation.',
    overhead:'Both products have the same diagnostic subclasses. The control mode has no frame wrappers; instrumented mode adds bounded main-process/post-draw counters. Compare symmetric baseline/candidate plus control/instrumented loader removal and first loader-absent callback timings; difference includes script parsing, wrappers, marks and emission, plus noise. No constant subtraction or per-method overhead estimate.'};
  let server,browser;
  try {
    const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
    server=http.createServer((request,response)=>{
      const relative=new URL(request.url,'http://127.0.0.1').pathname;
      // Chrome may request this despite the custom shell having no favicon link.
      // Handle this one conventional probe without hiding any exported-resource error.
      if(relative==='/favicon.ico'){response.writeHead(204);response.end();return;}
      const match=relative.match(/^\/(baseline|candidate)\/(control|instrumented)\/(.*)$/);
      if(!match){response.writeHead(404);response.end();return;}
      const web=path.join(pairs[match[1]],match[2],'web'),file=path.resolve(web,match[3]);
      if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){response.writeHead(404);response.end();return;}
      response.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');
      response.setHeader('Cache-Control','public, max-age=3600');response.end(fs.readFileSync(file));
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const origin='http://127.0.0.1:'+server.address().port;
    browser=await chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||'chrome'});
    report.browser={version:browser.version(),sandbox:true};
    const session=await browser.newBrowserCDPSession();report.graphics=await session.send('SystemInfo.getInfo');
    report.graphics_flags=(report.graphics.commandLine||'').match(/--[^\s]*(?:gpu|angle|gl=|vulkan|swiftshader|sandbox)[^\s]*/g)||[];
    const schedule=['control','instrumented'].flatMap(mode=>['baseline','candidate','candidate','baseline'].map(variant=>({mode,variant})));
    for(const [index,{mode,variant}] of schedule.entries()) {
      const context=await browser.newContext({viewport:{width:1360,height:880}});
      await context.addInitScript(installCollector);
      const external=[];
      // Routing disables Playwright's HTTP cache: observe requests without intercepting.
      context.on('request',request=>{const url=request.url();
        if(!url.startsWith(origin+'/')&&!url.startsWith('data:')&&!url.startsWith('blob:'))external.push(url);
      });
      try {
        const page=await context.newPage();
        for(const warmth of ['cold_http','warm_http']) {
          const errors=[],consoleErrors=[],onError=error=>errors.push(String(error));
          const onConsole=message=>{if(message.type()==='error'||/\b(?:SCRIPT )?ERROR:/.test(message.text()))consoleErrors.push({type:message.type(),text:message.text()});};
          page.on('pageerror',onError);page.on('console',onConsole);
          const trial={sequence:index+1,variant,mode,warmth,overlay_id:manifests[variant][mode].overlay_id,
            manifest_sha256:hash(fs.readFileSync(path.join(pairs[variant],mode,'web/diagnostic-manifest.json'))),
            observed:null,phases:null,errors,console_errors:consoleErrors,status:'running'};
          report.trials.push(trial);
          await page.goto(origin+'/'+variant+'/'+mode+'/index.html',{waitUntil:'domcontentloaded'});
          await page.waitForFunction(()=>typeof window.__littleLeafPhaseObservation?.firstObservedCallbackMs==='number',null,{timeout:90000});
          // No screenshot/readback, profiler or interaction during the observation.
          await page.waitForTimeout(11000);
          // Stop browser measurement before serializing the buffered engine packet.
          await page.evaluate(()=>{window.__littleLeafPhaseObservation.stopped=true;});
          if(mode==='instrumented')await page.evaluate(()=>{if(typeof window.__littleLeafDescentCollect!=='function')throw new Error('Missing native collection callback');window.__littleLeafDescentCollect();});
          if(mode==='instrumented')await page.waitForFunction(()=>window.__littleLeafPhaseObservation.packetCount===1,null,{timeout:10000});
          const observed=await page.evaluate(()=>{const s=window.__littleLeafPhaseObservation;return {...s,
            vaultSource:JSON.parse(window.__littleLeafVault.bootJson).source,
            resources:performance.getEntriesByType('resource').map(r=>({path:new URL(r.name).pathname,transferSize:r.transferSize,encodedBodySize:r.encodedBodySize,durationMs:r.duration})),
            hardware:{concurrency:navigator.hardwareConcurrency,memoryGiB:navigator.deviceMemory,userAgent:navigator.userAgent}};});
          trial.observed=observed;
          assert.equal(observed.vaultSource,'fresh','Real browser vault fresh-source boot required');
          assert.deepEqual(errors,[]);assert.deepEqual(consoleErrors,[],'Engine/console errors are not accepted');assert.deepEqual(external,[],'No external-service requests permitted');
          let phases=null;
          if(mode==='instrumented'){assert.equal(observed.packetCount,1,'Exactly one packet');phases=validatePacket(observed.packet,manifests[variant][mode]);}
          else {assert.equal(observed.packetCount,0,'Control must be uninstrumented');assert.equal(observed.packet,null);}
          trial.phases=phases;trial.post_loader_windows=postLoaderWindows(observed);trial.process_memory=await ownedProcessMemory(session);trial.status='passed';
          fs.writeFileSync(path.join(out,'startup-phases.json'),JSON.stringify(report,null,2));
          page.off('pageerror',onError);page.off('console',onConsole);
          await page.goto('about:blank');
          // Only this newly created context/origin; keep HTTP cache, reset generated saves/preferences.
          const storage=await context.newCDPSession(page);
          await storage.send('Storage.clearDataForOrigin',{origin,storageTypes:'indexeddb,local_storage'});await storage.detach();
        }
      } finally {await context.close();}
    }
    await session.detach();report.browser_status='passed_diagnostic_only';
  } catch(error){report.browser_status='failed';report.error=String(error);if(report.trials.at(-1)?.status==='running')report.trials.at(-1).status='failed';process.exitCode=1;}
  finally {
    fs.writeFileSync(path.join(out,'startup-phases.json'),JSON.stringify(report,null,2));
    if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));
  }
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={main,postLoaderWindows,ownedProcessMemory};
