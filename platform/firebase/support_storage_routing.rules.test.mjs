// Real Firestore emulator + production browser adapter/codec/client. Auth is a
// rules test context and the journal is FixtureIDB, not real browser IndexedDB.
// No Functions transport, browser UI or production service is exercised.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import vm from 'node:vm';
import {initializeTestEnvironment,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDocFromServer,runTransaction,serverTimestamp} from 'firebase/firestore';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import fixtureIDB from '../../tests/fixtures/save_log_idb_fixture.js';
import {fixture,document,sign,writerId,profileId,mailId} from './support_storage_fixture.mjs';
import {createSupportMailService} from './support_mail_service.mjs';
for(const name of ['little_leaf_vault','little_leaf_firebase'])
  vm.runInThisContext(readFileSync(new URL(`../web/${name}.js`,import.meta.url),'utf8'));
const api=globalThis.LittleLeafFirebase,codec=globalThis.LittleLeafAuthorityCodec;
const oldRules=readFileSync(new URL('../../tests/fixtures/storage-current-main.rules',import.meta.url),'utf8');
assert.equal(createHash('sha256').update(oldRules).digest('hex'),'54b8c54ca686839b0dde12ef2de5aaf6f3dc9ed4410bb052dcf5c5e89e3895f5',
  'unchanged main63642fdd rules fixture');
assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/,'Local emulator only');
const app=initializeApp({projectId:'demo-little-leaf'}),admin=getFirestore(app);
const service=createSupportMailService({db:admin,enabled:true});
const google={firebase:{sign_in_provider:'google.com'}},fence={writerId,writerEpoch:1};
let completed=0;
for(const [policy,rules] of [['current-main',oldRules],['candidate',readFileSync('firestore.rules','utf8')]]){
  const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules}});
  try{
    await env.clearFirestore();
    async function setup(label,version=15){
      const uid=`routing-${policy}-${label}`,db=env.authenticatedContext(uid,google).firestore();
      const {original}=fixture(),payload=JSON.parse(original.payload);
      if(version===16){payload.version=16;payload.layout_hold_format='little_leaf.layout_hold.v1';
        payload.runtime.layout_hold_format=payload.layout_hold_format;
        payload.runtime.service.layout_hold={format:payload.layout_hold_format,hosts:[{id:payload.next_item_id++,kind:'stove',x:1,z:1,rot:0}],guests:[],staff:[],dishes:[],floor:[]};}
      const record=sign({...original,payload:JSON.stringify(payload),campaigns:{'existing-compensation':{status:'granted',coins:1000,revision:1,grantedAt:1}}});
      const sessionRef=doc(db,'players',uid,'session','owner'),saveRef=doc(db,'players',uid,'saves','cafe');
      await setDoc(sessionRef,{schema:1,owner:writerId,epoch:1,device:'Mac',updatedAt:serverTimestamp(),request:null,ack:null});
      await setDoc(saveRef,document(record));
      let calls=0,sets=0,controlReads=0,time=1000,hook=async()=>{};
      const ownership={sessionRef,assertActive:()=>fence,async renew(){},close(){}};
      const sdk={doc,async getDocFromServer(ref){if(ref.path.includes('/saveControl/'))controlReads++;return getDocFromServer(ref);},
        runTransaction(db,action){return runTransaction(db,tx=>action({async get(ref){const snapshot=await tx.get(ref);await hook(ref,snapshot);return snapshot;},
          set(ref,value){sets++;tx.set(ref,value);}}));}};
      const protectedCommit=async request=>{calls++;return service.commitProtectedSave({auth:{uid,token:google}},request);};
      const journal=await api.openJournal(new fixtureIDB.FixtureIDB(),{cloudOnly:true});
      const remote=api.createRemote(db,sdk,ownership,protectedCommit);
      const create=()=>api.createClient({uid,codec,remote,journal,ownership,cloudStartup:true,currentUid:()=>uid,status(){},now:()=>time});
      return {uid,db,record,payload,sessionRef,saveRef,journal,remote,create,ownership,sdk,
        counts:()=>({calls,sets,controlReads}),tick:()=>time+=31000,setHook:value=>hook=value,
        head:async()=>JSON.parse((await getDocFromServer(saveRef)).data().record),
        claim:async base=>{
          await admin.doc(`players/${uid}/mail/${mailId}`).set({schema:1,mailId,issueId:mailId,profileId,status:'unclaimed',coins:60,
            items:[{catalogId:'plant',quantity:1,catalogRevision:1}],claimedAt:null});
          return service.claimMail({auth:{uid,token:google}},{mailId,operationId:'33333333-3333-4333-8333-333333333333',profileId,
            revision:base.revision,digest:base.digest,...fence});
        }};
    }
    const storedPayload=record=>{
      const data=JSON.parse(record.payload),item=data.items.find(item=>item.kind==='stove');assert(item);
      data.version=17;data.storage_format='little_leaf.storage.v1';data.storage=data.storage||{items:[],dining_sets:[]};
      data.items=data.items.filter(value=>value.id!==item.id);data.storage.items.push(item);return data;
    };
    for(const version of [15,16]){
      const h=await setup(`v${version}`,version),client=h.create();assert.equal((await client.boot()).ok,true);
      if(policy==='current-main')await assertFails(getDocFromServer(doc(h.db,'players',h.uid,'saveControl','protocol')));
      const stored=storedPayload(h.record),saved=await client.commit(JSON.stringify(stored),1,profileId);assert.equal(saved.ok,true);
      await client.sync();let entry=await h.journal.read(h.uid);assert.equal(entry.pending,false,'ordinary Storage reaches real cloud ACK');
      let cloud=await h.head();assert.equal(cloud.format,2);assert.deepEqual(cloud.campaigns,h.record.campaigns);
      assert.equal(JSON.parse(cloud.payload).coins,h.payload.coins);assert.deepEqual(JSON.parse(cloud.payload).storage,stored.storage);
      assert.deepEqual(JSON.parse(cloud.payload).runtime,h.payload.runtime,'held service bytes survive the payload-version upgrade');
      client.close();const reloaded=h.create();assert.equal((await reloaded.boot()).payload,JSON.stringify(stored));
      const unpacked=structuredClone(stored),item=unpacked.storage.items.pop();unpacked.items.push(item);
      assert.equal((await reloaded.commit(JSON.stringify(unpacked),2,profileId)).ok,true);h.tick();await reloaded.sync();
      entry=await h.journal.read(h.uid);assert.equal(entry.pending,false);cloud=await h.head();
      const final=JSON.parse(cloud.payload);assert.equal(final.storage.items.length,0);assert.equal(final.coins,h.payload.coins);
      assert.deepEqual(final.items.slice().sort((a,b)=>a.id-b.id),h.payload.items.slice().sort((a,b)=>a.id-b.id));
      assert.equal(final.next_item_id,h.payload.next_item_id);assert.deepEqual(cloud.campaigns,h.record.campaigns);
      assert.equal(h.counts().calls,0);assert.equal(h.counts().controlReads,0,'ordinary route never probes the denied path');
      reloaded.close();completed++;
    }
    // Real denied session/rules write keeps pending progress, no callable fallback.
    {
      const h=await setup('expired'),client=h.create();assert.equal((await client.boot()).ok,true);
      await client.commit(JSON.stringify(storedPayload(h.record)),1,profileId);
      await admin.doc(`players/${h.uid}/session/owner`).update({updatedAt:new Date(Date.now()-120000)});
      await client.sync();assert.equal((await h.journal.read(h.uid)).pending,true);
      assert.equal((await h.head()).digest,h.record.digest);assert.equal(h.counts().calls,0);client.close();completed++;
    }
    {
      const h=await setup('foreign'),other=env.authenticatedContext('different-account',google).firestore();
      const wrong=api.createRemote(other,{doc,getDocFromServer,runTransaction});
      await assert.rejects(wrong.compareAndSet(h.uid,h.record.digest,document(sign({...h.record,revision:2})),()=>{}),{code:'permission-denied'});
      assert.equal((await h.head()).digest,h.record.digest);completed++;
    }
    if(policy==='candidate'){
      // Actual server Claim between transaction read and write changes authority.
      const h=await setup('claim-race'),candidate=document(sign({...h.record,revision:2,payload:JSON.stringify(storedPayload(h.record))}));
      let claimed=false;
      h.setHook(async ref=>{if(ref.path===h.saveRef.path&&!claimed){claimed=true;await h.claim(h.record);}});
      await assert.rejects(h.remote.compareAndSet(h.uid,h.record.digest,candidate,()=>{}),
        problem=>['PROTOCOL_CHANGED','permission-denied'].includes(problem.code));
      const protectedHead=await h.head();assert.equal(protectedHead.format,3);assert.equal(JSON.parse(protectedHead.payload).coins,h.payload.coins+60);
      assert.equal(h.counts().calls,0,'ordinary attempt never retries via protected callable after a race');completed++;
      const old=await setup('control-race');let enrolled=false;
      old.setHook(async ref=>{if(ref.path===old.saveRef.path&&!enrolled){enrolled=true;
        await admin.doc(`players/${old.uid}/saveControl/protocol`).set({schema:1,version:1,claimSequence:1,stockRevision:0});}});
      await assert.rejects(old.remote.compareAndSet(old.uid,old.record.digest,document(sign({...old.record,revision:2})),()=>{}),{code:'permission-denied'});
      assert.equal((await old.head()).digest,old.record.digest);assert.equal(old.counts().calls,0);completed++;
      h.setHook(async()=>{});
      const unpacked=JSON.parse(protectedHead.payload),gift=unpacked.storage.items.pop();unpacked.items.push({...gift,x:8,z:8});
      const protectedNext=sign({...protectedHead,revision:protectedHead.revision+1,payload:JSON.stringify(unpacked),
        mailState:{...protectedHead.mailState,stockRevision:protectedHead.mailState.stockRevision+1}});
      const beforeSets=h.counts().sets;await h.remote.compareAndSet(h.uid,protectedHead.digest,document(protectedNext),()=>{});
      assert.equal(h.counts().calls,1);assert.equal(h.counts().sets,beforeSets,'protected route performs no direct write');
      assert.equal((await h.head()).digest,protectedNext.digest);completed++;
      const downgrade={...protectedNext,format:2,revision:protectedNext.revision+1};delete downgrade.mailState;
      await assert.rejects(h.remote.compareAndSet(h.uid,protectedNext.digest,document(sign(downgrade)),()=>{}),{code:'PROTOCOL_CHANGED'});
      const absent=api.createRemote(h.db,h.sdk,h.ownership);
      await assert.rejects(absent.compareAndSet(h.uid,protectedNext.digest,document(sign({...protectedNext,revision:protectedNext.revision+1})),()=>{}),{code:'UPDATE_REQUIRED'});
      assert.equal((await h.head()).digest,protectedNext.digest);completed++;
      const stale=await setup('stale'),winner=sign({...stale.record,revision:2});
      await stale.remote.compareAndSet(stale.uid,stale.record.digest,document(winner),()=>{});
      await assert.rejects(stale.remote.compareAndSet(stale.uid,stale.record.digest,document(sign({...stale.record,revision:3})),()=>{}),{code:'REVISION_CONFLICT'});
      assert.equal((await stale.head()).digest,winner.digest);completed++;
    }
    console.log(`Storage routing real rules: ${policy} passed.`);
  }finally{await env.clearFirestore();await env.cleanup();}
}
await deleteApp(app);
console.log(JSON.stringify({passed:true,cases:completed,real_firestore_rules:true,real_sdk:true,real_indexeddb:false,real_functions_transport:false,
  production_access:false,node:process.version,policies:['main63642fdd immutable fixture','unchanged R2 candidate']}));
