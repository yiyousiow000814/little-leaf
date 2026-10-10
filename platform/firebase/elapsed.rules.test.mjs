import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDocFromServer,writeBatch,runTransaction,onSnapshot,serverTimestamp,Timestamp,deleteDoc} from 'firebase/firestore';

// A distinct emulator project and generated account fixtures; no production
// configuration, credentials, browser profile or player data is used.
const env=await initializeTestEnvironment({projectId:'demo-little-leaf-elapsed',firestore:{rules:readFileSync('firestore.rules','utf8')}});
const google={firebase:{sign_in_provider:'google.com'}},writer='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const otherWriter='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',profile='12345678-1234-1234-1234-123456789012';
let serial=0,checks=0;
const sessions=[];
function fixture(){
  const uid=`elapsed-${++serial}`,db=env.authenticatedContext(uid,google).firestore();
  return {uid,db,session:doc(db,'players',uid,'session','owner'),save:doc(db,'players',uid,'saves','cafe'),interval:doc(db,'players',uid,'background','interval')};
}
const owner=(at=serverTimestamp())=>({schema:1,owner:writer,epoch:1,device:'Mac',updatedAt:at,request:null,ack:null});
const save=(revision=1,digest='a'.repeat(64))=>({schema:1,profileId:profile,revision,digest,record:'synthetic fixture',writerId:writer,writerEpoch:1,device:'Mac'});
function interval(at=serverTimestamp()){
  return {schema:1,id:`${String(serial).padStart(8,'0')}-aaaa-4aaa-aaaa-aaaaaaaaaaaa`,profileId:profile,owner:writer,epoch:1,device:'Mac',anchorAt:at,startAt:at,
    state:'open',baseDigest:'a'.repeat(64),baseRevision:1,endAt:null,resultDigest:null,resultRevision:null};
}
async function read(ref){return (await getDocFromServer(ref)).data();}
async function seed(f,values){
  await env.withSecurityRulesDisabled(async context=>{
    const db=context.firestore(),batch=writeBatch(db);
    for(const [kind,data] of Object.entries(values))batch.set(doc(db,f[kind].path),data);
    await batch.commit();
  });
}
async function fresh(){const f=fixture();await assertSucceeds(setDoc(f.session,owner()));await assertSucceeds(setDoc(f.save,save()));return f;}
async function start(f,patch={}){
  const batch=writeBatch(f.db),s=await read(f.session);
  batch.set(f.session,{...s,updatedAt:serverTimestamp()});batch.set(f.interval,{...interval(),...patch});return batch.commit();
}
async function seal(f,patch={}){
  const batch=writeBatch(f.db),s=await read(f.session),c=await read(f.interval);
  batch.set(f.session,{...s,updatedAt:serverTimestamp()});batch.set(f.interval,{...c,state:'sealed',endAt:serverTimestamp(),...patch});return batch.commit();
}
async function consume(f,record=save(2,'b'.repeat(64)),patch={}){
  const c=await read(f.interval),batch=writeBatch(f.db);
  batch.set(f.save,record);batch.set(f.interval,{...c,state:'consumed',resultDigest:record.digest,resultRevision:record.revision,...patch});return batch.commit();
}
async function expiredOpen(minutes){
  const f=await fresh();await assertSucceeds(start(f));
  const c=await read(f.interval),at=Timestamp.fromMillis(Date.now()-minutes*60000);
  // Only the emulator's disabled-rules fixture clock advances. Rules still
  // evaluate seal request.time and must not require an unexpired normal lease.
  await seed(f,{session:owner(at),interval:{...c,anchorAt:at,startAt:at}});return f;
}
const plain=value=>value==null?null:JSON.parse(JSON.stringify(value));
const sdk={doc,getDocFromServer,runTransaction,onSnapshot,serverTimestamp};
function storage(){const map=new Map();return {map,getItem:key=>map.get(key)||null,setItem:(key,value)=>map.set(key,value),removeItem:key=>map.delete(key)};}
function adapter(f,store,journal,remotePatch=value=>value){
  const sessionRemote=remotePatch(LittleLeafFirebaseSession.createRemote(f.db,sdk,f.uid));
  const ownership=LittleLeafFirebaseSession.createSession({uid:f.uid,currentUid:()=>f.uid,deviceLabel:'Mac',remote:sessionRemote,elapsedStorage:store});sessions.push(ownership);
  const saveRemote=LittleLeafFirebase.createRemote(f.db,sdk,ownership);
  const client=LittleLeafFirebase.createClient({uid:f.uid,currentUid:()=>f.uid,codec:LittleLeafAuthorityCodec,ownership,journal,remote:saveRemote,status(){}});
  return {ownership,client,saveRemote,sessionRemote};
}
function memoryJournal(){let local=null;return {async read(){return plain(local);},async replace(uid,expected,next){assert.deepEqual(local,plain(expected));local=plain(next);},async readRecoveryBackup(){return null;},local:()=>plain(local)};}
async function adapterReady(remotePatch=value=>value){
  const f=fixture(),store=storage(),journal=memoryJournal(),a=adapter(f,store,journal,remotePatch);
  await a.ownership.start();const boot=await a.client.boot();assert(boot.ok,JSON.stringify(boot));
  const payload=readFileSync('../../tests/fixtures/startup-retry-v15.json','utf8');
  assert((await a.client.commit(payload,0,boot.profileId)).ok);await a.client.sync();return {f,store,journal,a,boot,payload};
}
function ageStart(f,minutes){return remote=>{
  const change=remote.changeCertificate.bind(remote);
  remote.changeCertificate=async(...args)=>{
    const result=await change(...args);
    if(result.certificate?.state==='open'){
      // Advance only the synthetic emulator fixture clock between the actual
      // start commit and its authoritative adapter readback. The runtime gets
      // the same exact server anchor subsequently used by its seal transaction.
      const at=Timestamp.fromMillis(Date.now()-minutes*60000);
      await seed(f,{session:{...result.session,updatedAt:at},interval:{...result.certificate,startAt:at,anchorAt:at}});
      return {session:await read(f.session),certificate:await read(f.interval)};
    }
    return result;
  };return remote;
};}
try{
  let f=await fresh();
  await assertFails(setDoc(f.interval,interval(Timestamp.fromMillis(1))));checks++;
  await assertFails(setDoc(f.interval,interval()));checks++;
  await assertFails(start(f,{extra:true}));checks++;
  await assertFails(start(f,{baseDigest:'f'.repeat(64)}));checks++;
  await assertSucceeds(start(f));checks++;
  let c=await read(f.interval);assert(c.startAt.isEqual(c.anchorAt));
  await assertFails(setDoc(f.interval,{...c,id:'cccccccc-cccc-4ccc-cccc-cccccccccccc',startAt:serverTimestamp(),anchorAt:serverTimestamp()}));checks++;
  await assertFails(setDoc(f.interval,{...c,state:'sealed',endAt:serverTimestamp()}));checks++;
  await assertFails(seal(f,{baseRevision:2}));checks++;
  await assertSucceeds(seal(f));checks++;
  c=await read(f.interval);assert(c.endAt.toMillis()>=c.startAt.toMillis());
  await assertFails(seal(f));checks++;
  await assertFails(setDoc(f.save,save(2,'b'.repeat(64))));checks++;
  await assertFails(setDoc(f.interval,{...c,state:'consumed',resultDigest:'b'.repeat(64),resultRevision:2}));checks++;
  await assertFails(consume(f,save(2,'b'.repeat(64)),{resultDigest:'c'.repeat(64)}));checks++;
  await assertFails(consume(f,save(3,'b'.repeat(64))));checks++;
  await assertFails(consume(f,save(2,'b'.repeat(64)),{endAt:serverTimestamp()}));checks++;
  await assertSucceeds(consume(f));checks++;
  const canonical=await read(f.save);await assertFails(consume(f));checks++;assert.deepEqual(await read(f.save),canonical);
  c=await read(f.interval);await assertFails(setDoc(f.interval,{...c,state:'cancelled',resultDigest:null,resultRevision:null}));checks++;
  await assertSucceeds(start(f,{id:'dddddddd-dddd-4ddd-dddd-dddddddddddd',baseDigest:canonical.digest,baseRevision:canonical.revision}));checks++;

  for(const minutes of [2,20]){
    f=await expiredOpen(minutes);await assertSucceeds(seal(f));c=await read(f.interval);
    assert(c.endAt.toMillis()-c.startAt.toMillis()>=minutes*60000,'full server duration survives normal lease expiry');
    await assertSucceeds(consume(f));checks+=2;
  }
  f=await expiredOpen(20);let s=await read(f.session);
  await assertSucceeds(setDoc(f.session,{...s,updatedAt:serverTimestamp()}));
  await assertFails(seal(f));checks++;

  f=await expiredOpen(20);s=await read(f.session);
  const request={id:'eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee',requester:otherWriter,device:'iPhone',at:serverTimestamp()};
  await assertSucceeds(setDoc(f.session,{...s,request}));await assertFails(seal(f));checks++;
  s=await read(f.session);await assertSucceeds(setDoc(f.session,{...s,request:null,ack:null,updatedAt:serverTimestamp()}));
  await assertFails(seal(f));checks++;

  f=await expiredOpen(20);await assertSucceeds(setDoc(f.session,{...owner(),owner:otherWriter,epoch:2,device:'iPhone'}));
  await assertFails(seal(f));checks++;
  const changedSave={...save(2,'c'.repeat(64)),writerId:otherWriter,writerEpoch:2,device:'iPhone'};
  await assertSucceeds(setDoc(f.save,changedSave));checks++;

  f=await expiredOpen(2);await seed(f,{save:save(2,'c'.repeat(64))});await assertFails(seal(f));checks++;
  f=await expiredOpen(20);await assertSucceeds(seal(f));c=await read(f.interval);
  await seed(f,{session:owner(Timestamp.fromMillis(Date.now()-61000))});await assertFails(consume(f));checks++;
  await assertSucceeds(setDoc(f.session,owner()));await assertSucceeds(consume(f));checks++;

  f=await expiredOpen(20);await assertSucceeds(seal(f));s=await read(f.session);
  await assertSucceeds(setDoc(f.session,{...s,request}));await assertFails(consume(f));checks++;
  await assertSucceeds(setDoc(f.save,save(2,'c'.repeat(64))));checks++;
  c=await read(f.interval);await assertSucceeds(setDoc(f.interval,{...c,state:'cancelled'}));checks++;
  const cancelled=await read(f.interval);await assertFails(consume(f));checks++;assert.deepEqual(await read(f.interval),cancelled);
  await assertFails(deleteDoc(f.interval));checks++;
  const stranger=env.authenticatedContext('unrelated-account',google).firestore();
  await assertFails(getDocFromServer(doc(stranger,f.interval.path)));checks++;
  const anonymous=env.authenticatedContext(f.uid,{firebase:{sign_in_provider:'anonymous'}}).firestore();
  await assertFails(getDocFromServer(doc(anonymous,f.interval.path)));checks++;
  f=await expiredOpen(20);c=await read(f.interval);
  await assertSucceeds(setDoc(f.interval,{...c,state:'cancelled'}));checks++;
  await assertFails(seal(f));checks++;
  // Actual SDK session/client path, with durable synthetic intent storage and
  // an exact CAS memory journal. This observes protocol behavior, not pixels or
  // native rate estimation; the caller supplies the already computed payload.
  for(const name of ['little_leaf_vault','little_leaf_firebase','little_leaf_firebase_session'])vm.runInThisContext(readFileSync(`../web/${name}.js`,'utf8'));
  const af=fixture(),store=storage(),journal=memoryJournal(),a=adapter(af,store,journal,ageStart(af,2));
  await a.ownership.start();const boot=await a.client.boot();assert(boot.ok,JSON.stringify(boot));
  const payload=readFileSync('../../tests/fixtures/startup-retry-v15.json','utf8');assert((await a.client.commit(payload,0,boot.profileId)).ok);await a.client.sync();
  const opened=await a.client.beginBackground(1,boot.profileId);assert(opened.ok,JSON.stringify(opened));
  const proved=await a.client.finishBackground(opened.token);assert(proved.ok,JSON.stringify(proved));assert(proved.seconds>=120);assert.equal(proved.discardedSeconds,0);
  const trial=JSON.stringify({...JSON.parse(payload),coins:JSON.parse(payload).coins+30});
  const committed=await a.client.commitBackground(trial,opened.token);assert(committed.ok,JSON.stringify(committed));assert.equal(journal.local().record.payload,trial);
  assert.equal((await read(af.interval)).state,'consumed');assert(!a.ownership.hasElapsedIntent);
  const exact=await read(af.save);assert.equal((await a.client.commitBackground(trial,opened.token)).code,'ELAPSED_CONSUMED');assert.deepEqual(await read(af.save),exact);checks++;

  for(const phase of ['open','sealed']){
    let blocked=false;
    const lost=await adapterReady(remote=>{
      const change=remote.changeCertificate.bind(remote);
      remote.changeCertificate=async(...args)=>{
        if(blocked)throw Object.assign(Error('synthetic offline'),{code:'OFFLINE'});
        const result=await change(...args);if(result.certificate?.state===phase){blocked=true;throw Object.assign(Error('lost certificate acknowledgement'),{code:'OFFLINE'});}return result;
      };return remote;
    });
    const token=await lost.a.client.beginBackground(1,lost.boot.profileId);
    if(phase==='open')assert(!token.ok);else {assert(token.ok);assert(!(await lost.a.client.finishBackground(token.token)).ok);}
    assert(lost.store.map.size>0,'interrupted start/seal intent survives missing terminal receipt');
    const oldSession=await read(lost.f.session);lost.a.ownership.close();
    await seed(lost.f,{session:{...oldSession,updatedAt:Timestamp.fromMillis(Date.now()-61000)}});
    const reopened=adapter(lost.f,lost.store,lost.journal);await reopened.ownership.start();
    assert.equal((await read(lost.f.interval)).state,'cancelled');assert.equal(lost.store.map.size,0);
    const loaded=await reopened.client.boot();assert(loaded.ok,JSON.stringify(loaded));assert.equal(loaded.payload,lost.payload);assert.equal(loaded.revision,1);checks++;
  }
  const uncertain=await adapterReady(),ut=await uncertain.a.client.beginBackground(1,uncertain.boot.profileId);assert(ut.ok);
  assert((await uncertain.a.client.finishBackground(ut.token)).ok);
  const cas=uncertain.a.saveRemote.compareAndSet.bind(uncertain.a.saveRemote);
  uncertain.a.saveRemote.compareAndSet=async(...args)=>{await cas(...args);throw Object.assign(Error('lost consume acknowledgement'),{code:'OFFLINE'});};
  assert(!(await uncertain.a.client.commitBackground(trial,ut.token)).ok);assert(uncertain.journal.local().elapsedPending);
  assert.equal((await read(uncertain.f.interval)).state,'consumed');const consumedSave=await read(uncertain.f.save),oldSession=await read(uncertain.f.session);
  uncertain.a.ownership.close();await seed(uncertain.f,{session:{...oldSession,updatedAt:Timestamp.fromMillis(Date.now()-61000)}});
  const recovered=adapter(uncertain.f,uncertain.store,uncertain.journal);await recovered.ownership.start();const receipt=await recovered.client.boot();
  assert(receipt.ok,JSON.stringify(receipt));assert.equal(receipt.payload,trial);assert.equal(receipt.revision,2);assert(!uncertain.journal.local().elapsedPending);assert.deepEqual(await read(uncertain.f.save),consumedSave);checks++;
  console.log(`Elapsed certificate rules passed: ${checks} focused checks; atomic start/seal, 2/20-minute server duration, bidirectional once-only consume, handoff/anchor/base fences and exact cancellation. Synthetic emulator fixtures only.`);
}finally{for(const session of sessions)session.close();await env.cleanup();}
