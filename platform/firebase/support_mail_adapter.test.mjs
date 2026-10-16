import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

vm.runInThisContext(readFileSync(new URL('../web/little_leaf_firebase.js',import.meta.url),'utf8'));
const factory=globalThis.LittleLeafFirebase;
const uid='syntheticRecipient20',fence={writerId:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',writerEpoch:1};
const ownership={assertActive:()=>fence,sessionRef:'session'};
const candidate={schema:1,profileId:'22222222-2222-4222-8222-222222222222',revision:5,
  digest:'b'.repeat(64),record:JSON.stringify({format:3,revision:5,digest:'b'.repeat(64)})};
let direct=0,calls=0,archive=0;
const sdk={doc:(_db,...path)=>path.join('/'),async getDocFromServer(ref){
  if(ref===`players/${uid}/saveControl/protocol`)return {exists:()=>true};
  assert.equal(ref,`players/${uid}/saves/cafe`);
  return {exists:()=>true,data:()=>({digest:'a'.repeat(64),revision:2,profileId:candidate.profileId})};},
  async runTransaction(){direct++;throw Error('direct transaction must not run');}};
const remote=factory.createRemote({},sdk,ownership,async request=>{
  calls++;assert.equal(request.digest,'a'.repeat(64));assert.equal(request.revision,2);
  assert.deepEqual({writerId:request.writerId,writerEpoch:request.writerEpoch},fence);
  return {status:'saved',record:{digest:candidate.digest}};
});
await remote.compareAndSet(uid,'a'.repeat(64),candidate,()=>{},async()=>{archive++;});
assert.equal(calls,1);assert.equal(archive,1);assert.equal(direct,0);
await assert.rejects(factory.createRemote({},sdk,ownership).compareAndSet(uid,'a'.repeat(64),candidate,()=>{}),
  {code:'UPDATE_REQUIRED'});
await assert.rejects(factory.createRemote({},sdk,ownership,async()=>({status:'saved',record:{digest:'c'.repeat(64)}}))
  .compareAndSet(uid,'a'.repeat(64),candidate,()=>{}),{code:'PROTOCOL_CHANGED'});
assert.equal(direct,0);
console.log('Protected save adapter: coalesced revision, exact cloud head/fence, missing runtime and mismatched confirmation passed.');
