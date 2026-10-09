// Bounded regression: actual released journal commit, denied real RPC, then final native UI.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const summary=entry=>({sha256:hash(entry),pending:entry.pending,base:entry.base,digest:entry.record.digest,revision:entry.record.revision,coins:JSON.parse(entry.record.payload).coins,uploading_digest:entry.uploading?.record?.digest || null});
export async function legacyPendingFlow(h){
 const {record,seed,read,setup,launch,journal,snapshot,until,check,shot,confirmedClick,resumeProof,origin,report,checkpoint}=h;
 report.legacy_pending=[];
 for(const choice of ['auto','local','cloud']){
  const uid='fullflow-legacy-'+choice,base=await record(1,42000);await seed(uid,base);
  const d=await setup(uid);await d.page.goto(origin+'/legacy.html');
  await d.page.waitForFunction(()=>globalThis.__legacyBoot);
  const boot=await d.page.evaluate(()=>__legacyBoot);assert.equal(boot.ok,true);assert.equal(boot.revision,1);
  const payload=JSON.stringify({...JSON.parse(base.payload),coins:41000});
  const committed=await d.page.evaluate(({payload,boot})=>__legacyClient.commit(payload,boot.revision,boot.profileId),{payload,boot});
  assert.equal(committed.ok,true);assert.equal(committed.durable,true);assert.equal(committed.cloudConfirmed,false);
  const pending=await journal(d.page,uid);assert.equal(pending.pending,true);assert.equal(pending.record.payload,payload);assert.equal(pending.record.revision,2);
  check(true,'released '+choice+': actual old commit durably wrote pending IndexedDB record');
  await d.page.evaluate(()=>__legacyClient.sync());
  const attempts=await d.page.evaluate(()=>__legacyAttempts);assert.equal(attempts.length,1);assert.equal(attempts[0].result,'permission-denied');
  assert.equal(attempts[0].candidate.writerId,undefined);assert.equal(attempts[0].candidate.writerEpoch,undefined);
  assert.equal(attempts[0].candidate.record,JSON.stringify(pending.record));
  const denied=await journal(d.page,uid);assert.deepEqual(denied.record,pending.record);assert.equal(denied.base,base.digest);assert.equal(denied.pending,true);
  assert.deepEqual(denied.uploading,{base:base.digest,record:pending.record});assert.equal((await read(uid)).record,JSON.stringify(base));
  check(true,'released '+choice+': new rules denied actual unfenced old transaction without losing pending bytes');
  const cloud=choice==='auto'?base:await record(3,43000,base.profileId);if(choice!=='auto')await seed(uid,cloud);
  // Navigation destroys the released JS runtime; same browser context and origin preserve real IDB.
  await launch(d);assert.equal(new URL(d.page.url()).origin,origin);
  if(choice==='auto'){
   await until(async()=>!(await journal(d.page,uid))?.pending,'legacy automatic cloud acknowledgment');
   const migrated=await journal(d.page,uid),saved=await read(uid),owner=await read(uid,'owner');
   assert.deepEqual(migrated.record,denied.record);assert.equal(saved.record,JSON.stringify(denied.record));
   assert.equal(saved.writerId,owner.owner);assert.equal(saved.writerEpoch,owner.epoch);assert.equal((await snapshot(d.page)).choicesAvailable,false);
   check(true,'released auto: exact pending record reconciled and acknowledged with current fence, no choice needed');
  }else{
   await until(async()=>(await snapshot(d.page)).available,'legacy genuine conflict cards');
   assert.deepEqual(await journal(d.page,uid),denied);assert.equal((await read(uid)).record,JSON.stringify(cloud));
   const state=await snapshot(d.page);assert.deepEqual(state.choices.map(c=>c.coins),[41000,43000]);
   assert.equal(state.choices[0].device,'Unknown device');assert(state.choices.every(c=>Number.isFinite(c.lastSavedAt) && c.lastSavedLabel && c.lastSavedLabel!=='Unknown'),'legacy choice has meaningful Last saved');
   check(true,'released '+choice+': newer cloud never overwritten and exact old pending retained before choice');
   await confirmedClick(d.page,'cloud',choice,false);
   await until(async()=>!(await snapshot(d.page)).busy,'legacy cancelled choice');
   assert.deepEqual(await journal(d.page,uid),denied);assert.equal((await read(uid)).record,JSON.stringify(cloud));
   check(true,'released '+choice+': cancelled native confirmation preserves both exact branches');
   await confirmedClick(d.page,'cloud',choice,true);
   await until(async()=>!(await snapshot(d.page)).choicesAvailable,'legacy confirmed choice');
   const backup=await journal(d.page,uid,['choice-v1',uid]);assert.deepEqual(backup.local,denied);assert.equal(backup.cloudDocument.record,JSON.stringify(cloud));
   const selected=await journal(d.page,uid),saved=await read(uid);assert.equal(selected.pending,false);assert.equal(saved.record,JSON.stringify(selected.record));
   assert.equal(JSON.parse(selected.record.payload).coins,choice==='local'?41000:43000);
   if(choice==='local'){const owner=await read(uid,'owner');assert(selected.record.revision>cloud.revision);assert.equal(saved.writerId,owner.owner);assert.equal(saved.writerEpoch,owner.epoch);}
   check(true,'released '+choice+': confirmed selection protected exact originals and acknowledged chosen progress');
  }
  await shot(d.page,'legacy-'+choice+'-resumed');await resumeProof(d,choice==='cloud'?43000:41000);
  report.legacy_pending.push({uid,choice,old_commit:{ok:committed.ok,durable:committed.durable,cloudConfirmed:committed.cloudConfirmed,revision:committed.revision},denied_rpc:{result:attempts[0].result,base:attempts[0].base,candidate_digest:attempts[0].candidate.digest,candidate_record_sha256:hash(attempts[0].candidate.record)},pending_before:summary(pending),pending_after_denial:summary(denied),native_resume_coins:choice==='cloud'?43000:41000});checkpoint();
  await d.context.close();
 }
}
