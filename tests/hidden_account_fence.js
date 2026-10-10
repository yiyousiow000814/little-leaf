'use strict';
// One existing synthetic session fixture, not the complete integration suite.
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,payload,api};',context);
const {environment,payload,api}=context.fixture;
(async()=>{
 const e=environment(),a=e.device('Mac');await a.ownership.start();
 const boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();
 const original=e.cloud(),cached=a.ownership.snapshot(),oldOwner=e.session().owner;assert.equal(cached.status,'active');
 // Watch delivery is absent: A still observes active while server fence advances.
 e.setSession({...e.session(),owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:2});
 assert.equal(a.ownership.snapshot().status,'active');
 const speculative=JSON.stringify({...JSON.parse(payload),coins:432,payroll_elapsed:12});
 const receipt=await a.client.commit(speculative,a.local().record.revision,boot.profileId);
 assert(receipt.durable);await a.client.sync();
 assert.equal(a.local().record.payload,speculative);assert(a.local().pending);
 assert.equal(e.cloud().digest,original.digest);assert.equal(e.cloud().record,original.record);
 // Exercise actual production compareAndSet too, including same-digest retry.
 let writes=0;const sdk={doc:(db,...p)=>p.join('/'),runTransaction:async(db,fn)=>fn({
  get:async ref=>({exists:()=>true,data:()=>ref==='owner'?e.session():original}),set:()=>writes++})};
 const remote=api.createRemote({},sdk,{sessionRef:'owner',assertActive:()=>({writerId:oldOwner,writerEpoch:1})});
 for(const next of [original,{...original,digest:'f'.repeat(64)}])
  await assert.rejects(remote.compareAndSet('synthetic-owner',original.digest,next,()=>{}),x=>x.code==='OWNERSHIP_LOST');
 assert.equal(writes,0);
 console.log(JSON.stringify({status:'passed',scenario:'unobserved takeover; preserved local speculative snapshot; old fence rejected even idempotent digest',authoritativeDigest:original.digest,localPending:a.local().pending,productionRemoteWrites:writes}));
})().catch(e=>{console.error(e);process.exitCode=1;});
