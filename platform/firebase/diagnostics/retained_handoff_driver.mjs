import {createRequire as sourceRequire} from 'node:module';
const {sourcePath}=sourceRequire(import.meta.url)('../../tests/source_paths.js');
// Actual compiled Godot UI + production boot/adapter/session/update + Firestore emulator.
// Only authentication is synthetic. No production endpoint, token or player save is used.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createRequire} from 'node:module';
import {createFixtureStore} from './fullflow_fixtures.mjs';
import {isConnectivityProbe,failureCategory,requestFamily,syntheticRPCOrigin,emulatorProxyTarget,emulatorPreflightHeaders,emulatorRequestKind,workletName,observeTransaction} from './fullflow_network.mjs';
import {initializeTestEnvironment,assertFails} from '@firebase/rules-unit-testing';
import {doc,getDocFromServer,setDoc,onSnapshot} from 'firebase/firestore';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {installEngineLaunchHook}=require('../../tests/tooling/engine_launch_hook.js');
const root=path.resolve(import.meta.dirname,'../..');
const arg=name=>{const i=process.argv.indexOf(name);assert(i>=0 && process.argv[i+1],name+' required');return path.resolve(process.argv[i+1]);};
const web=arg('--web-build'),out=arg('--output'),native=arg('--engine-report');
const itchVariant=process.argv.includes('--itch-test-variant')?arg('--itch-test-variant'):null;
const officialOrigin='https://little-leaf-41e5d.firebaseapp.com';
const itchPage='https://siowyiyou.itch.io/__little_leaf_synthetic_test__';
const classicPage='https://html-classic.itch.zone/__little_leaf_synthetic_test__';
assert(process.argv.includes('--diagnostic-only') && itchVariant,'retained nested diagnostic only');
const retainedGeometryInputPath=arg('--retained-geometry-input'),retainedGeometryResultPath=arg('--retained-geometry-result');
const retainedGeometryInput=JSON.parse(fs.readFileSync(retainedGeometryInputPath));
const retainedGeometryResult=JSON.parse(fs.readFileSync(retainedGeometryResultPath));
assert.equal(retainedGeometryResult.synthetic_only,true);
assert.deepEqual(retainedGeometryResult.snapshot,retainedGeometryInput.snapshot);
assert.deepEqual(retainedGeometryResult.viewport,retainedGeometryInput.viewport);
const engine=JSON.parse(fs.readFileSync(native)),manifest=JSON.parse(fs.readFileSync(path.join(web,'release-manifest.json')));
assert.equal(engine.status,'passed');assert.equal(engine.source_commit,manifest.source_commit);assert.equal(engine.player_save_used,false);
function nativeResult(name,marker){const log=fs.readFileSync(path.join(path.dirname(native),name+'.log'),'utf8');const rows=log.split('\n').filter(line=>line.startsWith(marker+' '));assert.equal(rows.length,1,'one exact native geometry result');return JSON.parse(rows[0].slice(marker.length+1));}
const recoveryLayout=nativeResult('test_cloud_recovery_ui','CLOUD_RECOVERY_UI_RESULT');
const updateLayout=nativeResult('test_update_notice','UPDATE_NOTICE_RESULT');
assert.deepEqual(recoveryLayout.failures,[]);assert.deepEqual(updateLayout.failures,[]);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
for(const [name,record] of Object.entries(manifest.files))assert.equal(sha(fs.readFileSync(path.join(web,name))),record.sha256,'exact exported '+name);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080','explicit local emulator only');
fs.mkdirSync(out,{recursive:true});
const report={passed:false,synthetic_only:true,real_compiled_ui:true,real_firestore_rules:true,real_google_sign_in:false,browser_sandbox:true,headless_browser:process.env.PLAYWRIGHT_HEADLESS==='1',source_commit:manifest.source_commit,source_tree:manifest.source_tree,export_manifest_sha256:sha(fs.readFileSync(path.join(web,'release-manifest.json'))),native_report_sha256:sha(fs.readFileSync(native)),diagnostic_only:process.argv.includes('--diagnostic-only'),checks:[],screenshots:[],source_sha256:Object.fromEntries(['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs','tests/diagnostics/probe_cloud_recovery_geometry.gd','tools/prepare_browser_qa.py','web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules'].map(n=>[n,sha(fs.readFileSync(sourcePath(root,n)))]))};
Object.assign(report,{diagnostic_only:true,scope:'retained-first-two-cases',full_suite:false,release_qualification:false,deployable:false,
 harness_git_head:'69f33801aac66844f2eaa1e15d4d767544d0d663',compiled_source_commit:'a897a31f20ad4b95a6f350b219cc12f56a17f3b6',
 native_geometry_fresh:false,retained_geometry_input_sha256:sha(fs.readFileSync(retainedGeometryInputPath)),retained_geometry_result_sha256:sha(fs.readFileSync(retainedGeometryResultPath))});
assert.equal(manifest.source_commit,report.compiled_source_commit);
const checkpoint=()=>fs.writeFileSync(path.join(out,'firebase-fullflow.json'),JSON.stringify(report,null,2));
const check=(ok,label)=>{assert(ok,label);report.checks.push(label);checkpoint();};
const fixture=JSON.parse(fs.readFileSync(path.join(root,'tests/fixtures/startup-retry-v15.json')));
vm.runInThisContext(fs.readFileSync(path.join(root,'platform/web/little_leaf_vault.js'),'utf8'));
const codec=globalThis.LittleLeafAuthorityCodec;
async function record(revision,coins,profileId=crypto.randomUUID()){
 const r={format:2,profileId,revision,createdAt:1,updatedAt:1700000000000+revision*1000,payload:JSON.stringify({...fixture,coins,operating_open:false}),digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
 r.digest=await codec.hash(codec.fingerprint(r));return r;
}
const envelope=(r,device='iPhone')=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r),device});
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync(path.join(root,'platform/firebase/firestore.rules'),'utf8')}});
const fixtureStore=createFixtureStore(env);
const read=(uid,kind='save')=>fixtureStore.read(uid,kind);
const seed=(uid,r)=>fixtureStore.seed(uid,envelope(r));
const sdkRoot=path.dirname(require.resolve('firebase/package.json'));
const source=name=>fs.readFileSync(path.join(root,'platform/web',name),'utf8');
const loadedRelease=itchVariant?JSON.parse(fs.readFileSync(path.join(itchVariant,'public/itch/hosting-release.json'))):{schema_version:1,version:manifest.version,source_commit:manifest.source_commit};
const clockOrigin=Date.now();report.proxyTimings=[];report.workletObservations=[];
function workletObservation(kind,name,result){
 const rows=report.workletObservations,existing=rows.find(row=>row.kind===kind&&row.name===name&&row.result===result);
 if(existing)existing.count=Math.min(100,existing.count+1);
 else if(rows.length<24)rows.push({kind,name,result,count:1});
}
let release={...loadedRelease};
const config={apiKey:'emulator-synthetic-key',authDomain:itchVariant?'little-leaf-41e5d.firebaseapp.com':'127.0.0.1',projectId:'demo-little-leaf',appId:'1:123:web:synthetic'};
let html;
if(itchVariant){
 const packet=JSON.parse(fs.readFileSync(path.join(itchVariant,'firebase-variant-manifest.json')));
 assert.equal(packet.status,'prepared-same-itch-local-candidate-not-deployable');
 assert.equal(packet.source_commit,manifest.source_commit);assert.equal(packet.source_tree,manifest.source_tree);
 for(const [name,digest]of Object.entries(packet.files))assert.equal(sha(fs.readFileSync(path.join(itchVariant,name))),digest,'exact test variant '+name);
 html=fs.readFileSync(path.join(itchVariant,'public/itch/index.html'),'utf8');
 report.itch_test_entry=true;report.itch_entry_sha256=sha(fs.readFileSync(path.join(itchVariant,'public/itch/index.html')));
 report.synthetic_public_config_substitution=true; // No real project, Auth or Firestore endpoint is reachable.
 const realConfig=JSON.parse(fs.readFileSync(path.join(root,'platform/firebase/public-config.json')));
 const options={surface:'trusted-itch-frame',runtimeOrigin:officialOrigin,runtimePath:'/itch/'};
 // The packager uses Python's flat-object JSON spacing. Check the exact bytes before substituting synthetic credentials.
 const pythonFlatJSON=value=>'{'+Object.entries(value).map(([key,item])=>JSON.stringify(key)+': '+JSON.stringify(item)).join(', ')+'}';
 const original='m.start('+pythonFlatJSON(realConfig)+','+pythonFlatJSON(options)+')';
 assert.equal(html.split(original).length,2,'one exact compiled stable entry');
 html=html.replace(original,'m.start('+JSON.stringify(config)+','+JSON.stringify(options)+')');
 for(const name of ['little_leaf_firebase.js','little_leaf_firebase_session.js','little_leaf_update.js','little_leaf_firebase_boot.mjs'])assert.equal(sha(fs.readFileSync(path.join(itchVariant,'public/itch',name))),sha(fs.readFileSync(path.join(root,'platform/web',name))));
}else{
html=fs.readFileSync(path.join(web,'index.html'),'utf8');
assert.equal(html.split('window.__littleLeafVault.boot()').length,2);
html=html.replace('window.__littleLeafVault.boot()','window.__littleLeafFirebaseReady.then(() => window.__littleLeafVault.boot())');
const injection='<script src="little_leaf_update.js"></script><script src="little_leaf_firebase_session.js"></script><script src="little_leaf_firebase.js"></script><script>window.__littleLeafRelease='+JSON.stringify(loadedRelease).replace(/</g,'\\u003c')+';window.__littleLeafFirebaseReady=import("./little_leaf_firebase_boot.mjs").then(m=>m.start('+JSON.stringify(config)+'));</script>';
assert.equal(html.split('<script src="index.js"></script>').length,2);
html=html.replace('<script src="index.js"></script>',injection+'<script src="index.js"></script>');
}
const auth=`const auth={currentUser:{uid:globalThis.__qaUid,isAnonymous:false},authStateReady:async()=>{}};export const browserLocalPersistence={};export const setPersistence=async()=>{};export const getRedirectResult=async()=>null;export const getAuth=()=>auth;export const getIdTokenResult=async()=>({claims:{firebase:{sign_in_provider:'google.com'}}});export class GoogleAuthProvider{};export const signInWithRedirect=async()=>{throw Error('SSO is outside this synthetic test')};export const signInWithPopup=async()=>{throw Error('SSO is outside this synthetic test')};export const signOut=async()=>{auth.currentUser=null};export const onAuthStateChanged=(a,fn)=>{queueMicrotask(()=>fn(a.currentUser));return()=>{}};`;
// The pinned SDK's emulator credential provider remains unchanged. Only its HTTP
// destination becomes a synthetic HTTPS URL; Playwright forwards it outside the browser.
// This is test-only transport plumbing, never a product SDK/settings change.
const httpsEmulator=itchVariant?`
 const before=db._getSettings(),credentials=db._authCredentials,emulatorOptions=db._getEmulatorOptions();
 if(before.host!=='127.0.0.1:8080'||before.ssl!==false||before.isUsingEmulator!==true||before.credentials!==undefined)throw Error('Pinned emulator settings changed');
 db._setSettings({...before,emulatorOptions,host:'firestore.fullflow.test:443',ssl:true});
 const after=db._getSettings();
 if(db._authCredentials!==credentials||db._getEmulatorOptions()!==emulatorOptions||after.host!=='firestore.fullflow.test:443'||after.ssl!==true||Object.keys(before).some(key=>!['host','ssl'].includes(key)&&JSON.stringify(before[key])!==JSON.stringify(after[key])))throw Error('Only emulator transport may change');
` : '';
const transactionObserver=itchVariant?`const transactionTimings={clockOrigin:${clockOrigin},sequence:0,rows:[]};
 const observeTransaction=${observeTransaction.toString()};
 export function runTransaction(db,update,options){return observeTransaction(real.runTransaction,db,update,options,transactionTimings);}`:'';
const firestore=`import * as real from '/sdk/firebase-firestore.js';export * from '/sdk/firebase-firestore.js';${transactionObserver}export function getFirestore(app){const db=real.initializeFirestore(app,{experimentalForceLongPolling:true});real.connectFirestoreEmulator(db,'127.0.0.1',8080,{mockUserToken:{sub:globalThis.__qaUid,firebase:{sign_in_provider:'google.com'}}});${httpsEmulator}globalThis.__qaFirestore={db,sdk:real${itchVariant?',transactionTimings':''}};return db;}`;
const server=http.createServer((req,res)=>{
 let worklet=null;
 try{const p=new URL(req.url,'http://127.0.0.1').pathname;worklet=workletName(officialOrigin+'/itch'+p);
 res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');res.setHeader('Cache-Control','no-store');
 // Only the Node-side fixture fetch may read these SDK bytes in itch mode.
 if(itchVariant && p.startsWith('/sdk/')){res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Cross-Origin-Resource-Policy','cross-origin');}
 let body,type='text/javascript';
 if(p==='/index.html'){body=html;type='text/html';}
 else if(p==='/seed.html'){body='<!doctype html><title>Synthetic fixture setup</title>';type='text/html';}
 else if(p==='/hosting-release.json'){body=JSON.stringify(release);type='application/json';}
 else if(p==='/sdk/auth.js')body=auth;
 else if(p==='/sdk/firestore-wrapper.js')body=firestore;
 else if(['/sdk/firebase-app.js','/sdk/firebase-firestore.js'].includes(p))body=fs.readFileSync(path.join(sdkRoot,path.basename(p)));
 else if(['/little_leaf_firebase.js','/little_leaf_firebase_session.js','/little_leaf_update.js','/little_leaf_firebase_boot.mjs'].includes(p))body=source(p.slice(1));
 else {assert.equal(path.basename(p),p.slice(1));body=fs.readFileSync(path.join(itchVariant?path.join(itchVariant,'public/itch'):web,p.slice(1)));type=p.endsWith('.wasm')?'application/wasm':p.endsWith('.js')?'text/javascript':'application/octet-stream';}
 if(worklet)workletObservation('local-server',worklet,200);
 res.writeHead(200,{'Content-Type':type});res.end(body);
 }catch(e){if(worklet)workletObservation('local-server',worklet,404);res.writeHead(404);res.end('Not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
let browser;const contexts=[],errors=[];
report.networkObservations=[];
function networkObservation(kind,family,result){
 const rows=report.networkObservations,existing=rows.find(row=>row.kind===kind&&row.family===family&&row.result===result);
 if(existing)existing.count=Math.min(100,existing.count+1);
 else if(rows.length<64)rows.push({kind,family,result,count:1});
}
async function until(fn,label,timeout=45000){const end=Date.now()+timeout;while(Date.now()<end){const value=await fn();if(value)return value;await new Promise(r=>setTimeout(r,150));}throw Error('Timed out: '+label);}
async function journal(page,uid,key=null){return page.evaluate(async({uid,key})=>{const db=await new Promise((yes,no)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>yes(q.result);q.onerror=()=>no(q.error);});try{return await new Promise((yes,no)=>{const tx=db.transaction('accounts'),q=tx.objectStore('accounts').get(key || uid);q.onsuccess=()=>yes(q.result||null);q.onerror=()=>no(q.error);});}finally{db.close();}},{uid,key});}
async function setup(uid,entry=null){
 const seedPhase={active:!!itchVariant};
 const context=await browser.newContext({viewport:{width:1360,height:880}});contexts.push(context);
 context.on('requestfailed',request=>networkObservation('failed',requestFamily(request.url(),origin),failureCategory(request.failure()?.errorText)));
 context.on('response',response=>{const family=requestFamily(response.url(),origin);if(['loopback-sdk','loopback-emulator','sdk-module','frame-sdk','synthetic-emulator'].includes(family))networkObservation('response',family,response.status());const name=workletName(response.url());if(name)workletObservation('browser-response',name,response.status());});
 await context.route('**/*',async route=>{const u=new URL(route.request().url());if(!itchVariant && (u.origin===origin || u.origin==='http://127.0.0.1:8080'))return route.continue();
 if(itchVariant && u.origin===syntheticRPCOrigin){
  if(route.request().frame().url()!==officialOrigin+'/itch/')return route.abort('blockedbyclient');
  if(route.request().method()==='OPTIONS'){
   try{return route.fulfill({status:204,headers:emulatorPreflightHeaders(u.href,route.request().headers()),body:''});}
   catch(_){errors.push('Nonfixture emulator preflight blocked');return route.abort('blockedbyclient');}
  }
  let target;try{target=emulatorProxyTarget(u.href,route.request().method());}
  catch(_){errors.push('Nonfixture emulator RPC blocked');return route.abort('blockedbyclient');}
  // APIRequestContext traffic is outside browser offline emulation; honor the
  // real context's navigator state before forwarding any SDK read/write.
  if(!await route.request().frame().evaluate(()=>navigator.onLine))return route.abort('internetdisconnected');
  const timing={device:contexts.indexOf(context)+1,kind:emulatorRequestKind(u.href,route.request().method()),start_ms:Date.now()-clockOrigin,outcome:'pending'};
  report.proxyTimings.push(timing);if(report.proxyTimings.length>256)report.proxyTimings.shift();
  try{
   const response=await route.fetch({url:target,maxRedirects:0,timeout:45000});
   timing.body_complete_ms=Date.now()-clockOrigin;timing.status=response.status();
   if(!await route.request().frame().evaluate(()=>navigator.onLine)){timing.outcome='offline';return route.abort('internetdisconnected');}
   await route.fulfill({response,headers:{...response.headers(),'access-control-allow-origin':officialOrigin,'access-control-allow-credentials':'true','cross-origin-resource-policy':'cross-origin'}});
   timing.fulfilled_ms=Date.now()-clockOrigin;timing.outcome='fulfilled';
   return;
  }catch(error){timing.end_ms=Date.now()-clockOrigin;timing.outcome=failureCategory(error.message);networkObservation('proxy','synthetic-emulator',timing.outcome);return route.abort('failed');}
 }
 if(itchVariant && u.href===itchPage)return route.fulfill({status:200,contentType:'text/html',body:'<!doctype html><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;overflow:hidden}</style><iframe src="'+classicPage+'" allow="autoplay; fullscreen"></iframe>'});
 if(itchVariant && u.href===classicPage)return route.fulfill({status:200,contentType:'text/html',body:fs.readFileSync(path.join(itchVariant,'itch-wrapper/index.html'))});
 if(itchVariant && [officialOrigin,'https://html-classic.itch.zone'].includes(u.origin)){
  const prefix=u.origin===officialOrigin?'/itch/':'/';
  assert(u.pathname.startsWith(prefix) && !u.search,'only exact isolated fixture paths');
  if(u.origin===officialOrigin && u.pathname==='/itch/sdk/firebase-firestore.js')return route.fulfill({status:200,contentType:'text/javascript',headers:{'Cross-Origin-Resource-Policy':'same-origin'},body:fs.readFileSync(path.join(sdkRoot,'firebase-firestore.js'))});
  const name=u.pathname.slice(prefix.length)||'index.html';assert.equal(path.basename(name),name);
  const worklet=workletName(u.href);if(worklet)workletObservation('intercepted',worklet,'started');
  if(u.origin==='https://html-classic.itch.zone')return route.fulfill({status:200,body:fs.readFileSync(path.join(itchVariant,'itch-wrapper',name)),contentType:name.endsWith('.js')?'text/javascript':name.endsWith('.wasm')?'application/wasm':'application/octet-stream'});
  const response=await route.fetch({url:origin+'/'+(name==='index.html'&&seedPhase.active?'seed.html':name),maxRedirects:0});
  if(worklet)workletObservation('fixture-response',worklet,response.status());
  const headers={...response.headers()};if(['index.html'].includes(name))headers['content-security-policy']='frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io';
  return route.fulfill({response,headers});
 }
 if(isConnectivityProbe(u.href,route.request().resourceType())){report.blockedConnectivityProbes=(report.blockedConnectivityProbes||0)+1;checkpoint();return route.abort('internetdisconnected');}
 const prefix='https://www.gstatic.com/firebasejs/12.19.0/';if(['firebase-app.js','firebase-auth.js','firebase-firestore.js'].some(name=>u.href===prefix+name)){const name=u.pathname.split('/').pop();const p=name==='firebase-auth.js'?'/sdk/auth.js':name==='firebase-firestore.js'?'/sdk/firestore-wrapper.js':'/sdk/firebase-app.js';return route.fulfill({status:200,contentType:'text/javascript',headers:{'Access-Control-Allow-Origin':'*','Cross-Origin-Resource-Policy':'cross-origin'},body:p==='/sdk/auth.js'?auth:p==='/sdk/firestore-wrapper.js'?firestore.replaceAll("'/sdk/","'"+(itchVariant?officialOrigin+'/itch':origin)+"/sdk/"):fs.readFileSync(path.join(sdkRoot,'firebase-app.js'))});}errors.push('Unexpected external request blocked: '+u.origin+u.pathname);return route.abort('blockedbyclient');});
 await context.addInitScript(({uid})=>{globalThis.__qaUid=uid;},{uid});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||m.type()==='warning')networkObservation('console','browser',failureCategory(m.text()));if(/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text());});
 let seedFrame=page;
 if(itchVariant){
  await page.goto(itchPage);
  const classic=await until(()=>page.frames().find(frame=>frame.url()===classicPage),'actual classic wrapper for seed');
  await classic.locator('#itch-account').click();
  seedFrame=await until(()=>page.frames().find(frame=>frame.url()===officialOrigin+'/itch/'),'actual nested seed frame');
  assert.deepEqual(await seedFrame.evaluate(()=>Array.from(location.ancestorOrigins)),['https://html-classic.itch.zone','https://siowyiyou.itch.io']);
  report.synthetic_seed_document=true;
 }else await page.goto(origin+'/seed.html');
 if(entry){await seedFrame.evaluate(async({uid,entry})=>{const db=await new Promise((yes,no)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>yes(q.result);q.onerror=()=>no(q.error);});await new Promise((yes,no)=>{const tx=db.transaction('accounts','readwrite');tx.objectStore('accounts').put(entry,uid);tx.oncomplete=yes;tx.onabort=()=>no(tx.error);});db.close();},{uid,entry});assert.deepEqual(await journal(seedFrame,uid),entry,'exact seed readback in game partition');}
 await page.addInitScript(installEngineLaunchHook,{args:['--','--skip-intro'],reportKey:'__fullflowEngine'});
 return {context,page,uid,seedFrame,seedPhase};
}
function gameFramePage(page,frame){return new Proxy(frame,{get(target,key){
 if(key==='mainFrame')return()=>frame;
 if(['on','off','removeListener','screenshot'].includes(key))return page[key].bind(page);
 const owner=key in target?target:page,value=owner[key];return typeof value==='function'?value.bind(owner):value;
}});}
async function launch(device){
 if(itchVariant){
  const page=device.page,frame=device.seedFrame;device.seedPhase.active=false;
  await frame.goto(officialOrigin+'/itch/');
  device.page=gameFramePage(page,frame);
  const ancestors=await frame.evaluate(()=>Array.from(location.ancestorOrigins));
  assert.deepEqual(ancestors,['https://html-classic.itch.zone','https://siowyiyou.itch.io']);report.itch_ancestor_origins=ancestors;
 }else await device.page.goto(origin+'/index.html');
 await device.page.waitForFunction(()=>!document.getElementById('status')&&globalThis.__fullflowEngine?.launchCalls===1,null,{timeout:90000});await device.page.waitForFunction(()=>globalThis.LittleLeafSaveLog?.snapshot().some(e=>e.layer==='controller'&&['read_accepted','read_failure'].includes(e.event)),null,{timeout:30000});await device.page.evaluate(({clockOrigin})=>{
 globalThis.__qaAdapterResults=[];const client=globalThis.__littleLeafVault;
 globalThis.__qaAdapterTimings=[];
 for(const name of ['boot','requestTakeover','finishTakeover','forceTakeover','preserveOwnerRuntime']){
  const original=client[name];client[name]=function(...args){
   const timing={method:name,start_ms:Date.now()-clockOrigin,outcome:'pending'};
   globalThis.__qaAdapterTimings.push(timing);if(globalThis.__qaAdapterTimings.length>64)globalThis.__qaAdapterTimings.shift();
   const promise=original.apply(this,args);promise.then(result=>{timing.end_ms=Date.now()-clockOrigin;timing.outcome='resolved';timing.cloudConfirmed=result?.cloudConfirmed??null;globalThis.__qaAdapterResults.push({method:name,result});},error=>{timing.end_ms=Date.now()-clockOrigin;timing.outcome='rejected';globalThis.__qaAdapterResults.push({method:name,error:String(error)});});return promise;
  };
 }
},{clockOrigin});return device;}
const snapshot=p=>p.evaluate(()=>JSON.parse(LittleLeafVault.recoverySnapshot()));
// Diagnostic observation only: persist bounded SDK/adapter timing before either
// successful context closure or timeout failure collection loses the live pages.
report.handoffTimings=[];
async function captureHandoffTimings(devices){
 for(let device=0;device<devices.length;device++){
  let timer;
  try{
   const observations=await Promise.race([devices[device].page.evaluate(()=>({
    transactionTimings:(globalThis.__qaFirestore?.transactionTimings?.rows||[]).slice(-128),
    adapterTimings:(globalThis.__qaAdapterTimings||[]).slice(-64),
    visibility:document.visibilityState,focused:document.hasFocus()
   })),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timing observation unavailable')),3000);})]);
   report.handoffTimings.push({device:device+1,...observations});
  }catch(_){report.handoffTimings.push({device:device+1,unavailable:true});}
  finally{clearTimeout(timer);try{checkpoint();}catch(_){report.timingCheckpointUnavailable=true;}}
 }
}

async function shot(p,name){await p.screenshot({path:path.join(out,name+'.png')});report.screenshots.push(name+'.png');}
function rectangle(mode,button){const r=recoveryLayout.geometry.find(x=>x.viewport?.width===1360 && x.viewport?.height===880 && x.mode===mode);assert(r?.buttons?.[button],mode+' '+button+' native geometry');return r.buttons[button];}
const nativeMessages=new WeakMap();let geometrySequence=0;
async function foreground(p){
 await p.bringToFront();await p.locator('#canvas').focus();
 await p.waitForFunction(()=>document.visibilityState==='visible' && document.hasFocus() && document.activeElement===document.getElementById('canvas'));
 await p.waitForTimeout(350);
}
async function click(p,mode,button){
 await foreground(p);
 assert.equal(mode,'other-device');assert.equal(button,'switch');
 const observations=await p.evaluate(()=>globalThis.__qaAdapterResults||[]);
 const nativeCallback=observations.filter(x=>['preserveOwnerRuntime','preserveRuntime','requestTakeover','finishTakeover','forceTakeover'].includes(x.method)).at(-1)||null;
 const observed={viewport:p.viewportSize(),snapshot:await snapshot(p),recoveryMessage:nativeMessages.get(p)||'',nativeCallback};
 assert.deepEqual(observed,retainedGeometryInput,'only exact retained snapshot and viewport may use the old measured rectangle');
 const [x,y,w,h]=retainedGeometryResult.buttons[button];
 assert([x,y,w,h].every(Number.isFinite)&&w>0&&h>0,'exact retained native rectangle');
 await p.mouse.click(x+w/2,y+h/2,{delay:50});nativeMessages.set(p,'');
}
async function nativeSave(d,beforeOverride=null){await d.page.waitForFunction(()=>globalThis.__littleLeafLifecycleV1?.current);await d.page.waitForTimeout(350);const before=beforeOverride || await until(async()=>{const entry=await journal(d.page,d.uid),state=await snapshot(d.page);return entry?.record && !state.ownershipPaused && !state.busy && entry;},'resumed native account journal',30000);await d.page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));await until(async()=>{const e=await journal(d.page,d.uid);return e?.record.revision>before.record.revision && e;},'native lifecycle durable save');const saved=await journal(d.page,d.uid);await d.page.evaluate(()=>window.dispatchEvent(new Event('pageshow')));return saved;}
async function confirmedClick(p,mode,button,accept){let finish;const handled=new Promise(resolve=>finish=resolve);p.once('dialog',async dialog=>{assert.equal(dialog.type(),'confirm');await (accept?dialog.accept():dialog.dismiss());finish();});await click(p,mode,button);let timer;try{await Promise.race([handled,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Expected native confirmation dialog')),10000);})]);}finally{clearTimeout(timer);}if(!accept)nativeMessages.set(p,'Choose either save when you are ready.');await p.waitForTimeout(100);}
async function resumeProof(d,coins){const e=await nativeSave(d);check(JSON.parse(e.record.payload).coins===coins,'native model really resumed chosen coins '+coins);return e;}
async function updateClick(p,button,error=false){await foreground(p);const r=updateLayout.geometry.find(x=>x.viewport?.width===1360 && x.viewport?.height===880 && x.error===error);assert(r?.buttons?.[button],'update native geometry');const [x,y,w,h]=r.buttons[button];await p.mouse.click(x+w/2,y+h/2);}
try{
 browser=await chromium.launch({headless:report.headless_browser,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || 'chrome'});
 // Old cache has proven no pending branch: cloud wins without upload or prompt.
 {const uid='fullflow-cache',base=await record(1,41000),cloud=await record(8,42000,base.profileId);await seed(uid,cloud);
 const d=await launch(await setup(uid,{record:base,base:base.digest,pending:false,device:'Mac'}));
 const sso=await d.page.evaluate(async()=>{
  const sdk=await import('https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js'),auth=sdk.getAuth(),before=auth.currentUser,rejected=[];
  for(const name of ['signInWithPopup','signInWithRedirect']){try{await sdk[name](auth,new sdk.GoogleAuthProvider());}catch(error){if(error.message==='SSO is outside this synthetic test')rejected.push(name);}}
  return {rejected,accountUnchanged:auth.currentUser===before};
 });
 check(sso.accountUnchanged && sso.rejected.join(',')==='signInWithPopup,signInWithRedirect','synthetic popup and redirect reject without changing the authenticated fixture');
 await d.page.waitForFunction(()=>LittleLeafSaveLog.snapshot().some(e=>e.layer==='controller'&&e.event==='read_accepted'));
 check((await read(uid)).digest===cloud.digest,'harmless cached save never uploaded on re-entry');check(!(await snapshot(d.page)).choicesAvailable,'harmless cache gives no choice');
 check((await journal(d.page,uid)).record.digest===cloud.digest,'latest cloud automatically loaded into journal');await shot(d.page,'old-cache-cloud-loaded');await d.context.close();}
 // Real native takeover button, old native freeze/snapshot/flush, server ack, then epoch switch.
 {const uid='fullflow-graceful',r=await record(1,42000);await seed(uid,r);const a=await launch(await setup(uid));const owner=await read(uid,'owner');const b=await launch(await setup(uid));
 check((await snapshot(b.page)).status==='other-device','second compiled game waits for explicit switch');
 const transitions=[];const db=env.authenticatedContext(uid,{firebase:{sign_in_provider:'google.com'}}).firestore();const stop=onSnapshot(doc(db,'players',uid,'session','owner'),s=>{if(s.exists())transitions.push(s.data());});
 await shot(b.page,'second-device-paused');await click(b.page,'other-device','switch');
 try{
 await until(async()=>{const x=await read(uid,'owner');return x.epoch===owner.epoch+1;},'graceful ownership transfer');
 }finally{await captureHandoffTimings([a,b]);}
 const pending=await journal(a.page,uid),cloud=await read(uid);const ack=transitions.find(x=>x.ack && x.owner===owner.owner);stop();
 check(!!ack && ack.ack.digest===cloud.digest && ack.ack.revision===cloud.revision,'old owner acknowledged exact final cloud save before ownership transfer');
 check(pending.record.digest===cloud.digest && !pending.pending,'old native snapshot durably saved and cloud-confirmed');check((await snapshot(a.page)).ownershipPaused,'old compiled game paused after handoff');
 await resumeProof(b,42000);await shot(a.page,'old-device-paused');
 const stale={...cloud,revision:cloud.revision+100,writerId:owner.owner,writerEpoch:owner.epoch};await assertFails(setDoc(doc(db,'players',uid,'saves','cafe'),stale));check(true,'actual rules reject stale writer even bypassing client checks');await a.context.close();await b.context.close();}
 check(errors.length===0,'compiled runtime reports no script or page errors: '+errors.join('; '));report.passed=true;
}catch(error){
 report.failure=String(error.stack||error);report.failureStates=[];
 for(const context of contexts)for(const originalPage of context.pages()){
  const frame=itchVariant?originalPage.frames().find(frame=>frame.url().startsWith(officialOrigin+'/itch/')):null;
  const page=frame?gameFramePage(originalPage,frame):originalPage;
  try{const uid=await page.evaluate(()=>globalThis.__qaUid);if(!/^fullflow-[a-z-]+$/.test(uid))continue;
   // Observe bootstrap first. The original local vault deliberately has no recoverySnapshot.
   // Each optional observation is independent so one unavailable API cannot hide the cause.
   const state={uid};report.failureStates.push(state);
   const observe=async(name,fn)=>{let timer;try{state[name]=await Promise.race([fn(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('observation unavailable')),3000);})]);}catch(_){state[name]={unavailable:true};}finally{clearTimeout(timer);checkpoint();}};
   await observe('startup',()=>page.evaluate(async()=>{
    const status=document.getElementById('status-label'),message=status?.textContent||'';
    const statusDigest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(message)))).map(x=>x.toString(16).padStart(2,'0')).join('');
    let timer;const ready=globalThis.__littleLeafFirebaseReady;let settlement='absent',reason='';
    if(ready)try{settlement=await Promise.race([Promise.resolve(ready).then(()=>'resolved',error=>{reason=String(error?.message||error);return 'rejected';}),new Promise(resolve=>{timer=setTimeout(()=>resolve('pending'),250);})]);}finally{clearTimeout(timer);}
    return {statusPresent:!!document.getElementById('status'),statusDigest,statusLength:message.length,
      settlement,reasonCategory:/local.network|private.network/i.test(reason)?'local-network':/fetch|network|import/i.test(reason)?'network':/permission/i.test(reason)?'permission':/storage|indexeddb/i.test(reason)?'storage':reason?'other':'none',
      launchCalls:globalThis.__fullflowEngine?.launchCalls??null,hookInstalled:!!globalThis.__fullflowEngine,
      firebaseClientInstalled:globalThis.__littleLeafVault?.storageKind==='firebase-firestore',recoverySnapshotAvailable:typeof globalThis.LittleLeafVault?.recoverySnapshot==='function',
      sdkInstalled:!!globalThis.__qaFirestore,secureContext:isSecureContext,crossOriginIsolated,
      visible:document.visibilityState,focused:document.hasFocus(),activeElement:document.activeElement?.tagName};
   }));
   await observe('snapshot',()=>page.evaluate(()=>typeof globalThis.LittleLeafVault?.recoverySnapshot==='function'?JSON.parse(LittleLeafVault.recoverySnapshot()):null));
   await observe('journal',()=>journal(page,uid));await observe('owner',()=>read(uid,'owner'));await observe('cloud',()=>read(uid));
   await observe('nativeLog',()=>page.evaluate(()=>globalThis.LittleLeafSaveLog?.snapshot()));await observe('adapterResults',()=>page.evaluate(()=>globalThis.__qaAdapterResults));
   await observe('transactionTimings',()=>page.evaluate(()=>globalThis.__qaFirestore?.transactionTimings?.rows));
   await observe('adapterTimings',()=>page.evaluate(()=>globalThis.__qaAdapterTimings));
   await observe('bootReceipt',()=>page.evaluate(()=>globalThis.__littleLeafVault?.bootJson));
   await observe('screenshot',async()=>{await shot(page,'failure-'+report.failureStates.length);return true;});
  }catch(observationError){report.failureStates.push({observationError:String(observationError)});}
 }
 throw error;
}finally{
 report.errors=errors;fs.writeFileSync(path.join(out,'firebase-fullflow.json'),JSON.stringify(report,null,2));
 for(const context of contexts)await context.close().catch(()=>{});await browser?.close();await new Promise(resolve=>server.close(resolve));await env.cleanup();
}
