'use strict';
// Synthetic protocol integration; actual server rules have a separate emulator suite.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase','little_leaf_firebase_session'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
const api=root.LittleLeafFirebase,sessionApi=root.LittleLeafFirebaseSession,codec=root.LittleLeafAuthorityCodec,payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const clone=x=>x==null?null:JSON.parse(JSON.stringify(x)),fail=code=>Object.assign(Error(code),{code});
function environment({timeoutMs=15000}={}){
 let time=100000,session=null,cloud=null,uid='synthetic-owner',writeFail=false,writeGate=null,readGate=null,writeCalls=0;const watchers=[];
 const remote={ref:{path:'synthetic-session'},async read(){return clone(session);},async change(fn,guard){guard();const next=fn(clone(session),clone(cloud),()=>time);guard();session=clone(next);for(const w of watchers)w(clone(session));return clone(session);},watch(fn){watchers.push(fn);return()=>{const i=watchers.indexOf(fn);if(i>=0)watchers.splice(i,1);};}};
 function device(label,prepareReload=null){
   const ownership=sessionApi.createSession({remote,uid:'synthetic-owner',currentUid:()=>uid,deviceLabel:label,now:()=>time});
   let local=null,replaceHook=null,readHook=null;const journal={async read(){if(readHook)await readHook();return clone(local);},async replace(id,expected,next){assert.deepEqual(local,clone(expected));local=clone(next);if(replaceHook)await replaceHook(next);},async readRecoveryBackup(){return null;}};
   const saveRemote={async read(){if(readGate)await readGate;return clone(cloud);},async compareAndSet(id,base,next,guard){writeCalls++;if(writeGate)await writeGate;guard();const fence=ownership.assertActive(true);if(!session||session.owner!==fence.writerId||session.epoch!==fence.writerEpoch||session.ack)throw fail('OWNERSHIP_LOST');if(time-session.updatedAt>=60000)throw fail('permission-denied');if(writeFail)throw fail(writeFail===true?'OFFLINE':writeFail);if(cloud?.digest===next.digest)return;if((cloud?.digest||null)!==base)throw fail('REVISION_CONFLICT');cloud={...clone(next),...fence};guard();}};
   const client=api.createClient({uid:'synthetic-owner',codec,journal,remote:saveRemote,currentUid:()=>uid,status(){},ownership,now:()=>time,deviceLabel:label,networkTimeoutMs:timeoutMs,prepareReload});
   return {ownership,client,local:()=>clone(local),setLocal:x=>local=clone(x),onReplace:fn=>replaceHook=fn,onRead:fn=>readHook=fn};
 }
 return {device,remote,deliver:value=>{for(const watch of watchers)watch(clone(value));},setSession:x=>session=clone(x),setCloud:x=>cloud=clone(x),session:()=>clone(session),cloud:()=>clone(cloud),advance:ms=>time+=ms,failWrites:x=>writeFail=x,setUid:x=>uid=x,writeCalls:()=>writeCalls,holdWrites(){let resolve;writeGate=new Promise(r=>resolve=r);return ()=>{writeGate=null;resolve();};},holdReads(){let resolve;readGate=new Promise(r=>resolve=r);return ()=>{readGate=null;resolve();};}};
}

async function setup(ack=true){
 const e=environment(),a=e.device('A');await a.ownership.start();const boot=await a.client.boot();assert(boot.ok);
 assert((await a.client.commit(payload,0,boot.profileId)).ok);await a.client.sync();
 const b=e.device('B');await b.ownership.start();await b.client.boot();await b.client.requestTakeover();
 if(ack)assert((await a.client.preserveOwnerRuntime(payload,1,boot.profileId)).cloudConfirmed);
 return {e,a,b,cloud:e.cloud(),session:e.session()};
}
function cleanup(s){s.a.client.close();s.b.client.close();}
module.exports=(async()=>{
 let scenarios=0;
 // The first transport rejection is known settled. Fresh server proof allows
 // exactly one new transaction for the original acknowledged request.
 for(const code of ['OFFLINE','NETWORK_TIMEOUT','unavailable','deadline-exceeded']){
  const s=await setup(),change=s.e.remote.change;let attempts=0,reads=0;const read=s.e.remote.read;
  s.e.remote.read=async()=>{reads++;return read();};
  s.e.remote.change=async(...args)=>{if(++attempts===1)throw fail(code);return change(...args);};
  const result=await s.b.client.finishTakeover();assert(result.ok,code);assert.equal(result.revision,2);
  assert.equal(attempts,2);assert.equal(reads,1);assert.equal(s.e.session().epoch,2);assert.deepEqual(s.e.cloud(),s.cloud);
  assert.equal(s.b.client.ownershipSnapshot().status,'active');cleanup(s);scenarios++;
 }
 // Do not repeat an uncertain success, or acquire a newer owner's epoch.
 for(const mutation of ['none','new-owner','subsequent-request','later-own-epoch']){
  const s=await setup(),change=s.e.remote.change;let attempts=0;
  s.e.remote.change=async(...args)=>{attempts++;await change(...args);const value=s.e.session();
   if(mutation==='new-owner'){value.owner=webcrypto.randomUUID();value.epoch++;}
   if(mutation==='subsequent-request')value.request={id:webcrypto.randomUUID(),requester:webcrypto.randomUUID(),device:'C',at:100000};
   if(mutation==='later-own-epoch')value.epoch+=2;
   s.e.setSession(value);throw fail('OFFLINE');
  };
  const result=await s.b.client.finishTakeover();assert.equal(result.ok,mutation==='none',mutation);
  assert.equal(attempts,1);assert.deepEqual(s.e.cloud(),s.cloud);cleanup(s);scenarios++;
 }
 // Every original request/ACK identity is checked by the readback and again
 // by the retry transaction, including changes after the confirming read.
 for(const moment of ['readback','retry'])for(const mutation of ['owner','epoch','request','requester','at','device','ack-id','digest','revision','no-ack']){
  const s=await setup(),change=s.e.remote.change,read=s.e.remote.read;let attempts=0;
  const mutate=()=>{const v=s.e.session();
   if(mutation==='owner')v.owner=webcrypto.randomUUID();
   if(mutation==='epoch')v.epoch++;
   if(mutation==='request')v.request.id=webcrypto.randomUUID();
   if(mutation==='requester')v.request.requester=webcrypto.randomUUID();
   if(mutation==='at')v.request.at++;
   if(mutation==='device')v.request.device='C';
   if(mutation==='ack-id')v.ack.requestId=webcrypto.randomUUID();
   if(mutation==='digest')v.ack.digest='f'.repeat(64);
   if(mutation==='revision')v.ack.revision++;
   if(mutation==='no-ack')v.ack=null;
   s.e.setSession(v);
  };
  s.e.remote.change=async(...args)=>{attempts++;if(attempts===1){if(moment==='readback')mutate();throw fail('OFFLINE');}if(moment==='retry')mutate();return change(...args);};
  const result=await s.b.client.finishTakeover();assert.equal(result.ok,false,moment+' '+mutation);assert.equal(result.code,'HANDOFF_CHANGED');
  assert.equal(attempts,moment==='readback'?1:2);assert.deepEqual(s.e.cloud(),s.cloud);cleanup(s);scenarios++;
 }
 // Account, close and a newer explicit request cancel this invocation. A
 // failed or unknown server read never authorizes the second transaction.
 for(const mutation of ['account','close','new-request','read-failure']){
  const s=await setup(),read=s.e.remote.read;let attempts=0;
  s.e.remote.change=async()=>{attempts++;throw fail('OFFLINE');};
  s.e.remote.read=async()=>{
   if(mutation==='account')s.e.setUid('different-account');
   if(mutation==='close')s.b.ownership.close();
   if(mutation==='new-request')await s.b.ownership.requestTakeover().catch(()=>{});
   if(mutation==='read-failure')throw fail('OFFLINE');
   return read();
  };
  const result=await s.b.client.finishTakeover();assert.equal(result.ok,false,mutation);assert.equal(attempts,mutation==='new-request'?2:1);
  assert.deepEqual(s.e.session(),s.session);assert.deepEqual(s.e.cloud(),s.cloud);cleanup(s);scenarios++;
 }
 // Permission denial and semantic errors are never retried automatically.
 for(const code of ['permission-denied','firestore/permission-denied','HANDOFF_CHANGED','HANDOFF_WAITING','NOT_READY']){
  const s=await setup();let attempts=0,reads=0;
  s.e.remote.change=async()=>{attempts++;throw fail(code);};s.e.remote.read=async()=>{reads++;return s.e.session();};
  const result=await s.b.client.finishTakeover();assert.equal(result.ok,false);assert.equal(result.code,code);assert.equal(attempts,1);assert.equal(reads,0);
  assert.deepEqual(s.e.session(),s.session);assert.deepEqual(s.e.cloud(),s.cloud);cleanup(s);scenarios++;
 }
 // After the bounded attempt fails, existing native Try again is reachable.
 // No loop/timer or extra request is dispatched until that explicit action.
 const s=await setup(),change=s.e.remote.change;let attempts=0;
 s.e.remote.change=async()=>{attempts++;throw fail('OFFLINE');};
 assert.equal((await s.b.client.finishTakeover()).ok,false);assert.equal(attempts,2);
 for(let n=0;n<120;n++){const state=s.b.client.ownershipSnapshot();assert.equal(state.status,'resume-needed');assert.equal(state.canRequestTakeover,true);assert.equal(state.canForceTakeover,false);}
 assert.equal(attempts,2);assert.deepEqual(s.e.session(),s.session);assert.deepEqual(s.e.cloud(),s.cloud);
 s.e.remote.change=change;assert((await s.b.client.requestTakeover()).ok);
 assert.equal(s.b.client.ownershipSnapshot().status,'takeover-ready');assert((await s.b.client.finishTakeover()).ok);assert.equal(s.e.session().epoch,2);cleanup(s);scenarios++;
 // A timed-out but unacknowledged request still needs the existing explicit
 // force action. Even an explicitly forced transport failure is not retried.
 for(const force of [false,true]){
  const t=await setup(false);t.e.advance(10001);assert(t.b.client.ownershipSnapshot().canForceTakeover);
  const original=t.e.session();let attempts=0,reads=0;t.e.remote.change=async()=>{attempts++;throw fail('OFFLINE');};t.e.remote.read=async()=>{reads++;return t.e.session();};
  assert.equal((await t.b.client.finishTakeover(force)).ok,false);assert.equal(attempts,1);assert.equal(reads,0);assert.deepEqual(t.e.session(),original);assert(t.b.client.ownershipSnapshot().canForceTakeover);cleanup(t);scenarios++;
 }
 console.log('Firebase takeover retry: '+scenarios+' synthetic scenarios passed; original ACK identity, one proven retry, uncertain-success readback, explicit failure recovery and no-ACK safety retained.');
})();
