// Production adapter and codec with generated transaction objects, not a real
// SDK, browser or rules run. The separate routing rules suite covers the SDK.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {fixture,document,sign,writerId,profileId} from './support_storage_fixture.mjs';
const root={crypto:webcrypto,TextEncoder,TextDecoder};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])
  vm.runInNewContext(readFileSync(new URL(`../web/${name}.js`,import.meta.url),'utf8'),root);
const factory=root.LittleLeafFirebase,uid='syntheticRecipient20',fence={writerId,writerEpoch:1};
const {original}=fixture(),ordinary=document(original);
const storage={...JSON.parse(original.payload),version:17,storage_format:'little_leaf.storage.v1',storage:{items:[],dining_sets:[]}};
const protectedRecord=sign({...original,format:3,revision:2,payload:JSON.stringify(storage),mailState:{schema:1,claimSequence:1,stockRevision:0}});
const protectedDoc=document(protectedRecord);
const next=record=>document(sign({...record,revision:record.revision+3}));
function harness(head=ordinary,{callable=true}={}){
  let current=structuredClone(head),sets=0,calls=0,reads=0,archives=0,attempts=0;
  const ownership={assertActive:()=>fence,sessionRef:'session'};
  const h={hook:async()=>{},owner:{owner:writerId,epoch:1,ack:null},denied:false,badResponse:false};
  const sdk={doc:(_db,...path)=>path.join('/'),async getDocFromServer(){throw Error('routing never reads the protocol or uses a nontransactional head');},
    async runTransaction(_db,action){attempts++;await h.hook('begin');const writes=[];
      const result=await action({async get(ref){reads++;if(h.denied)throw Object.assign(Error('denied'),{code:'permission-denied'});
        await h.hook(ref==='session'?'owner':'head');return {exists:()=>ref==='session'||current!==null,data:()=>structuredClone(ref==='session'?h.owner:current)};},
        set(ref,value){writes.push(structuredClone(value));}});
      await h.hook('commit');sets+=writes.length;if(writes.length)current=writes[0];return result;}};
  const remote=factory.createRemote({},sdk,ownership,callable?async request=>{
    calls++;assert.deepEqual({writerId:request.writerId,writerEpoch:request.writerEpoch},fence);
    assert.equal(request.revision,current.revision);assert.equal(request.digest,current.digest);
    await h.hook('callable');current=document(request.candidate);
    return {status:'saved',record:{digest:h.badResponse?'f'.repeat(64):current.digest}};
  }:null);
  return Object.assign(h,{remote,ownership,cloud:()=>structuredClone(current),setHead:value=>current=structuredClone(value),
    counts:()=>({sets,calls,reads,archives,attempts}),save:(candidate,base=head?.digest||null,guard=()=>{})=>
      remote.compareAndSet(uid,base,candidate,guard,async()=>{archives++;await h.hook('archive');})});
}
for(const format of [1,2]){
  const record=sign({...original,format});if(format===1)delete record.campaigns;
  // Campaigns are excluded from format1 fingerprint and absent in historical records.
  const h=harness(document(record)),candidate=next(record);await h.save(candidate);
  assert.equal(h.counts().sets,1);assert.equal(h.counts().calls,0);assert.equal(h.counts().archives,1);
  await h.save(candidate);assert.equal(h.counts().sets,1,'lost ACK is exact-head idempotent');
}
{
  const h=harness(null),candidate=next(original);await h.save(candidate);
  assert.equal(h.counts().sets,1);assert.equal(h.counts().calls,0,'fresh ordinary save needs no mail service');
}
{
  const h=harness(protectedDoc),candidate=next(protectedRecord);await h.save(candidate);
  assert.equal(h.counts().sets,0);assert.equal(h.counts().calls,1);assert.equal(h.counts().archives,1);
  await h.save(candidate);assert.equal(h.counts().calls,1,'protected exact-head ACK does not resubmit');
}
for(const [head,candidate] of [[protectedDoc,next(original)],[ordinary,next(protectedRecord)],[null,next(protectedRecord)]]){
  const h=harness(head);await assert.rejects(h.save(candidate),{code:'PROTOCOL_CHANGED'});
  assert.equal(h.counts().sets+h.counts().calls,0,'downgrade and client-created protection cannot write');
}
{
  const h=harness(protectedDoc,{callable:false});await assert.rejects(h.save(next(protectedRecord)),{code:'UPDATE_REQUIRED'});
  assert.equal(h.counts().sets,0);
}
{
  const h=harness(protectedDoc);h.badResponse=true;
  await assert.rejects(h.save(next(protectedRecord)),{code:'PROTOCOL_CHANGED'});assert.equal(h.counts().sets,0);
}
for(const head of [{...ordinary,digest:'0'.repeat(64)},{...ordinary,record:'broken'},document(sign({...original,format:99}))]){
  const h=harness(head);await assert.rejects(h.save(next(original)),{code:'CORRUPT_AUTHORITY'});
  assert.equal(h.counts().sets+h.counts().calls,0);
}
{
  const h=harness();await assert.rejects(h.save({...next(original),digest:'0'.repeat(64)}),{code:'CORRUPT_AUTHORITY'});
  assert.equal(h.counts().attempts,0,'malformed candidate cannot reach the transaction');
}
for(const phase of ['denied','owner','stale','profile','revision','claim','archive','guard']){
  const h=harness();let candidate=next(original),guard=()=>{},code='REVISION_CONFLICT';
  if(phase==='denied'){h.denied=true;code='permission-denied';}
  if(phase==='owner'){h.owner.epoch=2;code='OWNERSHIP_LOST';}
  if(phase==='stale')h.setHead(document(sign({...original,revision:2,updatedAt:5})));
  if(phase==='profile')candidate=document(sign({...original,profileId:'44444444-4444-4444-8444-444444444444',revision:4}));
  if(phase==='revision')candidate=document(sign({...original,revision:1,updatedAt:4}));
  if(phase==='claim'){h.hook=async stage=>{if(stage==='head')h.setHead(protectedDoc);};code='PROTOCOL_CHANGED';}
  if(phase==='archive'){h.hook=async stage=>{if(stage==='archive')throw Object.assign(Error('archive'),{code:'PRE_GRID_ARCHIVE_UNVERIFIED'});};code='PRE_GRID_ARCHIVE_UNVERIFIED';}
  if(phase==='guard'){guard=()=>{if(h.counts().reads)throw Object.assign(Error('account changed'),{code:'NOT_READY'});};code='NOT_READY';}
  await assert.rejects(h.save(candidate,ordinary.digest,guard),{code});
  assert.equal(h.counts().sets+h.counts().calls,0,`${phase} never falls back or writes`);
}
const legacyProtected=document(sign({...original,format:3,mailState:{schema:1,claimSequence:1,stockRevision:0}}));
await assert.rejects(harness(legacyProtected).save(next(original)),{code:'STORAGE_REVIEW_REQUIRED'});
console.log('Save adapter synthetic: verified ordinary/protected routing, exact ACK, no control reads, downgrade/upgrade/corruption/stale/owner/account/claim-race/archive/denied gates passed.');
