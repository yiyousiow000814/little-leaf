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
import {isConnectivityProbe} from './fullflow_network.mjs';
import {initializeTestEnvironment,assertFails} from '@firebase/rules-unit-testing';
import {doc,getDocFromServer,setDoc,onSnapshot} from 'firebase/firestore';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {installEngineLaunchHook}=require('../tests/engine_launch_hook.js');
const root=path.resolve(import.meta.dirname,'..');
const arg=name=>{const i=process.argv.indexOf(name);assert(i>=0 && process.argv[i+1],name+' required');return path.resolve(process.argv[i+1]);};
const web=arg('--web-build'),out=arg('--output'),native=arg('--engine-report');
const geometryProject=process.env.CLOUD_GEOMETRY_PROJECT;assert(geometryProject,'disposable native geometry required');
const geometryBinding=JSON.parse(fs.readFileSync(path.join(geometryProject,'../binding.json')));
for(const [name,digest] of Object.entries(geometryBinding.source_sha256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex'),digest,'geometry source '+name);
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
const report={passed:false,synthetic_only:true,real_compiled_ui:true,real_firestore_rules:true,real_google_sign_in:false,browser_sandbox:true,source_commit:manifest.source_commit,source_tree:manifest.source_tree,export_manifest_sha256:sha(fs.readFileSync(path.join(web,'release-manifest.json'))),native_report_sha256:sha(fs.readFileSync(native)),diagnostic_only:process.argv.includes('--diagnostic-only'),checks:[],screenshots:[],source_sha256:Object.fromEntries(['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs','tests/probe_cloud_recovery_geometry.gd','ci/prepare_browser_qa.py','web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules'].map(n=>[n,sha(fs.readFileSync(path.join(root,n)))]))};
const checkpoint=()=>fs.writeFileSync(path.join(out,'firebase-fullflow.json'),JSON.stringify(report,null,2));
const check=(ok,label)=>{assert(ok,label);report.checks.push(label);checkpoint();};
const fixture=JSON.parse(fs.readFileSync(path.join(root,'tests/fixtures/startup-retry-v15.json')));
vm.runInThisContext(fs.readFileSync(path.join(root,'web/little_leaf_vault.js'),'utf8'));
const codec=globalThis.LittleLeafAuthorityCodec;
async function record(revision,coins,profileId=crypto.randomUUID()){
 const r={format:2,profileId,revision,createdAt:1,updatedAt:1700000000000+revision*1000,payload:JSON.stringify({...fixture,coins,operating_open:false}),digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
 r.digest=await codec.hash(codec.fingerprint(r));return r;
}
const envelope=(r,device='iPhone')=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r),device});
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync(path.join(root,'firebase/firestore.rules'),'utf8')}});
const fixtureStore=createFixtureStore(env);
const read=(uid,kind='save')=>fixtureStore.read(uid,kind);
const seed=(uid,r)=>fixtureStore.seed(uid,envelope(r));
const sdkRoot=path.dirname(require.resolve('firebase/package.json'));
const source=name=>fs.readFileSync(path.join(root,'web',name),'utf8');
let release={schema_version:1,version:manifest.version,source_commit:manifest.source_commit};
const config={apiKey:'emulator-synthetic-key',authDomain:'127.0.0.1',projectId:'demo-little-leaf',appId:'1:123:web:synthetic'};
let html=fs.readFileSync(path.join(web,'index.html'),'utf8');
assert.equal(html.split('window.__littleLeafVault.boot()').length,2);
html=html.replace('window.__littleLeafVault.boot()','window.__littleLeafFirebaseReady.then(() => window.__littleLeafVault.boot())');
const injection='<script src="little_leaf_update.js"></script><script src="little_leaf_firebase_session.js"></script><script src="little_leaf_firebase.js"></script><script>window.__littleLeafFirebaseReady=import("./little_leaf_firebase_boot.mjs").then(m=>m.start('+JSON.stringify(config)+'));</script>';
assert.equal(html.split('<script src="index.js"></script>').length,2);
html=html.replace('<script src="index.js"></script>',injection+'<script src="index.js"></script>');
const auth=`const auth={currentUser:{uid:globalThis.__qaUid,isAnonymous:false},authStateReady:async()=>{}};export const browserLocalPersistence={};export const setPersistence=async()=>{};export const getRedirectResult=async()=>null;export const getAuth=()=>auth;export class GoogleAuthProvider{};export const signInWithRedirect=async()=>{throw Error('SSO is outside this synthetic test')};export const signInWithPopup=async()=>{throw Error('SSO is outside this synthetic test')};export const signOut=async()=>{auth.currentUser=null};export const onAuthStateChanged=(a,fn)=>{queueMicrotask(()=>fn(a.currentUser));return()=>{}};`;
const firestore=`import * as real from '/sdk/firebase-firestore.js';export * from '/sdk/firebase-firestore.js';export function getFirestore(app){const db=real.initializeFirestore(app,{experimentalForceLongPolling:true});real.connectFirestoreEmulator(db,'127.0.0.1',8080,{mockUserToken:{sub:globalThis.__qaUid,firebase:{sign_in_provider:'google.com'}}});globalThis.__qaFirestore={db,sdk:real};return db;}`;
const server=http.createServer((req,res)=>{
 try{const p=new URL(req.url,'http://127.0.0.1').pathname;
 res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');res.setHeader('Cache-Control','no-store');
 let body,type='text/javascript';
 if(p==='/index.html'){body=html;type='text/html';}
 else if(p==='/seed.html'){body='<!doctype html><title>Synthetic fixture setup</title>';type='text/html';}
 else if(p==='/hosting-release.json'){body=JSON.stringify(release);type='application/json';}
 else if(p==='/sdk/auth.js')body=auth;
 else if(p==='/sdk/firestore-wrapper.js')body=firestore;
 else if(['/sdk/firebase-app.js','/sdk/firebase-firestore.js'].includes(p))body=fs.readFileSync(path.join(sdkRoot,path.basename(p)));
 else if(['/little_leaf_firebase.js','/little_leaf_firebase_session.js','/little_leaf_update.js','/little_leaf_firebase_boot.mjs'].includes(p))body=source(p.slice(1));
 else {assert.equal(path.basename(p),p.slice(1));body=fs.readFileSync(path.join(web,p.slice(1)));type=p.endsWith('.wasm')?'application/wasm':p.endsWith('.js')?'text/javascript':'application/octet-stream';}
 res.writeHead(200,{'Content-Type':type});res.end(body);
 }catch(e){res.writeHead(404);res.end('Not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
let browser;const contexts=[],errors=[];
async function until(fn,label,timeout=45000){const end=Date.now()+timeout;while(Date.now()<end){const value=await fn();if(value)return value;await new Promise(r=>setTimeout(r,150));}throw Error('Timed out: '+label);}
async function journal(page,uid,key=null){return page.evaluate(async({uid,key})=>{const db=await new Promise((yes,no)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>yes(q.result);q.onerror=()=>no(q.error);});try{return await new Promise((yes,no)=>{const tx=db.transaction('accounts'),q=tx.objectStore('accounts').get(key || uid);q.onsuccess=()=>yes(q.result||null);q.onerror=()=>no(q.error);});}finally{db.close();}},{uid,key});}
async function setup(uid,entry=null){
 const context=await browser.newContext({viewport:{width:1360,height:880}});contexts.push(context);
 await context.route('**/*',async route=>{const u=new URL(route.request().url());if(u.origin===origin || u.origin==='http://127.0.0.1:8080')return route.continue();
 if(isConnectivityProbe(u.href,route.request().resourceType())){report.blockedConnectivityProbes=(report.blockedConnectivityProbes||0)+1;checkpoint();return route.abort('internetdisconnected');}
 const prefix='https://www.gstatic.com/firebasejs/12.19.0/';if(u.href.startsWith(prefix)){const name=u.pathname.split('/').pop();const p=name==='firebase-auth.js'?'/sdk/auth.js':name==='firebase-firestore.js'?'/sdk/firestore-wrapper.js':'/sdk/firebase-app.js';return route.fulfill({status:200,contentType:'text/javascript',headers:{'Access-Control-Allow-Origin':'*','Cross-Origin-Resource-Policy':'cross-origin'},body:p==='/sdk/auth.js'?auth:p==='/sdk/firestore-wrapper.js'?firestore.replaceAll("'/sdk/","'"+origin+"/sdk/"):fs.readFileSync(path.join(sdkRoot,'firebase-app.js'))});}errors.push('Unexpected external request blocked: '+u.origin+u.pathname);return route.abort('blockedbyclient');});
 await context.addInitScript(({uid})=>{globalThis.__qaUid=uid;},{uid});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text());});
 await page.goto(origin+'/seed.html');
 if(entry)await page.evaluate(async({uid,entry})=>{const db=await new Promise((yes,no)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>yes(q.result);q.onerror=()=>no(q.error);});await new Promise((yes,no)=>{const tx=db.transaction('accounts','readwrite');tx.objectStore('accounts').put(entry,uid);tx.oncomplete=yes;tx.onabort=()=>no(tx.error);});db.close();},{uid,entry});
 await page.addInitScript(installEngineLaunchHook,{args:['--','--skip-intro'],reportKey:'__fullflowEngine'});
 return {context,page,uid};
}
async function launch(device){await device.page.goto(origin+'/index.html');await device.page.waitForFunction(()=>!document.getElementById('status')&&globalThis.__fullflowEngine?.launchCalls===1,null,{timeout:90000});await device.page.waitForFunction(()=>globalThis.LittleLeafSaveLog?.snapshot().some(e=>e.layer==='controller'&&['read_accepted','read_failure'].includes(e.event)),null,{timeout:30000});await device.page.evaluate(()=>{
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
 await foreground(p);
 const directory=process.env.CLOUD_GEOMETRY_PROJECT;assert(directory,'source-bound disposable native geometry project required');
 const id=++geometrySequence,input=path.join(out,'geometry-'+id+'-input.json'),output=path.join(out,'geometry-'+id+'-result.json');
 const observations=await p.evaluate(()=>globalThis.__qaAdapterResults||[]);
 const nativeCallback=observations.filter(x=>['preserveOwnerRuntime','preserveRuntime','requestTakeover','finishTakeover','forceTakeover'].includes(x.method)).at(-1)||null;
 fs.writeFileSync(input,JSON.stringify({viewport:p.viewportSize(),snapshot:await snapshot(p),recoveryMessage:nativeMessages.get(p)||'',nativeCallback}));
 await promisify(execFile)(process.env.GODOT_BIN||'godot',['--headless','--audio-driver','Dummy','--path',directory,'--script','res://tests/probe_cloud_recovery_geometry.gd','--',input,output],{timeout:30000,env:{...process.env,XDG_DATA_HOME:path.join(out,'native-data'),XDG_CONFIG_HOME:path.join(out,'native-config'),XDG_CACHE_HOME:path.join(out,'native-cache')}});
 const measured=JSON.parse(fs.readFileSync(output));assert(measured.buttons[button],mode+' '+button+' visible in exact snapshot geometry');
 const [x,y,w,h]=measured.buttons[button];await p.mouse.click(x+w/2,y+h/2,{delay:50});nativeMessages.set(p,'');
}
async function nativeSave(d,beforeOverride=null){await d.page.waitForFunction(()=>globalThis.__littleLeafLifecycleV1?.current);await d.page.waitForTimeout(350);const before=beforeOverride || await until(async()=>{const entry=await journal(d.page,d.uid),state=await snapshot(d.page);return entry?.record && !state.ownershipPaused && !state.busy && entry;},'resumed native account journal',30000);await d.page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));await until(async()=>{const e=await journal(d.page,d.uid);return e?.record.revision>before.record.revision && e;},'native lifecycle durable save');const saved=await journal(d.page,d.uid);await d.page.evaluate(()=>window.dispatchEvent(new Event('pageshow')));return saved;}
async function confirmedClick(p,mode,button,accept){let finish;const handled=new Promise(resolve=>finish=resolve);p.once('dialog',async dialog=>{assert.equal(dialog.type(),'confirm');await (accept?dialog.accept():dialog.dismiss());finish();});await click(p,mode,button);let timer;try{await Promise.race([handled,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Expected native confirmation dialog')),10000);})]);}finally{clearTimeout(timer);}if(!accept)nativeMessages.set(p,'Choose either save when you are ready.');await p.waitForTimeout(100);}
async function resumeProof(d,coins){const e=await nativeSave(d);check(JSON.parse(e.record.payload).coins===coins,'native model really resumed chosen coins '+coins);return e;}
async function updateClick(p,button,error=false){await foreground(p);const r=updateLayout.geometry.find(x=>x.viewport?.width===1360 && x.viewport?.height===880 && x.error===error);assert(r?.buttons?.[button],'update native geometry');const [x,y,w,h]=r.buttons[button];await p.mouse.click(x+w/2,y+h/2);}
try{
 browser=await chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL || 'chrome'});
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
 await until(async()=>{const x=await read(uid,'owner');return x.epoch===owner.epoch+1;},'graceful ownership transfer');
 const pending=await journal(a.page,uid),cloud=await read(uid);const ack=transitions.find(x=>x.ack && x.owner===owner.owner);stop();
 check(!!ack && ack.ack.digest===cloud.digest && ack.ack.revision===cloud.revision,'old owner acknowledged exact final cloud save before ownership transfer');
 check(pending.record.digest===cloud.digest && !pending.pending,'old native snapshot durably saved and cloud-confirmed');check((await snapshot(a.page)).ownershipPaused,'old compiled game paused after handoff');
 await resumeProof(b,42000);await shot(a.page,'old-device-paused');
 const stale={...cloud,revision:cloud.revision+100,writerId:owner.owner,writerEpoch:owner.epoch};await assertFails(setDoc(doc(db,'players',uid,'saves','cafe'),stale));check(true,'actual rules reject stale writer even bypassing client checks');await a.context.close();await b.context.close();}
 // Independent synthetic pending branch uses actual compiled two-card choice + browser confirm.
 for(const choice of ['local','cloud']){const uid='fullflow-choice-'+choice,base=await record(1,42000),local=await record(2,41000,base.profileId),cloud=await record(3,43000,base.profileId);await seed(uid,cloud);
 const original={record:local,base:base.digest,pending:true,device:'Mac'};const d=await launch(await setup(uid,original));await until(async()=>(await snapshot(d.page)).available,'native conflict cards');
 const s=await snapshot(d.page);check(s.choices.length===2 && s.choices[0].coins===41000 && s.choices[1].coins===43000 && s.choices[0].device==='Mac' && s.choices[1].device==='iPhone' && s.choices.every(c=>c.lastSavedLabel && c.lastSavedAt),'two cards expose exact coins/time/device metadata');await shot(d.page,'choice-'+choice);
 await confirmedClick(d.page,'cloud',choice,false);await until(async()=>!(await snapshot(d.page)).busy,'choice cancellation');check((await journal(d.page,uid)).record.digest===local.digest && (await read(uid)).digest===cloud.digest,'cancel leaves both branches unchanged');
 await confirmedClick(d.page,'cloud',choice,true);await until(async()=>!(await snapshot(d.page)).choicesAvailable,'native confirmed selection');
 const backup=await journal(d.page,uid,['choice-v1',uid]);assert.deepEqual(backup.local,original);assert.equal(backup.cloudDocument.record,JSON.stringify(cloud));check(true,'exact local journal and cloud bytes protected before selected model resumes');await resumeProof(d,choice==='local'?41000:43000);await d.context.close();}
 // Offline old native save survives an explicit timed-out takeover and reconnect conflict.
 {const uid='fullflow-offline',r=await record(1,42000);await seed(uid,r);const a=await launch(await setup(uid));const beforeOffline=await journal(a.page,uid);assert(beforeOffline?.record);await a.context.setOffline(true);const pending=await nativeSave(a,beforeOffline);check(pending.pending,'offline native save is durably pending');const b=await launch(await setup(uid));await click(b.page,'other-device','switch');
 await until(async()=>(await snapshot(b.page)).canForceTakeover,'explicit timeout available',30000);await shot(b.page,'takeover-timeout');
 await confirmedClick(b.page,'timeout','switch',false);check((await read(uid,'owner')).epoch===1,'cancel force does not transfer owner');
 await confirmedClick(b.page,'timeout','switch',true);await until(async()=>(await read(uid,'owner')).epoch===2,'force transfer');await resumeProof(b,42000);await b.page.evaluate(()=>__littleLeafVault.sync());
 await until(async()=>!(await journal(b.page,uid)).pending,'new owner cloud save');await a.context.setOffline(false);await a.page.evaluate(()=>window.dispatchEvent(new Event('focus')));await until(async()=>(await snapshot(a.page)).ownershipPaused,'old device notices fenced owner');
 const retained=await journal(a.page,uid);check(retained.pending && retained.record.revision>=pending.record.revision,'offline pending progress remains local after fencing');await shot(a.page,'offline-pending-preserved');await until(async()=>!(await snapshot(a.page)).busy,'old native snapshot finished');await click(a.page,'other-device','switch');await until(async()=>(await snapshot(a.page)).choicesAvailable,'reconnected incompatible offline branch requires choice');check((await journal(a.page,uid)).pending,'reconnected branch is not silently discarded');await shot(a.page,'offline-return-conflict');await a.context.close();await b.context.close();}
 // Actual notice buttons. Later never refreshes. Save timeout retains durable progress.
 {const uid='fullflow-update',r=await record(1,42000);await seed(uid,r);const d=await launch(await setup(uid));let navigations=0;d.page.on('framenavigated',frame=>{if(frame===d.page.mainFrame())navigations++;});
 release={schema_version:1,version:'9.0.0',source_commit:'a'.repeat(40)};await d.page.evaluate(()=>LittleLeafUpdate.poll());await d.page.waitForFunction(()=>JSON.parse(LittleLeafUpdate.snapshot()).available);await shot(d.page,'update-available');await updateClick(d.page,'later');check(!(await d.page.evaluate(()=>JSON.parse(LittleLeafUpdate.snapshot()).available)) && navigations===0,'Later dismisses update without reload');
 release={schema_version:1,version:'9.0.1',source_commit:'b'.repeat(40)};await d.page.evaluate(()=>LittleLeafUpdate.poll());await d.page.waitForTimeout(350);const before=await journal(d.page,uid);
 // Hold real emulator RPCs, not adapter callbacks. Ownership remains locally active;
 // the network-only deadline must return after the known durable native snapshot.
 let releaseRpc;const held=new Promise(resolve=>releaseRpc=resolve);await d.context.route('http://127.0.0.1:8080/**',async route=>{await held;await route.continue().catch(()=>{});});
 await updateClick(d.page,'update');await until(async()=>{const e=await journal(d.page,uid);return e.record.revision>before.record.revision&&e.pending;},'update native durable snapshot');
 await d.page.waitForTimeout(17000);check(navigations===0,'timed-out cloud confirmation never reloads');check((await journal(d.page,uid)).pending,'timed-out update retains pending exact durable snapshot');await shot(d.page,'update-timeout-preserved');releaseRpc();await d.context.unroute('http://127.0.0.1:8080/**');await d.context.close();}
 // A separate healthy account proves the native Save and update route reaches one reload.
 {release={schema_version:1,version:manifest.version,source_commit:manifest.source_commit};const uid='fullflow-update-success',r=await record(1,42000);await seed(uid,r);const d=await launch(await setup(uid));let navigations=0;d.page.on('framenavigated',frame=>{if(frame===d.page.mainFrame())navigations++;});
 release={schema_version:1,version:'9.0.2',source_commit:'c'.repeat(40)};await d.page.evaluate(()=>LittleLeafUpdate.poll());await updateClick(d.page,'update');await until(()=>navigations===1,'confirmed native update reload',45000);
 await d.page.waitForFunction(()=>globalThis.__littleLeafVault?.storageKind==='firebase-firestore' && !document.getElementById('status'),null,{timeout:90000});await d.page.waitForFunction(()=>LittleLeafSaveLog.snapshot().some(e=>e.layer==='controller'&&e.event==='read_accepted'),null,{timeout:30000});check((await snapshot(d.page)).status==='active','updated same tab resumes native play with a fresh fenced epoch');const saved=await journal(d.page,uid);check(!saved.pending && saved.record.digest===(await read(uid)).digest,'successful native update reload follows exact cloud confirmation');check(navigations===1,'successful update reloads once');await shot(d.page,'update-confirmed-reloaded');await d.context.close();}
 check(errors.length===0,'compiled runtime reports no script or page errors: '+errors.join('; '));report.passed=true;
}catch(error){
 report.failure=String(error.stack||error);report.failureStates=[];
 for(const context of contexts)for(const page of context.pages()){
  try{const uid=await page.evaluate(()=>globalThis.__qaUid);if(!/^fullflow-[a-z-]+$/.test(uid))continue;
   report.failureStates.push({uid,snapshot:await snapshot(page),journal:await journal(page,uid),owner:await read(uid,'owner'),cloud:await read(uid),nativeLog:await page.evaluate(()=>globalThis.LittleLeafSaveLog?.snapshot()),adapterResults:await page.evaluate(()=>globalThis.__qaAdapterResults),bootReceipt:await page.evaluate(()=>globalThis.__littleLeafVault?.bootJson),domState:await page.evaluate(()=>({visible:document.visibilityState,focused:document.hasFocus(),activeElement:document.activeElement?.tagName}))});await shot(page,'failure-'+report.failureStates.length);
  }catch(observationError){report.failureStates.push({observationError:String(observationError)});}
 }
 throw error;
}finally{
 report.errors=errors;fs.writeFileSync(path.join(out,'firebase-fullflow.json'),JSON.stringify(report,null,2));
 for(const context of contexts)await context.close().catch(()=>{});await browser?.close();await new Promise(resolve=>server.close(resolve));await env.cleanup();
}
