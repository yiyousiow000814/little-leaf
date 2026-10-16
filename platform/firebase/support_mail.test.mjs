import assert from 'node:assert/strict';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {createSupportMailService} from './support_mail_service.mjs';
import {hash,fingerprint,verifyRecord,normalizeIssue} from './support_mail_contract.mjs';

initializeApp({projectId:'demo-little-leaf'});
const db=getFirestore(),clock=Date.now(),service=createSupportMailService({db,enabled:true,now:()=>clock});
const player='syntheticRecipient20',owner='syntheticSupportOwner20',other='syntheticOther20';
const profileId='22222222-2222-4222-8222-222222222222',writerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const auth=id=>({auth:{uid:id,token:{firebase:{sign_in_provider:'google.com'}}}});
const original={format:2,profileId,revision:1,createdAt:clock-1000,updatedAt:clock-1000,
  origin:{source:'fresh',legacyDigest:null,importedAt:clock-1000},previous:null,campaigns:{},
  payload:JSON.stringify({schema:'little_leaf_reconstructed_cafe',version:15,new_reconstruction:true,
    checkout_format:'little_leaf.checkout.v1',layout_motion_format:'little_leaf.layout_motion.v1',coins:40,items:[]})};
original.digest=hash(fingerprint(original));verifyRecord(original);
const saveRef=db.doc(`players/${player}/saves/cafe`),controlRef=db.doc(`players/${player}/saveControl/protocol`);
await saveRef.set({schema:1,profileId,revision:1,digest:original.digest,record:JSON.stringify(original),
  writerId,writerEpoch:1,device:'Mac'});
await db.doc(`players/${player}/session/owner`).set({schema:1,owner:writerId,epoch:1,device:'Mac',
  updatedAt:Timestamp.fromMillis(clock),request:null,ack:null});
const roleRef=db.doc(`supportAdmins/${owner}`);
await roleRef.set({enabled:true,capabilities:['lookup','issue']});
const issueId='11111111-1111-4111-8111-111111111111',operationId='33333333-3333-4333-8333-333333333333';
const input={issueId,recipientUid:player,profileId,caseId:'synthetic-case-20',subject:'A note for you',body:'Here are your gifts.',coins:60,
  items:[{catalogId:'plant',quantity:2},{catalogId:'stove',quantity:1}]};
assert.equal((await service.capabilities(auth(owner))).canIssue,true);
assert.equal((await service.capabilities(auth(other))).canIssue,false);
await assert.rejects(service.lookup(auth(other),player),{code:'PERMISSION_DENIED'});
assert.equal((await service.lookup(auth(owner),player)).revision,1);
for(const invalid of [{...input,items:[{catalogId:'register',quantity:1}]},{...input,coins:-1},
  {...input,items:[{catalogId:'plant',quantity:2},{catalogId:'plant',quantity:2}]},
  {...input,body:'\u0001'}])assert.throws(()=>normalizeIssue(invalid),{code:'INVALID_ISSUE'});
await service.previewMail(auth(owner),input);
await assert.rejects(service.issueMail(auth(other),input),{code:'PERMISSION_DENIED'});
const sent=await Promise.all([service.issueMail(auth(owner),input),service.issueMail(auth(owner),input)]);
assert(sent.every(value=>value.mailId===issueId));
assert.equal((await db.doc(`players/${player}/mail/${issueId}`).get()).data().status,'unclaimed');
assert.equal((await saveRef.get()).data().digest,original.digest,'sending does not pay');
await assert.rejects(service.issueMail(auth(owner),{...input,body:'Changed letter'}),{code:'ISSUE_CONFLICT'});
const another={...input,issueId:'44444444-4444-4444-8444-444444444444'};
await service.previewMail(auth(owner),another);
await assert.rejects(service.issueMail(auth(owner),another),{code:'CASE_ALREADY_ISSUED'});
const request={mailId:issueId,operationId,profileId,revision:1,digest:original.digest,writerId,writerEpoch:1};
await assert.rejects(service.claimMail(auth(other),request),{code:'MAIL_UNAVAILABLE'});
const results=await Promise.all([service.claimMail(auth(player),request),service.claimMail(auth(player),request)]);
assert(results.every(value=>value.status==='claimed'&&value.record.revision===2));
const granted=results[0].record;
assert.equal(JSON.parse(granted.payload).coins,100);
assert.deepEqual(results[0].stock.counts,{plant:2,stove:1});
assert.equal((await controlRef.get()).data().claimSequence,1);
assert.equal((await db.doc(`players/${player}/mailClaims/${issueId}`).get()).data().toDigest,granted.digest);
assert.equal((await db.doc(`players/${player}/saveBackups/supportMailV1`).get()).data().record,JSON.stringify(original));
assert.equal((await service.claimMail(auth(player),request)).record.digest,granted.digest,'response loss returns current head');
const candidate={...granted,revision:3,updatedAt:clock+1,
  payload:JSON.stringify({...JSON.parse(granted.payload),coins:90}),previous:null};
candidate.digest=hash(fingerprint(candidate));
await assert.rejects(service.commitProtectedSave(auth(player),{...request,candidate}),{code:'REVISION_CONFLICT'});
const next=await service.commitProtectedSave(auth(player),{...request,revision:2,digest:granted.digest,candidate});
assert.equal(next.record.digest,candidate.digest);
const replay=await service.commitProtectedSave(auth(player),{...request,revision:2,digest:granted.digest,candidate});
assert.equal(replay.record.digest,candidate.digest);
const lowered={...candidate,revision:4,updatedAt:clock+2,mailState:{...candidate.mailState,claimSequence:0}};
lowered.digest=hash(fingerprint(lowered));
await assert.rejects(service.commitProtectedSave(auth(player),{...request,revision:3,digest:candidate.digest,candidate:lowered}),{code:'CORRUPT_AUTHORITY'});
await roleRef.set({enabled:false,capabilities:['lookup','issue']});
await assert.rejects(service.lookup(auth(owner),player),{code:'PERMISSION_DENIED'});
const stopped=createSupportMailService({db,enabled:false,now:()=>clock});
await assert.rejects(stopped.claimMail(auth(player),request),{code:'FEATURE_DISABLED'});
assert.equal((await stopped.commitProtectedSave(auth(player),{...request,revision:2,digest:granted.digest,candidate})).record.digest,candidate.digest,
  'kill switch preserves protected-save recovery');
const placed={...candidate,revision:4,updatedAt:clock+2,mailState:{...candidate.mailState,stockRevision:2},
  payload:JSON.stringify({...JSON.parse(candidate.payload),items:[{id:1,kind:'plant',x:0,z:0,rot:0}],next_item_id:2})};
placed.digest=hash(fingerprint(placed));
const placeRequest={...request,revision:3,digest:candidate.digest,candidate:placed,
  operationId:'55555555-5555-4555-8555-555555555555',consumed:[{itemId:1,catalogId:'plant'}]};
await assert.rejects(service.commitGiftPlacement(auth(player),{...placeRequest,consumed:[{itemId:1,catalogId:'register'}]}),
  {code:'INVALID_PLACEMENT'});
const placedResult=await service.commitGiftPlacement(auth(player),placeRequest);
assert.equal(placedResult.stock.counts.plant,1);
assert.equal(placedResult.record.digest,placed.digest);
assert.equal((await service.commitGiftPlacement(auth(player),placeRequest)).record.digest,placed.digest);
await assert.rejects(service.commitGiftPlacement(auth(player),{...placeRequest,consumed:[{itemId:2,catalogId:'plant'}]}),
  {code:'ISSUE_CONFLICT'});
console.log('Support mail emulator: issue idempotency, role revocation, atomic gift claim and placement, backup, protected save and kill switch passed.');
