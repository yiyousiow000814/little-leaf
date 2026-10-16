import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {grant} from './support_mail_contract.mjs';
import fixture from '../../tests/fixtures/save_log_idb_fixture.js';

const root={crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])
  vm.runInNewContext(readFileSync(new URL(`../web/${name}.js`,import.meta.url),'utf8'),root);
const {FixtureIDB}=fixture,api=root.LittleLeafFirebase,codec=root.LittleLeafAuthorityCodec;
const payload=readFileSync(new URL('../../tests/fixtures/unified_building_candidate.json',import.meta.url),'utf8');
const uid='syntheticRecipient20',profileId='22222222-2222-4222-8222-222222222222';
const mailId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',fence={writerId:'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',writerEpoch:1};
const owned={assertActive:()=>fence,async renew(){},close(){}};
const document=record=>({schema:1,profileId:record.profileId,revision:record.revision,digest:record.digest,record:JSON.stringify(record)});
const initial={format:2,profileId,revision:2,createdAt:1,updatedAt:2,payload,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
initial.digest=await codec.hash(codec.fingerprint(initial));
let cloud=document(initial),claims=0,placements=0,losePlaceResponse=true,failBeforePlace=false;
const journal=await api.openJournal(new FixtureIDB(),{cloudOnly:true});
const remote={async read(){return structuredClone(cloud);},async compareAndSet(_uid,base,next,check){
  check();assert.equal(base,cloud.digest);cloud=document(next);
}};
const supportClaim=async request=>{
  claims++;assert.deepEqual({writerId:request.writerId,writerEpoch:request.writerEpoch},fence);
  assert.equal(request.digest,cloud.digest);
  const old=JSON.parse(cloud.record),awarded=grant(old,{profileId,status:'unclaimed',coins:25,
    items:[{catalogId:'plant',quantity:1,catalogRevision:1}]},{schema:1,revision:0,counts:{}},1000);
  cloud=document(awarded.record);
  return {status:'claimed',record:awarded.record,stock:awarded.stock,
    receipt:{fromDigest:old.digest,toDigest:awarded.record.digest}};
};
const supportPlace=async request=>{
  placements++;assert.equal(request.digest,cloud.digest);
  assert.equal(request.consumed.length,1);
  if(failBeforePlace)throw Object.assign(Error('Network unavailable before server commit'),{code:'OFFLINE'});
  const before=cloud.digest;cloud=document(request.candidate);
  if(losePlaceResponse){losePlaceResponse=false;throw Object.assign(Error('Response lost'),{code:'OFFLINE'});}
  return {status:'placed',record:request.candidate,stock:{schema:1,revision:request.candidate.mailState.stockRevision,counts:{plant:0}},
    receipt:{fromDigest:before,toDigest:request.candidate.digest}};
};
const create=()=>api.createClient({uid,codec,remote,journal,ownership:owned,cloudStartup:true,
  currentUid:()=>uid,status(){},supportClaim,supportPlace});
const client=create(),boot=await client.boot();assert.equal(boot.ok,true);
const claimed=await client.claimSupportMail(mailId,profileId,2);
assert.equal(claimed.ok,true);assert.equal(claims,1);
assert.equal(JSON.parse(claimed.payload).coins,JSON.parse(payload).coins+25);
assert.equal((await journal.read(uid)).record.digest,cloud.digest);
const nextPayload=JSON.parse(claimed.payload),itemId=900001;
nextPayload.items.push({id:itemId,kind:'plant',x:5,z:4,rot:0});
const ordinary=await client.commit(claimed.payload,3,profileId);
assert.equal(ordinary.ok,true);
assert.equal((await journal.read(uid)).pending,true);
assert.equal((await client.prepareGiftDecoration(4,profileId)).ok,true,'preflight confirms pending ordinary progress before draft commit');
assert.equal((await journal.read(uid)).pending,false);
const placed=await client.commitGiftDecoration(JSON.stringify(nextPayload),4,profileId,[{itemId,catalogId:'plant'}]);
assert.equal(placed.ok,false);assert.equal(placed.uncertain,true);
assert.equal(placements,1);assert.equal((await journal.read(uid)).pending,true);
client.close();
const reopened=create(),recovered=await reopened.boot();
assert.equal(recovered.ok,true);assert.equal(recovered.revision,5);
assert.equal((await journal.read(uid)).pending,false);
assert.equal(placements,1);assert.equal(claims,1);
const second=JSON.parse(recovered.payload),secondItem=900002;
second.items.push({id:secondItem,kind:'plant',x:6,z:4,rot:0});
failBeforePlace=true;
const attempted=await reopened.commitGiftDecoration(JSON.stringify(second),5,profileId,[{itemId:secondItem,catalogId:'plant'}]);
assert.equal(attempted.ok,false);assert.equal(attempted.uncertain,true);
const pending=(await journal.read(uid)).record.digest,unchangedCloud=cloud.digest;
reopened.close();
const blocked=create(),blockedBoot=await blocked.boot();
assert.equal(blockedBoot.code,'GIFT_RECOVERY_REQUIRED','startup must not auto-upload an unconfirmed placement');
assert.equal(cloud.digest,unchangedCloud);assert.equal((await journal.read(uid)).record.digest,pending);
assert.equal(blocked.recoverySnapshot().canExport,true);
assert.equal(blocked.recoverySnapshot().giftPlacementPending,true);
const exported=await blocked.exportRecovery();
assert.equal(exported.ok,true,'the pending exact intent remains exportable before confirmation');
assert.equal(JSON.parse(exported.text).pendingEntry.record.digest,pending);
failBeforePlace=false;
const explicitlyResumed=await blocked.resumeGiftPlacement();
assert.equal(explicitlyResumed.ok,true,'an explicit recovery action retries the same pending placement');
assert.equal(explicitlyResumed.revision,6);assert.equal((await journal.read(uid)).pending,false);
blocked.close();
console.log('Support client: claim, ordinary-save preflight, no silent upload and explicit gift recovery passed.');
