import {createRequire as sourceRequire} from 'node:module';
const {sourcePath}=sourceRequire(import.meta.url)('../../tests/tooling/source_paths.js');
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
import {installHandoffObservation,proxyCategory,operationLabel} from './current_handoff_observer.mjs';
import {createFixtureStore} from './fullflow_fixtures.mjs';
import {isConnectivityProbe,failureCategory,requestFamily,syntheticRPCOrigin,emulatorProxyTarget,emulatorPreflightHeaders,installPackagedWorklets,createRouteLifetime} from './fullflow_network.mjs';
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
const engine=JSON.parse(fs.readFileSync(native)),manifest=JSON.parse(fs.readFileSync(path.join(web,'release-manifest.json')));
assert(itchVariant,'exact same-iframe current-stage variant required');
assert.equal(manifest.source_commit,'59e3e572e5d7723b7515f1a0a2af226bafe38b2f');
assert.equal(manifest.source_tree,'2dc00d31ff80b9d1ca3e24bdf8f6f712f3d8e199');
assert.equal(engine.status,'passed');assert.equal(engine.source_commit,manifest.source_commit);assert.equal(engine.player_save_used,false);
const retainedInput=JSON.parse(fs.readFileSync(arg('--retained-geometry-input'))),retainedGeometry=JSON.parse(fs.readFileSync(arg('--retained-geometry-result')));
assert.deepEqual(retainedInput.viewport,{width:1360,height:880});assert.deepEqual(retainedGeometry.snapshot,retainedInput.snapshot);
function nativeResult(name,marker){const log=fs.readFileSync(path.join(path.dirname(native),name+'.log'),'utf8');const rows=log.split('\n').filter(line=>line.startsWith(marker+' '));assert.equal(rows.length,1,'one exact native geometry result');return JSON.parse(rows[0].slice(marker.length+1));}
const recoveryLayout=nativeResult('test_cloud_recovery_ui','CLOUD_RECOVERY_UI_RESULT');
const updateLayout=nativeResult('test_update_notice','UPDATE_NOTICE_RESULT');
assert.deepEqual(recoveryLayout.failures,[]);assert.deepEqual(updateLayout.failures,[]);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
for(const [name,record] of Object.entries(manifest.files))assert.equal(sha(fs.readFileSync(path.join(web,name))),record.sha256,'exact exported '+name);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080','explicit local emulator only');
fs.mkdirSync(out,{recursive:true});
const report={passed:false,synthetic_only:true,real_compiled_ui:true,real_firestore_rules:true,real_google_sign_in:false,browser_sandbox:true,headless_browser:process.env.PLAYWRIGHT_HEADLESS==='1',source_commit:manifest.source_commit,source_tree:manifest.source_tree,export_manifest_sha256:sha(fs.readFileSync(path.join(web,'release-manifest.json'))),native_report_sha256:sha(fs.readFileSync(native)),diagnostic_only:process.argv.includes('--diagnostic-only'),checks:[],screenshots:[],source_sha256:Object.fromEntries(['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs','tests/diagnostics/probe_cloud_recovery_geometry.gd','tools/qualification/prepare_browser_qa.py','web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules'].map(n=>[n,sha(fs.readFileSync(sourcePath(root,n)))]))};
Object.assign(report,{full_suite:false,release_qualification:false,deployable:false,current_failed_run:38298556083,phase_diagnostic:true,native_geometry_fresh:false,synthetic_first_two_only:true,original_first_two_sequence:true,native_resume_proof_preserved:true,source_overlay_not_git_head:true,observer_driver_sha256:sha(fs.readFileSync(import.meta.filename)),observer_module_sha256:sha(fs.readFileSync(new URL('./current_handoff_observer.mjs',import.meta.url))),proxyTimings:[],proxyTimingsDropped:0,unexpectedExternalRequests:0});
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
// Diagnostic-only timing; return each original Promise unchanged.
let activeHandoffPoll=null;
const observedEnvironment={projectId:env.projectId,withSecurityRulesDisabled(callback){
 const sample=activeHandoffPoll;if(sample)sample.rulesDisabledEnteredAt=Date.now();
 const operation=env.withSecurityRulesDisabled(context=>{
  if(sample)sample.rulesCallbackEnteredAt=Date.now();
  const result=callback(context);
  if(sample)Promise.resolve(result).then(()=>{sample.rulesCallbackReturnedAt=Date.now();},()=>{sample.rulesCallbackFailedAt=Date.now();});
  return result;
 });
 if(sample)operation.then(()=>{sample.rulesDisabledReturnedAt=Date.now();},()=>{sample.rulesDisabledFailedAt=Date.now();});
 return operation;
}};
const fixtureStore=createFixtureStore(observedEnvironment);
function ownerObservation(value){
 if(!value)return null;
 const stamp=value.updatedAt;
 return {owner:value.owner,epoch:value.epoch,requestId:value.request?.id??null,requester:value.request?.requester??null,
  ack:value.ack?{requestId:value.ack.requestId,digest:value.ack.digest,revision:value.ack.revision}:null,
  updatedAt:typeof stamp==='number'?stamp:{seconds:stamp?.seconds??null,nanoseconds:stamp?.nanoseconds??null}};
}
const read=(uid,kind='save')=>{
 const sample=activeHandoffPoll;if(sample)sample.readEnteredAt=Date.now();
 const result=fixtureStore.read(uid,kind);
 if(sample)result.then(value=>{sample.readReturnedAt=Date.now();sample.owner=ownerObservation(value);},()=>{sample.readFailedAt=Date.now();});
 return result;
};
const seed=(uid,r)=>fixtureStore.seed(uid,envelope(r));
const sdkRoot=path.dirname(require.resolve('firebase/package.json'));
const source=name=>fs.readFileSync(path.join(root,'platform/web',name),'utf8');
const loadedRelease=itchVariant?JSON.parse(fs.readFileSync(path.join(itchVariant,'public/itch/hosting-release.json'))):{schema_version:1,version:manifest.version,source_commit:manifest.source_commit};
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
const firestore=`import * as real from '/sdk/firebase-firestore.js';export * from '/sdk/firebase-firestore.js';export function getFirestore(app){const db=real.initializeFirestore(app,{experimentalForceLongPolling:true});real.connectFirestoreEmulator(db,'127.0.0.1',8080,{mockUserToken:{sub:globalThis.__qaUid,firebase:{sign_in_provider:'google.com'}}});${httpsEmulator}globalThis.__qaFirestore={db,sdk:real};return db;}`;
const server=http.createServer((req,res)=>{
 try{const p=new URL(req.url,'http://127.0.0.1').pathname;
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
 res.writeHead(200,{'Content-Type':type});res.end(body);
 }catch(e){res.writeHead(404);res.end('Not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
let browser,caseFailure;const contexts=[],errors=[],routeLifetimes=new WeakMap();
const closeContext=context=>routeLifetimes.get(context).close();
report.networkObservations=[];
const phaseSpan=(context,route)=>{const span={context:contexts.indexOf(context),operation:operationLabel(route.request().url(),route.request().method()),startedAt:Date.now(),fetchedBodyAt:null,fulfillResolvedAt:null,failedAt:null,outcome:'pending'};if(report.proxyTimings.length<128)report.proxyTimings.push(span);else report.proxyTimingsDropped++;return span;};
function networkObservation(kind,family,result){
 const rows=report.networkObservations,existing=rows.find(row=>row.kind===kind&&row.family===family&&row.result===result);
 if(existing)existing.count=Math.min(100,existing.count+1);
 else if(rows.length<64)rows.push({kind,family,result,count:1});
}
function timingCheckpoint(){try{checkpoint();}catch(_){report.timingWriteUnavailable=true;}}
async function until(fn,label,timeout=45000){
 const end=Date.now()+timeout;
 const trace=label==='graceful ownership transfer'?report.handoffObservation:null;
 if(trace)trace.until={enteredAt:end-timeout,deadlineAt:end,timeoutMs:timeout,polls:[],dropped:0,outcome:'pending'};
 while(Date.now()<end){
  const sample=trace?{enteredAt:Date.now()}:null;
  if(trace){if(trace.until.polls.length<512)trace.until.polls.push(sample);else trace.until.dropped++;activeHandoffPoll=sample;}
  let value;
  try{value=await fn();}
  catch(error){if(trace){sample.predicateThrewAt=Date.now();activeHandoffPoll=null;trace.until.outcome='predicate-error';trace.until.exitedAt=Date.now();timingCheckpoint();}throw error;}
  if(trace){sample.predicateReturnedAt=Date.now();sample.matched=!!value;activeHandoffPoll=null;}
  if(value){if(trace){trace.until.outcome='success';trace.until.exitedAt=Date.now();timingCheckpoint();}return value;}
  await new Promise(r=>setTimeout(r,150));
 }
 if(trace){trace.until.outcome='timeout';trace.until.exitedAt=Date.now();timingCheckpoint();}
 throw Error('Timed out: '+label);
}
async function journal(page,uid,key=null){return page.evaluate(async({uid,key})=>{const db=await new Promise((yes,no)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>yes(q.result);q.onerror=()=>no(q.error);});try{return await new Promise((yes,no)=>{const tx=db.transaction('accounts'),q=tx.objectStore('accounts').get(key || uid);q.onsuccess=()=>yes(q.result||null);q.onerror=()=>no(q.error);});}finally{db.close();}},{uid,key});}
async function setup(uid,entry=null){
 const seedPhase={active:!!itchVariant};
 const context=await browser.newContext({viewport:{width:1360,height:880}});contexts.push(context);
 await context.addInitScript(installHandoffObservation);
 const routes=createRouteLifetime(context,errors);routeLifetimes.set(context,routes);
 if(itchVariant){
  const packet=JSON.parse(fs.readFileSync(path.join(itchVariant,'firebase-variant-manifest.json')));
  const modules={};
  for(const name of ['index.audio.worklet.js','index.audio.position.worklet.js']){
   const bytes=fs.readFileSync(path.join(itchVariant,'public/itch',name));
   assert.equal(sha(bytes),packet.files['public/itch/'+name],'exact packaged worklet '+name);
   modules[name]=bytes.toString('base64');
  }
  await context.addInitScript(installPackagedWorklets,{origin:officialOrigin,pathname:'/itch/',modules});
 }
 context.on('requestfailed',request=>networkObservation('failed',requestFamily(request.url(),origin),failureCategory(request.failure()?.errorText)));
 context.on('response',response=>{const family=requestFamily(response.url(),origin);if(['loopback-sdk','loopback-emulator','sdk-module','frame-sdk','synthetic-emulator'].includes(family))networkObservation('response',family,response.status());});
 await context.route('**/*',routes.handle(async route=>{const u=new URL(route.request().url());if(!itchVariant && (u.origin===origin || u.origin==='http://127.0.0.1:8080'))return route.continue();
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
   const span=phaseSpan(context,route);
   try{
    const response=await route.fetch({url:target,maxRedirects:0,timeout:45000});span.fetchedBodyAt=Date.now();span.status=response.status();
    if(!await route.request().frame().evaluate(()=>navigator.onLine)){span.outcome='offline';return route.abort('internetdisconnected');}
    const fulfilled=route.fulfill({response,headers:{...response.headers(),'access-control-allow-origin':officialOrigin,'access-control-allow-credentials':'true','cross-origin-resource-policy':'cross-origin'}});
    return fulfilled.then(()=>{span.fulfillResolvedAt=Date.now();span.outcome='fulfilled';},error=>{span.failedAt=Date.now();span.outcome=proxyCategory(error);throw error;});
   }catch(error){span.failedAt=Date.now();span.outcome=proxyCategory(error);networkObservation('proxy','synthetic-emulator',failureCategory(error.message));return route.abort('failed');}
 }
 if(itchVariant && u.href===itchPage)return route.fulfill({status:200,contentType:'text/html',body:'<!doctype html><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;overflow:hidden}</style><iframe src="'+classicPage+'" allow="autoplay; fullscreen"></iframe>'});
 if(itchVariant && u.href===classicPage)return route.fulfill({status:200,contentType:'text/html',body:fs.readFileSync(path.join(itchVariant,'itch-wrapper/index.html'))});
 if(itchVariant && [officialOrigin,'https://html-classic.itch.zone'].includes(u.origin)){
  const prefix=u.origin===officialOrigin?'/itch/':'/';
  assert(u.pathname.startsWith(prefix) && !u.search,'only exact isolated fixture paths');
  if(u.origin===officialOrigin && u.pathname==='/itch/sdk/firebase-firestore.js')return route.fulfill({status:200,contentType:'text/javascript',headers:{'Cross-Origin-Resource-Policy':'same-origin'},body:fs.readFileSync(path.join(sdkRoot,'firebase-firestore.js'))});
  const name=u.pathname.slice(prefix.length)||'index.html';assert.equal(path.basename(name),name);
  if(u.origin==='https://html-classic.itch.zone')return route.fulfill({status:200,body:fs.readFileSync(path.join(itchVariant,'itch-wrapper',name)),contentType:name.endsWith('.js')?'text/javascript':name.endsWith('.wasm')?'application/wasm':'application/octet-stream'});
  const response=await route.fetch({url:origin+'/'+(name==='index.html'&&seedPhase.active?'seed.html':name),maxRedirects:0});
  const headers={...response.headers()};if(['index.html'].includes(name))headers['content-security-policy']='frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io';
  return route.fulfill({response,headers});
 }
 if(isConnectivityProbe(u.href,route.request().resourceType())){report.blockedConnectivityProbes=(report.blockedConnectivityProbes||0)+1;checkpoint();return route.abort('internetdisconnected');}
 const prefix='https://www.gstatic.com/firebasejs/12.19.0/';if(['firebase-app.js','firebase-auth.js','firebase-firestore.js'].some(name=>u.href===prefix+name)){const name=u.pathname.split('/').pop();const p=name==='firebase-auth.js'?'/sdk/auth.js':name==='firebase-firestore.js'?'/sdk/firestore-wrapper.js':'/sdk/firebase-app.js';return route.fulfill({status:200,contentType:'text/javascript',headers:{'Access-Control-Allow-Origin':'*','Cross-Origin-Resource-Policy':'cross-origin'},body:p==='/sdk/auth.js'?auth:p==='/sdk/firestore-wrapper.js'?firestore.replaceAll("'/sdk/","'"+(itchVariant?officialOrigin+'/itch':origin)+"/sdk/"):fs.readFileSync(path.join(sdkRoot,'firebase-app.js'))});}report.unexpectedExternalRequests++;errors.push('Unexpected external request blocked');return route.abort('blockedbyclient');}));
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
 await device.page.waitForFunction(()=>!document.getElementById('status')&&globalThis.__fullflowEngine?.launchCalls===1,null,{timeout:90000});await device.page.waitForFunction(()=>globalThis.LittleLeafSaveLog?.snapshot().some(e=>e.layer==='controller'&&['read_accepted','read_failure'].includes(e.event)),null,{timeout:30000});await device.page.evaluate(()=>{
 globalThis.__qaAdapterResults=[];const client=globalThis.__littleLeafVault;
 for(const name of ['boot','requestTakeover','finishTakeover','forceTakeover','preserveOwnerRuntime']){
  const original=client[name];client[name]=function(...args){const promise=original.apply(this,args);promise.then(result=>globalThis.__qaAdapterResults.push({method:name,result}),error=>globalThis.__qaAdapterResults.push({method:name,error:String(error)}));return promise;};
 }
});return device;}
const snapshot=p=>p.evaluate(()=>JSON.parse(LittleLeafVault.recoverySnapshot()));
async function shot(p,name){await p.screenshot({path:path.join(out,name+'.png')});report.screenshots.push(name+'.png');}
function rectangle(mode,button){const r=recoveryLayout.geometry.find(x=>x.viewport?.width===1360 && x.viewport?.height===880 && x.mode===mode);assert(r?.buttons?.[button],mode+' '+button+' native geometry');return r.buttons[button];}
const nativeMessages=new WeakMap();let geometrySequence=0;
async function foreground(p){
 await p.bringToFront();await p.locator('#canvas').focus();
 await p.waitForFunction(()=>document.visibilityState==='visible' && document.hasFocus() && document.activeElement===document.getElementById('canvas'));
 await p.waitForTimeout(350);
}
async function click(p,mode,button){
 assert.equal(mode,'other-device');assert.equal(button,'switch');assert.equal(++geometrySequence,1);
 await foreground(p);assert.deepEqual(p.viewportSize(),retainedInput.viewport);
 assert.deepEqual(await snapshot(p),retainedInput.snapshot,'same UI-relevant snapshot as exact current retained geometry');
 const r=retainedGeometry.buttons.switch;assert(r?.length===4);const [x,y,w,h]=r;
 report.reusedGeometry={input_sha256:sha(fs.readFileSync(arg('--retained-geometry-input'))),result_sha256:sha(fs.readFileSync(arg('--retained-geometry-result'))),viewport:retainedInput.viewport,button:'switch'};
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
 check((await journal(d.page,uid)).record.digest===cloud.digest,'latest cloud automatically loaded into journal');await shot(d.page,'old-cache-cloud-loaded');await closeContext(d.context);}
  // The original cache case above has fully closed and drained its routes.
  // Keep the finite proxy budget for the target transfer, without changing RPCs.
  report.precedingCache={completed:true,checks:report.checks.length,contextCount:contexts.length,proxyEvents:report.proxyTimings.length,proxyDropped:report.proxyTimingsDropped};
  report.proxyTimings=[];report.proxyTimingsDropped=0;checkpoint();
 // Real native takeover button, old native freeze/snapshot/flush, server ack, then epoch switch.
 {const uid='fullflow-graceful',r=await record(1,42000);await seed(uid,r);const a=await launch(await setup(uid));const owner=await read(uid,'owner');report.handoffObservation={initialOwner:ownerObservation(owner),expectedEpoch:owner.epoch+1,initialOwnerReadReturnedAt:Date.now()};const b=await launch(await setup(uid));
 check((await snapshot(b.page)).status==='other-device','second compiled game waits for explicit switch');
 const transitions=[];const db=env.authenticatedContext(uid,{firebase:{sign_in_provider:'google.com'}}).firestore();const stop=onSnapshot(doc(db,'players',uid,'session','owner'),s=>{if(s.exists())transitions.push(s.data());});
 await shot(b.page,'second-device-paused');report.handoffObservation.clickEnteredAt=Date.now();await click(b.page,'other-device','switch');report.handoffObservation.clickReturnedAt=Date.now();
 await until(async()=>{const x=await read(uid,'owner');return x.epoch===owner.epoch+1;},'graceful ownership transfer');
 const pending=await journal(a.page,uid),cloud=await read(uid);const ack=transitions.find(x=>x.ack && x.owner===owner.owner);stop();
 check(!!ack && ack.ack.digest===cloud.digest && ack.ack.revision===cloud.revision,'old owner acknowledged exact final cloud save before ownership transfer');
 check(pending.record.digest===cloud.digest && !pending.pending,'old native snapshot durably saved and cloud-confirmed');check((await snapshot(a.page)).ownershipPaused,'old compiled game paused after handoff');
 await resumeProof(b,42000);await shot(a.page,'old-device-paused');
 const stale={...cloud,revision:cloud.revision+100,writerId:owner.owner,writerEpoch:owner.epoch};await assertFails(setDoc(doc(db,'players',uid,'saves','cafe'),stale));check(true,'actual rules reject stale writer even bypassing client checks');report.handoffPhases=[await a.page.evaluate(()=>globalThis.__qaHandoffObservation),await b.page.evaluate(()=>globalThis.__qaHandoffObservation)];checkpoint();await closeContext(a.context);await closeContext(b.context);}
 check(errors.length===0,'compiled runtime reports no script or page errors: '+errors.join('; '));report.passed=true;
}catch(error){
 if(report.handoffObservation){report.handoffObservation.failureCaptureEnteredAt=Date.now();timingCheckpoint();}
 caseFailure=error;
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
   await observe('bootReceipt',()=>page.evaluate(()=>globalThis.__littleLeafVault?.bootJson));
    await observe('handoffPhases',()=>page.evaluate(()=>globalThis.__qaHandoffObservation));
   await observe('screenshot',async()=>{await shot(page,'failure-'+report.failureStates.length);return true;});
  }catch(observationError){report.failureStates.push({observationError:String(observationError)});}
 }
 throw error;
}finally{
 let cleanupFailure;
 const cleanup=async operation=>{try{await operation();}catch(error){cleanupFailure??=error;errors.push('Fixture cleanup failed');}};
 for(const context of contexts)await cleanup(()=>closeContext(context));
 await cleanup(()=>browser?.close());await cleanup(()=>new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve())));await cleanup(()=>env.cleanup());
 // Teardown must not hide an earlier assertion, or make a late route error green.
 if(cleanupFailure || errors.length){
  report.passed=false;
  if(!caseFailure)report.failure=String((cleanupFailure || Error('Fixture route/runtime errors: '+errors.join('; '))).stack);
 }
 report.errors=errors;
 let finalFailure=caseFailure || cleanupFailure || (!report.passed && Error(report.failure));
 try{checkpoint();}catch(error){console.error('Final fullflow report write failed');finalFailure ||= error;}
 if(!caseFailure && finalFailure)throw finalFailure;
}
