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
let cloud=document(initial),claims=0,placements=0,losePlaceResponse=true;
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
  const before=cloud.digest;cloud=document(request.candidate);
  if(losePlaceResponse){losePlaceResponse=false;throw Object.assign(Error('Response lost'),{code:'OFFLINE'});}
  return {status:'placed',record:request.candidate,stock:{schema:1,revision:2,counts:{plant:0}},
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
const placed=await client.commitGiftDecoration(JSON.stringify(nextPayload),3,profileId,[{itemId,catalogId:'plant'}]);
assert.equal(placed.ok,false);assert.equal(placed.uncertain,true);
assert.equal(placements,1);assert.equal((await journal.read(uid)).pending,true);
client.close();
const reopened=create(),recovered=await reopened.boot();
assert.equal(recovered.ok,true);assert.equal(recovered.revision,4);
assert.equal((await journal.read(uid)).pending,false);
assert.equal(placements,1);assert.equal(claims,1);
console.log('Support client: authoritative claim and exact gift placement response-loss recovery passed.');
