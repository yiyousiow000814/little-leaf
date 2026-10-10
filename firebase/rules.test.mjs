import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,deleteDoc,collection,getDocs,getDocFromServer,runTransaction,serverTimestamp} from 'firebase/firestore';
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules:readFileSync('firestore.rules','utf8')}});
try {
  const google={firebase:{sign_in_provider:'google.com'}};
  const alice=env.authenticatedContext('alice',google).firestore(),bob=env.authenticatedContext('bob',google).firestore(),anon=env.unauthenticatedContext().firestore(),guest=env.authenticatedContext('guest',{firebase:{sign_in_provider:'anonymous'}}).firestore();
  const ref=(db,id='alice')=>doc(db,'players',id,'saves','cafe');
  const writerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
  const ownerRef=(db,id)=>doc(db,'players',id,'session','owner');
  const initialSession={schema:1,owner:writerId,epoch:1,device:'Mac',updatedAt:serverTimestamp(),request:null,ack:null};
  await assertSucceeds(setDoc(ownerRef(alice,'alice'),initialSession));
  await assertSucceeds(setDoc(ownerRef(bob,'bob'),initialSession));
  const data={writerId,writerEpoch:1,schema:1,profileId:'12345678-1234-1234-1234-123456789012',revision:1,digest:'a'.repeat(64),record:'synthetic'};
  await assertFails(getDoc(ref(anon)));await assertFails(setDoc(ref(anon),data));
  await assertFails(setDoc(ref(bob),data));await assertFails(setDoc(ref(guest,'guest'),data));
  await assertSucceeds(setDoc(ref(alice),data));await assertSucceeds(getDoc(ref(alice)));
  await assertFails(getDoc(ref(bob)));await assertFails(getDocs(collection(alice,'players','alice','saves')));
  await assertFails(deleteDoc(ref(alice)));
  await assertFails(setDoc(ref(alice),data));
  await assertFails(setDoc(ref(alice),{...data,revision:0}));
  await assertFails(setDoc(ref(alice),{...data,revision:2,profileId:'98765432-1234-1234-1234-123456789012'}));
  for(const patch of [{device:'invented platform'},{schema:2},{revision:1.5},{revision:9007199254740992},{digest:'bad'},{record:42},{record:'x'.repeat(900001)},{extra:true}]) await assertFails(setDoc(ref(alice),{...data,revision:2,...patch}));
  const missing={...data,revision:2};delete missing.digest;await assertFails(setDoc(ref(alice),missing));
  await assertFails(setDoc(doc(alice,'players','alice','saves','other'),data));
  await assertFails(setDoc(doc(alice,'anything','else'),data));
  await assertSucceeds(setDoc(ref(alice),{...data,revision:4})); // coalesced offline revisions
  await assertSucceeds(setDoc(ref(bob,'bob'),data));
  const root=globalThis;
  vm.runInThisContext(readFileSync('../web/little_leaf_firebase.js','utf8'));
  const sdk={doc,getDocFromServer,runTransaction,serverTimestamp};
  const raceDB=env.authenticatedContext('race',google).firestore();
  await assertSucceeds(setDoc(ownerRef(raceDB,'race'),initialSession));
  const ownership={assertActive:()=>({writerId,writerEpoch:1}),sessionRef:ownerRef(raceDB,'race')};
  const remote=root.LittleLeafFirebase.createRemote(raceDB,sdk,ownership),guard=()=>{};
  assert.equal(await remote.read('race'),null);
  await remote.compareAndSet('race',null,data,guard);
  await remote.compareAndSet('race',null,data,guard); // ambiguous prior acknowledgment is idempotent
  const updates=await Promise.allSettled([
    remote.compareAndSet('race',data.digest,{...data,revision:2,digest:'b'.repeat(64)},guard),
    remote.compareAndSet('race',data.digest,{...data,revision:2,digest:'c'.repeat(64)},guard)
  ]);
  assert.equal(updates.filter(r=>r.status==='fulfilled').length,1,'only one stale-base transaction wins');
  assert(['REVISION_CONFLICT','permission-denied'].includes(updates.find(r=>r.status==='rejected').reason.code),'CAS or monotonic server rules reject loser');
  assert.equal((await remote.read('race')).revision,2);
  await assert.rejects(remote.compareAndSet('race',null,data,()=>{throw Error('account changed');}),/account changed/);
  console.log('Actual adapter Firestore emulator CAS/race/idempotency checks passed.');
  console.log('Strict Firestore emulator rules checks passed: synthetic demo project only.');
} finally {await env.cleanup();}
