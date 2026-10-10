import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,deleteDoc,getDocFromServer,runTransaction,serverTimestamp,Timestamp,onSnapshot} from 'firebase/firestore';
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules:readFileSync('firestore.rules','utf8')}});
const sessions=[];
try{
  // Same JavaScript realm as the actual SDK; no VM prototype normalization.
  for(const name of ['little_leaf_vault','little_leaf_firebase','little_leaf_firebase_session'])vm.runInThisContext(readFileSync(`../web/${name}.js`,'utf8'));
  // Actual SDK + adapter: an initially blocked new runtime must resume after
  // acknowledged takeover, including when it has no local journal yet.
  {
    const account='session-adapter-resume',sdk={doc,getDocFromServer,runTransaction,serverTimestamp,onSnapshot};
    const database=env.authenticatedContext(account,{firebase:{sign_in_provider:'google.com'}}).firestore();
    const clone=v=>v==null?null:JSON.parse(JSON.stringify(v));
    function device(label){
      const ownership=LittleLeafFirebaseSession.createSession({uid:account,currentUid:()=>account,deviceLabel:label,remote:LittleLeafFirebaseSession.createRemote(database,sdk,account)});sessions.push(ownership);let local=null;
      const journal={async read(){return clone(local);},async replace(uid,expected,next){assert.deepEqual(local,clone(expected));local=clone(next);},async readRecoveryBackup(){return null;}};
      const client=LittleLeafFirebase.createClient({uid:account,currentUid:()=>account,codec:LittleLeafAuthorityCodec,ownership,journal,remote:LittleLeafFirebase.createRemote(database,sdk,ownership),status(){}});return {ownership,client,local:()=>local};
    }
    const first=device('Mac'),second=device('iPhone');await first.ownership.start();const boot=await first.client.boot();assert(boot.ok);
    const payload=readFileSync('../tests/fixtures/startup-retry-v15.json','utf8');assert((await first.client.commit(payload,0,boot.profileId)).ok);
    await second.ownership.start();assert.equal((await second.client.boot()).code,'OWNERSHIP_LOST');assert.equal(second.local(),null);
    assert((await second.client.requestTakeover()).ok);await first.ownership.refresh();assert((await first.client.preserveOwnerRuntime(payload,1,boot.profileId)).cloudConfirmed);
    await second.ownership.refresh();const resumed=await second.client.finishTakeover();assert(resumed.ok,JSON.stringify(resumed));assert.equal(resumed.payload,payload);assert(second.local());
  }
  const uid='session-suite',google={firebase:{sign_in_provider:'google.com'}};
  const db=env.authenticatedContext(uid,google).firestore(),other=env.authenticatedContext('other',google).firestore();
  const sessionRef=database=>doc(database,'players',uid,'session','owner'),saveRef=doc(db,'players',uid,'saves','cafe');
  const sdk={doc,getDocFromServer,runTransaction,serverTimestamp,onSnapshot};
  const make=label=>{const s=LittleLeafFirebaseSession.createSession({uid,currentUid:()=>uid,deviceLabel:label,remote:LittleLeafFirebaseSession.createRemote(db,sdk,uid)});sessions.push(s);return s;};
  const a=make('Mac'),b=make('iPhone');await a.start();await b.start();assert.equal(b.snapshot().status,'other-device');
  const firstFence=a.fence,profileId='12345678-1234-1234-1234-123456789012';
  const first={schema:1,profileId,revision:1,digest:'a'.repeat(64),record:'synthetic',...firstFence};
  await assertSucceeds(setDoc(saveRef,first));
  await assertFails(setDoc(saveRef,{...first,revision:2,writerEpoch:2}));
  await assertFails(setDoc(saveRef,{schema:1,profileId,revision:2,digest:'b'.repeat(64),record:'unfenced legacy'}));
  await b.requestTakeover();await a.refresh();assert.equal(a.snapshot().status,'handoff-requested');
  await assert.rejects(b.takeOver(true),e=>e.code==='HANDOFF_WAITING');
  const requested=(await getDocFromServer(sessionRef(db))).data();
  await assertFails(setDoc(sessionRef(db),{schema:1,owner:requested.request.requester,epoch:2,device:'iPhone',updatedAt:serverTimestamp(),request:null,ack:null}));
  await assertFails(setDoc(sessionRef(db),{...requested,ack:{requestId:requested.request.id,digest:'f'.repeat(64),revision:999}}));
  const final={...first,revision:2,digest:'b'.repeat(64),device:'Mac'};
  await assertSucceeds(setDoc(saveRef,final));await a.acknowledge(final.digest,2);
  assert.equal((await getDocFromServer(sessionRef(db))).data().owner,firstFence.writerId,'old owner retains ownership through final flush and ack');
  await assertFails(setDoc(saveRef,{...first,revision:3,digest:'c'.repeat(64)}));
  await b.refresh();await b.takeOver();const secondFence=b.fence;assert.equal(secondFence.writerEpoch,2);
  // These writes deliberately bypass all client ownership checks.
  await assertFails(setDoc(saveRef,{...first,revision:100,digest:'d'.repeat(64)}));
  await assertSucceeds(setDoc(saveRef,{...final,...secondFence,revision:3,digest:'c'.repeat(64)}));
  await assertFails(deleteDoc(sessionRef(db)));await assertFails(getDoc(sessionRef(other)));
  await a.refresh();await a.requestTakeover();let value=(await getDocFromServer(sessionRef(db))).data();
  // Isolated emulator admin aging represents an offline owner, not a production bypass.
  await env.withSecurityRulesDisabled(async context=>{await setDoc(sessionRef(context.firestore()),{...value,request:{...value.request,at:Timestamp.fromMillis(Date.now()-11000)}});});
  await a.refresh();await a.takeOver(true);const thirdFence=a.fence;assert.equal(thirdFence.writerEpoch,3);
  await assertFails(setDoc(saveRef,{...final,...secondFence,revision:100,digest:'e'.repeat(64)}));
  value=(await getDocFromServer(sessionRef(db))).data();
  await assertFails(setDoc(sessionRef(db),{...value,owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:4,updatedAt:serverTimestamp()}));
  await env.withSecurityRulesDisabled(async context=>{await setDoc(sessionRef(context.firestore()),{...value,updatedAt:Timestamp.fromMillis(Date.now()-61000)});});
  await assertFails(setDoc(saveRef,{...final,...thirdFence,revision:101,digest:'f'.repeat(64)}));
  const c=make('Linux device');await c.start();assert.equal(c.fence.writerEpoch,4);
  // Abandoned request can be canceled only by an explicit owner action in the app.
  await b.refresh();await b.requestTakeover();await c.refresh();await c.requestTakeover();assert.equal((await getDocFromServer(sessionRef(db))).data().request,null);
  await b.refresh();await assert.rejects(b.takeOver(),e=>e.code==='HANDOFF_CHANGED');
  // Same-tab update continuation uses the existing server rules unchanged.
  const reloadUid='reload-suite',reloadDb=env.authenticatedContext(reloadUid,google).firestore();
  const reloadSave=doc(reloadDb,'players',reloadUid,'saves','cafe');
  const newReload=()=>{const s=LittleLeafFirebaseSession.createSession({uid:reloadUid,currentUid:()=>reloadUid,deviceLabel:'Mac',remote:LittleLeafFirebaseSession.createRemote(reloadDb,sdk,reloadUid)});sessions.push(s);return s;};
  const oldPage=newReload();await oldPage.start();const oldReloadFence=oldPage.fence;
  const reloadDocument={...first,...oldReloadFence,device:'Mac'};await setDoc(reloadSave,reloadDocument);
  const continuation=oldPage.reloadContinuation(reloadDocument.digest,reloadDocument.revision);oldPage.close();
  const newPage=newReload();await newPage.start(continuation);assert.equal(newPage.fence.writerEpoch,2);assert.notEqual(newPage.fence.writerId,oldReloadFence.writerId);
  assert.deepEqual((await getDocFromServer(reloadSave)).data(),reloadDocument,'reload does not manufacture a new save');
  const clonedTab=newReload();await clonedTab.start(continuation);assert.equal(clonedTab.snapshot().status,'other-device');
  await assertFails(setDoc(reloadSave,{...reloadDocument,revision:2}));
  await assertSucceeds(setDoc(reloadSave,{...reloadDocument,...newPage.fence,revision:2,digest:'b'.repeat(64)}));
  assert.equal(newPage.fence.writerEpoch,2,'duplicate receipt never grants a second writer');
  const parallelReceipt=newPage.reloadContinuation('b'.repeat(64),2);newPage.close();
  const twinA=newReload(),twinB=newReload();const raced=await Promise.allSettled([twinA.start(parallelReceipt),twinB.start({...parallelReceipt})]);console.log('Reload concurrent outcomes',raced.map(r=>r.status==='rejected'?r.reason:r.value));if(raced.some(r=>r.status==='rejected'))throw raced.find(r=>r.status==='rejected').reason;
  await twinA.refresh();await twinB.refresh();assert.equal([twinA,twinB].filter(s=>s.snapshot().status==='active').length,1,'concurrent copied tickets grant exactly one writer');
  const winner=twinA.snapshot().status==='active'?twinA:twinB;assert.equal(winner.fence.writerEpoch,3);
  await assertFails(setDoc(reloadSave,{...reloadDocument,revision:3}));
  const abandoned=newReload();await abandoned.start();await abandoned.requestTakeover();abandoned.close();
  const retryPage=newReload();await retryPage.start();await assert.rejects(retryPage.requestTakeover(),e=>e.code==='HANDOFF_BUSY');
  const ownerRef=doc(reloadDb,'players',reloadUid,'session','owner'),pendingOwner=(await getDocFromServer(ownerRef)).data();
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'players',reloadUid,'session','owner'),{...pendingOwner,updatedAt:Timestamp.fromMillis(Date.now()-61000)}));
  const beforeRetry=(await getDocFromServer(reloadSave)).data();await retryPage.requestTakeover();assert.equal(retryPage.snapshot().status,'active');assert.equal(retryPage.fence.writerEpoch,4);assert.deepEqual((await getDocFromServer(reloadSave)).data(),beforeRetry,'explicit recovery after abandoned request only changes ownership');


  console.log('Actual Firestore session rules passed: old final-flush/ack ordering, exact ack proof, server stale-epoch rejection, explicit timeout, expired lease, legacy rejection, ownership isolation and canceled request.');
}finally{for(const s of sessions)s.close();await env.cleanup();}
