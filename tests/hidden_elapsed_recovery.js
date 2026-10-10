'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let prefix=fs.readFileSync('tests/firebase_session.js','utf8').split('(async()=>{')[0];
prefix=prefix.replace('root.globalThis=root;', `root.globalThis=root;const probeStore=new Map();root.localStorage={getItem:k=>probeStore.get(k)||null,setItem:(k,v)=>probeStore.set(k,v),removeItem:k=>probeStore.delete(k)};`);
prefix=prefix.replace('return {ownership,client,local:', 'return {journal,saveRemote,ownership,client,local:');
const context={require,console,setTimeout,clearTimeout,TextEncoder};
vm.runInNewContext(prefix+'\nglobalThis.fixture={environment,payload,codec,api,probeStore};',context);
const {environment,payload,codec,api,probeStore}=context.fixture;
const plain=value=>JSON.parse(JSON.stringify(value));
function restart(e,a,owner){return api.createClient({uid:'synthetic-owner',codec,journal:a.journal,remote:a.saveRemote,currentUid:()=> 'synthetic-owner',status(){},ownership:owner.ownership});}
async function ready(){probeStore.clear();const e=environment(),a=e.device('Mac');await a.ownership.start();const boot=await a.client.boot();await a.client.commit(payload,0,boot.profileId);await a.client.sync();const t=await a.client.beginBackground(1,boot.profileId);e.advance(2200);assert((await a.client.finishBackground(t.token)).ok);return {e,a,boot,t};}
(async()=>{
 let {e,a,boot,t}=await ready();const cas=a.saveRemote.compareAndSet;
 a.saveRemote.compareAndSet=async(...args)=>{await cas(...args);throw Object.assign(Error('lost ack'),{code:'OFFLINE'});};
 const trial=JSON.stringify({...JSON.parse(payload),payroll_elapsed:JSON.parse(payload).payroll_elapsed+2.2});
 assert(!(await a.client.commitBackground(trial,t.token)).ok);assert(a.local().elapsedPending);assert.equal(a.local().record.revision,1);assert.equal(a.local().pending,false,'trial never enters ordinary upload queue');
 assert.equal(a.local().elapsedPending.record.digest,e.cloud().digest);assert.equal((await a.client.preserveRuntime(payload,1,boot.profileId)).code,'ELAPSED_UNCERTAIN');
 const protectedEntry=a.local(),update=await a.client.saveForUpdate(payload,1,boot.profileId);assert.equal(update.updateError?.code || update.code,'ELAPSED_UNCERTAIN');assert.deepEqual(a.local(),protectedEntry,'rejected update cannot rewrite or corrupt elapsed intent');
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
 // A different canonical record retains the real CAS source, not a synthetic
 // pending projection. Export contains both exact baseline and protected trial.
 ({e,a,boot,t}=await ready());a.saveRemote.compareAndSet=async()=>{throw Object.assign(Error('uncertain'),{code:'OFFLINE'});};
 assert(!(await a.client.commitBackground(trial,t.token)).ok);const actual=a.local(),trialRecord=actual.elapsedPending.record;
 const other={...actual.record,revision:2,payload:JSON.stringify({...JSON.parse(payload),coins:JSON.parse(payload).coins+7}),updatedAt:Date.now()};other.digest=await codec.hash(codec.fingerprint(other));
 e.setCloud({...e.cloud(),revision:2,digest:other.digest,record:JSON.stringify(other)});a.ownership.close();e.advance(61000);fresh=e.device('Mac');await fresh.ownership.start();
 let archive=null;a.journal.readChoiceBackup=async()=>archive;a.journal.recover=async()=>{throw Error('unexpected legacy replacement');};
 a.journal.choose=async(id,expected,next,backup,guard)=>{guard();assert.deepEqual(plain(a.local()),plain(expected));archive=JSON.parse(JSON.stringify(backup));a.setLocal(JSON.parse(JSON.stringify(next)));};
 reopened=restart(e,a,fresh);loaded=await reopened.boot();assert.equal(loaded.code,'REVISION_CONFLICT');const recovery=reopened.recoverySnapshot();assert(recovery.canExport);assert.equal(recovery.expectedLocalDigest,trialRecord.digest);assert.equal(recovery.choices.length,1);assert.equal(recovery.choices[0].id,'cloud');
 const exported=await reopened.exportRecovery();assert(exported.ok,JSON.stringify(exported));const bundle=JSON.parse(exported.text);assert.deepEqual(bundle.pendingEntry,plain(actual));assert.deepEqual(bundle.baselineRecord,plain(actual.record));assert.deepEqual(bundle.elapsedTrialRecord,plain(trialRecord));assert.deepEqual(a.local(),actual,'export never changes protected journal');
 assert.equal((await reopened.prepareChoice('local',trialRecord.digest,other.digest)).code,'ELAPSED_UNCERTAIN');assert.deepEqual(a.local(),actual,'unconfirmed trial never becomes a new-epoch upload');
 const selected=await reopened.prepareChoice('cloud',trialRecord.digest,other.digest);assert(selected.ok,JSON.stringify(selected));assert((await reopened.confirmChoice(selected.selectionToken)).ok);assert.equal(a.local().record.digest,other.digest);assert.deepEqual(archive.local,plain(actual),'cloud choice archives baseline and separate exact trial atomically');
 // Re-read the choice archive through preview, then recover the cloud through
 // the legacy protected slot. Both readers must accept the validated separate
 // elapsed intent, without accepting an ordinary acknowledged baseline.
 a.setLocal(plain(actual));reopened=restart(e,a,fresh);loaded=await reopened.boot();assert.equal(loaded.code,'REVISION_CONFLICT');assert.match(reopened.recoverySnapshot().choiceReason,/previous pair/,'valid elapsed choice archive is full, not corrupt');
 let legacyArchive=null;a.journal.readRecoveryBackup=async()=>legacyArchive;
 a.journal.recover=async(id,expected,next,guard)=>{guard();assert.deepEqual(plain(a.local()),plain(expected));legacyArchive=plain(expected);a.setLocal(plain(next));};
 assert((await reopened.recoverCloud(other.digest)).ok);const afterRecovery=await reopened.exportRecovery();assert(afterRecovery.ok,JSON.stringify(afterRecovery));assert.deepEqual(JSON.parse(afterRecovery.text).elapsedTrialRecord,plain(trialRecord));assert.deepEqual(legacyArchive,plain(actual));
 const acknowledgedOnly={...plain(actual),elapsedPending:null};legacyArchive=acknowledgedOnly;
 const invalidExport=await reopened.exportRecovery();assert(!invalidExport.ok,'acknowledged baseline alone is not a protected backup');assert.match(reopened.recoverySnapshot().reason,/could not be verified/);assert.deepEqual(legacyArchive,acknowledgedOnly,'invalid backup is never changed');
 legacyArchive=null;archive={...archive,local:acknowledgedOnly};a.setLocal(plain(actual));reopened=restart(e,a,fresh);await reopened.boot();assert.match(reopened.recoverySnapshot().choiceReason,/could not be verified/,'choice archive also rejects unprotected baseline');assert.deepEqual(archive.local,acknowledgedOnly);
 console.log('Passed: durable separate trial intent, lost ack exact snapshot recovery, same-epoch baseline blocked, new-epoch abort without credit, interrupted probe exact-tag cleanup.');
})().catch(e=>{console.error(e);process.exitCode=1;});
