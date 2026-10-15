'use strict';
// Generated saves and the atomic in-memory IDB fixture only. No browser,
// production Firebase, player profile or filesystem save is opened or changed.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const {FixtureIDB}=require('../fixtures/save_log_idb_fixture');
const root={crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout};
for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
const api=root.LittleLeafFirebase,codec=root.LittleLeafAuthorityCodec;
const legacy=fs.readFileSync('tests/fixtures/unified_building/public_closed.json','utf8');
const modern=fs.readFileSync('tests/fixtures/unified_building_candidate.json','utf8');
const clone=value=>structuredClone(value),fail=code=>Object.assign(Error(code),{code});
const doc=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
let checks=0;const ok=(value,message)=>{assert(value,message);checks++;};
async function record(payload=legacy,revision=7,profileId=webcrypto.randomUUID()){
 const r={format:2,profileId,revision,createdAt:1,updatedAt:2,payload,digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
 r.digest=await codec.hash(codec.fingerprint(r));return r;
}
async function harness(){
 const idb=new FixtureIDB(),journal=await api.openJournal(idb),uid='generated-'+webcrypto.randomUUID(),original=await record();
 await journal.replace(uid,null,{base:original.digest,pending:false,record:original});
 let cloud=doc(original),writes=0,attempts=0,identity=uid,mode='',time=0,renewHook=null;
 const ownership={assertActive(){return{writerId:'generated-writer',writerEpoch:7};},async renew(){if(renewHook)await renewHook();},close(){}};
 const remote={async read(){return clone(cloud);},async compareAndSet(id,base,next,guard){
  attempts++;guard();if(mode==='before')throw fail('OFFLINE');
  if(cloud?.digest!==next.digest){if(base!==(cloud?.digest||null))throw fail('REVISION_CONFLICT');cloud=clone(next);writes++;}
  if(mode==='after')throw fail('OFFLINE');
 }};
 const make=()=>api.createClient({uid,codec,journal,remote,ownership,currentUid:()=>identity,status(){},now:()=>time});
 const rows=()=>idb.databases.get('little-leaf.firebase-journal.v1').stores.get('accounts');
 const key=JSON.stringify(['pre-grid-v1',uid]);
 return {idb,journal,uid,original,make,remote,ownership,cloud:()=>clone(cloud),writes:()=>writes,attempts:()=>attempts,
  archive:()=>rows().get(key),setArchive:value=>value===undefined?rows().delete(key):rows().set(key,value),
  local:()=>journal.read(uid),setLocal:async value=>journal.replace(uid,await journal.read(uid),value),
  setMode:value=>mode=value,setCloud:value=>cloud=clone(value),setUid:value=>identity=value,
  onRenew:hook=>renewHook=hook,tick:()=>time+=30001};
}
async function migrate(h){const c=h.make(),boot=await c.boot();assert(boot.ok);const saved=await c.commit(modern,boot.revision,boot.profileId);assert(saved.ok);return{c,saved};}
(async()=>{
 for(const damage of ['missing','corrupt']){
  const h=await harness(),{c}=await migrate(h),pending=await h.local();c.close();
  h.setArchive(damage==='missing'?undefined:'damaged original archive');const archive=h.archive(),reopened=h.make(),result=await reopened.boot();
  ok(!result.ok,`${damage} original blocks reopened pending migration`);
  ok(h.attempts()===0&&h.writes()===0,`${damage} original never reaches cloud CAS`);
  ok(reopened.recoverySnapshot().canExport,`${damage} original still permits pending export`);
  const exported=await reopened.exportRecovery();ok(exported.ok,`${damage} original does not block safe read-only export`);
  assert.deepEqual(JSON.parse(exported.text).pendingEntry,pending);checks++;
  ok(JSON.parse(exported.text).note.includes('Upload remains blocked'),`${damage} archive export discloses its limit`);
  assert.deepEqual(await h.local(),pending);assert.equal(h.archive(),archive);checks+=2;reopened.close();
 }
 // Old-format pending entries remain compatible; an actual revision-zero
 // startup is the other explicit archive-free origin, not a missing marker.
 {
  const h=await harness(),pending={base:h.original.digest,pending:true,record:await record(legacy,8,h.original.profileId)};
  await h.setLocal(pending);const c=h.make();ok((await c.boot()).ok&&h.writes()===1,'legacy pending entry without new metadata still uploads');
  ok(!Object.hasOwn(await h.local(),'preGrid')&&h.archive()===undefined,'legacy pending does not acquire invented provenance');c.close();
 }
 {
  const h=await harness();await h.setLocal(null);h.setCloud(null);const c=h.make(),boot=await c.boot();
  ok(boot.ok&&boot.source==='fresh','actual empty account boots revision-zero');ok((await c.commit(modern,0,boot.profileId)).ok,'fresh preset stages without migration original');
  const pending=await h.local();assert.deepEqual(pending.preGrid,{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]});checks++;c.close();
  const reopened=h.make();ok((await reopened.boot()).ok&&h.writes()===1&&h.archive()===undefined,'explicit fresh pending marker survives reopen without archive');reopened.close();
 }
 // A valid but unrelated original must not satisfy the required archive identity.
 {
  const h=await harness(),{c}=await migrate(h),pending=await h.local();c.close();
  const other=await harness();(await migrate(other)).c.close();h.setArchive(other.archive());
  const reopened=h.make();ok(!(await reopened.boot()).ok,'unrelated valid archive blocks reopen');
  ok(h.attempts()===0,'unrelated archive never reaches CAS');assert.deepEqual(await h.local(),pending);checks++;reopened.close();
 }
 // The requirement is persisted, bounded, independent of source payload size,
 // and retained after acknowledgment and a second ordinary edit/reopen.
 {
  const h=await harness(),{c,saved}=await migrate(h),pending=await h.local(),archives=await codec.verifyPreGridArchives(h.archive());
  ok(pending.preGrid.format==='little-leaf.pre-grid-requirement.v1','journal stores versioned requirement');
  assert.deepEqual(pending.preGrid.archiveDigests,[archives[0].archiveDigest]);checks++;
  ok(JSON.stringify(pending.preGrid).length<200,'requirement does not duplicate original payload');c.close();
  const reopened=h.make(),boot=await reopened.boot();ok(boot.ok&&h.writes()===1,'valid archive resumes one exact migration upload');
  assert.deepEqual((await h.local()).preGrid,pending.preGrid);checks++;
  ok((await reopened.commit(modern,saved.revision,saved.profileId)).ok,'later edit retains migrated lineage');
  assert.deepEqual((await h.local()).preGrid,pending.preGrid);checks++;reopened.close();
  const again=h.make();ok((await again.boot()).ok&&h.writes()===2,'later pending edit resumes with original requirement');again.close();
  const acknowledged=h.make();ok((await acknowledged.boot()).ok,'acknowledged migrated journal reopens');
  assert.deepEqual((await h.local()).preGrid,pending.preGrid);checks++;acknowledged.close();
 }
 // Appending an independently protected original does not invalidate earlier
 // requirements. Removing a required one, even with valid checksums, does.
 {
  const h=await harness(),{c}=await migrate(h),original=h.archive();c.close();
  const other=await harness();(await migrate(other)).c.close();h.setArchive(JSON.stringify([...JSON.parse(original),...JSON.parse(other.archive())]));
  const reopened=h.make();ok((await reopened.boot()).ok&&h.writes()===1,'append-only archive growth permits exact required original');reopened.close();
 }
 for(const action of ['commit','preserveRuntime']){
  const h=await harness(),{c,saved}=await migrate(h),before=await h.local();h.setArchive(undefined);
  const result=await c[action](modern,saved.revision,saved.profileId);
  ok(!result.ok,`${action} cannot silently erase an existing archive requirement`);
  assert.deepEqual(await h.local(),before);checks++;ok(h.attempts()===0,`${action} archive failure never touches cloud`);c.close();
 }
 for(const change of ['missing','unknown','extra','duplicate','wrong-digest','too-many']){
  const h=await harness(),{c}=await migrate(h),pending=await h.local();c.close();
  if(change==='missing')delete pending.preGrid;
  if(change==='unknown')pending.preGrid.format='little-leaf.pre-grid-requirement.v2';
  if(change==='extra')pending.preGrid.future=true;
  if(change==='duplicate')pending.preGrid.archiveDigests.push(pending.preGrid.archiveDigests[0]);
  if(change==='wrong-digest')pending.preGrid.archiveDigests=['f'.repeat(64)];
  if(change==='too-many')pending.preGrid.archiveDigests=Array.from({length:9},(_,i)=>String(i).repeat(64));
  await h.setLocal(pending);const archive=h.archive(),reopened=h.make();
  ok(!(await reopened.boot()).ok,`${change} requirement fails closed`);ok(h.attempts()===0,`${change} requirement never reaches CAS`);
  assert.deepEqual(await h.local(),pending);assert.equal(h.archive(),archive);checks+=2;reopened.close();
 }
 // A frozen snapshot can differ from the newest pending revision. Its archive
 // requirement must survive an offline CAS and be checked again independently.
 for(const damage of ['missing','snapshot-marker']){
  const h=await harness(),{c}=await migrate(h);h.setMode('before');await c.sync();
  const pending=await h.local();ok(!!pending.uploading,'offline attempt retains exact upload');
  assert.deepEqual(pending.uploading.preGrid,pending.preGrid);checks++;c.close();
  if(damage==='missing')h.setArchive(undefined);else {delete pending.uploading.preGrid;await h.setLocal(pending);}
  h.setMode('');const attempts=h.attempts(),reopened=h.make();ok(!(await reopened.boot()).ok,`${damage} snapshot requirement blocks retry`);
  ok(h.attempts()===attempts&&h.writes()===0,`${damage} snapshot cannot issue another CAS`);assert.deepEqual(await h.local(),pending);checks++;reopened.close();
 }
 // The second archive check occurs after lease renewal, not just at staging.
 for(const change of ['archive','account','owner']){
  const h=await harness(),{c}=await migrate(h);h.onRenew(()=>{
   if(change==='archive')h.setArchive(undefined);
   if(change==='account')h.setUid('another-account');
   if(change==='owner')h.ownership.assertActive=()=>{throw fail('OWNERSHIP_LOST');};
  });
  await c.sync();ok(h.attempts()===0,`${change} change during renewal prevents CAS`);
  const pending=await h.local();ok(pending.pending&&!!pending.uploading,`${change} change preserves frozen pending upload`);
  if(change==='archive'){
   ok(c.recoverySnapshot().canExport,'archive-blocked running client can export its frozen pending journal');
   const exported=await c.exportRecovery();ok(exported.ok,'running archive failure does not block read-only export');
   assert.deepEqual(JSON.parse(exported.text).pendingEntry,pending);checks++;
  }
  c.close();
 }
 // Exercise the production remote callback with generated transaction objects.
 // Archive loss during server reads and a retried callback must both abort
 // before tx.set, while retaining the ordinary writer/epoch/base fences.
 for(const phase of ['success','server-read','transaction-retry','server-owner','server-base']){
  const h=await harness(),{c}=await migrate(h);let sets=0,attempts=0;
  const owner={owner:'generated-writer',epoch:7,ack:false};h.ownership.sessionRef='generated-session';
  const sdk={doc:()=> 'generated-save',async runTransaction(db,action){
   const run=async()=>{attempts++;await action({async get(ref){
    if(ref==='generated-session')return{exists:()=>true,data:()=>phase==='server-owner'?{...owner,epoch:8}:owner};
    if(phase==='server-read'||phase==='transaction-retry'&&attempts===2)h.setArchive(undefined);
    return{exists:()=>true,data:()=>phase==='server-base'?{...h.cloud(),digest:'f'.repeat(64)}:h.cloud()};
   },set(ref,value){sets++;ok(value.writerId==='generated-writer'&&value.writerEpoch===7,'CAS retains exact writer fence');}});};
   await run();if(phase==='transaction-retry'){sets=0;await run();}
  }};
  const production=api.createRemote({},sdk,h.ownership);h.remote.compareAndSet=production.compareAndSet;
  await c.sync();ok(sets===(phase==='success'?1:0),`${phase} production CAS writes only with intact archive and fences`);
  if(phase!=='success')ok((await h.local()).pending,`${phase} leaves pending progress intact`);c.close();
 }
 // Lost acknowledgment is still uncertain, never an excuse for a second write.
 {
  const h=await harness(),{c}=await migrate(h);h.setMode('after');await c.sync();
  const pending=await h.local();ok(h.writes()===1&&pending.pending&&!!pending.uploading,'lost acknowledgment retains exact uncertain snapshot');c.close();
  h.setMode('');const reopened=h.make();ok((await reopened.boot()).ok&&h.writes()===1&&h.attempts()===1,'cloud digest readback reconciles without replay');
  assert.deepEqual((await h.local()).preGrid,pending.preGrid);checks++;reopened.close();
 }
 {
  const h=await harness(),{c,saved}=await migrate(h);h.setMode('before');await c.sync();const frozen=(await h.local()).uploading;
  const later=await c.commit(modern,saved.revision,saved.profileId);ok(later.ok,'later local edit can coexist with an offline frozen upload');
  assert.deepEqual((await h.local()).uploading,frozen);checks++;c.close();h.setMode('');
  const reopened=h.make();ok((await reopened.boot()).ok,'frozen older upload reopens with valid original');
  let local=await h.local();ok(local.pending&&local.record.revision===later.revision&&local.base===frozen.record.digest,'older acknowledgment keeps newer durable progress pending');
  assert.deepEqual(local.preGrid,frozen.preGrid);checks++;h.tick();await reopened.sync();local=await h.local();
  ok(!local.pending&&h.writes()===2&&local.base===local.record.digest,'newer pending revision uploads with the same original requirement');reopened.close();
 }
 // A valid fresh/cloud-origin grid save explicitly needs no local migration
 // archive. Unknown building contracts are never rewritten into that case.
 {
  const h=await harness();await h.setLocal(null);const r=await record(modern);h.setCloud(doc(r));
  const c=h.make(),boot=await c.boot();ok(boot.ok,'new device can adopt a valid grid cloud save');
  assert.deepEqual((await h.local()).preGrid,{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]});checks++;
  ok((await c.commit(modern,r.revision,r.profileId)).ok,'cloud-origin grid save can stage an ordinary edit');await c.sync();
  ok(h.writes()===1&&h.archive()===undefined,'cloud-origin edit does not invent an original archive');c.close();
 }
 for(const change of ['building','wall']){
  const h=await harness(),pending={base:h.original.digest,pending:true,record:await record(JSON.stringify({...JSON.parse(modern),...(change==='building'?{building_format:'little_leaf.grid_building.v2'}:{wall_format:4})}),8,h.original.profileId),preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}};
  await h.setLocal(pending);const c=h.make();ok(!(await c.boot()).ok,`unknown ${change} schema blocks reopen`);
  ok(h.attempts()===0,`unknown ${change} schema never reaches CAS`);assert.deepEqual(await h.local(),pending);checks++;c.close();
 }
 // Explicit local choice archives the real old cloud identity before rekeying
 // the selected branch, then persists that requirement through offline reopen.
 {
  const h=await harness(),localRecord=await record(modern,9),pending={base:'0'.repeat(64),pending:true,record:localRecord,preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}};
  await h.setLocal(pending);const c=h.make();ok((await c.boot()).code==='REVISION_CONFLICT','choice fixture requires explicit review');
  const preview=c.recoverySnapshot(),prepared=await c.prepareChoice('local',preview.expectedLocalDigest,preview.expectedCloudDigest);
  ok(prepared.ok&&h.archive()===undefined,'choice preparation remains read-only');h.setMode('before');
  ok((await c.confirmChoice(prepared.selectionToken)).code==='OFFLINE','choice stages before uncertain network result');
  const staged=await h.local(),archives=await codec.verifyPreGridArchives(h.archive());
  ok(staged.record.profileId===h.original.profileId&&archives[0].digest===h.original.digest,'choice requirement uses true original cloud identity');
  assert.deepEqual(staged.preGrid.archiveDigests,[archives[0].archiveDigest]);checks++;
  assert.deepEqual(staged.uploading.preGrid,staged.preGrid);checks++;c.close();h.setArchive(undefined);h.setMode('');
  const attempts=h.attempts(),reopened=h.make();ok(!(await reopened.boot()).ok&&h.attempts()===attempts,'staged choice cannot upload after original archive loss');
  assert.deepEqual(await h.local(),staged);checks++;reopened.close();
 }
 for(const action of ['choice','recover']){
  const h=await harness(),cloud=await record(modern,9),pending={base:'0'.repeat(64),pending:true,record:h.original};
  h.setCloud(doc(cloud));await h.setLocal(pending);const c=h.make();ok((await c.boot()).code==='REVISION_CONFLICT',`${action} cloud selection starts from a reviewed conflict`);
  const preview=c.recoverySnapshot();let selected;
  if(action==='choice'){const prepared=await c.prepareChoice('cloud',preview.expectedLocalDigest,preview.expectedCloudDigest);assert(prepared.ok);selected=await c.confirmChoice(prepared.selectionToken);}
  else selected=await c.recoverCloud(preview.expectedCloudDigest);
  ok(selected.ok&&h.attempts()===0,`${action} cloud selection does not upload`);const local=await h.local(),archives=await codec.verifyPreGridArchives(h.archive());
  assert.deepEqual(local.preGrid.archiveDigests,[archives[0].archiveDigest]);checks++;
  ok(archives[0].digest===h.original.digest,`${action} retains the true original local identity`);c.close();h.setArchive(undefined);
  const reopened=h.make();ok(!(await reopened.boot()).ok,`${action} acknowledged selection retains its archive requirement`);
  assert.deepEqual(await h.local(),local);checks++;reopened.close();
 }
 // The exact centered v2/wall4 pair is supported; each partial/crossed pair
 // remains invalid. A v1-to-v2 save must preserve v1's exact payload first.
 const centered=fs.readFileSync('tests/fixtures/unified_building_v2_candidate-modern.json','utf8'),centeredData=JSON.parse(centered);
 for(const pair of [[3,'little_leaf.grid_building.v2'],[4,'little_leaf.grid_building.v1'],[5,'little_leaf.grid_building.v2'],[4,'unknown']]){
  const h=await harness(),c=h.make(),boot=await c.boot(),before=await h.local();
  const bad=JSON.stringify({...centeredData,wall_format:pair[0],building_format:pair[1]});
  ok(!(await c.commit(bad,boot.revision,boot.profileId)).ok,'crossed or unknown building marker pair refuses staging');
  assert.deepEqual(await h.local(),before);checks++;ok(h.archive()===undefined&&h.attempts()===0,'invalid marker pair preserves original authority and archive');c.close();
 }
 for(const sourcePayload of [legacy,modern]){
  const h=await harness(),source=await record(sourcePayload);h.original=source;h.setCloud(doc(source));
  await h.setLocal({base:source.digest,pending:false,record:source,...(sourcePayload===modern?{preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}}:{})});
  const c=h.make(),boot=await c.boot();ok(boot.ok,'source building generation boots');
  ok((await c.commit(centered,boot.revision,boot.profileId)).ok,'exact centered pair stages only after original archive proof');
  const pending=await h.local(),archives=await codec.verifyPreGridArchives(h.archive());
  ok(archives.length===1&&archives[0].payload===sourcePayload&&archives[0].recordText===JSON.stringify(source),'upgrade archive retains exact original payload and record bytes');
  assert.deepEqual(pending.preGrid.archiveDigests,[archives[0].archiveDigest]);checks++;
  c.close();const reopened=h.make();ok((await reopened.boot()).ok&&h.writes()===1,'centered pending save reopens and uploads with exact archive');
  const accepted=await h.local();ok(accepted.record.payload===centered&&!accepted.pending,'centered payload remains exact through acknowledgment');reopened.close();
 }
 {
  const h=await harness(),source=await record(modern);h.setCloud(doc(source));await h.setLocal({base:source.digest,pending:false,record:source,preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}});
  const c=h.make(),boot=await c.boot();ok((await c.commit(centered,boot.revision,boot.profileId)).ok,'v1 upgrade stages for archive-loss control');
  const pending=await h.local();c.close();h.setArchive(undefined);const reopened=h.make();
  ok(!(await reopened.boot()).ok&&h.attempts()===0,'missing v1 original prevents centered pending upload');assert.deepEqual(await h.local(),pending);checks++;reopened.close();
 }
 for(const name of ['candidate-grass','candidate-rebuilt']){
  const payload=fs.readFileSync('tests/fixtures/unified_building_v2_'+name+'.json','utf8'),h=await harness(),c=h.make(),boot=await c.boot();
  ok((await c.commit(payload,boot.revision,boot.profileId)).ok,'actual native '+name+' v2 save passes the authority boundary');
  const local=await h.local(),archives=await codec.verifyPreGridArchives(h.archive());ok(local.record.payload===payload&&archives[0].payload===legacy,'actual native '+name+' preserves new and original exact bytes');c.close();
 }
 console.log(JSON.stringify({passed:true,checks,synthetic_only:true,real_indexeddb:false,real_firebase:false}));
})().catch(error=>{console.error(error);process.exitCode=1;});
