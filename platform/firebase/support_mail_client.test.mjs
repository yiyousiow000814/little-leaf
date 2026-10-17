import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import fixtureIDB from '../../tests/fixtures/save_log_idb_fixture.js';
import {createSupportMailService} from './support_mail_service.mjs';
import {fixture,auth,key,profileId,writerId,mailId,document,sign} from './support_storage_fixture.mjs';

const root={crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(readFileSync(new URL(`../web/${name}.js`,import.meta.url),'utf8'),root);
const {FixtureIDB}=fixtureIDB,api=root.LittleLeafFirebase,codec=root.LittleLeafAuthorityCodec;
const {db,documents,original}=fixture();let time=1000,claims=0,saves=0,loseClaimResponse=true,loseSaveResponse=false;
const service=createSupportMailService({db,enabled:true,now:()=>1000});
const uid=auth.auth.uid,fence={writerId,writerEpoch:1},owned={assertActive:()=>fence,async renew(){},close(){}};
const journal=await api.openJournal(new FixtureIDB(),{cloudOnly:true});
const cloud=()=>documents.get(key('saves/cafe'));
const remote={async read(){return structuredClone(cloud());},async compareAndSet(_uid,base,next,check){
  saves++;check();if(cloud().digest===next.digest)return;assert.equal(base,cloud().digest);
  const candidate=JSON.parse(next.record);
  if(candidate.format===3)await service.commitProtectedSave(auth,{profileId,revision:cloud().revision,digest:base,candidate,...fence});
  else documents.set(key('saves/cafe'),document(candidate));
  if(loseSaveResponse){loseSaveResponse=false;throw Object.assign(Error('Synthetic ACK response loss'),{code:'OFFLINE'});}
}};
let announceClaim,releaseClaim;
const claimStarted=new Promise(resolve=>{announceClaim=resolve;}),claimGate=new Promise(resolve=>{releaseClaim=resolve;});
const supportClaim=async request=>{
  claims++;announceClaim();await claimGate;assert.deepEqual({writerId:request.writerId,writerEpoch:request.writerEpoch},fence);
  const result=await service.claimMail(auth,request);
  if(loseClaimResponse){loseClaimResponse=false;throw Object.assign(Error('Synthetic claim response loss'),{code:'OFFLINE'});}
  return result;
};
const create=()=>api.createClient({uid,codec,remote,journal,ownership:owned,cloudStartup:true,now:()=>time,
  currentUid:()=>uid,status(){},supportClaim});
const client=create();assert.equal((await client.boot()).ok,true);
const preparing=client.commit(original.payload,1,profileId);
assert.equal((await client.claimSupportMail(mailId,profileId,1)).code,'SAVE_BUSY','claim cannot begin during a pending native save transition');
assert.equal((await preparing).ok,true);
assert.equal((await journal.read(uid)).pending,true);
const claiming=client.claimSupportMail(mailId,profileId,2);await claimStarted;
assert.equal((await client.commit(original.payload,2,profileId)).code,'SAVE_BUSY','ordinary save cannot interleave a claim');
assert.equal((await client.claimSupportMail(mailId,profileId,2)).code,'SAVE_BUSY','duplicate concurrent client claim is serialized');
assert.equal((await client.saveForUpdate(original.payload,2,profileId)).code,'SAVE_BUSY','update snapshot cannot interleave an authoritative claim');
releaseClaim();const claimed=await claiming;
assert.equal(claimed.ok,true);assert.equal(claims,2,'lost claim response retries the same operation');
assert.equal(JSON.parse(claimed.payload).coins,100);assert.equal(JSON.parse(claimed.payload).storage.items.length,2);
assert.equal((await journal.read(uid)).record.digest,cloud().digest);assert.equal((await journal.read(uid)).pending,false);
assert.equal(Object.hasOwn(claimed,'stock'),false,'the claimed payload is the only owned-stock authority');
assert.equal(typeof client.commitGiftDecoration,'undefined','there is no parallel gift placement save');
const before=JSON.parse(claimed.payload),stored=structuredClone(before),bought=stored.items.find(item=>item.kind==='stove');
stored.items=stored.items.filter(item=>item.id!==bought.id);stored.storage.items.push(bought);
let committed=await client.commit(JSON.stringify(stored),3,profileId);assert.equal(committed.ok,true);
let pending=await journal.read(uid);assert.equal(pending.record.mailState.stockRevision,2);
assert.equal(pending.giftPlacement,undefined,'normal Storage Apply uses the ordinary journal only');
const restored=structuredClone(stored);restored.storage.items=restored.storage.items.filter(item=>item.id!==bought.id);restored.items.push(bought);
committed=await client.commit(JSON.stringify(restored),4,profileId);assert.equal(committed.ok,true);
pending=await journal.read(uid);assert.equal(pending.record.mailState.stockRevision,3);
assert.equal(codec.storageFingerprint(JSON.parse(pending.record.payload)),codec.storageFingerprint(before),'coalesced round trip has original final stock');
time+=31000;await client.sync();assert.equal((await journal.read(uid)).pending,false);
assert.equal(JSON.parse(cloud().record).mailState.stockRevision,3,'server accepts the coalesced +2 round trip');
const unpacked=structuredClone(restored),free=unpacked.storage.items.shift();unpacked.items.push({...free,x:8,z:8});
committed=await client.commit(JSON.stringify(unpacked),5,profileId);assert.equal(committed.ok,true);
loseSaveResponse=true;time+=31000;await client.sync();
pending=await journal.read(uid);assert.equal(pending.pending,true,'unconfirmed cloud ACK never becomes a local receipt');
assert.equal(pending.record.digest,cloud().digest,'the server committed before synthetic response loss');
assert(pending.uploading,'the exact upload remains journaled for replay');
time+=31000;await client.sync();assert.equal((await journal.read(uid)).pending,false,'ordinary exact-snapshot replay recovers the ACK');
assert.equal(JSON.parse(cloud().record).mailState.stockRevision,4);
assert.equal(JSON.parse(JSON.parse(cloud().record).payload).coins,100,'store and unpack do not charge or refund');
client.close();const reopened=create();assert.equal((await reopened.boot()).ok,true);
assert.equal((await journal.read(uid)).record.digest,cloud().digest,'server authority survives refresh');
const confirmedBeforeDuplicate=await journal.read(uid),confirmedCloud=cloud().digest;
const repeated=await reopened.claimSupportMail(mailId,profileId,confirmedBeforeDuplicate.record.revision);
assert.equal(repeated.code,'CLAIM_RECOVERY_REQUIRED','a later independently repeated Claim is not the original frozen operation');
assert.equal(repeated.uncertain,true,'mismatched current-head receipt freezes for an explicit cloud reload');
assert.deepEqual(await journal.read(uid),confirmedBeforeDuplicate,'no same-revision or arbitrary newer payload is installed');
assert.equal(cloud().digest,confirmedCloud,'duplicate Claim never credits or rewrites the current authority');
assert.equal((await reopened.commit(confirmedBeforeDuplicate.record.payload,confirmedBeforeDuplicate.record.revision,profileId)).code,'NOT_READY');

// Old draft-only placement intent is evidence, not a request to mint inventory.
const current=await journal.read(uid),legacy={...current,pending:true,giftPlacement:{operationId:'55555555-5555-4555-8555-555555555555',consumed:[{itemId:1,catalogId:'plant'}]}};
await journal.replace(uid,current,legacy);reopened.close();const blocked=create(),savedCloud=cloud().digest;
assert.equal((await blocked.boot()).code,'STORAGE_REVIEW_REQUIRED');
assert.equal(cloud().digest,savedCloud);assert.deepEqual(await journal.read(uid),legacy);
assert.equal(blocked.recoverySnapshot().canExport,true);
const exported=await blocked.exportRecovery();assert.equal(exported.ok,true);
assert.equal(JSON.parse(exported.text).pendingEntry.giftPlacement.operationId,legacy.giftPlacement.operationId);
assert.equal(typeof blocked.resumeGiftPlacement,'undefined','legacy operation cannot auto-replay through a new schema');
blocked.close();assert(saves>=4);
// Genuine old draft authority is envelope3/save15, not save17 with an old
// marker. Startup must quarantine its intent before refusing it for gameplay.
const oldCloudRecord=sign({...original,format:3,revision:2,mailState:{schema:1,claimSequence:1,stockRevision:1}});
const oldPayload=JSON.parse(original.payload),oldItemId=oldPayload.next_item_id++;
oldPayload.items.push({id:oldItemId,kind:'plant',x:8,z:8,rot:0});
const oldPendingRecord=sign({...oldCloudRecord,revision:3,payload:JSON.stringify(oldPayload),mailState:{...oldCloudRecord.mailState,stockRevision:2}});
const oldIntent={base:oldCloudRecord.digest,pending:true,record:oldPendingRecord,
  preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]},
  giftPlacement:{operationId:'77777777-7777-4777-8777-777777777777',consumed:[{itemId:oldItemId,catalogId:'plant'}]}};
async function legacyProbe({intent=oldIntent,cloudDoc=document(oldCloudRecord),switchOnRead=false}={}) {
  const saved=await api.openJournal(new FixtureIDB(),{cloudOnly:true});await saved.replace(uid,null,intent);
  let localReads=0,localWrites=0,remoteWrites=0,activeUid=uid;
  const wrapped={...saved,async read(account){localReads++;assert.equal(account,uid);return saved.read(account);},
    async replace(){localWrites++;throw Error('Quarantine must never replace the journal');}};
  const remote={async read(account){assert.equal(account,uid);if(switchOnRead)activeUid='different-account';return structuredClone(cloudDoc);},
    async compareAndSet(){remoteWrites++;throw Error('Quarantine must never upload');}};
  const client=api.createClient({uid,codec,remote,journal:wrapped,ownership:owned,cloudStartup:true,now:()=>time,currentUid:()=>activeUid,status(){}});
  const boot=await client.boot();
  return {saved,client,boot,reads:()=>localReads,writes:()=>localWrites+remoteWrites,switchAccount:()=>{activeUid='different-account';}};
}
const old=await legacyProbe();
assert.equal(old.boot.code,'STORAGE_REVIEW_REQUIRED');assert.equal(old.client.recoverySnapshot().canExport,true);
assert.equal(old.client.recoverySnapshot().giftPlacementPending,true);assert.equal(old.client.recoverySnapshot().available,false);
const oldExport=await old.client.exportRecovery();assert.equal(oldExport.ok,true);
assert.deepEqual(JSON.parse(oldExport.text).pendingEntry,oldIntent,'legacy export preserves the exact original intent and payload bytes');
assert.equal((await old.saved.read(uid)).record.payload,oldIntent.record.payload);
await old.client.sync();assert.equal(old.writes(),0);assert.deepEqual(await old.saved.read(uid),oldIntent);
assert.equal((await old.client.commit(original.payload,3,profileId)).code,'NOT_READY','quarantine never makes old state playable');
old.switchAccount();assert.equal((await old.client.exportRecovery()).code,'NOT_READY','account changes cannot export quarantined bytes');old.client.close();
for(const mutate of [intent=>intent.giftPlacement.operationId='invalid',intent=>intent.record.digest='0'.repeat(64)]) {
  const malformed=structuredClone(oldIntent);mutate(malformed);const probe=await legacyProbe({intent:malformed});
  assert.equal(probe.boot.code,'CORRUPT_AUTHORITY');assert.equal(probe.client.recoverySnapshot().canExport,false);
  assert.equal((await probe.client.exportRecovery()).code,'RECOVERY_UNAVAILABLE');assert.equal(probe.writes(),0);
  assert.deepEqual(await probe.saved.read(uid),malformed);probe.client.close();
}
const badCloud=await legacyProbe({cloudDoc:{...document(oldCloudRecord),digest:'0'.repeat(64)}});
assert.equal(badCloud.boot.code,'CORRUPT_AUTHORITY');assert.equal(badCloud.reads(),0,'unverified cloud identity never opens legacy quarantine');
assert.equal(badCloud.client.recoverySnapshot().canExport,false);assert.equal(badCloud.writes(),0);badCloud.client.close();
const switched=await legacyProbe({switchOnRead:true});assert.equal(switched.boot.code,'NOT_READY');assert.equal(switched.reads(),0);
assert.equal((await switched.client.exportRecovery()).code,'NOT_READY');assert.equal(switched.writes(),0);switched.client.close();
const stale=await legacyProbe(),changed=structuredClone(oldIntent);changed.giftPlacement.operationId='88888888-8888-4888-8888-888888888888';
await stale.saved.replace(uid,oldIntent,changed);
assert.equal((await stale.client.exportRecovery()).code,'REVISION_CONFLICT','another tab cannot silently substitute a different quarantined intent');
assert.equal(stale.writes(),0);assert.deepEqual(await stale.saved.read(uid),changed);stale.client.close();
console.log('Support client: synthetic claim/journal/ACK recovery and genuine envelope3/save15 intent quarantine/export passed; malformed/cloud-identity/account/stale-copy cases remain blocked without writes. Real browser/Auth/Firestore not exercised.');
