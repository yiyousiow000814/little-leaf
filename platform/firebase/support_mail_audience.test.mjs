// Generated accounts and an in-memory serial transaction fixture only.
// This does not contact Auth, Firestore, deployed Functions or real players.
import assert from 'node:assert/strict';
import {createSupportMailService} from './support_mail_service.mjs';
import {normalizeAudienceIssue,uuid,hash} from './support_mail_contract.mjs';
import {fixture,document,sign,writerId} from './support_storage_fixture.mjs';
const admin='syntheticMailAdmin',context={auth:{uid:admin,token:{firebase:{sign_in_provider:'google.com'}}}};
const ids=i=>`${String(i).padStart(8,'0')}-1111-4111-8111-111111111111`;
const input=(i=1,audience={mode:'selected',publicUids:['123456789012','123456789013']})=>({issueId:ids(i),audience,
  caseId:'case-'+i,subject:' Hello ',body:' A letter ',coins:25,items:[{catalogId:'plant',quantity:2}]});
function setup(count=2) {
  const f=fixture();f.documents.clear();let time=1000;
  f.documents.set(`supportAdmins/${admin}`,{enabled:true,capabilities:['lookup','issue','issue_many','issue_all']});
  const add=(i,withPublic=true)=>{
    const player='syntheticPlayer'+String(i).padStart(4,'0'),publicUid=String(123456789012+i);
    const record=sign({...f.original,profileId:ids(1000+i)});
    f.documents.set(`players/${player}/saves/cafe`,document(record));
    f.documents.set(`players/${player}/session/owner`,{schema:1,owner:writerId,epoch:1,updatedAt:{toMillis:()=>time},request:null,ack:null});
    if(withPublic) {
      f.documents.set(`players/${player}/identity/public`,{schema:1,publicUid});
      f.documents.set(`playerUidIndex/${publicUid}`,{schema:1,authUid:player});
    }
    return {player,publicUid,record};
  };
  const players=Array.from({length:count},(_,i)=>add(i));
  const service=createSupportMailService({db:f.db,enabled:true,now:()=>time});
  return {...f,service,players,add,setTime:value=>time=value};
}
const calls=async(f,v)=>{let r;do {r=await f.service.previewMail(context,v);}while(r.status==='preparing');return {...v,previewHash:r.previewHash};};
const mails=f=>[...f.documents].filter(([path])=>/^players\/[^/]+\/mail\//.test(path));
const saved=f=>[...f.documents].filter(([path])=>path.endsWith('/saves/cafe')).map(([k,v])=>[k,JSON.stringify(v)]);
let checks=0;function check(value,message){checks++;assert(value,message);}
{
  const normalized=normalizeAudienceIssue(input(1,{mode:'selected',publicUids:['123456789013','123456789012','123456789013']}));
  assert.deepEqual(normalized.audience.publicUids,['123456789012','123456789013']);checks++;
  for(const audience of [{mode:'selected',publicUids:[]},{mode:'selected',publicUids:['012345678901']},
    {mode:'selected',publicUids:Array(101).fill('123456789012')},{mode:'all',publicUids:[]},{mode:'other'}]) {
    assert.throws(()=>normalizeAudienceIssue(input(1,audience)),{code:'INVALID_ISSUE'});checks++;
  }
}
{
  const f=setup(),v=input(),before=saved(f),ready=await calls(f,v);
  const result=await f.service.issueMail(context,ready);
  assert.deepEqual([result.total,result.sentCount,result.failedCount,result.pendingCount],[2,2,0,0]);checks++;
  assert.deepEqual(saved(f),before);checks++;
  check(mails(f).length===2,'Send creates mail, never changes either save');
  const mailIds=mails(f).map(([,m])=>m.mailId);
  check(mailIds.every(uuid)&&new Set(mailIds).size===2,'each recipient has a distinct valid mail UUID');
  const repeat=await f.service.issueMail(context,ready);
  check(repeat.sentCount===2&&mails(f).length===2,'retry does not redeliver');
  await assert.rejects(f.service.issueMail(context,{...ready,coins:26}),{code:'PREVIEW_CHANGED'});checks++;
  await assert.rejects(f.service.previewMail(context,{...v,coins:26}),{code:'ISSUE_CONFLICT'});checks++;
  // A new campaign with the same original case must still hit each case guard.
  const sameCase={...input(3),caseId:v.caseId},r=await calls(f,sameCase);
  const failed=await f.service.issueMail(context,r);
  check(failed.status==='completed_with_failures'&&failed.failedCount===2&&mails(f).length===2,'case identity is not renamed for a campaign');
  // Claim one delivered letter twice with unchanged atomic claim code.
  const [path,m]=mails(f)[0],player=path.split('/')[1],record=JSON.parse(f.documents.get(`players/${player}/saves/cafe`).record);
  const auth={auth:{uid:player,token:{firebase:{sign_in_provider:'google.com'}}}},request={mailId:m.mailId,operationId:ids(90),
    profileId:record.profileId,revision:record.revision,digest:record.digest,writerId,writerEpoch:1};
  const claimed=await f.service.claimMail(auth,request),again=await f.service.claimMail(auth,request);
  const data=JSON.parse(claimed.record.payload);
  check(claimed.record.digest===again.record.digest&&data.coins===65&&data.storage.items.length===2,'one claim grants wallet and canonical Storage exactly once');
}
{
  const f=setup(51);f.add(51,false);const v=input(4,{mode:'all'}),before=saved(f);
  const first=await f.service.previewMail(context,v);
  check(first.status==='preparing'&&first.preparedCount===50&&first.recipientCount===null,'first All page does not pretend final count');
  check(first.previewHash===null&&first.totals===null,'unfinished cohort has no usable final-confirmation token or totals');
  await assert.rejects(f.service.issueMail(context,{...v,previewHash:first.previewHash}),{code:'PREVIEW_REQUIRED'});checks++;
  const ready=await f.service.previewMail(context,v);
  check(ready.status==='ready'&&ready.recipientCount===52,'All includes cloud cafés without a public UID');
  assert.deepEqual(ready.totals,{coins:1300,items:[{catalogId:'plant',quantity:104}]});checks++;
  check(ready.captureStartedAt===1000&&ready.captureCompletedAt===1000,'review records actual bounded-scan interval');
  await assert.rejects(f.service.issueMail(context,{...v,previewHash:first.previewHash}),{code:'PREVIEW_CHANGED'});checks++;
  await assert.rejects(f.service.issueMail(context,{...v,previewHash:hash(JSON.stringify(normalizeAudienceIssue(v)))}),{code:'PREVIEW_CHANGED'});checks++;
  f.add(52);const issued={...v,previewHash:ready.previewHash};
  let r=await f.service.issueMail(context,issued);
  check(r.sentCount===10&&r.pendingCount===42,'one Send call is bounded to ten deliveries');
  // A profile changed after review is a non-delivery, never a retarget.
  const changed=f.players[20],newRecord=sign({...changed.record,profileId:ids(8000)});
  f.documents.set(`players/${changed.player}/saves/cafe`,document(newRecord));
  f.setTime(1000+11*60*1000);
  while(r.pendingCount)r=await f.service.issueMail(context,issued);
  check(r.sentCount===51&&r.failedCount===1&&r.total===52,'started delivery resumes after expiry and counts the changed profile');
  check(mails(f).length===51&&!mails(f).some(([p])=>p.includes('syntheticPlayer0052')),'ready cohort never adds a later player');
  check(f.db.queryReads.every(q=>q.group==='saves'&&q.limit===50),'All enumeration is bounded');
  check(![...f.documents.keys()].some(k=>k==='players/syntheticPlayer0051/identity/public'),'mail does not allocate public IDs');
  for(const [key,bytes] of before)if(!key.includes(changed.player))assert.equal(JSON.stringify(f.documents.get(key)),bytes);
  checks++;
}
{
  const f=setup(15),v=input(5,{mode:'selected',publicUids:f.players.map(p=>p.publicUid)}),ready=await calls(f,v);
  f.db.failAtCommit=f.db.commits+4;
  await assert.rejects(f.service.issueMail(context,ready),{code:'OFFLINE'});checks++;
  check(mails(f).length===3,'failed fourth commit retains only three complete deliveries');
  let result=await f.service.issueMail(context,ready);while(result.pendingCount)result=await f.service.issueMail(context,ready);
  check(result.sentCount===15&&mails(f).length===15,'uncertain caller retry resumes immutable receipts without duplicates');
}
{
  const f=setup(),v=input(6),ready=await calls(f,v);
  f.documents.get(`supportAdmins/${admin}`).capabilities=['issue'];
  await assert.rejects(f.service.issueMail(context,ready),{code:'PERMISSION_DENIED'});checks++;
  check(mails(f).length===0,'revoked audience permission prevents every delivery');
  f.documents.get(`supportAdmins/${admin}`).capabilities=['issue','issue_many'];
  f.db.afterCommit=()=>{f.documents.get(`supportAdmins/${admin}`).enabled=false;};
  await assert.rejects(f.service.issueMail(context,ready),{code:'PERMISSION_DENIED'});checks++;
  check(mails(f).length===1,'role revocation between deliveries stops subsequent recipients');
}
{
  const f=setup(),v=input(7),ready=await calls(f,v);f.setTime(602000);
  await assert.rejects(f.service.issueMail(context,ready),{code:'PREVIEW_EXPIRED'});checks++;
  check(mails(f).length===0,'expired unstarted review sends nothing');
  const off=createSupportMailService({db:f.db});
  await assert.rejects(off.previewMail(context,input(8)),{code:'FEATURE_DISABLED'});checks++;
  const caps=await off.capabilities(context);check(!caps.canIssueMany&&!caps.canIssueAll,'all audience capabilities default closed');
}
{
  const f=setup(),v=input(9),ready=await calls(f,v),other={auth:{...context.auth,uid:'syntheticOtherAdmin'}};
  f.documents.set('supportAdmins/syntheticOtherAdmin',{enabled:true,capabilities:['issue','issue_many','issue_all']});
  await assert.rejects(f.service.issueMail(other,ready),{code:'PREVIEW_REQUIRED'});checks++;
  const target=f.players[0];f.documents.get(`players/${target.player}/identity/public`).publicUid='999999999999';
  const r=await f.service.issueMail(context,ready);
  check(r.failedCount===1&&r.sentCount===1&&r.failures[0].code==='IDENTITY_CHANGED','changed public identity is not re-resolved to another player');
  check(!mails(f).some(([p])=>p.includes(target.player)),'failed recipient receives no mail');
}
console.log(`Support mail audience: ${checks} synthetic checks passed. Frozen selected/All cohorts, bounded preparation/delivery, explicit authority, per-player UUIDs, case/retry/claim invariants. No live service exercised.`);
