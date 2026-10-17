// Real local Firestore transactions/query cursors; generated identities only.
// No Auth/Functions transport, production account or deployed service is used.
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {createSupportMailService} from './support_mail_service.mjs';
import {fixture,document,sign} from './support_storage_fixture.mjs';
assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/,
  'This generated-identity test only permits the local emulator');
const app=initializeApp({projectId:'demo-little-leaf-audience'}),db=getFirestore(app);
const admin='syntheticAudienceAdmin',auth={auth:{uid:admin,token:{firebase:{sign_in_provider:'google.com'}}}};
const {original}=fixture(),baseline=JSON.stringify(original),now=Date.now();
const service=createSupportMailService({db,enabled:true,now:()=>now});
const id=n=>`${String(n).padStart(8,'0')}-aaaa-4aaa-aaaa-aaaaaaaaaaaa`;
const player=n=>'syntheticAudience'+String(n).padStart(4,'0');
const issue=(n,audience)=>({issueId:id(n),audience,caseId:'audience-case-'+n,subject:'A little note',body:'Generated fixture only.',
  coins:40,items:[{catalogId:'plant',quantity:2}]});
try {
  const batch=db.batch();
  batch.set(db.doc(`supportAdmins/${admin}`),{enabled:true,capabilities:['issue','issue_many','issue_all']});
  for(let n=0;n<52;n++) {
    const record=sign({...original,profileId:id(100+n)});
    batch.set(db.doc(`players/${player(n)}/saves/cafe`),document(record));
    if(n<2) {
      const publicUid=String(123456789012+n);
      batch.set(db.doc(`players/${player(n)}/identity/public`),{schema:1,publicUid});
      batch.set(db.doc(`playerUidIndex/${publicUid}`),{schema:1,authUid:player(n)});
    }
  }
  await batch.commit();
  const selected=issue(1,{mode:'selected',publicUids:['123456789013','123456789012','123456789013']});
  const review=await service.previewMail(auth,selected);
  assert.equal(review.recipientCount,2);const request={...selected,previewHash:review.previewHash};
  const results=await Promise.all([service.issueMail(auth,request),service.issueMail(auth,request)]);
  assert(results.every(r=>r.sentCount===2&&r.pendingCount===0));
  const selectedMail=await db.collectionGroup('mail').get();assert.equal(selectedMail.size,2);
  assert.equal(new Set(selectedMail.docs.map(d=>d.id)).size,2);
  const all=issue(2,{mode:'all'}),first=await service.previewMail(auth,all);
  assert.equal(first.status,'preparing');assert.equal(first.preparedCount,50);assert.equal(first.recipientCount,null);
  const ready=await service.previewMail(auth,all);assert.equal(ready.recipientCount,52);
  const late=sign({...original,profileId:id(999)});await db.doc(`players/${player(99)}/saves/cafe`).set(document(late));
  const changed=sign({...original,profileId:id(888)});await db.doc(`players/${player(25)}/saves/cafe`).set(document(changed));
  let result=await service.issueMail(auth,{...all,previewHash:ready.previewHash});
  assert.equal(result.sentCount,10);assert.equal(result.pendingCount,42);
  while(result.pendingCount)result=await service.issueMail(auth,{...all,previewHash:ready.previewHash});
  assert.deepEqual([result.total,result.sentCount,result.failedCount,result.pendingCount],[52,51,1,0]);
  assert.equal((await db.collection(`players/${player(99)}/mail`).get()).size,0);
  assert.equal((await db.collection(`players/${player(25)}/mail`).get()).size,0);
  assert.equal((await db.collectionGroup('mail').get()).size,53);
  const data=(await db.doc(`players/${player(0)}/saves/cafe`).get()).data();
  assert.equal(JSON.parse(data.record).payload,JSON.parse(baseline).payload,'Send never changes wallet or stock');
  await db.doc(`supportAdmins/${admin}`).update({enabled:false});
  await assert.rejects(service.issueMail(auth,{...all,previewHash:ready.previewHash}),{code:'PERMISSION_DENIED'});
  console.log('Support mail audience emulator: selected concurrency, All document-name paging, bounded frozen cohort, changed-profile reporting and authority revocation passed. Local emulator only.');
} finally {await deleteApp(app);}
