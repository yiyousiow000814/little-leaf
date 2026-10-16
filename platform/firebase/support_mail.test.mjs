import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {createSupportMailService} from './support_mail_service.mjs';
import {hash,fingerprint,verifyRecord,normalizeIssue} from './support_mail_contract.mjs';

initializeApp({projectId:'demo-little-leaf'});
const db=getFirestore(),clock=Date.now(),service=createSupportMailService({db,enabled:true,publicUidEnabled:true,now:()=>clock});
const player='syntheticRecipient20',owner='syntheticSupportOwner20',other='syntheticOther20';
const profileId='22222222-2222-4222-8222-222222222222',writerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const auth=id=>({auth:{uid:id,token:{firebase:{sign_in_provider:'google.com'}}}});
const original={format:2,profileId,revision:1,createdAt:clock-1000,updatedAt:clock-1000,
  origin:{source:'fresh',legacyDigest:null,importedAt:clock-1000},previous:null,campaigns:{},
  payload:JSON.stringify({...JSON.parse(readFileSync(new URL('../../tests/fixtures/unified_building_candidate.json',import.meta.url),'utf8')),coins:40})};
original.digest=hash(fingerprint(original));verifyRecord(original);
const saveRef=db.doc(`players/${player}/saves/cafe`),controlRef=db.doc(`players/${player}/saveControl/protocol`);
await saveRef.set({schema:1,profileId,revision:1,digest:original.digest,record:JSON.stringify(original),
  writerId,writerEpoch:1,device:'Mac'});
await db.doc(`players/${player}/session/owner`).set({schema:1,owner:writerId,epoch:1,device:'Mac',
  updatedAt:Timestamp.fromMillis(clock),request:null,ack:null});
const roleRef=db.doc(`supportAdmins/${owner}`);
await roleRef.set({enabled:true,capabilities:['lookup','issue']});
const publicId=(await service.myPublicUid(auth(player))).publicUid;
assert.match(publicId,/^[1-9][0-9]{11}$/);
assert.equal((await service.myPublicUid(auth(player))).publicUid,publicId,'same account keeps its public UID');
assert.equal((await db.doc(`players/${player}/identity/public`).get()).data().publicUid,publicId);
assert.equal((await db.doc(`playerUidIndex/${publicId}`).get()).data().authUid,player);
const issueId='11111111-1111-4111-8111-111111111111',operationId='33333333-3333-4333-8333-333333333333';
const input={issueId,recipientPublicUid:publicId,profileId,caseId:'synthetic-case-20',subject:'A note for you',body:'Here are your gifts.',coins:60,
  items:[{catalogId:'plant',quantity:2},{catalogId:'stove',quantity:1}]};
assert.equal((await service.capabilities(auth(owner))).canIssue,true);
assert.equal((await service.capabilities(auth(other))).canIssue,false);
await assert.rejects(service.lookup(auth(other),publicId),{code:'PERMISSION_DENIED'});
await assert.rejects(service.lookup(auth(owner),player),{code:'INVALID_UID'});
const found=await service.lookup(auth(owner),publicId);
assert.equal(found.revision,1);
assert.equal(found.publicUid,publicId);
assert.equal(Object.hasOwn(found,'uid'),false,'owner lookup does not reveal private Auth UID');
for(let i=0;i<19;i++)await service.lookup(auth(owner),publicId);
await assert.rejects(service.lookup(auth(owner),publicId),{code:'RATE_LIMITED'});
for(const invalid of [{...input,items:[{catalogId:'register',quantity:1}]},{...input,coins:-1},
  {...input,items:[{catalogId:'plant',quantity:2},{catalogId:'plant',quantity:2}]},
  {...input,body:'\u0001'}])assert.throws(()=>normalizeIssue(invalid),{code:'INVALID_ISSUE'});
const preview=await service.previewMail(auth(owner),input);
assert.equal(preview.recipientPublicUid,publicId);
assert.equal(Object.hasOwn(preview,'recipientUid'),false);
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
assert.deepEqual(JSON.parse(granted.payload).storage.items.map(item=>item.kind),['plant','plant','stove']);
assert.equal((await db.doc(`players/${player}/giftStock/current`).get()).exists,false);
assert.equal((await controlRef.get()).data().claimSequence,1);
assert.equal((await db.doc(`players/${player}/mailClaims/${issueId}`).get()).data().toDigest,granted.digest);
assert.equal((await db.doc(`players/${player}/saveBackups/supportMailV1`).get()).data().record,JSON.stringify(original));
assert.equal((await service.claimMail(auth(player),request)).record.digest,granted.digest,'response loss returns current head');
// A server-dated claim can precede a valid save from a slower device clock.
// Revision and digest, not client wall time, order protected progress.
const candidate={...granted,revision:3,updatedAt:clock-1000,
  payload:JSON.stringify({...JSON.parse(granted.payload),coins:90}),previous:null};
candidate.digest=hash(fingerprint(candidate));
await assert.rejects(service.commitProtectedSave(auth(player),{...request,candidate}),{code:'REVISION_CONFLICT'});
const next=await service.commitProtectedSave(auth(player),{...request,revision:2,digest:granted.digest,candidate});
assert.equal(next.record.digest,candidate.digest);
const replay=await service.commitProtectedSave(auth(player),{...request,revision:2,digest:granted.digest,candidate});
assert.equal(replay.record.digest,candidate.digest);
const coalesced={...candidate,revision:6,updatedAt:clock-500,
  payload:JSON.stringify({...JSON.parse(candidate.payload),coins:91})};
coalesced.digest=hash(fingerprint(coalesced));
assert.equal((await service.commitProtectedSave(auth(player),{...request,revision:3,digest:candidate.digest,candidate:coalesced})).record.revision,6);
// Resume the placement fixture from the coalesced authoritative head.
const placedBase=coalesced;
const lowered={...candidate,revision:4,updatedAt:clock+2,mailState:{...candidate.mailState,claimSequence:0}};
lowered.digest=hash(fingerprint(lowered));
await assert.rejects(service.commitProtectedSave(auth(player),{...request,revision:6,digest:coalesced.digest,candidate:lowered}),{code:'CORRUPT_AUTHORITY'});
await roleRef.set({enabled:false,capabilities:['lookup','issue']});
await assert.rejects(service.lookup(auth(owner),publicId),{code:'PERMISSION_DENIED'});
const stopped=createSupportMailService({db,enabled:false,now:()=>clock});
await assert.rejects(stopped.claimMail(auth(player),request),{code:'FEATURE_DISABLED'});
assert.equal((await stopped.commitProtectedSave(auth(player),{...request,revision:3,digest:candidate.digest,candidate:coalesced})).record.digest,coalesced.digest,
  'kill switch preserves protected-save recovery');
const data=JSON.parse(placedBase.payload),stored=data.storage.items.shift();
data.items.push({...stored,x:8,z:8});
const placed={...placedBase,revision:7,updatedAt:clock+2,mailState:{...placedBase.mailState,stockRevision:2},payload:JSON.stringify(data)};
placed.digest=hash(fingerprint(placed));
const placeRequest={...request,revision:6,digest:placedBase.digest,candidate:placed};
const ownerRef=db.doc(`players/${player}/session/owner`);
await ownerRef.update({ack:{requestId:'66666666-6666-4666-8666-666666666666',digest:placedBase.digest,revision:6}});
await assert.rejects(service.commitProtectedSave(auth(player),placeRequest),{code:'OWNERSHIP_LOST'});
await ownerRef.update({ack:null});
const placedResult=await service.commitProtectedSave(auth(player),placeRequest);
assert.equal(JSON.parse(placedResult.record.payload).storage.items.length,2);
assert.equal(placedResult.record.digest,placed.digest);
assert.equal(JSON.parse(placed.payload).coins,91,'unpack does not charge');
assert.equal((await controlRef.get()).data().stockRevision,2);
assert.equal((await service.commitProtectedSave(auth(player),placeRequest)).record.digest,placed.digest);
const legacy=db.doc(`players/${player}/giftStock/current`);
await legacy.set({schema:1,revision:0,counts:{}});
await assert.rejects(service.claimMail(auth(player),request),{code:'STORAGE_REVIEW_REQUIRED'});
await assert.rejects(service.commitProtectedSave(auth(player),placeRequest),{code:'STORAGE_REVIEW_REQUIRED'});
assert.deepEqual((await legacy.get()).data(),{schema:1,revision:0,counts:{}});
console.log('Support mail emulator: issue idempotency, role revocation, atomic Storage claim, backup, protected ordinary unpack, legacy preservation and kill switch passed.');
