'use strict';
// Production binding/client/session composition. Synthetic transaction boundary;
// no SDK credentials, hosted identity, Firestore rules claim or player storage.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const clone=x=>x==null?null:JSON.parse(JSON.stringify(x)),fault=code=>Object.assign(Error(code),{code});
const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['vault','firebase','firebase_session','google_binding'])vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_'+name+'.js','utf8'),root);
const codec=root.LittleLeafAuthorityCodec;
async function fixture(){
 let time=100000,uid='synthetic-google',session=null,cloud=null,certificate=null,writes=0,consumes=0,afterConsume=false,cancelGate=null,consumeGate=null,consumeStarted=null;
 const store=new Map(),intents=new Map(),listeners=[];
 const journal={async read(key){return clone(store.get(JSON.stringify(key)));},async replace(key,expected,next){key=JSON.stringify(key);assert.deepEqual(clone(store.get(key)),clone(expected));store.set(key,clone(next));},async readRecoveryBackup(){return null;}};
 const elapsedStorage={getItem:k=>intents.get(k)||null,setItem:(k,v)=>intents.set(k,v),removeItem:k=>intents.delete(k)};
 const notify=()=>listeners.forEach(fn=>fn(clone(session)));
 const sessionRemote={async read(){return clone(session);},async readCertificate(){return clone(certificate);},async change(fn,guard){guard();session=clone(fn(clone(session),clone(cloud),()=>time));guard();notify();return clone(session);},
  async changeCertificate(fn,guard){if(cancelGate&&certificate?.state==='open')await cancelGate;guard();const next=fn({session:clone(session),save:clone(cloud),certificate:clone(certificate)},()=>time);guard();if(next.session)session=clone(next.session);if(next.certificate)certificate=clone(next.certificate);notify();return {session:clone(session),certificate:clone(certificate)};},watch(fn){listeners.push(fn);return()=>{listeners.splice(listeners.indexOf(fn),1);};}};
 const ownership=root.LittleLeafFirebaseSession.createSession({remote:sessionRemote,uid,currentUid:()=>uid,now:()=>time,elapsedStorage});
 const remote={async read(){return clone(cloud);},async compareAndSet(id,base,next,guard,proof){
  if(consumeGate&&proof){consumeStarted();await consumeGate;}guard();const fence=ownership.assertActive(true);
  assert.equal(session.owner,fence.writerId);assert.equal(session.epoch,fence.writerEpoch);
  if(cloud?.digest===next.digest)return;
  if((cloud?.digest||null)!==base)throw fault('REVISION_CONFLICT');
  if(proof){assert.equal(certificate.state,'sealed');assert.equal(certificate.id,proof.certificateId);assert.equal(certificate.baseDigest,base);assert.equal(certificate.owner,fence.writerId);assert.equal(certificate.epoch,fence.writerEpoch);certificate={...certificate,state:'consumed',resultDigest:next.digest,resultRevision:next.revision};consumes++;}
  else if(certificate&&!['consumed','cancelled'].includes(certificate.state))throw fault('ELAPSED_UNCERTAIN');
  cloud={...clone(next),...fence};writes++;if(proof&&afterConsume)throw fault('OFFLINE');
 }};
 const client=()=>root.LittleLeafFirebase.createClient({uid,currentUid:()=>uid,codec,ownership,remote,journal,status(){},now:()=>time});
 await ownership.start();let account=client(),boot=await account.boot();assert(boot.ok);assert((await account.commit(payload,0,boot.profileId)).ok);await account.sync();
 const source=clone(store.get(JSON.stringify(uid)).record);
 const binding=()=>root.LittleLeafGoogleBinding.create({uid:'synthetic-google',currentUid:()=>uid,codec,ownership,remote,journal,source:async()=>clone(source),now:()=>time});
 return {ownership,account,client,binding,source,journal,advance:ms=>time+=ms,cloud:()=>clone(cloud),certificate:()=>clone(certificate),entry:()=>clone(store.get(JSON.stringify('synthetic-google'))),counts:()=>({writes,consumes}),afterConsume:()=>afterConsume=true,holdCancel(){let resolve;cancelGate=new Promise(r=>resolve=r);return()=>{cancelGate=null;resolve();};},holdConsume(){let resolve;consumeGate=new Promise(r=>resolve=r);const release=()=>{consumeGate=null;resolve();};release.started=new Promise(r=>consumeStarted=r);return release;},setUid:value=>uid=value};
}
async function select(binding){const view=await binding.inspect();assert(view.ok,JSON.stringify(view));return binding.choose('local',view.localDigest,view.cloudDigest);}
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 const checks=[];
 // An armed certificate must block selection until its *terminal* fence returns.
 let f=await fixture(),r=f.entry().record,armed=await f.account.beginBackground(r.revision,r.profileId);assert(armed.ok);
 assert.equal(f.certificate().state,'open');assert.equal((await f.binding().inspect()).code,'ELAPSED_UNCERTAIN');
 const release=f.holdCancel();let cleared=false;const cancellation=f.account.cancelBackground().then(x=>{cleared=true;return x;});await flush();assert(!cleared);assert(f.ownership.hasElapsedIntent);assert.equal((await f.binding().inspect()).ok,false);
 release();const terminal=await cancellation;assert(terminal.ok&&terminal.backgroundCleared);assert.equal(f.certificate().state,'cancelled');assert(!f.ownership.hasElapsedIntent);assert.equal(f.counts().consumes,0);assert.deepEqual(f.entry().record,f.source);checks.push('armed binding waits for terminal certificate cancellation; zero credit');
 await f.ownership.start();assert((await select(f.binding())).cloudConfirmed);const writes=f.counts().writes;assert((await f.binding().retry()).cloudConfirmed);assert.equal(f.counts().writes,writes);checks.push('binding after terminal fence acquires active status and repeated binding adds no write');f.ownership.close();
 // A dispatched consume cannot be treated as cancelled or replaced by binding.
 f=await fixture();r=f.entry().record;armed=await f.account.beginBackground(r.revision,r.profileId);f.advance(10000);const proof=await f.account.finishBackground(armed.token);assert(proof.ok);
 const trial=JSON.stringify({...JSON.parse(r.payload),coins:JSON.parse(r.payload).coins+7,background_profit_remainder:0.25});
 const releaseConsume=f.holdConsume();const consume=f.account.commitBackground(trial,armed.token);await releaseConsume.started;
 assert.equal((await f.account.cancelBackground()).code,'ELAPSED_UNCERTAIN');assert.equal((await f.binding().inspect()).ok,false);assert.equal((await f.account.commit(r.payload,r.revision,r.profileId)).ok,false);assert.equal(f.entry().elapsedPending.record.payload,trial);
 releaseConsume();const late=await consume;assert(!late.ok || late.reloadRequired);assert.equal(f.counts().consumes,0,'cancelled guard fences undispatched synthetic transaction');assert.equal(f.entry().elapsedPending.record.payload,trial);checks.push('dispatched uncertainty blocks selection and ordinary writes and preserves exact trial');f.ownership.close();
 // Lost consume acknowledgement must reconcile the exact complete trial once.
 f=await fixture();r=f.entry().record;armed=await f.account.beginBackground(r.revision,r.profileId);f.advance(10000);assert((await f.account.finishBackground(armed.token)).ok);f.afterConsume();assert(!(await f.account.commitBackground(trial,armed.token)).ok);
 assert.equal(f.certificate().state,'consumed');assert.equal(f.counts().consumes,1);assert.equal((await f.account.cancelBackground()).code,'ELAPSED_UNCERTAIN');assert.equal((await f.binding().inspect()).ok,false);assert.equal(f.entry().elapsedPending.record.payload,trial);
 await f.ownership.start();const restored=f.client(),receipt=await restored.boot();assert(receipt.ok,JSON.stringify(receipt));assert.equal(receipt.payload,trial);assert.equal(f.entry().record.payload,trial);assert(!f.entry().elapsedPending);assert.equal(JSON.parse(f.cloud().record).payload,trial);assert.equal(f.counts().consumes,1);assert.equal((await restored.finishBackground(armed.token)).code,'ELAPSED_CONSUMED');checks.push('interrupted consume reload reconciles full trial exactly once without baseline rollback');
 // Explicit later binding is still a whole-state choice, never a wallet merge.
 const target=f.binding(),choice=await target.inspect();assert(choice.ok&&!choice.resumable);const result=await target.choose('cloud',choice.localDigest,choice.cloudDigest);assert(result.cloudConfirmed,JSON.stringify(result));assert.equal(JSON.parse(f.cloud().record).payload,trial);assert.deepEqual(f.source.payload,r.payload);const finalWrites=f.counts().writes;assert((await f.binding().retry()).cloudConfirmed);assert.equal(f.counts().writes,finalWrites);assert.equal(f.counts().consumes,1);checks.push('post-reconciliation binding keeps complete cloud trial and repeated operation adds no earnings/write');
 f.setUid('other-synthetic');assert.equal((await f.binding().inspect()).code,'ACCOUNT_CHANGED');assert.equal(f.counts().writes,finalWrites);checks.push('account switch rejected before further binding mutation');f.setUid('synthetic-google');f.ownership.close();
 console.log(JSON.stringify({scope:'local production binding/client/session composition; synthetic transactions only',checks,passed:checks.length,hosted:false,production_save_used:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
