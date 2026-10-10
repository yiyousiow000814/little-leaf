'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
prefix=prefix.replace('root.globalThis=root;', `root.globalThis=root;const probeStore=new Map();root.localStorage={getItem:k=>probeStore.get(k)||null,setItem:(k,v)=>probeStore.set(k,v),removeItem:k=>probeStore.delete(k)};`);
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,payload};',context);
const {environment,payload}=context.fixture;
(async()=>{
 let e=environment(),a=e.device('Mac');await a.ownership.start();let boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();
 let t=await a.client.beginBackground(1,boot.profileId);assert(t.ok);e.advance(4600);let p=await a.client.finishBackground(t.token);assert(p.ok);assert.equal(p.seconds,4.6);
 const data=JSON.parse(payload),trial=JSON.stringify({...data,payroll_elapsed:data.payroll_elapsed+4.6});
 const baseline=e.cloud();assert.equal(e.cloud().digest,baseline.digest,'proof does not mutate business');
 let result=await a.client.commitBackground(trial,t.token);assert(result.ok&&result.cloudConfirmed&&result.revision===2);
 assert.equal(JSON.parse(JSON.parse(e.cloud().record).payload).payroll_elapsed,data.payroll_elapsed+4.6);
 const once=e.cloud(),writes=e.writeCalls();assert.equal((await a.client.commitBackground(trial,t.token)).code,'ELAPSED_CONSUMED');assert.deepEqual(e.cloud(),once);assert.equal(e.writeCalls(),writes);
 // No second hidden claim from the same visibility event. Explicit Pause
 // invalidation cancels the armed token without any business snapshot write.
 t=await a.client.beginBackground(2,boot.profileId);assert(t.ok);assert.equal((await a.client.beginBackground(2,boot.profileId)).code,'SAVE_BUSY');a.client.cancelBackground();assert.equal((await a.client.finishBackground(t.token)).code,'ELAPSED_CONSUMED');assert.deepEqual(e.cloud(),once);
 // A takeover after proof but before commit must leave canonical funds intact.
 t=await a.client.beginBackground(2,boot.profileId);e.advance(2200);p=await a.client.finishBackground(t.token);assert(p.ok&&p.seconds===2.2);
 e.setSession({...e.session(),owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:e.session().epoch+1});
 result=await a.client.commitBackground(JSON.stringify({...data,coins:data.coins+200}),t.token);assert(!result.ok);assert.deepEqual(e.cloud(),once);assert.equal(a.local().record.revision,2);
 console.log('Passed: exact server elapsed receipt, no proof-side business write, fenced single commit, duplicate visibility/commit, Pause cancellation, post-proof takeover rejection.');
})().catch(e=>{console.error(e);process.exitCode=1;});
