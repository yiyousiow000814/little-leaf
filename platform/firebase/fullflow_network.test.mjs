import assert from 'node:assert/strict';
import vm from 'node:vm';
import {EventEmitter} from 'node:events';
import {readFileSync} from 'node:fs';
import {isConnectivityProbe,failureCategory,requestFamily,syntheticRPCOrigin,emulatorProxyTarget,emulatorPreflightHeaders,installPackagedWorklets,createRouteLifetime,packagedPckChunk,installPackagedPckStream,createContextConnectivity} from './fullflow_network.mjs';
// Exercise the actual driver facade without importing its browser/emulator setup.
const driver=readFileSync(new URL('./fullflow.test.mjs',import.meta.url),'utf8');
const frameFacadeSource=driver.slice(driver.indexOf('function gameFramePage('),driver.indexOf('\nasync function launch('));
assert(frameFacadeSource.startsWith('function gameFramePage('));
const frameFacade=vm.runInNewContext('('+frameFacadeSource+')');
{
  const page=new EventEmitter(),frame=new EventEmitter(),facade=frameFacade(page,frame);let delivered=0;
  const listener=dialog=>{assert.equal(dialog.type(),'confirm');delivered++;};
  facade.once('dialog',listener);
  assert.equal(page.listenerCount('dialog'),1,'frame facade once must register the Page dialog listener');
  assert.equal(frame.listenerCount('dialog'),0,'Frame must not retain Page dialog listeners');
  frame.emit('dialog',{type:()=>{throw Error('Frame event must not satisfy Page confirmation');}});
  const dialog={type:()=> 'confirm'};page.emit('dialog',dialog);page.emit('dialog',dialog);
  assert.equal(delivered,1,'Page once is consumed exactly once');
  facade.once('dialog',listener);facade.removeListener('dialog',listener);assert.equal(page.listenerCount('dialog'),0);
  facade.on('dialog',listener);facade.off('dialog',listener);assert.equal(page.listenerCount('dialog'),0);
  assert.equal(facade.mainFrame(),frame);
}
const confirmedClickSource=driver.slice(driver.indexOf('async function confirmedClick('),driver.indexOf('\nasync function resumeProof('));
assert(confirmedClickSource.startsWith('async function confirmedClick('));
for(const accept of [true,false]){
  const page=new EventEmitter(),frame=new EventEmitter(),facade=frameFacade(page,frame),calls=[],timers=[],cleared=[],messages=new WeakMap();
  frame.waitForTimeout=async ms=>assert.equal(ms,100);
  const dialog={type:()=>{calls.push('type');return 'confirm';},accept:async()=>{calls.push('accept');},dismiss:async()=>{calls.push('dismiss');}};
  const confirmedClick=vm.runInNewContext('('+confirmedClickSource+')',{assert,nativeMessages:messages,
    click:async(p,mode,button)=>{assert.equal(p,facade);assert.equal(mode,'choice');assert.equal(button,'local');page.emit('dialog',dialog);},
    setTimeout:(callback,ms)=>{const timer={callback,ms};timers.push(timer);return timer;},clearTimeout:timer=>cleared.push(timer)});
  await confirmedClick(facade,'choice','local',accept);
  assert.deepEqual(calls,['type',accept?'accept':'dismiss'],'original confirmation type and decision checks execute');
  assert.equal(timers[0].ms,10000,'original confirmation timeout remains unchanged');assert.equal(cleared[0],timers[0]);
  assert.equal(page.listenerCount('dialog'),0);
  assert.equal(messages.get(facade),accept?undefined:'Choose either save when you are ready.');
}
{
  const page=new EventEmitter(),frame=new EventEmitter(),facade=frameFacade(page,frame);let cleared=false;
  const confirmedClick=vm.runInNewContext('('+confirmedClickSource+')',{assert,nativeMessages:new WeakMap(),click:async()=>{},
    setTimeout:(callback,ms)=>{assert.equal(ms,10000);queueMicrotask(callback);return 1;},clearTimeout:()=>{cleared=true;}});
  await assert.rejects(confirmedClick(facade,'choice','local',true),/Expected native confirmation dialog/);
  assert(cleared,'missing dialogs still fail and clear the original timer');page.removeAllListeners();
}
console.log('Frame facade: Page once dispatch/removal is exact; actual confirmation accepts/dismisses, retains its10s timeout and fails when no dialog arrives.');
assert(isConnectivityProbe('https://www.google.com/images/cleardot.gif?zx=synthetic','image'));
assert(isConnectivityProbe('http://www.google.com/images/cleardot.gif','image'));
for(const [url,type] of [['https://www.google.com/images/cleardot.gif','script'],['https://www.google.com/accounts','image'],['https://www.google.com.evil.test/images/cleardot.gif','image'],['https://accounts.google.com/images/cleardot.gif','image']])assert(!isConnectivityProbe(url,type));
console.log('Offline network fixture: only exact SDK connectivity image is locally aborted; no external request allowed.');
for(const [message,category] of [['blocked by Local Network Access: PRIVATE_TOKEN','local-network'],['Mixed Content PRIVATE_TOKEN','mixed-content'],['CORS PRIVATE_TOKEN','cross-origin'],['Failed to fetch PRIVATE_TOKEN','network'],['permission-denied PRIVATE_TOKEN','permission-denied'],['IndexedDB PRIVATE_TOKEN','storage'],['SyntaxError PRIVATE_TOKEN','script'],['PRIVATE_TOKEN','other']])assert.equal(failureCategory(message),category);
assert.equal(requestFamily('http://127.0.0.1:43123/sdk/firebase-firestore.js?token=PRIVATE_TOKEN','http://127.0.0.1:43123'),'loopback-sdk');
assert.equal(requestFamily('http://127.0.0.1:8080/PRIVATE_TOKEN','http://127.0.0.1:43123'),'loopback-emulator');
assert.equal(requestFamily('https://evil.test/PRIVATE_TOKEN','http://127.0.0.1:43123'),'other');
assert.equal(requestFamily('not a URL PRIVATE_TOKEN','http://127.0.0.1:43123'),'other');
assert.equal(requestFamily(syntheticRPCOrigin+'/PRIVATE_TOKEN','http://127.0.0.1:43123'),'synthetic-emulator');
assert.equal(requestFamily('https://little-leaf-41e5d.firebaseapp.com/itch/sdk/firebase-firestore.js','http://127.0.0.1:43123'),'frame-sdk');
console.log('Failure observations expose only finite categories, including secret-bearing unknown inputs.');
const channel='/google.firestore.v1.Firestore/Listen/channel?database=projects%2Fdemo-little-leaf%2Fdatabases%2F(default)&RID=rpc';
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+channel,'GET'),'http://127.0.0.1:8080'+channel);
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+'/v1/projects/demo-little-leaf/databases/(default)/documents:commit','POST'),'http://127.0.0.1:8080/v1/projects/demo-little-leaf/databases/(default)/documents:commit');
for(const [url,method] of [[syntheticRPCOrigin+channel,'DELETE'],['https://firestore.googleapis.com'+channel,'GET'],[syntheticRPCOrigin+'/v1/projects/little-leaf-41e5d/databases/(default)/documents:commit','POST'],[syntheticRPCOrigin+'/google.firestore.v1.Firestore/Listen/channel?database=projects%2Flittle-leaf-41e5d%2Fdatabases%2F(default)','GET'],[syntheticRPCOrigin+'/unknown','GET'],['https://user:PRIVATE_TOKEN@firestore.fullflow.test'+channel,'GET'],[syntheticRPCOrigin+channel+'#PRIVATE_TOKEN','GET']])assert.throws(()=>emulatorProxyTarget(url,method));
assert.throws(()=>emulatorProxyTarget(syntheticRPCOrigin+channel+'&database=projects%2Fproduction%2Fdatabases%2F(default)','GET'));
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+channel.replace('/Listen/','/Write/'),'POST'),'http://127.0.0.1:8080'+channel.replace('/Listen/','/Write/'));
console.log('HTTPS emulator proxy permits only fixed loopback, demo project and known SDK RPCs.');
const preflight={origin:'https://little-leaf-41e5d.firebaseapp.com','access-control-request-method':'POST','access-control-request-headers':'Authorization, content-type, x-goog-api-client, x-firebase-gmpid, google-cloud-resource-prefix, x-goog-request-params'};
assert.deepEqual(emulatorPreflightHeaders(syntheticRPCOrigin+channel,preflight),{'access-control-allow-origin':preflight.origin,'access-control-allow-credentials':'true','access-control-allow-methods':'GET, POST','access-control-allow-headers':'authorization, content-type, x-goog-api-client, x-firebase-gmpid, google-cloud-resource-prefix, x-goog-request-params'});
for(const extra of [{origin:'https://evil.test'},{'access-control-request-method':'DELETE'},{'access-control-request-headers':'PRIVATE_TOKEN'},{'access-control-request-private-network':'true'}])assert.throws(()=>emulatorPreflightHeaders(syntheticRPCOrigin+channel,{...preflight,...extra}));
assert.throws(()=>emulatorPreflightHeaders(syntheticRPCOrigin+'/PRIVATE_TOKEN',preflight));
console.log('Preflight stays local and refuses unknown methods, origins, headers and private-network grants.');

function deferred(){let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};}
function routeHarness({onClose=()=>{},gate=null,closeError=null,emitClose=true}={}){
  const context=new EventEmitter(),errors=[];let closeCalls=0;
  context.close=async()=>{closeCalls++;onClose();if(gate)await gate.promise;if(closeError)throw closeError;if(emitClose)context.emit('close');};
  return {context,errors,routes:createRouteLifetime(context,errors),closeCalls:()=>closeCalls};
}
const closedError=operation=>Error(operation+': Target page, context or browser has been closed');
// Reproduce the original callback boundary: a pending onLine evaluation rejects
// when its owner closes, even though the test's own close operation succeeds.
{
  const evaluation=deferred(),h=routeHarness({onClose:()=>evaluation.reject(closedError('frame.evaluate'))});
  const frame={evaluate:()=>evaluation.promise};
  const unowned=(async()=>{if(!await frame.evaluate(()=>true))throw Error('offline');})();
  const rejection=assert.rejects(unowned,/frame.evaluate: Target page/);
  await h.context.close();await rejection;
}
for(const operation of ['frame.evaluate','route.fetch','route.fulfill']){
  const request=deferred(),h=routeHarness({onClose:()=>request.reject(closedError(operation))});
  const callback=h.routes.handle(async()=>{await request.promise;});
  const pending=callback({});await h.routes.close();await pending;
  assert.deepEqual(h.errors,[],'only confirmed owned '+operation+' cancellation is expected');
  assert.equal(h.routes.close(),h.routes.close(),'close is idempotent');assert.equal(h.closeCalls(),1);
}
{
  const request=deferred(),finished=deferred(),h=routeHarness({onClose:()=>request.reject(closedError('frame.evaluate'))});
  const pending=h.routes.handle(async()=>{try{await request.promise;}finally{await finished.promise;}})({});
  let drained=false;const closing=h.routes.close().then(()=>{drained=true;});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(drained,false,'close waits for callback finally');
  finished.resolve();await closing;await pending;assert.equal(drained,true);assert.deepEqual(h.errors,[]);
}
{
  const failure=closedError('frame.evaluate'),h=routeHarness();await h.routes.handle(async()=>{throw failure;})({});
  assert.deepEqual(h.errors,['Fixture route callback failed: target-closed'],'live frame closure is fatal');await assert.rejects(h.routes.close(),error=>error===failure);
}
{
  const request=deferred(),h=routeHarness();const pending=h.routes.handle(()=>request.promise)({});
  const failure=closedError('frame.evaluate');h.context.emit('close');request.reject(failure);await pending;
  assert.deepEqual(h.errors,['Fixture route callback failed: target-closed'],'unrequested browser closure is fatal');await assert.rejects(h.routes.close(),error=>error===failure);
}
for(const error of [Error('Unexpected fixture failure'),Error('frame.evaluate: Frame was detached')]){
  const request=deferred(),h=routeHarness({onClose:()=>request.reject(error)});
  const pending=h.routes.handle(()=>request.promise)({});await assert.rejects(h.routes.close(),failure=>failure===error);await pending;
  assert.deepEqual(h.errors,['Fixture route callback failed: other'],'owned close does not excuse unrelated errors');
}
{
  const request=deferred(),h=routeHarness({onClose:()=>request.reject(closedError('frame.evaluate')),emitClose:false});
  const pending=h.routes.handle(()=>request.promise)({});
  await assert.rejects(h.routes.close(),/Fixture context close not confirmed/);await pending;
  assert(h.errors.includes('Fixture route callback failed: target-closed'));assert(h.errors.includes('Fixture context cleanup failed'));
}
{
  const failure=Error('Context close failed'),h=routeHarness({closeError:failure});
  await assert.rejects(h.routes.close(),error=>error===failure);assert.deepEqual(h.errors,['Fixture context cleanup failed']);
}
{
  const gate=deferred(),h=routeHarness({gate});let forwarded=0,aborted=0;
  const callback=h.routes.handle(async()=>{forwarded++;});const closing=h.routes.close();
  await callback({abort:async reason=>{assert.equal(reason,'blockedbyclient');aborted++;}});
  assert.equal(forwarded,0);assert.equal(aborted,1,'retiring live context blocks forwarding');
  gate.resolve();await closing;await callback({abort:()=>{throw Error('Already closed route must not be used');}});
  assert.equal(forwarded,0);assert.deepEqual(h.errors,[],'closed context never runs a late callback');
}
{
  const held=deferred(),h=routeHarness();h.context.once('close',held.resolve);
  const pending=h.routes.handle(async route=>{await held.promise;await route.fallback();})({fallback:async()=>{throw closedError('route.fallback');}});
  await h.routes.close();await pending;assert.deepEqual(h.errors,[],'owned update gate releases on close before callback drain');
}
console.log('Route lifetime: original teardown rejection reproduced; owned cancellation drains; live/unrequested/unrelated failures and unconfirmed cleanup remain fatal; retiring contexts never forward.');

const workletOrigin='https://little-leaf-41e5d.firebaseapp.com';
const moduleBytes={'index.audio.worklet.js':Buffer.from([0,10,13,127,128,255]),
  'index.audio.position.worklet.js':Buffer.from('registerProcessor("test", class {});\n')};
const modules=Object.fromEntries(Object.entries(moduleBytes).map(([name,bytes])=>[name,bytes.toString('base64')]));
function workletHarness(location={origin:workletOrigin,pathname:'/itch/',href:workletOrigin+'/itch/'}){
  const active=new Map(),calls=[],revoked=[];
  class FixtureURL extends URL{
    static createObjectURL(blob){const url='blob:'+location.origin+'/'+active.size;active.set(url,blob);return url;}
    static revokeObjectURL(url){assert(active.delete(url));revoked.push(url);}
  }
  class AudioWorklet{
    async addModule(url,...options){calls.push({bytes:Buffer.from(await active.get(url).arrayBuffer()),options});if(this.reject)throw Error('Original module rejected');return 'executed';}
  }
  const original=AudioWorklet.prototype.addModule;
  const install=vm.runInNewContext('('+installPackagedWorklets.toString()+')',{location,URL:FixtureURL,Blob,Uint8Array,atob,AudioWorklet});
  return {install,AudioWorklet,original,active,calls,revoked};
}
const h=workletHarness();h.install({origin:workletOrigin,pathname:'/itch/',modules});
for(const name of Object.keys(modules)){
  assert.equal(await new h.AudioWorklet().addModule(name,{credentials:'same-origin'}),'executed');
  assert.deepEqual(h.calls.at(-1).bytes,moduleBytes[name]);
  assert.equal(h.calls.at(-1).options[0].credentials,'same-origin');
  assert.equal(h.active.size,0);
}
const rejected=new h.AudioWorklet();rejected.reject=true;
await assert.rejects(rejected.addModule(workletOrigin+'/itch/index.audio.worklet.js'),/Original module rejected/);
assert.equal(h.active.size,0);assert.equal(h.revoked.length,3);
for(const url of [workletOrigin+'/itch/index.audio.worklet.js?changed=1',workletOrigin+'/itch/unknown.js','https://evil.test/itch/index.audio.worklet.js']){
  await assert.rejects(new h.AudioWorklet().addModule(url),/Unknown compiled worklet URL/);
}
assert.equal(h.calls.length,3,'unknown URLs never execute or fetch');
for(const location of [{origin:workletOrigin,pathname:'/',href:workletOrigin+'/'},{origin:'https://html-classic.itch.zone',pathname:'/itch/',href:'https://html-classic.itch.zone/itch/'}]){
  const other=workletHarness(location);other.install({origin:workletOrigin,pathname:'/itch/',modules});
  assert.equal(other.AudioWorklet.prototype.addModule,other.original,'only exact nested game frame changes');
}
assert.throws(()=>workletHarness().install({origin:workletOrigin,pathname:'/itch/',modules:{...modules,unknown:'AA=='}}),/Exact packaged worklets required/);
console.log('Packaged worklet fixture: exact binary bytes/options execute, failures propagate, Blob URLs revoke, unknown URLs refuse, other frames unchanged.');

// This fixture test verifies bounded transfer, not compiled-game acceptance.
const pckBytes=Buffer.from(Array.from({length:600001},(_,i)=>i%251));
for(const offset of [-1,.5,pckBytes.length,NaN,Infinity])assert.throws(()=>packagedPckChunk(pckBytes,offset),/offset/);
assert.throws(()=>packagedPckChunk(new Uint8Array(1),0),/offset/);
function pckHarness(location={origin:workletOrigin,pathname:'/itch/',href:workletOrigin+'/itch/'},reader=offset=>packagedPckChunk(pckBytes,offset)){
 const calls=[],forwarded=[];
 const original=async(...args)=>{forwarded.push(args);return 'original-fetch';};
 const context={location,URL,Headers,Response,ReadableStream,Uint8Array,atob,DOMException,fetch:original,
  __littleLeafPackagedPckChunk:async offset=>{calls.push(offset);return reader(offset);}};
 const install=vm.runInNewContext('('+installPackagedPckStream.toString()+')',context);
 return {context,calls,forwarded,original,install};
}
const ph=pckHarness();ph.install({origin:workletOrigin,pathname:'/itch/',bytes:pckBytes.length});
const response=await ph.context.fetch('index.pck');
assert.equal(response.url,workletOrigin+'/itch/index.pck');assert.equal(response.headers.get('content-length'),String(pckBytes.length));
assert.deepEqual(Buffer.from(await response.arrayBuffer()),pckBytes,'exact complete binary bytes reach the real Response');
assert.deepEqual(ph.calls,[0,262144,524288],'no large CDP payload');
assert.equal(await ph.context.fetch('index.wasm'),'original-fetch');
assert.equal(await ph.context.fetch('https://evil.test/index.pck'),'original-fetch');assert.equal(ph.forwarded.length,2);
await assert.rejects(ph.context.fetch('index.pck',{method:'POST'}),/complete packaged/);
await assert.rejects(ph.context.fetch('index.pck',{headers:{Range:'bytes=1-2'}}),/complete packaged/);
const abort=new AbortController();abort.abort();await assert.rejects(ph.context.fetch('index.pck',{signal:abort.signal}),/abort/i);
const truncated=pckHarness(undefined,()=> 'AA==');truncated.install({origin:workletOrigin,pathname:'/itch/',bytes:pckBytes.length});
await assert.rejects((await truncated.context.fetch('index.pck')).arrayBuffer(),/chunk differs/);
const failed=pckHarness(undefined,()=>{throw Error('reader failed');});failed.install({origin:workletOrigin,pathname:'/itch/',bytes:pckBytes.length});
await assert.rejects((await failed.context.fetch('index.pck')).arrayBuffer(),/reader failed/);
let release;const cancelled=pckHarness(undefined,()=>new Promise(resolve=>release=resolve));
cancelled.install({origin:workletOrigin,pathname:'/itch/',bytes:pckBytes.length});
const cancelResponse=await cancelled.context.fetch('index.pck');await cancelResponse.body.cancel();release(packagedPckChunk(pckBytes,0));
await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(cancelled.calls,[0],'cancelled consumer never asks for more bytes');
for(const location of [{origin:workletOrigin,pathname:'/',href:workletOrigin+'/'},{origin:'https://html-classic.itch.zone',pathname:'/itch/',href:'https://html-classic.itch.zone/itch/'}]){
 const other=pckHarness(location);other.install({origin:workletOrigin,pathname:'/itch/',bytes:pckBytes.length});assert.equal(other.context.fetch,other.original);
}
for(const bytes of [0,-1,192*1024*1024+1,NaN])assert.throws(()=>pckHarness().install({origin:workletOrigin,pathname:'/itch/',bytes}),/Finite packaged/);
console.log('Packaged PCK fixture: exact binary Response,256KiB messages, offset/size bounds, abort/cancel/failure propagation and exact-frame scope passed.');

// Exact synthetic proxy state is confirmed at the fixture-owned transitions.
{
 const applied=[],toggle=deferred();let browserOnline=true,evaluations=0;
 const frame={evaluate:async()=>{evaluations++;return browserOnline;}};
 const context=Object.assign(new EventEmitter(),{setOffline:async value=>{applied.push(value);await toggle.promise;browserOnline=!value;}});
 const control=createContextConnectivity(context);
 assert.equal(await control.isOnline(await control.capture()),false,'unconfirmed setup cannot forward proxy RPCs');
 assert.throws(()=>control.setOffline(frame,true),/Invalid fixture/);
 await control.initialize(frame);assert.equal(evaluations,1);
 for(let i=0;i<1000;i++)assert.equal(await control.isOnline(await control.capture()),true);
 assert.equal(evaluations,1,'RPC checks add no browser evaluations');
 const offline=control.setOffline(frame,true);let settled=false;
 const pendingCheck=control.capture().then(value=>{settled=true;return value;});
 await Promise.resolve();assert.equal(settled,false,'requests wait for actual transition confirmation');
 assert.throws(()=>control.setOffline(frame,false),/Invalid fixture/);
 toggle.resolve();await offline;assert.equal(await pendingCheck,null);assert.equal(evaluations,2);
 await control.setOffline(frame,false);assert.equal(await control.isOnline(await control.capture()),true);assert.equal(evaluations,3);
 assert.deepEqual(applied,[true,false],'each original browser transition executes exactly once');
 assert.throws(()=>control.setOffline(frame,1),/Invalid fixture/);
}
for(const failure of ['setOffline','confirmation','mismatch']){
 let browserOnline=true,fail=false;const sentinel=Error('exact synthetic failure');
 const frame={evaluate:async()=>{if(fail&&failure==='confirmation')throw sentinel;return fail&&failure==='mismatch'?true:browserOnline;}};
 const context=Object.assign(new EventEmitter(),{setOffline:async value=>{if(fail&&failure==='setOffline')throw sentinel;browserOnline=!value;}});
 const control=createContextConnectivity(context);await control.initialize(frame);fail=true;
 await assert.rejects(control.setOffline(frame,true),error=>failure==='mismatch'?/confirmation differs/.test(error.message):error===sentinel);
 assert.equal(await control.isOnline(await control.capture()),false,'failed or unknown transitions remain closed');
}
{
 const control=createContextConnectivity(Object.assign(new EventEmitter(),{setOffline:async()=>{throw Error('must not run');}}));
 await assert.rejects(control.initialize({evaluate:async()=>false}),/did not start online/);
 assert.equal(await control.isOnline(await control.capture()),false);
 assert.equal(driver.includes('.context.setOffline('),false,'every fullflow toggle uses confirmed fixture custody');
 assert.equal((driver.match(/connectivity\.capture\(\)/g)||[]).length,1,'pre-forward confirmation remains');
 assert.equal((driver.match(/connectivity\.isOnline\(connectivityEpoch\)/g)||[]).length,1,'post-response confirmation retains exact pre-forward epoch');
}
console.log('Confirmed context connectivity: exact actual browser toggles, fail-closed unknown/error/mismatch, transition races, pre/post proxy checks and no per-RPC renderer queries. This is fixture verification, not release qualification.');

{
 let actualOnline=true;const frame={evaluate:async()=>actualOnline};
 const control=createContextConnectivity(Object.assign(new EventEmitter(),{setOffline:async value=>{actualOnline=!value;}}));
 await control.initialize(frame);const captured=await control.capture();assert.equal(await control.isOnline(captured),true);
 await control.setOffline(frame,true);assert.equal(await control.isOnline(captured),false);
 await control.setOffline(frame,false);assert.equal(await control.isOnline(captured),false,'late response crossing offline/online cannot be delivered');
 assert.equal(await control.isOnline(await control.capture()),true,'new requests use the freshly confirmed online epoch');
}
console.log('In-flight proxy responses cannot cross a confirmed offline/online epoch; already forwarded server writes remain uncertain.');

{
 let first=true;const confirmation=deferred(),context=Object.assign(new EventEmitter(),{setOffline:async()=>{}});
 const frame={evaluate:async()=>{if(first){first=false;return true;}return confirmation.promise;}};
 const control=createContextConnectivity(context);await control.initialize(frame);const captured=await control.capture();
 const transition=control.setOffline(frame,false);await Promise.resolve();context.emit('close');
 assert.equal(await control.capture(),null);assert.equal(await control.isOnline(captured),false);
 confirmation.resolve(true);await assert.rejects(transition,/context closed/);
 assert.equal(await control.capture(),null,'late actual-frame confirmation cannot reopen a closed context');
 assert.throws(()=>control.setOffline(frame,false),/Invalid fixture/);
}
console.log('Context closure invalidates proxy epochs and late confirmations cannot reopen forwarding.');
