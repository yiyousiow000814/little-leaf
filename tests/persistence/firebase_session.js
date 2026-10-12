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
async function renewalCoalescingChecks(){
 function fixture(){
  let value=null,uid='renewal-fixture',runtimeHeld=true,time=100000,held=false,confirmationHeld=false,receive,writes=0;
  const calls=[],confirmations=[];
  const remote={
   async read(){return clone(value);},
   async change(action,guard){
    guard();
    if(held){let resolve,reject;const ready=new Promise((a,b)=>{resolve=a;reject=b;});calls.push({resolve,reject});await ready;}
    guard();const next=action(clone(value),null,()=>++time);guard();value=clone(next);writes++;if(receive)receive(clone(value));const result=clone(value);
    if(confirmationHeld){let resolve;const ready=new Promise(done=>{resolve=done;});confirmations.push({resolve});await ready;}
    return result;
   },watch(fn){receive=fn;return()=>{receive=null;};}
  };
  const session=sessionApi.createSession({remote,uid:'renewal-fixture',currentUid:()=>uid,now:()=>time,
   assertRuntime(){if(!runtimeHeld)throw fail('NOT_READY');}});
  return {session,calls,confirmations,start:()=>session.start(),hold(){held=true;},holdConfirmation(){confirmationHeld=true;},value:()=>clone(value),writes:()=>writes,
   replace(next){value=clone(next);if(receive)receive(clone(value));},uid(next){uid=next;},runtime(next){runtimeHeld=next;}};
 }
 const request=()=>({id:webcrypto.randomUUID(),requester:webcrypto.randomUUID(),device:'Phone',at:{seconds:100,nanoseconds:1}});
 for(const handoff of [false,true]){
  const f=fixture();await f.start();if(handoff)f.replace({...f.value(),request:request()});f.hold();
  const before=f.writes(),calls=[f.session.renew(),f.session.renew()];
  try{assert.equal(f.calls.length,1,'identical concurrent renewal callers must share one server change');}
  finally{for(const call of f.calls)call.resolve();await Promise.allSettled(calls);}
  const results=await Promise.all(calls);assert.equal(f.writes(),before+1);assert.equal(results[0].status,handoff?'handoff-requested':'active');
  const next=f.session.renew();assert.equal(f.calls.length,2,'settled renewal is never a completed-result cache');f.calls[1].resolve();await next;
 }
 // Each delayed caller retains its captured account/runtime/owner/request/ACK
 // fences. Neither same-owner intent changes nor closure can authorize a write.
 const mutations={
  account:f=>f.uid('other'),runtime:f=>f.runtime(false),close:f=>f.session.close(),
  owner:f=>f.replace({...f.value(),owner:webcrypto.randomUUID()}),epoch:f=>f.replace({...f.value(),epoch:2}),
  request:f=>f.replace({...f.value(),request:{...f.value().request,id:webcrypto.randomUUID()}}),
  requester:f=>f.replace({...f.value(),request:{...f.value().request,requester:webcrypto.randomUUID()}}),
  requestStamp:f=>f.replace({...f.value(),request:{...f.value().request,at:{seconds:100,nanoseconds:2}}}),
  ack:f=>f.replace({...f.value(),ack:{requestId:f.value().request.id,digest:'a'.repeat(64),revision:1}})
 };
 for(const [name,mutate] of Object.entries(mutations)){
  const f=fixture();await f.start();f.replace({...f.value(),request:request()});f.hold();const before=f.writes();
  const pending=Promise.allSettled([f.session.renew(),f.session.renew()]);assert.equal(f.calls.length,1,name);mutate(f);
  const after=f.value();f.calls[0].resolve();const results=await pending;
  const code=['account','runtime','close'].includes(name)?'NOT_READY':['owner','epoch'].includes(name)?'OWNERSHIP_LOST':'HANDOFF_CHANGED';
  assert(results.every(x=>x.status==='rejected'&&x.reason.code===code),name+' must refuse every stale caller');assert.equal(f.writes(),before,name+' wrote after its fence changed');assert.deepEqual(f.value(),after);
 }
 // A rejected old intent cannot clear a replacement slot or mark its newer
 // confirmed state offline. A third matching caller still joins that new work.
 const replacement=fixture();await replacement.start();replacement.hold();
 const old=Promise.allSettled([replacement.session.renew()]);replacement.replace({...replacement.value(),request:request()});
 const newer=replacement.session.renew();assert.equal(replacement.calls.length,2);
 const denial=fail('permission-denied');replacement.calls[0].reject(denial);assert.equal((await old)[0].reason,denial);
 assert.equal(replacement.session.snapshot().status,'handoff-requested');
 const joined=replacement.session.renew();assert.equal(replacement.calls.length,2,'late rejection cleared the replacement');
 replacement.calls[1].resolve();await Promise.all([newer,joined]);assert.equal(replacement.session.snapshot().status,'handoff-requested');
 const newerEpoch=fixture();await newerEpoch.start();newerEpoch.hold();const stale=Promise.allSettled([newerEpoch.session.renew()]);
 newerEpoch.replace({...newerEpoch.value(),epoch:2});const confirmedRenewal=newerEpoch.session.renew();newerEpoch.calls[1].resolve();await confirmedRenewal;
 newerEpoch.calls[0].reject(denial);assert.equal((await stale)[0].reason,denial);assert.equal(newerEpoch.session.snapshot().status,'active','late rejection made the confirmed replacement offline');
 // A late successful response is also stale: do not publish the old active
 // state over a newer same-epoch request/ACK confirmed by the listener.
 const delayed=fixture();await delayed.start();delayed.holdConfirmation();
 const older=Promise.allSettled([delayed.session.renew()]);assert.equal(delayed.confirmations.length,1);
 const intent=request(),confirmed={...delayed.value(),request:intent,ack:{requestId:intent.id,digest:'b'.repeat(64),revision:2}};
 delayed.replace(confirmed);const committed=delayed.writes();delayed.confirmations[0].resolve();
 const oldResult=(await older)[0];assert.equal(oldResult.status,'rejected');assert.equal(oldResult.reason.code,'HANDOFF_CHANGED');assert.deepEqual(delayed.value(),confirmed);assert.equal(delayed.writes(),committed);
 assert.equal(delayed.session.snapshot().ownershipPaused,true);assert.throws(()=>delayed.session.assertActive(true),e=>e.code==='OWNERSHIP_LOST');
 // Shared denial reaches every caller unchanged. A later same-owner server
 // renewal is fresh and can recover connectivity without clearing save latches.
 const denied=fixture();await denied.start();denied.hold();const error=fail('permission-denied');
 const failed=Promise.allSettled([denied.session.renew(),denied.session.renew()]);assert.equal(denied.calls.length,1);denied.calls[0].reject(error);
 const failures=await failed;assert(failures.every(x=>x.status==='rejected'&&x.reason===error));assert.equal(denied.session.snapshot().status,'offline');
 const recovery=denied.session.renew();assert.equal(denied.calls.length,2);denied.calls[1].resolve();await recovery;assert.equal(denied.session.snapshot().status,'active');
 console.log('Renewal coalescing: identical calls, fresh settlement, nine delayed fences, replacement rejection and shared permission/offline recovery passed.');
}
(async()=>{
 await renewalCoalescingChecks();
 // A successful write is followed by an independent transaction readback,
 // not a document read that can still reflect queued pre-transition state.
 let confirmedSession=null,transactionCalls=0,writes=0;
 const readbackSdk={doc:(db,...parts)=>parts.join('/'),serverTimestamp:()=>100000,getDocFromServer:async()=>({exists:()=>false}),onSnapshot:()=>()=>{},runTransaction:async(db,fn)=>{transactionCalls++;return fn({get:async ref=>({exists:()=>ref.endsWith('/owner')&&!!confirmedSession,data:()=>clone(confirmedSession)}),set:(ref,value)=>{writes++;confirmedSession=clone(value);}});}};
 const readback=sessionApi.createSession({uid:'readback',currentUid:()=> 'readback',now:()=>100000,remote:sessionApi.createRemote({},readbackSdk,'readback')});await readback.start();assert.equal(readback.snapshot().status,'active');assert.equal(transactionCalls,2);assert.equal(writes,1,'confirmation read must never retry or add a write');
 const delayedWatch=environment(),watchA=delayedWatch.device('Mac'),watchB=delayedWatch.device('iPhone');await watchA.ownership.start();const watchBoot=await watchA.client.boot();await watchA.client.commit(payload,0,watchBoot.profileId);await watchB.ownership.start();await watchB.client.boot();await watchB.client.requestTakeover();await watchA.client.preserveOwnerRuntime(payload,1,watchBoot.profileId);const olderWatch=delayedWatch.session();let injected=false;watchB.onRead(()=>{if(!injected){injected=true;delayedWatch.deliver(olderWatch);}});const watchResume=await watchB.client.finishTakeover();assert(watchResume.ok,JSON.stringify(watchResume));assert.equal(watchB.ownership.snapshot().status,'active','late prior-epoch observation cannot revoke confirmed newer ownership');
 const renewalRace=environment(),renewing=renewalRace.device('Mac');await renewing.ownership.start();renewalRace.setSession({...renewalRace.session(),owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:2});await assert.rejects(renewing.ownership.renew(),e=>e.code==='OWNERSHIP_LOST');assert.equal(renewing.ownership.snapshot().status,'other-device','confirmed competing owner is a fence, not an offline error');
 let e=environment(),a=e.device('Mac'),b=e.device('iPhone');await a.ownership.start();let boot=await a.client.boot();assert(boot.ok);await a.client.commit(payload,0,boot.profileId);await b.ownership.start();assert.equal(b.ownership.snapshot().status,'other-device');assert.equal((await b.client.boot()).code,'OWNERSHIP_LOST');let r=await b.client.requestTakeover();assert(r.ok);assert.equal(a.ownership.snapshot().status,'handoff-requested');assert.equal(b.ownership.snapshot().status,'waiting');assert.equal((await b.client.forceTakeover()).code,'HANDOFF_WAITING');assert.equal(e.cloud(),null);
 const oldOwner=e.session().owner,native=JSON.stringify({...JSON.parse(payload),coins:432});r=await a.client.preserveOwnerRuntime(native,1,boot.profileId);assert(r.ok&&r.durable&&r.cloudConfirmed);assert.equal(JSON.parse(e.cloud().record).payload,native);assert.equal(e.session().owner,oldOwner);assert.equal(e.session().ack.digest,e.cloud().digest);assert.equal(b.ownership.snapshot().status,'takeover-ready');boot=await b.client.finishTakeover();assert(boot.ok);assert.equal(boot.payload,native);assert.equal(e.session().epoch,2);assert.equal(a.ownership.snapshot().status,'other-device');assert.equal((await a.client.commit(payload,r.revision,r.profileId)).code,'OWNERSHIP_LOST');assert.equal(a.local().record.payload,native);
 assert.equal(e.session().request,null);await a.client.refreshOwnership();assert.equal(e.session().request,null,'no automatic ping-pong');
 const oldCache=a.local();await b.client.commit(payload,boot.revision,boot.profileId);await b.client.sync();await a.client.requestTakeover();await b.client.preserveOwnerRuntime(payload,b.local().record.revision,boot.profileId);const afterFlush=e.cloud();boot=await a.client.finishTakeover();assert(boot.ok);assert.equal(boot.payload,JSON.parse(afterFlush.record).payload);assert.equal(a.client.recoverySnapshot().choicesAvailable,false);assert.deepEqual(e.cloud(),afterFlush);assert(!oldCache.pending);assert(afterFlush.revision>oldCache.record.revision);
 e=environment();a=e.device('Mac');b=e.device('iPhone');await a.ownership.start();boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();await b.ownership.start();await b.client.requestTakeover();e.failWrites(true);const beforeCloud=e.cloud();r=await a.client.preserveOwnerRuntime(native,1,boot.profileId);assert(r.durable&&!r.cloudConfirmed);assert(a.local().pending);assert.deepEqual(e.cloud(),beforeCloud);assert.equal(e.session().ack,null);e.advance(10001);assert(b.ownership.snapshot().canForceTakeover);e.failWrites(false);boot=await b.client.forceTakeover();assert(boot.ok);assert.equal(boot.payload,payload);assert(a.local().pending);assert.equal(a.local().record.payload,native);assert.equal(e.session().epoch,2);
 r=await a.client.preserveOwnerRuntime(native,a.local().record.revision,a.local().record.profileId);assert(r.durable&&!r.cloudConfirmed);assert.deepEqual(e.cloud(),beforeCloud);
 const c=e.device('Linux device');await c.ownership.start();await a.client.requestTakeover();const request=e.session().request;assert.equal((await c.client.requestTakeover()).code,'HANDOFF_BUSY');assert.deepEqual(e.session().request,request);
 e.setUid('other');const saved=a.local();assert.equal((await a.client.preserveOwnerRuntime(payload,saved.record.revision,saved.record.profileId)).code,'NOT_READY');assert.deepEqual(a.local(),saved);
 // Current owner can explicitly cancel an abandoned handoff instead of staying stuck.
 e=environment();a=e.device('Mac');b=e.device('iPhone');await a.ownership.start();boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();await b.ownership.start();await b.client.requestTakeover();assert(a.ownership.snapshot().canRequestTakeover);r=await a.client.requestTakeover();assert(r.ok);assert.equal(e.session().request,null);assert.equal(a.ownership.snapshot().status,'active');assert.equal((await b.client.finishTakeover()).code,'HANDOFF_CHANGED');
 // Ownership changes after a durable local commit must not lose its revision receipt.
 e=environment();a=e.device('Mac');b=e.device('iPhone');await a.ownership.start();boot=await a.client.boot();await b.ownership.start();let requested=false;
 a.onReplace(async next=>{if(next.pending&&!requested){requested=true;await b.client.requestTakeover();}});
 r=await a.client.commit(native,0,boot.profileId);assert(r.ok&&r.durable&&r.revision===1);a.onReplace(null);r=await a.client.preserveOwnerRuntime(native,1,boot.profileId);assert(r.cloudConfirmed);assert((await b.client.finishTakeover()).ok);
 // A suspended page confirms its same-owner lease before upload, rather than
 // latching a preventable expiry refusal as a production rules denial.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);
 const expiredOwner=e.session();e.advance(61000);await a.client.refreshOwnership();await a.client.sync();
 assert(!a.local().pending);assert.equal(e.cloud().revision,1);assert.equal(e.session().owner,expiredOwner.owner);assert.equal(e.session().epoch,expiredOwner.epoch);assert(e.session().updatedAt>expiredOwner.updatedAt);assert.equal(a.client.ownershipSnapshot().status,'active');
 e.failWrites('permission-denied');await a.client.commit(native,1,boot.profileId);e.advance(30001);await a.client.sync();assert(a.local().pending);assert.equal(a.client.ownershipSnapshot().status,'resume-needed');const deniedCalls=e.writeCalls();e.failWrites(false);e.advance(61000);await a.client.renewOwnership();await a.client.sync();assert.equal(e.writeCalls(),deniedCalls,'real save permission denial is never silently cleared by renewal');assert(a.local().pending);
 // Genuine renewal denial receives the same protected export/pause as save
 // denial. Later renewal success never silently clears that permission latch.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);
 const normalRenew=e.remote.change;e.remote.change=async()=>{throw fail('permission-denied');};await a.client.sync();assert(a.local().pending);assert(a.client.recoverySnapshot().canExport);assert.equal(a.client.ownershipSnapshot().status,'resume-needed');assert.equal(e.writeCalls(),0);
 e.remote.change=normalRenew;await a.client.renewOwnership();e.advance(30001);await a.client.sync();assert.equal(e.writeCalls(),0);assert(a.local().pending);assert((await a.client.exportRecovery()).ok);
 // A separately confirmed competing owner is ownership loss, not a rule-cutover
 // latch. Keep the explicit takeover path and this device pending data available.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);
 const rival={...e.session(),owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:2};e.remote.change=async()=>{e.setSession(rival);throw fail('permission-denied');};await a.client.sync();assert.equal(a.client.ownershipSnapshot().status,'other-device');assert(a.client.ownershipSnapshot().canRequestTakeover);assert(a.local().pending);assert.equal(e.writeCalls(),0);
 // Update flow never mistakes a locally durable snapshot for cloud confirmation.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();
 r=await a.client.saveForUpdate(native,0,boot.profileId);assert(r.ok&&r.durable&&r.cloudConfirmed&&r.updateToken);
 assert.equal(JSON.parse(e.cloud().record).payload,native);
 let ready=await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken);assert(ready.ok&&ready.cloudConfirmed);
 assert.equal((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).code,'UPDATE_CHANGED','reload permission is single use');
 r=await a.client.saveForUpdate(native,r.revision,r.profileId);assert(r.cloudConfirmed);
 await a.client.commit(payload,r.revision,r.profileId);assert.equal((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).code,'UPDATE_CHANGED');
 r=await a.client.saveForUpdate(native,a.local().record.revision,boot.profileId);assert(r.cloudConfirmed);b=e.device('iPhone');await b.ownership.start();await b.client.requestTakeover();assert.equal((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).code,'OWNERSHIP_LOST','handoff cannot race a reload gate');
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();e.failWrites(true);r=await a.client.saveForUpdate(native,0,boot.profileId);assert(r.ok&&r.durable&&!r.cloudConfirmed&&!r.updateToken);assert.equal(a.local().record.payload,native);assert(a.local().pending);assert.equal(e.cloud(),null);assert.equal(a.client.ownershipSnapshot().status,'active');assert.equal(a.client.recoverySnapshot().needsRuntimeSnapshot,false,'ordinary offline update failure keeps safe background retry available');
 e.failWrites(false);r=await a.client.saveForUpdate(native,r.revision,r.profileId);assert(r.cloudConfirmed);assert((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).ok);
 r=await a.client.saveForUpdate(native,r.revision,r.profileId);e.setUid('other');assert.equal((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).code,'NOT_READY');
 // A never-settling write times out only after a known local durable receipt.
 e=environment({timeoutMs:5});a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();let releaseWrite=e.holdWrites();
 r=await a.client.saveForUpdate(native,0,boot.profileId);assert(r.durable&&!r.cloudConfirmed&&!r.updateToken);assert.equal(r.updateError.code,'NETWORK_TIMEOUT');assert.equal(r.revision,1);assert.equal(e.writeCalls(),1);assert(a.local().uploading);
 await a.client.commit(payload,1,boot.profileId);r=await a.client.saveForUpdate(payload,2,boot.profileId);assert(r.durable&&!r.cloudConfirmed);assert.equal(r.revision,3);assert.equal(e.writeCalls(),1,'retry shares the original uncertain upload task');
 releaseWrite();await new Promise(resolve=>setTimeout(resolve,10));assert.equal(e.cloud().revision,1);assert.equal(a.local().record.revision,3);assert.equal(a.local().record.payload,payload);assert(a.local().pending,'late ack preserves newer durable edits');assert(!a.client.canReloadUpdate(boot.profileId,3,'invented'));
 r=await a.client.saveForUpdate(payload,3,boot.profileId);assert(r.cloudConfirmed);assert.equal(e.writeCalls(),2);ready=await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken);assert(ready.ok);assert(a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken));await a.client.commit(native,r.revision,r.profileId);assert(!a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken),'synchronous final gate rejects newer local edits');
 // Cloud preview hangs do not swallow the durable native revision receipt.
 let releaseRead=e.holdReads();r=await a.client.preserveRuntime(payload,a.local().record.revision,boot.profileId);assert(r.durable);assert.equal(r.reconciliationError.code,'NETWORK_TIMEOUT');releaseRead();
 // A conflict's stalled cloud preview also returns its exact durable receipt.
 e=environment({timeoutMs:5});a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();e.failWrites('REVISION_CONFLICT');releaseRead=e.holdReads();
 let conflictWatchdog;try{r=await Promise.race([a.client.saveForUpdate(native,0,boot.profileId),new Promise((_,reject)=>{conflictWatchdog=setTimeout(()=>reject(Error('Conflict preview swallowed the durable receipt')),500);})]);}finally{clearTimeout(conflictWatchdog);}assert(r.ok&&r.durable&&!r.cloudConfirmed&&!r.updateToken);assert.equal(r.revision,1);assert.equal(r.updateError.code,'REVISION_CONFLICT');assert.equal(a.local().record.payload,native);assert(a.local().pending);assert.equal(e.cloud(),null);assert.equal(a.client.ownershipSnapshot().status,'resume-needed');
 const protectedConflict=a.local();releaseRead();await new Promise(resolve=>setTimeout(resolve,10));assert.deepEqual(a.local(),protectedConflict,'late conflict preview cannot change pending progress');assert.equal(e.cloud(),null);assert(!a.client.canReloadUpdate(boot.profileId,1,'invented'));
 // Readiness timeout cannot consume a ticket later and cannot authorize reload.
 e=environment({timeoutMs:5});a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();r=await a.client.saveForUpdate(native,0,boot.profileId);releaseRead=e.holdReads();ready=await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken);assert(!ready.ok);assert.equal(ready.code,'NETWORK_TIMEOUT');assert(!a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken));releaseRead();await new Promise(resolve=>setTimeout(resolve,10));assert(!a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken));assert((await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken)).ok);assert(a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken));e.setUid('other');assert(!a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken));
 // A continuation never reuses a writer identity: exact old epoch is consumed.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();r=await a.client.saveForUpdate(payload,0,boot.profileId);const oldFence=a.ownership.fence;
 const ticket=a.ownership.reloadContinuation(e.cloud().digest,e.cloud().revision);a.ownership.close();b=e.device('Mac');await b.ownership.start(ticket);
 assert.equal(e.session().epoch,oldFence.writerEpoch+1);assert.notEqual(b.ownership.fence.writerId,oldFence.writerId);assert.equal(e.cloud().revision,r.revision,'reload handoff does not rewrite the saved cafe');
 const duplicate=e.device('Mac');await duplicate.ownership.start(clone(ticket));assert.equal(duplicate.ownership.snapshot().status,'other-device');assert.equal(e.session().epoch,2,'copied receipt cannot consume epoch twice');
 for(const kind of ['expired','save-changed','owner-changed','request-pending','account']){
  e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();r=await a.client.saveForUpdate(payload,0,boot.profileId);const t=a.ownership.reloadContinuation(e.cloud().digest,e.cloud().revision);a.ownership.close();
  if(kind==='expired')e.advance(30001);
  if(kind==='save-changed')e.setCloud({...e.cloud(),revision:2,digest:'f'.repeat(64)});
  if(kind==='owner-changed')e.setSession({...e.session(),owner:webcrypto.randomUUID(),epoch:2});
  if(kind==='request-pending')e.setSession({...e.session(),request:{id:webcrypto.randomUUID(),requester:webcrypto.randomUUID(),device:'iPhone',at:100000}});
  if(kind==='account')t.uid='other';
  const before=e.session(),saved=e.cloud();b=e.device('Mac');await b.ownership.start(t);assert.equal(b.ownership.snapshot().status,'other-device',kind);assert.deepEqual(e.session(),before,kind+' preserves ownership');assert.deepEqual(e.cloud(),saved,kind+' preserves save');
 }
 // Server-stamped lease boundary rejects a locally young ticket after clock skew.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();await a.client.saveForUpdate(payload,0,boot.profileId);const skew=a.ownership.reloadContinuation(e.cloud().digest,e.cloud().revision);a.ownership.close();e.advance(61000);skew.createdAt+=61000;skew.expiresAt+=61000;
 b=e.device('Mac');await b.ownership.start(skew);assert.equal(e.session().epoch,2);assert.equal(e.session().request,null,'expired server lease uses normal fresh acquisition, not reload acknowledgment');assert.equal(e.cloud().revision,1);
 const map=new Map(),storage={getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v),removeItem:k=>map.delete(k)};
 assert(sessionApi.storeReload(storage,ticket));assert.equal(sessionApi.consumeReload(storage,'navigate',ticket.uid,ticket.createdAt),null);assert.equal(map.size,0);
 assert(sessionApi.storeReload(storage,ticket));assert.deepEqual(clone(sessionApi.consumeReload(storage,'reload',ticket.uid,ticket.createdAt)),clone(ticket));assert.equal(sessionApi.consumeReload(storage,'reload',ticket.uid,ticket.createdAt),null);
 assert(!sessionApi.storeReload({setItem(){throw Error('quota');}},ticket));
 e=environment();a=e.device('Mac',()=>false);await a.ownership.start();boot=await a.client.boot();r=await a.client.saveForUpdate(payload,0,boot.profileId);await a.client.checkUpdateReady(r.profileId,r.revision,r.updateToken);assert(!a.client.canReloadUpdate(r.profileId,r.revision,r.updateToken),'storage failure prevents reload');assert.equal(a.local().pending,false);
 // Lost acknowledgment after a continuation request leaves all save bytes intact.
 e=environment();a=e.device('Mac');await a.ownership.start();boot=await a.client.boot();await a.client.saveForUpdate(payload,0,boot.profileId);const lost=a.ownership.reloadContinuation(e.cloud().digest,e.cloud().revision),lostSaved=e.cloud();a.ownership.close();const realChange=e.remote.change;e.remote.change=async(...args)=>{await realChange(...args);throw fail('OFFLINE');};b=e.device('Mac');await assert.rejects(b.ownership.start(lost));assert.deepEqual(e.cloud(),lostSaved);assert.equal(e.session().epoch,1);assert.equal(e.session().ack,null);e.remote.change=realChange;const next=e.device('Mac');await next.ownership.start();assert.equal(next.ownership.snapshot().status,'other-device');await assert.rejects(next.ownership.requestTakeover(),e=>e.code==='HANDOFF_BUSY');e.advance(60001);await next.ownership.requestTakeover();assert.equal(next.ownership.snapshot().status,'active');assert.equal(e.session().epoch,2);assert.deepEqual(e.cloud(),lostSaved,'explicit expired-lease recovery never overwrites saved progress');
 await require('./firebase_request_retry.js');
 await require('./firebase_ack_retry.js');
 await require('./firebase_handoff_continuation.js');
 console.log('Synthetic session: freeze/snapshot/flush/ack before fenced takeover, timeout force, old-cache resume, offline pending retention, abandoned-request cancel, no ping-pong and account/request races passed.');
})().catch(e=>{console.error(e);process.exit(1);});
