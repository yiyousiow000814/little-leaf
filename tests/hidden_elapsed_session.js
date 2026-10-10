'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
prefix=prefix.replace('root.globalThis=root;', `root.globalThis=root;const probeStore=new Map();root.localStorage={getItem:k=>probeStore.get(k)||null,setItem:(k,v)=>probeStore.set(k,v),removeItem:k=>probeStore.delete(k)};`);
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,sessionApi};',context);
const {environment,sessionApi}=context.fixture;
(async()=>{
 let e=environment(),a=e.device('Mac');await a.ownership.start();
 let t=await a.ownership.beginElapsed();e.advance(4600);await a.ownership.renew();
 let p=await a.ownership.finishElapsed(t.token);assert.equal(p.seconds,4.6);assert.equal(p.discardedSeconds,0);assert.equal(e.session().request,null);
 await assert.rejects(a.ownership.finishElapsed(t.token),x=>x.code==='ELAPSED_CONSUMED');
 // Freeze/resume has no client wall clock entitlement; only server time counts.
 t=await a.ownership.beginElapsed();e.advance(2200);p=await a.ownership.finishElapsed(t.token);assert.equal(p.seconds,2.2);
 t=await a.ownership.beginElapsed();e.advance(90000);p=await a.ownership.finishElapsed(t.token);assert.equal(p.seconds,60);assert.equal(p.discardedSeconds,30);
 // A valid same-owner cancellation leaves a newer server stamp: endpoint
 // owner/epoch alone would miss the temporary safety pause.
 t=await a.ownership.beginElapsed();const anchor=e.session();e.advance(1000);
 e.setSession({...anchor,updatedAt:anchor.updatedAt+1000});e.advance(1000);
 await assert.rejects(a.ownership.finishElapsed(t.token),x=>x.code==='ELAPSED_CHANGED');
 e=environment();a=e.device('Mac');await a.ownership.start();t=await a.ownership.beginElapsed();
 e.deliver(null);e.deliver(e.session());e.advance(2200);
 await assert.rejects(a.ownership.finishElapsed(t.token),x=>x.code==='ELAPSED_CHANGED','reconnection cannot restore an invalidated interval');
 e=environment();a=e.device('Mac');await a.ownership.start();t=await a.ownership.beginElapsed();const beforeAccount=e.session();e.setUid('other');e.advance(2200);
 await assert.rejects(a.ownership.finishElapsed(t.token),x=>x.code==='NOT_READY');assert.deepEqual(e.session(),beforeAccount);
 e=environment();a=e.device('Mac');await a.ownership.start();t=await a.ownership.beginElapsed();e.advance(1000);
 e.setSession({...e.session(),owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:e.session().epoch+1});
 await assert.rejects(a.ownership.finishElapsed(t.token),x=>x.code==='ELAPSED_CHANGED');
 // A cancellation/renewal occurring between write and readback cannot extend
 // the interval: the tagged marker and original stamp must both still match.
 const original={schema:1,owner:'a',epoch:1,device:'Mac',updatedAt:100000,request:null,ack:null},probe={id:'token',requester:'b'};
 const sealed={...original,request:{...probe,device:'Mac',at:104600}};
 assert.equal(sessionApi.elapsedProof(original,original,sealed,probe).seconds,4.6);
 assert.throws(()=>sessionApi.elapsedProof(original,original,{...sealed,updatedAt:105000,request:null},probe),x=>x.code==='ELAPSED_CHANGED');
 const nano=(seconds,nanoseconds)=>({seconds,nanoseconds,toMillis:()=>seconds*1000+nanoseconds/1e6});
 assert.throws(()=>sessionApi.elapsedProof({...original,updatedAt:nano(100,1)},{...original,updatedAt:nano(100,2)},sealed,probe),x=>x.code==='ELAPSED_CHANGED');
 console.log('Passed: server-bounded hidden/frozen elapsed, duplicate claim, expiry tail, unchanged-session guard, takeover, disconnect/reconnect, account switch, readback race, timestamp precision.');
})().catch(e=>{console.error(e);process.exitCode=1;});
