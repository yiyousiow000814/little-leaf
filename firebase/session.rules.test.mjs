import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,deleteDoc,getDocFromServer,runTransaction,serverTimestamp,Timestamp,onSnapshot} from 'firebase/firestore';
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules:readFileSync('firestore.rules','utf8')}});
const sessions=[];
try{
  // Same JavaScript realm as the actual SDK; no VM prototype normalization.
  for(const name of ['little_leaf_firebase','little_leaf_firebase_session'])vm.runInThisContext(readFileSync(`../web/${name}.js`,'utf8'));
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
  console.log('Actual Firestore session rules passed: old final-flush/ack ordering, exact ack proof, server stale-epoch rejection, explicit timeout, expired lease, legacy rejection, ownership isolation and canceled request.');
}finally{for(const s of sessions)s.close();await env.cleanup();}
