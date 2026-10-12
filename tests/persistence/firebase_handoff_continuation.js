'use strict';
// Actual client/session protocol, synthetic server and durable journal only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const source=process.env.HANDOFF_SOURCE_ROOT||process.cwd(),root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase','little_leaf_firebase_session'])vm.runInNewContext(fs.readFileSync(path.join(source,'platform/web',name+'.js'),'utf8'),root);
const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8'),native=JSON.stringify({...JSON.parse(payload),coins:432}),clone=value=>value==null?null:JSON.parse(JSON.stringify(value));
let phase='setup';const deadline=setTimeout(()=>{console.error('Synthetic handoff did not settle: '+phase);process.exitCode=1;},5000);
const fail=code=>Object.assign(Error(code),{code});
function deferred(){let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};}
async function tick(){await new Promise(resolve=>setImmediate(resolve));}
function environment(){
 let session=null,cloud=null,uid='synthetic-owner',saveCalls=0,ackCalls=0,denySave=false,denyAck=false,uploadGate=null,ackHook=null;const watchers=[];
 const remote={ref:{path:'synthetic-session'},async read(){return clone(session);},async change(transition,guard){
   guard();const next=transition(clone(session),clone(cloud),()=>100000);guard();
   if(next.ack&&!session?.ack){ackCalls++;if(denyAck)throw fail('permission-denied');}
   session=clone(next);for(const watch of watchers)watch(clone(session));if(next.ack&&ackHook)ackHook();return clone(session);
 },watch(fn){watchers.push(fn);return()=>{watchers.splice(watchers.indexOf(fn),1);};}};
 function device(){
  const ownership=root.LittleLeafFirebaseSession.createSession({remote,uid:'synthetic-owner',currentUid:()=>uid,now:()=>100000});
  let local=null,replaceHook=null,readHook=null;
  const journal={async read(){return clone(local);},async replace(id,expected,next){assert.deepEqual(local,clone(expected));local=clone(next);if(replaceHook)await replaceHook(next);}};
  const saveRemote={async read(){const value=clone(cloud);if(readHook)await readHook();return value;},async compareAndSet(id,base,next,guard){
   guard();saveCalls++;if(denySave)throw fail('permission-denied');const fence=ownership.assertActive(true);
   assert.equal(session.owner,fence.writerId);assert.equal(session.epoch,fence.writerEpoch);assert.equal(session.ack,null);
   assert.equal(cloud?.digest||null,base);cloud={...clone(next),...fence};if(uploadGate)await uploadGate.promise;
  }};
  const client=root.LittleLeafFirebase.createClient({uid:'synthetic-owner',currentUid:()=>uid,codec:root.LittleLeafAuthorityCodec,journal,remote:saveRemote,ownership,status(){},now:()=>100000,networkTimeoutMs:10});
  return {client,ownership,local:()=>clone(local),setLocal:value=>{local=clone(value);},onReplace:hook=>{replaceHook=hook;},onRead:hook=>{readHook=hook;}};
 }
 return {device,cloud:()=>clone(cloud),session:()=>clone(session),saveCalls:()=>saveCalls,ackCalls:()=>ackCalls,
   setUid:value=>{uid=value;},setCloud:value=>{cloud=clone(value);},setSession(value){session=clone(value);for(const watch of watchers)watch(clone(session));},denySave:value=>{denySave=value;},denyAck:value=>{denyAck=value;},holdUpload:gate=>{uploadGate=gate;},onAck:hook=>{ackHook=hook;}};
}
async function setup(){
 const e=environment(),a=e.device(),b=e.device();await a.ownership.start();const boot=await a.client.boot();assert(boot.ok);
 assert((await a.client.commit(payload,0,boot.profileId)).ok);await a.client.sync();await b.ownership.start();await b.client.requestTakeover();
 return {e,a,b,boot};
}
async function journalTimeout(){
 const state=await setup(),gate=deferred();state.a.onReplace(async next=>{if(next.record.revision===2&&!next.pending)await gate.promise;});
 const result=await state.a.client.preserveOwnerRuntime(native,1,state.boot.profileId);
 assert(result.ok&&result.durable&&!result.cloudConfirmed);assert.equal(result.handoffError.code,'NETWORK_TIMEOUT');
 assert.equal(state.a.local().pending,false);assert.equal(state.e.cloud().revision,2);assert.equal(state.e.session().ack,null);
 return {...state,gate,result};
}
module.exports=(async()=>{
 // A late response wakes the existing frozen intent without a timer, focus,
 // second native snapshot or additional save CAS. The already exact cloud
 // read is sufficient; the real session ACK transaction rechecks its save.
 phase='late upload must wake its frozen continuation';
 let s=await setup(),lateUpload=deferred(),acknowledged=deferred();s.e.holdUpload(lateUpload);
 assert.equal((await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId)).handoffError.code,'NETWORK_TIMEOUT');
 let saved=s.e.cloud(),writes=s.e.saveCalls(),reads=0;s.e.onAck(()=>acknowledged.resolve());
 s.a.onRead(()=>{reads++;assert.equal(reads,1,'confirmed exact r2 needs no duplicate save read before the atomic ACK');});
 lateUpload.resolve();await acknowledged.promise;await tick();
 assert.deepEqual(s.e.cloud(),saved);assert.equal(s.e.saveCalls(),writes);assert.equal(s.e.ackCalls(),1);
 assert.equal(s.a.local().pending,false);assert.equal(s.a.local().record.revision,2);
 assert((await s.b.client.finishTakeover()).ok);assert.equal(s.e.session().epoch,2);
 assert.equal((await s.a.client.commit(payload,2,s.boot.profileId)).code,'OWNERSHIP_LOST');
 // A cloud replacement after the validated read must still fail the atomic
 // ACK. Reusing that read never substitutes for the real server save fence.
 phase='cloud changes before atomic ACK';s=await setup();lateUpload=deferred();s.e.holdUpload(lateUpload);
 assert.equal((await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId)).handoffError.code,'NETWORK_TIMEOUT');
 const replaced=deferred();s.a.onReplace(next=>{if(!next.pending&&next.record.revision===2){s.e.setCloud({...s.e.cloud(),writerEpoch:2});replaced.resolve();}});
 lateUpload.resolve();await replaced.promise;await s.a.client.refreshOwnership();await tick();
 assert.equal(s.e.session().ack,null);assert.equal(s.e.ackCalls(),0);assert.equal(s.a.local().record.revision,2);
 // Disposal invalidates the queued wake; a late response cannot reopen a
 // closed client or acknowledge its former request.
 phase='disposed client late completion';s=await setup();lateUpload=deferred();s.e.holdUpload(lateUpload);
 assert.equal((await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId)).handoffError.code,'NETWORK_TIMEOUT');
 saved=s.e.cloud();writes=s.e.saveCalls();s.a.client.close();lateUpload.resolve();await tick();
 assert.equal(s.e.session().ack,null);assert.equal(s.e.ackCalls(),0);assert.equal(s.e.saveCalls(),writes);assert.deepEqual(s.e.cloud(),saved);
 // Exact current failure projection: cloud/journal r2, durable callback true,
 // cloudConfirmed false, ACK null. No native snapshot is requested again.
 s=await journalTimeout();saved=s.e.cloud();writes=s.e.saveCalls();
 await Promise.all([s.a.client.renewOwnership(),s.a.client.refreshOwnership()]);
 assert.equal(s.e.saveCalls(),writes);assert.equal(s.e.ackCalls(),0,'still-live upload/journal cannot be duplicated');
 s.gate.resolve();await tick();await s.a.client.renewOwnership();
 assert.deepEqual(s.e.cloud(),saved,'continuation reuses exact r2 rather than resnapshotting');
 assert.equal(s.e.session().ack?.digest,saved.digest,'timed-out durable snapshot now completes its handshake');
 assert.equal(s.e.session().ack.revision,2);assert.equal(s.a.local().record.revision,2);
 const resumed=await s.b.client.finishTakeover();assert(resumed.ok);assert.equal(resumed.payload,native);assert.equal(resumed.revision,2);assert.equal(s.e.session().epoch,2);
 assert.equal((await s.a.client.commit(payload,2,s.boot.profileId)).code,'OWNERSHIP_LOST');
 // Server save committed, response lost: reconcile before any additional CAS.
 s=await setup();const upload=deferred();s.e.holdUpload(upload);
 const uncertain=await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId);assert.equal(uncertain.handoffError.code,'NETWORK_TIMEOUT');
 saved=s.e.cloud();writes=s.e.saveCalls();upload.resolve();await tick();await s.a.client.renewOwnership();
 assert.deepEqual(s.e.cloud(),saved);assert.equal(s.e.saveCalls(),writes);assert.equal(s.a.local().pending,false);assert.equal(s.e.session().ack.digest,saved.digest);
 // ACK already committed, response delayed through a real takeover. Drain the
 // original operation; confirm the exact terminal transfer without a new ACK.
 s=await setup();const ack=deferred(),acknowledge=s.a.ownership.acknowledge;
 s.a.ownership.acknowledge=async(...args)=>{const result=await acknowledge(...args);await ack.promise;return result;};
 const ackUncertain=await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId);assert.equal(ackUncertain.handoffError.code,'NETWORK_TIMEOUT');
 saved=s.e.cloud();assert((await s.b.client.finishTakeover()).ok);await s.a.client.refreshOwnership();assert.equal(s.e.ackCalls(),1);
 ack.resolve();await tick();await s.a.client.refreshOwnership();assert.deepEqual(s.e.cloud(),saved);assert.equal(s.e.ackCalls(),1);assert.equal(s.e.session().epoch,2);
 // Every frozen identity dimension fences continuation before an ACK/write.
 for(const mutation of ['request','requester','epoch','cloud','profile','digest','journal','account']){
  s=await journalTimeout();saved=s.e.cloud();writes=s.e.saveCalls();
  const owner=s.e.session();
  if(mutation==='request')owner.request.id=webcrypto.randomUUID();
  if(mutation==='requester')owner.request.requester=webcrypto.randomUUID();
  if(mutation==='epoch')owner.epoch++;
  if(['request','requester','epoch'].includes(mutation))s.e.setSession(owner);
  if(mutation==='cloud')s.e.setCloud({...saved,writerEpoch:owner.epoch+1});
  if(['profile','digest'].includes(mutation)){
   const record=JSON.parse(saved.record);if(mutation==='profile')record.profileId=webcrypto.randomUUID();else record.payload=JSON.stringify({...JSON.parse(payload),coins:999});
   record.digest=await root.LittleLeafAuthorityCodec.hash(root.LittleLeafAuthorityCodec.fingerprint(record));
   s.e.setCloud({...saved,profileId:record.profileId,digest:record.digest,record:JSON.stringify(record)});
  }
  if(mutation==='journal')s.a.setLocal({...s.a.local(),device:'another local tab'});
  if(mutation==='account')s.e.setUid('different-account');
  const retained=s.a.local();s.gate.resolve();await tick();await s.a.client.refreshOwnership();await s.a.client.renewOwnership();
  assert.deepEqual(s.a.local(),retained,mutation+' cannot replace the protected journal');assert.equal(s.e.saveCalls(),writes);assert.equal(s.e.session().ack,null,mutation+' cannot acknowledge a different intent');
 }
 // Explicit same-owner cancel/recovery invalidates a delayed continuation.
 // Its finally block cannot pause the freshly loaded client afterwards.
 phase='explicit recovery read';s=await journalTimeout();const read=deferred(),reading=deferred();let readOnce=true;
 s.a.onRead(async()=>{if(readOnce){readOnce=false;reading.resolve();await read.promise;}});
 s.gate.resolve();
 const retry=s.a.client.refreshOwnership();await reading.promise;
 phase='explicit recovery finish';const recovered=await s.a.client.requestTakeover();assert(recovered.ok,JSON.stringify(recovered));await retry;
 assert.equal(recovered.revision,2);assert.equal(s.e.session().request,null);
 read.resolve();await tick();assert((await s.a.client.commit(payload,2,s.boot.profileId)).ok,'stale continuation cannot re-pause the recovered runtime');
 // An unknown local transaction must settle before explicit recovery/new writes.
 phase='unknown journal receipt';s=await setup();const delayedUpload=deferred();s.e.holdUpload(delayedUpload);
 assert.equal((await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId)).handoffError.code,'NETWORK_TIMEOUT');
 const localReceipt=deferred(),replacing=deferred();
 s.a.onReplace(async next=>{if(next.record.revision===2&&!next.pending){replacing.resolve();await localReceipt.promise;}});
 delayedUpload.resolve();
 const localRetry=s.a.client.refreshOwnership();await replacing.promise;
 phase='unknown journal recovery';const blocked=await s.a.client.requestTakeover();assert.equal(blocked.code,'NETWORK_TIMEOUT');
 phase='unknown journal blocked write';const blockedWrite=s.a.client.commit(payload,2,s.boot.profileId);let writeReturned=false;blockedWrite.then(()=>{writeReturned=true;});
 await tick();assert.equal(writeReturned,false,'ordinary write waits for the unknown journal receipt');assert.equal(s.a.local().record.revision,2);
 phase='unknown journal retry drain';localReceipt.resolve();await localRetry;assert.equal((await blockedWrite).code,'NOT_READY');await tick();s.a.onReplace(null);
 phase='unknown journal fresh finish';assert((await s.a.client.finishTakeover()).ok);
 phase='unknown journal resumed write';assert((await s.a.client.commit(payload,2,s.boot.profileId)).ok);
 for(const denial of ['save','ack']){
  s=await setup();s.e[denial==='save'?'denySave':'denyAck'](true);
  const denied=await s.a.client.preserveOwnerRuntime(native,1,s.boot.profileId);assert.equal(denied.handoffError.code,'permission-denied');
  const local=s.a.local(),calls=[s.e.saveCalls(),s.e.ackCalls()];s.e.denySave(false);s.e.denyAck(false);
  await s.a.client.refreshOwnership();await s.a.client.renewOwnership();
  assert.deepEqual([s.e.saveCalls(),s.e.ackCalls()],calls,'permission denial is never a generic automatic retry');assert.deepEqual(s.a.local(),local);assert.equal(s.e.session().ack,null);
 }
 console.log('Frozen handoff: journal/save/ACK timeouts, exact r2 takeover, singleflight, identity fences, explicit recovery races and sticky permission denial passed.');
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>clearTimeout(deadline));
