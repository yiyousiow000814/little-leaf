'use strict';
// Private diagnostic adapter: instrument the exact checkout's genuine Web gate,
// never patch/export production or change game state. Node CommonJS, Playwright 1.63.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const Module = require('node:module'), os = require('node:os'), cp = require('node:child_process');

function installSampler() {
  const cap = 48000;
  const times = new Float64Array(cap), good = new Uint8Array(cap);
  let n = 0, lost = 0, handle = 0;
  const startedClockOffset = Date.now() - performance.now();
  const longFrames = [];
  let observer;
  if (PerformanceObserver.supportedEntryTypes.includes('long-animation-frame')) {
    observer = new PerformanceObserver(list => {
      for (const e of list.getEntries()) {
        if (longFrames.length < 2400)
          longFrames.push([e.startTime, e.duration, e.blockingDuration, e.renderStart, e.styleAndLayoutStart]);
      }
    });
    observer.observe({type:'long-animation-frame', buffered:false});
  }
  function frame(ts) {
    if(n < cap) { times[n] = ts; good[n++] = document.visibilityState === 'visible' && document.hasFocus() ? 1 : 0; }
    else lost++;
    handle = requestAnimationFrame(frame);
  }
  handle = requestAnimationFrame(frame);
  return {
    freeze() {
      cancelAnimationFrame(handle); observer?.disconnect();
      let renderer = null;
      try {
        const gl = document.getElementById('canvas')?.getContext('webgl2');
        const ext = gl?.getExtension('WEBGL_debug_renderer_info');
        renderer = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : null;
      } catch (_) { /* Unavailable on some browser policies. */ }
      return {timeOrigin: startedClockOffset, wall_clock_drift_ms: Date.now() - performance.now() - startedClockOffset, raf: Array.from(times.subarray(0,n)),
        visibleFocused: Array.from(good.subarray(0,n)), lost, longFrames, longFrameSupport: !!observer,
        longFrameCapHit: longFrames.length === 2400, environment: {userAgent:navigator.userAgent,
          cores:navigator.hardwareConcurrency, renderer, dpr:devicePixelRatio, size:[innerWidth,innerHeight]}};
    }
  };
}
const stats = xs => {
  if (!xs.length) return {count:0};
  const y = xs.slice().sort((a,b) => a-b), q = p => y[Math.max(0,Math.ceil(p*y.length)-1)];
  return {count:y.length,p50_ms:q(.5),p95_ms:q(.95),p99_ms:q(.99),max_ms:y.at(-1),
    over_20ms:y.filter(x=>x>20).length,over_34ms:y.filter(x=>x>34).length};
};
// Pair controller request->validated only (actual synchronous save preparation
// when validated), and vault put->confirmed (async durable persistence latency).
// Existing diagnostic timestamps are wall-clock milliseconds. Mark overlap
// conservatively with +/-1 ms precision; association is not causation.
function paired(events,timeOrigin) {
  const spans=[], point=e=>Date.parse(e.timestamp)-timeOrigin;
  let prep=null; const writes=new Map();
  for (const e of events) {
    if(e.layer==='controller') {
      if(e.event==='save_requested') prep=point(e);
      if(e.event==='save_validated' && prep!==null) {spans.push(['controller_prepare',prep,point(e)]); prep=null;}
      if(['save_skipped','save_queued','save_failure'].includes(e.event)) prep=null;
    }
    if(e.layer==='vault' && e.event==='save_submitted' && Number.isFinite(e.revision)) {
      if(!writes.has(e.revision)) writes.set(e.revision,point(e));
    }
    if(e.layer==='vault' && e.event==='save_confirmed' && writes.has(e.revision)) {
      spans.push(['indexeddb_put_to_confirm',writes.get(e.revision),point(e)]);
      writes.delete(e.revision);
    }
    if(e.layer==='vault' && e.event==='save_failure') writes.clear();
  }
  return spans.filter(([,a,b])=>Number.isFinite(a)&&Number.isFinite(b)&&b>=a);
}
function analyze(raw, marks, events) {
  const reliableClock = !Number.isFinite(raw.wall_clock_drift_ms) || Math.abs(raw.wall_clock_drift_ms)<=2;
  const spans=reliableClock ? paired(events,raw.timeOrigin) : [];
  function phase(from,to) {
    const all=[], focus=[], prep=[], txn=[], other=[], excluded=[];
    if(!Number.isFinite(from)||!Number.isFinite(to)||to<=from)return {available:false};
    for(let i=1;i<raw.raf.length;i++){
      const a=raw.raf[i-1],b=raw.raf[i],d=b-a;
      if(a<from||b>to)continue;
      all.push(d);
      if (!raw.visibleFocused[i-1] || !raw.visibleFocused[i]) {excluded.push(d);continue;}
      // Omit a screenshot neighborhood only from the "in focus, no screenshot"
      // buckets, but retain complete rAF intervals and the excluded counts.
      if(marks.order_screenshot_begin!==undefined && marks.order_screenshot_end!==undefined &&
         a<=marks.order_screenshot_end+34 && b>=marks.order_screenshot_begin-34) {excluded.push(d);continue;}
      focus.push(d);
      const touching = kind => spans.some(([k,start,end])=>k===kind && a<=end+1 && b>=start-1);
      const p=touching('controller_prepare'), t=touching('indexeddb_put_to_confirm');
      if(p)prep.push(d); if(t)txn.push(d); if(!p&&!t)other.push(d);
    }
    return {all:stats(all),foreground_without_screenshot:stats(focus),excluded_from_subgroups:excluded.length,
      near_controller_prepare:stats(prep),near_async_indexeddb:stats(txn),neither:stats(other)};
  }
  return {scope:'Browser callback pacing, not presented frames, CPU/GPU time or headroom',
    acceptance_headroom_ms:null, save_clock_reliable:reliableClock, active: phase(marks.service_begin, marks.payment_paid),
    seated_order_to_payment:phase(marks.order_screenshot_end,marks.payment_paid), spans,
    save_log_maybe_truncated:events[0]?.sequence>1};
}
if(process.argv[2]==='--self-test'){
  const timeOrigin=Date.parse('2026-11-19T04:00:00Z'), event=(ms,event,layer,revision)=>({timestamp:new Date(timeOrigin+ms).toISOString(),event,layer,revision});
  const input=[event(18,'save_requested','controller'),event(23,'save_validated','controller'),
    event(30,'save_submitted','vault',4),event(40,'save_confirmed','vault',4)];
  const out=analyze({timeOrigin,raf:[0,16,32,48,81],visibleFocused:[1,1,1,1,0]},
    {service_begin:0,payment_paid:81,order_screenshot_begin:undefined,order_screenshot_end:undefined},input);
  assert.deepEqual(out.spans,[['controller_prepare',18,23],['indexeddb_put_to_confirm',30,40]]);
  assert.equal(out.active.all.count,4);assert.equal(out.active.foreground_without_screenshot.count,3);
  assert.equal(out.active.near_controller_prepare.count,1);assert.equal(out.active.near_async_indexeddb.count,2);
  assert.equal(out.acceptance_headroom_ms,null);
  console.log('6 sampler analysis checks passed');return;
}
const arg = name => {const i=process.argv.indexOf('--'+name);assert(i>=0&&process.argv[i+1],name+' required');return process.argv[i+1];};
const root=path.resolve(arg('repo')), out=path.resolve(arg('output'));
const source=path.join(root,'tests/presentation/fresh_tutorial_browser.js');
const artifactHashes=Object.fromEntries(['index.html','index.js','index.wasm','index.pck','release-manifest.json'].map(f=>[f,require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(arg('web-build'),f))).digest('hex')]));
const exact=cp.execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
assert.equal(exact,arg('expected-commit'),'Source checkout must match requested commit');
const tree=cp.execFileSync('git',['rev-parse','HEAD^{tree}'],{cwd:root,encoding:'utf8'}).trim();
const host={platform:process.platform, arch:process.arch, os:os.release(), model:os.cpus()[0]?.model, availableParallelism:os.availableParallelism(), load:os.loadavg()};
const marker=async (page,name)=>{
  const ms=await page.evaluate(()=>performance.now());
  marks[name]=ms;
};
const marks={};
let script=fs.readFileSync(source,'utf8');
function after(needle, addition) {
  assert(script.indexOf(needle)>=0 && script.indexOf(needle)===script.lastIndexOf(needle),'Exact gate hook must occur once: '+needle);
  script=script.replace(needle,needle+'\n'+addition);
}
const api=Object.freeze({sampler:installSampler,mark:marker,
  async finish(page,scenario = {name:'Unmodified starter café, unskipped tutorial, actual first order and cash settlement.'}) {
    const snapshot=await page.evaluate(()=>{const raw=window.__llCadence.freeze();
      return {raw,events:(window.LittleLeafSaveLog?.snapshot()??[]).map(({profile,...row})=>row)};});
    fs.writeFileSync(path.join(out,'active-service-cadence.json'),JSON.stringify({source:{exact,tree},artifact_sha256:artifactHashes,host,marks,...snapshot,
      scenario,
      ...analyze(snapshot.raw,marks,snapshot.events)},null,2)+'\n');
  }
});
async function seededTrial() {
  const http=require('node:http'), crypto=require('node:crypto');
  const fresh=require(source), fixture=fs.readFileSync(arg('seed-fixture'),'utf8');
  const {layout} = fresh.validateBinding(path.resolve(arg('web-build')),path.resolve(arg('layout-report')),path.resolve(arg('engine-report')));
  const home=path.resolve(arg('web-build')), save = JSON.parse(fixture);
  const digest=v=>crypto.createHash('sha256').update(v).digest('hex');
  assert.equal(digest(fixture),'ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f','Only the matched generated synthetic starter fixture is allowed');
  assert.equal(save.built_walls.length,21); assert.equal(save.runtime.customers.length,1);
  assert(save.operating_open && save.served===0 && save.total_earned===0);
  const vault = fs.readFileSync(path.join(root,'platform/web/little_leaf_vault.js'),'utf8');
  const drv=process.env.PLAYWRIGHT_MODULE||'playwright';
  const requireFromRepo=Module.createRequire(source);
  assert.equal(requireFromRepo(drv+'/package.json').version,'1.63.0');
  const server=http.createServer((req,res)=>{
    const pathname=new URL(req.url,'http://localhost').pathname;
    if(pathname==='/fixture'){res.setHeader('content-type','text/html');return res.end('<title>Disposable synthetic checkout</title>');}
    const file=path.resolve(home,'.'+pathname);
    if(!file.startsWith(home+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}
    res.setHeader('content-type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  let browser;
  fs.mkdirSync(out,{recursive:true});
  try {
    await new Promise((resolve,reject)=>server.once('error',reject).listen(0,'127.0.0.1',resolve));
    const origin='http://127.0.0.1:'+server.address().port;
    browser=await requireFromRepo(drv).chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||'chrome'});
    const context=await browser.newContext({viewport:{width:1360,height:880},deviceScaleFactor:1,serviceWorkers:'block'});
    await context.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
    const page=await context.newPage(), failures=[];
    fresh.observePageFailures(page,failures);
    await page.goto(origin+'/fixture');
    assert.deepEqual(await page.evaluate(async()=>[await indexedDB.databases(),localStorage.length,sessionStorage.length]),[[],0,0]);
    await page.addScriptTag({content:vault});
    const authority=await page.evaluate(async payload=>{
      const seed=await __littleLeafVault.boot();
      const saved=await __littleLeafVault.commit(payload,seed.revision,seed.profileId);
      __littleLeafVault.close();return {ok:saved.ok,durable:saved.durable,rev:saved.revision};
    },fixture);
    assert(authority.ok&&authority.durable&&authority.rev===1,'One durable seed via actual vault');
    await page.addInitScript(new Function('window.__llCadence = ('+installSampler.toString()+')()'));
    await fresh.navigateFreshGame(page,origin+'/index.html');
    await page.waitForFunction(()=>LittleLeafSaveLog.snapshot().some(e=>e.layer==='controller'&&e.event==='read_accepted'&&e.source==='authority'),null,{timeout:30000});
    const snapshots=[];
    async function until(ok,ms){
      const end=performance.now()+ms;while(performance.now()<end){
        assert(!failures.length,JSON.stringify(failures));
        const ack=await page.evaluate(()=>JSON.parse(__littleLeafVault.bootJson));
        const state=fresh.summarize(ack);
        if(state?.revision>authority.rev){
          const payload=JSON.parse(ack.payload);
          assert(state.open&&payload.built_walls.length===21,'Production save preserves matched open café and wall count');
          if(snapshots.at(-1)?.revision!==state.revision)
            snapshots.push({revision:state.revision,guests:state.guests.map(g=>({phase:g.phase,seated:g.seated})),served:state.served,earned:state.earned});
          if(ok(state))return state;
        }
        await new Promise(r=>setTimeout(r,400));
      }throw Error('Natural service condition timed out');
    }
    // Read-only polling observes genuine acknowledged saves on ordinary wall time.
    await marker(page,'service_begin');
    const order=await until(s=>s.guests.some(g=>g.seated&&s.orders.includes(g.id)),100000);
    marks.order_screenshot_end=await page.evaluate(()=>performance.now()); // No capture during timed run.
    const paid=await until(s=>s.served>order.served,150000);
    assert.equal(paid.earned-order.earned,(paid.served-order.served)*layout.meal_payment,'Actual meal economics');
    await marker(page,'payment_paid');
    await api.finish(page,{name:'Loaded synthetic 21-wall starter; genuine active-service continuation, no browser guest manipulation',fixture_sha256:digest(fixture),
      wall_count:21,payment_delta:paid.earned-order.earned,snapshots,startup_tutorial_tested:false});
    await page.screenshot({path:path.join(out,'post-measurement.png'),timeout:10000});
    assert.equal(failures.length,0);
  }finally{if(browser)await browser.close();if(server.listening){server.closeAllConnections();await new Promise(r=>server.close(r));}}
}
if(process.argv.includes('--seed-fixture')){
  seededTrial().catch(e=>{console.error(e);process.exitCode=1;});return;
}
after("page = await context.newPage();","await page.addInitScript(__llCadenceAdapter.install);");
after('const naturalStarted = Date.now();',"await __llCadenceAdapter.mark(page,'service_begin');");
after("check(order.tutorial.status === 'completed', 'Natural-service observation starts after the tutorial is dismissed');",
  "await __llCadenceAdapter.mark(page,'order_screenshot_begin');");
after("await page.screenshot({path: path.join(output, 'natural-order-after-tutorial.png'), timeout: Math.min(10000, budget.remaining())});",
  "await __llCadenceAdapter.mark(page,'order_screenshot_end');");
after('validateNaturalPayment(paid, order, layout, initial);',
  "await __llCadenceAdapter.mark(page,'payment_paid'); await __llCadenceAdapter.finish(page);");
// The file on disk remains exactly as hashed by validateBinding. Compile a
// temporary module at the logical path so its original relative require works.
script=script.replace('if (require.main === module) main();','main();');
const adapter=new Module(source,module);
adapter.filename=source; adapter.paths=Module._nodeModulePaths(path.dirname(source));
globalThis.__llCadenceAdapter=Object.freeze({install:new Function('window.__llCadence = ('+api.sampler.toString()+')()'),mark:api.mark,finish:api.finish});
adapter._compile(script,source);
