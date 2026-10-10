'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
prefix=prefix.replace('root.globalThis=root;', `root.globalThis=root;const probeStore=new Map();root.localStorage={getItem:k=>probeStore.get(k)||null,setItem:(k,v)=>probeStore.set(k,v),removeItem:k=>probeStore.delete(k)};`);
prefix=prefix.replace('return {ownership,client,local:', 'return {journal,saveRemote,ownership,client,local:');
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,payload,codec,api,probeStore};',context);
const {environment,payload,codec,api,probeStore}=context.fixture;
function restart(e,a,owner){return api.createClient({uid:'synthetic-owner',codec,journal:a.journal,remote:a.saveRemote,currentUid:()=> 'synthetic-owner',status(){},ownership:owner.ownership});}
async function ready(){probeStore.clear();const e=environment(),a=e.device('Mac');await a.ownership.start();const boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();const t=await a.client.beginBackground(1,boot.profileId);e.advance(2200);assert((await a.client.finishBackground(t.token)).ok);return {e,a,boot,t};}
(async()=>{
 let {e,a,boot,t}=await ready();const cas=a.saveRemote.compareAndSet;
 a.saveRemote.compareAndSet=async(...args)=>{await cas(...args);throw Object.assign(Error('lost ack'),{code:'OFFLINE'});};
 const trial=JSON.stringify({...JSON.parse(payload),payroll_elapsed:JSON.parse(payload).payroll_elapsed+2.2});
 assert(!(await a.client.commitBackground(trial,t.token)).ok);assert(a.local().elapsedPending);assert.equal(a.local().record.revision,1);assert.equal(a.local().pending,false,'trial never enters ordinary upload queue');
 assert.equal(a.local().elapsedPending.record.digest,e.cloud().digest);assert.equal((await a.client.preserveRuntime(payload,1,boot.profileId)).code,'ELAPSED_UNCERTAIN');
 a.saveRemote.compareAndSet=cas;a.ownership.close();e.advance(61000);let fresh=e.device('Mac');await fresh.ownership.start();let reopened=restart(e,a,fresh),loaded=await reopened.boot();assert(loaded.ok&&loaded.revision===2&&loaded.payload===trial);assert(!a.local().elapsedPending);assert.equal(e.writeCalls(),2,'recovery never uploads or replays a trial');
 ({e,a,boot,t}=await ready());const baseline=e.cloud();a.saveRemote.compareAndSet=async()=>{throw Object.assign(Error('no ack'),{code:'OFFLINE'});};
 assert(!(await a.client.commitBackground(trial,t.token)).ok);assert(a.local().elapsedPending);assert.deepEqual(e.cloud(),baseline);
 loaded=await restart(e,a,a).boot();assert.equal(loaded.code,'ELAPSED_UNCERTAIN','baseline read under original epoch cannot prove abort');
 a.ownership.close();e.advance(61000);fresh=e.device('Mac');await fresh.ownership.start();loaded=await restart(e,a,fresh).boot();assert(loaded.ok&&loaded.revision===1&&loaded.payload===payload);assert(!a.local().elapsedPending);assert.deepEqual(e.cloud(),baseline,'confirmed newer epoch discards failed trial without credit');
 // Interrupted probe intent is durable before the request transaction. Restart
 // clears only the matching original owner/epoch/tag; it grants no elapsed time.
 probeStore.clear();e=environment();a=e.device('Mac');await a.ownership.start();t=await a.ownership.beginElapsed();e.advance(2200);
 const change=e.remote.change;e.remote.change=async(...args)=>{const result=await change(...args);if(result.request)throw Object.assign(Error('lost readback'),{code:'OFFLINE'});return result;};
 await assert.rejects(a.ownership.finishElapsed(t.token));assert.equal(probeStore.size,1);const req=e.session().request;assert(req);e.remote.change=change;a.ownership.close();fresh=e.device('Mac');await fresh.ownership.start();assert.equal(e.session().request,null);assert.equal(probeStore.size,0);
 assert.equal(e.cloud(),null,'probe recovery never creates a business snapshot');
 console.log('Passed: durable separate trial intent, lost ack exact snapshot recovery, same-epoch baseline blocked, new-epoch abort without credit, interrupted probe exact-tag cleanup.');
})().catch(e=>{console.error(e);process.exitCode=1;});
