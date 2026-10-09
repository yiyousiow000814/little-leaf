'use strict';
// Synthetic adapter contracts. Real IndexedDB atomicity is covered separately by
// firebase_recovery_browser.js; neither suite uses a real Firebase account.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto,TextEncoder};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(fs.readFileSync(`web/${name}.js`,'utf8'),root);
const codec=root.LittleLeafAuthorityCodec,api=root.LittleLeafFirebase,fixture=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const clone=x=>x==null?null:JSON.parse(JSON.stringify(x)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b),fail=code=>Object.assign(Error(code),{code});
async function record(revision,coins,profileId=webcrypto.randomUUID()){
  const r={format:2,profileId,revision,createdAt:1,updatedAt:revision+10,payload:JSON.stringify({...JSON.parse(fixture),coins}),digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
  r.digest=await codec.hash(codec.fingerprint(r));return r;
}
const doc=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
async function harness(){
  const profile=webcrypto.randomUUID(),base=await record(1,100,profile),uploading=await record(2,110,profile),latest=await record(3,120,profile),cloudRecord=await record(4,900,profile);
  const original={base:base.digest,pending:true,record:latest,uploading:{base:base.digest,record:uploading}};
  let uid='synthetic-account',local=clone(original),backup=null,cloud=doc(cloudRecord),reads=0,writes=0,readHook=null,recoverHook=null,storageFailure=false;
  const journal={async read(){return clone(local);},async readRecoveryBackup(){return clone(backup);},async replace(id,expected,next){assert.equal(id,'synthetic-account');if(!same(local,expected))throw fail('REVISION_CONFLICT');local=clone(next);},async recover(id,expected,next,guard){
    assert.equal(id,'synthetic-account');if(recoverHook)await recoverHook();guard();
    if(backup&&!same(backup,expected))throw fail('RECOVERY_ARCHIVE_FULL');
    if(same(local,next)&&same(backup,expected))return;
    if(!same(local,expected))throw fail('REVISION_CONFLICT');
    if(storageFailure)throw fail('STORAGE_ERROR');backup=clone(expected);local=clone(next);
  }};
  const remote={async read(id){assert.equal(id,'synthetic-account');reads++;if(readHook)await readHook();return clone(cloud);},async compareAndSet(){writes++;throw Error('Recovery unexpectedly wrote cloud');}};
  const states=[],make=()=>api.createClient({uid:'synthetic-account',codec,journal,remote,currentUid:()=>uid,status:s=>states.push(s)});
  return {c:make(),make,original,cloudRecord,states,journal,local:()=>clone(local),backup:()=>clone(backup),cloud:()=>clone(cloud),writes:()=>writes,reads:()=>reads,setCloud:x=>cloud=x,setLocal:x=>local=x,setBackup:x=>backup=x,setUid:x=>uid=x,readHook:x=>readHook=x,recoverHook:x=>recoverHook=x,storageFailure:x=>storageFailure=x};
}
(async()=>{
  let h=await harness(),b=await h.c.boot(),s=h.c.recoverySnapshot();
  assert.equal(b.code,'REVISION_CONFLICT');assert.equal(s.available,true);assert.equal(s.cloudRevision,4);assert.equal(s.pendingRevision,3);assert.equal(s.expectedCloudDigest,h.cloudRecord.digest);assert.equal(s.canExport,true);assert.equal(h.writes(),0);assert.deepEqual(h.local(),h.original);
  let exported=await h.c.exportRecovery();assert(exported.ok);assert.deepEqual(JSON.parse(exported.text).pendingEntry,h.original);assert(!exported.text.includes('synthetic-account'));
  const before=h.cloud(),loaded=await h.c.recoverCloud(s.expectedCloudDigest);assert(loaded.ok);assert.equal(loaded.revision,4);assert.equal(loaded.payload,h.cloudRecord.payload);assert.equal(loaded.profileId,h.cloudRecord.profileId);assert.deepEqual(h.cloud(),before);assert.equal(h.writes(),0);assert.deepEqual(h.backup(),h.original);assert.equal(h.local().pending,false);assert.equal(h.local().base,h.cloudRecord.digest);assert.equal((await h.c.boot()).revision,4);
  assert((await h.c.recoverCloud(s.expectedCloudDigest)).ok);assert.deepEqual(h.backup(),h.original);assert.equal(h.c.recoverySnapshot().available,false);assert.equal(h.c.recoverySnapshot().canExport,true);
  assert.deepEqual(JSON.parse((await h.c.exportRecovery()).text).pendingEntry,h.original);
  const reload=h.make();assert((await reload.boot()).ok);assert(reload.recoverySnapshot().canExport);assert.deepEqual(JSON.parse((await reload.exportRecovery()).text).pendingEntry,h.original);
  assert((await h.c.commit(h.cloudRecord.payload,4,h.cloudRecord.profileId)).ok);assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_UNAVAILABLE');assert.equal(h.local().record.revision,5);assert.deepEqual(h.backup(),h.original);

  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();const newer=await record(5,950,h.cloudRecord.profileId);h.setCloud(doc(newer));assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_CHANGED');assert.equal(h.c.recoverySnapshot().expectedCloudDigest,newer.digest);assert.equal(h.c.recoverySnapshot().cloudRevision,5);assert.deepEqual(h.local(),h.original);assert.equal(h.backup(),null);assert.equal((await h.c.recoverCloud(newer.digest)).revision,5);
  h=await harness();await h.c.boot();assert.equal((await h.c.recoverCloud(null)).code,'RECOVERY_CONFIRMATION_REQUIRED');assert.deepEqual(h.local(),h.original);

  for(const cloud of [null,{schema:1,record:'bad-json'}]){
    h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.setCloud(cloud);
    assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,cloud?'CORRUPT_AUTHORITY':'RECOVERY_MISSING');assert.equal(h.c.recoverySnapshot().available,false);assert.equal(h.c.recoverySnapshot().canExport,true);assert((await h.c.exportRecovery()).ok);assert.deepEqual(h.local(),h.original);assert.equal(h.backup(),null);
    h.setCloud(doc(h.cloudRecord));assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_CHANGED');assert((await h.c.recoverCloud(s.expectedCloudDigest)).ok);
    h=await harness();h.setCloud(cloud);assert.equal((await h.c.boot()).code,'CORRUPT_AUTHORITY');assert.equal(h.c.recoverySnapshot().available,false);assert((await h.c.exportRecovery()).ok);assert.deepEqual(h.local(),h.original);
  }
  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.readHook(async()=>{throw fail('OFFLINE');});assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'OFFLINE');assert.deepEqual(h.local(),h.original);h.readHook(null);assert((await h.c.recoverCloud(s.expectedCloudDigest)).ok);
  h=await harness();h.readHook(async()=>{throw fail('OFFLINE');});assert((await h.c.boot()).ok);assert.equal(h.c.recoverySnapshot().available,false);assert.deepEqual(h.local(),h.original);

  h=await harness();const older={...h.original,record:await record(2,105,h.original.record.profileId),uploading:null};h.setBackup(older);await h.c.boot();s=h.c.recoverySnapshot();assert.equal(s.available,false);assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_ARCHIVE_FULL');assert.deepEqual(h.local(),h.original);assert.deepEqual(h.backup(),older);exported=JSON.parse((await h.c.exportRecovery()).text);assert.deepEqual(exported.pendingEntry,h.original);assert.deepEqual(exported.protectedBackup,older);
  h=await harness();h.setBackup({damaged:true});await h.c.boot();s=h.c.recoverySnapshot();assert.equal(s.available,false);assert(s.canExport);assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_ARCHIVE_DAMAGED');assert.deepEqual(h.backup(),{damaged:true});exported=JSON.parse((await h.c.exportRecovery()).text);assert.deepEqual(exported.pendingEntry,h.original);assert(!exported.protectedBackup);assert(exported.note);
  h=await harness();h.setBackup({damaged:true});h.setCloud(doc(h.original.record));assert((await h.c.boot()).ok);assert.equal(h.c.recoverySnapshot().canExport,false);assert.match(h.c.recoverySnapshot().reason,/could not be verified/);assert.equal((await h.c.exportRecovery()).code,'RECOVERY_ARCHIVE_DAMAGED');
  h=await harness();h.setBackup(h.original);await h.c.boot();assert((await h.c.recoverCloud(h.c.recoverySnapshot().expectedCloudDigest)).ok);assert.deepEqual(h.backup(),h.original);

  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.storageFailure(true);assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'STORAGE_ERROR');assert.deepEqual(h.local(),h.original);assert.equal(h.backup(),null);h.storageFailure(false);assert((await h.c.recoverCloud(s.expectedCloudDigest)).ok);
  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();const changed={...h.original,record:await record(6,876,h.original.record.profileId)};h.recoverHook(async()=>h.setLocal(changed));assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'REVISION_CONFLICT');assert.deepEqual(h.local(),changed);assert.equal(h.backup(),null);assert.equal((await h.c.exportRecovery()).code,'REVISION_CONFLICT');
  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.recoverHook(async()=>h.setBackup({racing:'protected'}));assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_ARCHIVE_FULL');assert.deepEqual(h.local(),h.original);assert.deepEqual(h.backup(),{racing:'protected'});

  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();let release;h.readHook(()=>new Promise(resolve=>{release=resolve;}));const pending=h.c.recoverCloud(s.expectedCloudDigest);await new Promise(resolve=>setImmediate(resolve));assert(h.c.recoverySnapshot().busy);assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'RECOVERY_BUSY');h.setUid('other-account');release();assert.equal((await pending).code,'NOT_READY');assert.deepEqual(h.local(),h.original);assert.equal(h.backup(),null);assert.equal(h.c.recoverySnapshot().canExport,false);assert.equal(h.c.recoverySnapshot().available,false);assert.equal(h.c.recoverySnapshot().cloudRevision,null);assert.equal(h.c.recoverySnapshot().pendingRevision,null);assert.equal((await h.c.exportRecovery()).code,'NOT_READY');
  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.recoverHook(async()=>h.setUid('other-account'));assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'NOT_READY');assert.deepEqual(h.local(),h.original);assert.equal(h.backup(),null);
  h=await harness();await h.c.boot();s=h.c.recoverySnapshot();h.c.close();assert.equal((await h.c.recoverCloud(s.expectedCloudDigest)).code,'NOT_READY');assert.deepEqual(h.local(),h.original);

  h=await harness();h.setCloud(doc(h.original.record));assert((await h.c.boot()).ok);assert.equal(h.local().pending,false);assert.equal(h.backup(),null);assert.equal(h.c.recoverySnapshot().available,false);assert.equal(h.writes(),0);
  console.log('Firebase synthetic recovery contracts passed: digest-bound confirmation, exact export/archive, no cloud writes, cloud/local/account races, missing/corrupt/offline, full/identical backup, storage retry, repeated actions and proven lost acknowledgment. Real IndexedDB atomicity requires firebase_recovery_browser.js.');
})().catch(e=>{console.error(e);process.exit(1);});
