import assert from 'node:assert/strict';
import {createSupportMailService} from './support_mail_service.mjs';

// Small transactional fixture for public UID allocation; Firestore/rules still
// require the separate emulator test before any rollout.
const documents=new Map([['playerUidIndex/123456789012',{schema:1,authUid:'someone-else'}]]);
const db={
  doc:path=>({path}),
  async runTransaction(callback){
    const writes=[];
    const tx={
      async get(ref){return {exists:documents.has(ref.path),data:()=>documents.get(ref.path)};},
      create(ref,value){writes.push([ref.path,value]);}
    };
    const result=await callback(tx);
    for(const [path,value] of writes){assert(!documents.has(path),`duplicate create ${path}`);documents.set(path,value);}
    return result;
  }
};
const candidates=['123456789012','987654321098','222222222222'];
const service=createSupportMailService({db,publicUidEnabled:true,randomPublicUid:()=>candidates.shift()});
const auth={auth:{uid:'syntheticRecipient20',token:{firebase:{sign_in_provider:'google.com'}}}};
assert.equal((await service.myPublicUid(auth)).publicUid,'987654321098','collision retries with a fresh UID');
assert.equal((await service.myPublicUid(auth)).publicUid,'987654321098','repeat returns the paired UID');
assert.deepEqual(documents.get('players/syntheticRecipient20/identity/public'),{schema:1,publicUid:'987654321098'});
assert.deepEqual(documents.get('playerUidIndex/987654321098'),{schema:1,authUid:'syntheticRecipient20'});
assert.deepEqual(documents.get('playerUidIndex/123456789012'),{schema:1,authUid:'someone-else'});
await assert.rejects(service.myPublicUid({auth:{uid:'syntheticRecipient20',token:{firebase:{sign_in_provider:'password'}}}}),{code:'UNAUTHENTICATED'});
await assert.rejects(createSupportMailService({db}).myPublicUid(auth),{code:'FEATURE_DISABLED'});
documents.delete('playerUidIndex/987654321098');
await assert.rejects(service.myPublicUid(auth),{code:'CORRUPT_IDENTITY'},'a broken pair fails closed');
console.log('Public UID allocator: 12-digit collision retry, stable pair, provider check and fail-closed corruption passed.');
