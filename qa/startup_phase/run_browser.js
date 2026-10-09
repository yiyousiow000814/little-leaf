'use strict';
// CI handoff only: run after browser access is authorized. Not run locally here.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
const os=require('node:os');
const {verifyManifest,validatePacket,hash}=require('./validate');
const {installCollector}=require('./collector');
async function main() {
  const args=process.argv.slice(2),value=name=>{assert(args.includes(name),'Missing '+name);return args[args.indexOf(name)+1];};
  const pair=path.resolve(value('--pair')),root=path.resolve(value('--source-root')),out=path.resolve(value('--output'));
  const manifests=Object.fromEntries(['control','instrumented'].map(mode=>[mode,verifyManifest(path.join(pair,mode,'web'),root)]));
  assert.equal(manifests.control.pair_id,manifests.instrumented.pair_id,'Matched pair required');
  assert(!fs.existsSync(out),'Use a new output directory');fs.mkdirSync(out,{recursive:true});
  const report={schema_version:1,diagnostic_only:true,release_qualified:false,
    source_commit:manifests.control.source_commit,source_tree:manifests.control.source_tree,pair_id:manifests.control.pair_id,
    browser_status:'running',trials:[],os:{platform:os.platform(),release:os.release(),arch:os.arch()},
    scope:'Fresh ordinary-Web boot and inclusive phase spans; no release qualification, visual/audio acceptance or device FPS claim. Cold/warm refer only to HTTP cache; Godot process and atlases restart on navigation.',
    overhead:'Compare symmetric control/instrumented loader removal and first loader-absent callback timings; difference includes script parsing, wrappers, marks and emission, plus noise. No constant subtraction or per-method overhead estimate.'};
  let server,browser;
  try {
    const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
    server=http.createServer((request,response)=>{
      const relative=new URL(request.url,'http://127.0.0.1').pathname;
      // Chrome may request this despite the custom shell having no favicon link.
      // Handle this one conventional probe without hiding any exported-resource error.
      if(relative==='/favicon.ico'){response.writeHead(204);response.end();return;}
      const match=relative.match(/^\/(control|instrumented)\/(.*)$/);
      if(!match){response.writeHead(404);response.end();return;}
      const web=path.join(pair,match[1],'web'),file=path.resolve(web,match[2]);
      if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){response.writeHead(404);response.end();return;}
      response.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');
      response.setHeader('Cache-Control','public, max-age=3600');response.end(fs.readFileSync(file));
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const origin='http://127.0.0.1:'+server.address().port;
    browser=await chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||'chrome'});
    report.browser={version:browser.version(),sandbox:true};
    const session=await browser.newBrowserCDPSession();report.graphics=await session.send('SystemInfo.getInfo');await session.detach();
    for(const [index,mode] of ['control','instrumented','instrumented','control'].entries()) {
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
          const trial={sequence:index+1,mode,warmth,overlay_id:manifests[mode].overlay_id,
            manifest_sha256:hash(fs.readFileSync(path.join(pair,mode,'web/diagnostic-manifest.json'))),
            observed:null,phases:null,errors,console_errors:consoleErrors,status:'running'};
          report.trials.push(trial);
          await page.goto(origin+'/'+mode+'/index.html',{waitUntil:'domcontentloaded'});
          await page.waitForFunction(()=>typeof window.__littleLeafPhaseObservation?.firstObservedCallbackMs==='number',null,{timeout:90000});
          // No screenshot/readback, profiler or interaction during the observation.
          await page.waitForTimeout(500);
          const observed=await page.evaluate(()=>{const s=window.__littleLeafPhaseObservation;s.stopped=true;return {...s,
            vaultSource:JSON.parse(window.__littleLeafVault.bootJson).source,
            resources:performance.getEntriesByType('resource').map(r=>({path:new URL(r.name).pathname,transferSize:r.transferSize,encodedBodySize:r.encodedBodySize,durationMs:r.duration})),
            hardware:{concurrency:navigator.hardwareConcurrency,memoryGiB:navigator.deviceMemory,userAgent:navigator.userAgent}};});
          trial.observed=observed;
          assert.equal(observed.vaultSource,'fresh','Real browser vault fresh-source boot required');
          assert.deepEqual(errors,[]);assert.deepEqual(consoleErrors,[],'Engine/console errors are not accepted');assert.deepEqual(external,[],'No external-service requests permitted');
          let phases=null;
          if(mode==='instrumented'){assert.equal(observed.packetCount,1,'Exactly one packet');phases=validatePacket(observed.packet,manifests[mode]);}
          else {assert.equal(observed.packetCount,0,'Control must be uninstrumented');assert.equal(observed.packet,null);}
          trial.phases=phases;trial.status='passed';
          fs.writeFileSync(path.join(out,'startup-phases.json'),JSON.stringify(report,null,2));
          page.off('pageerror',onError);page.off('console',onConsole);
          await page.goto('about:blank');
          // Only this newly created context/origin; keep HTTP cache, reset generated saves/preferences.
          const storage=await context.newCDPSession(page);
          await storage.send('Storage.clearDataForOrigin',{origin,storageTypes:'indexeddb,local_storage'});await storage.detach();
        }
      } finally {await context.close();}
    }
    report.browser_status='passed_diagnostic_only';
  } catch(error){report.browser_status='failed';report.error=String(error);if(report.trials.at(-1)?.status==='running')report.trials.at(-1).status='failed';process.exitCode=1;}
  finally {
    fs.writeFileSync(path.join(out,'startup-phases.json'),JSON.stringify(report,null,2));
    if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));
  }
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={main};
