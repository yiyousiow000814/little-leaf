'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
prefix=prefix.replace('writeCalls=0;const watchers', 'writeCalls=0,ackGate=null,hashGate=null;const watchers');
prefix=prefix.replace("codec,journal,remote:saveRemote", "codec:{...codec,hash:async v=>{if(hashGate)await hashGate;return codec.hash(v);}},journal,remote:saveRemote");
prefix=prefix.replace('cloud={...clone(next),...fence};guard();','cloud={...clone(next),...fence};if(ackGate)await ackGate;');
prefix=prefix.replace('return {device,remote,deliver:', 'return {holdHash(){let resolve;hashGate=new Promise(r=>resolve=r);return ()=>{hashGate=null;resolve();};},holdAck(){let resolve;ackGate=new Promise(r=>resolve=r);return ()=>{ackGate=null;resolve();};},device,remote,deliver:');
prefix=prefix.replace('root.globalThis=root;', `root.globalThis=root;const probeStore=new Map();root.localStorage={getItem:k=>probeStore.get(k)||null,setItem:(k,v)=>probeStore.set(k,v),removeItem:k=>probeStore.delete(k)};`);
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,payload,codec};',context);
const {environment,payload,codec}=context.fixture;
const delay=()=>new Promise(r=>setTimeout(r,15));
async function ready(){const e=environment({timeoutMs:5}),a=e.device('Mac');await a.ownership.start();const boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();return {e,a,boot};}
async function proved(x){const t=await x.a.client.beginBackground(1,x.boot.profileId);x.e.advance(2200);assert((await x.a.client.finishBackground(t.token)).ok);return t;}
(async()=>{
 let x=await ready(),release=x.e.holdWrites();await x.a.client.commit(payload,1,x.boot.profileId);
 let pending=x.a.client.beginBackground(2,x.boot.profileId);await Promise.resolve();x.a.client.cancelBackground();release();assert(!(await pending).ok);
 assert.equal(x.e.session().request,null,'cancelled upload cannot arm a new interval');
 x=await ready();let t=await x.a.client.beginBackground(1,x.boot.profileId);x.e.advance(2200);release=x.e.holdReads();pending=x.a.client.finishBackground(t.token);await delay();x.a.client.cancelBackground();release();assert(!(await pending).ok);
 assert.equal((await x.a.client.commitBackground(payload,t.token)).code,'ELAPSED_CONSUMED');
 x=await ready();t=await proved(x);const releaseHash=x.e.holdHash();
 pending=x.a.client.commitBackground(payload,t.token);await Promise.resolve();x.a.client.cancelBackground();releaseHash();assert(!(await pending).ok);assert.equal(x.e.cloud().revision,1,'cancel before hash receipt cannot write');
 x=await ready();t=await proved(x);release=x.e.holdAck();let settled=false;
 pending=x.a.client.commitBackground(payload,t.token).then(r=>{settled=true;return r;});await delay();
 assert.equal(x.e.cloud().revision,2);assert.equal(settled,false,'local timeout cannot discard an in-flight committed transaction');
 x.a.client.cancelBackground();assert.equal(x.a.client.ownershipSnapshot().status,'resume-needed');assert.equal((await x.a.client.beginBackground(1,x.boot.profileId)).code,'SAVE_BUSY');
 release();const result=await pending;assert(result.ok&&result.cloudConfirmed&&result.durable&&result.reloadRequired);
 assert.equal(x.a.local().record.digest,x.e.cloud().digest,'late receipt journals the exact confirmed trial');
 assert.equal(x.a.local().record.revision,2);assert.equal((await x.a.client.commit(payload,1,x.boot.profileId)).ok,false,'old runtime remains blocked until reconciliation');
 assert.equal(x.e.writeCalls(),2,'one initial write plus exactly one elapsed write');
 console.log('Passed: cancel during upload/seal/hash, delayed authoritative commit acknowledgement beyond timeout, retained claim, exact late receipt, blocked old model writes.');
})().catch(e=>{console.error(e);process.exitCode=1;});
