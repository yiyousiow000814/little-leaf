'use strict';
// Synthetic records only. The browser wrapper runs these same transitions in real IDB.
async function permissionCutover({api,legacy,codec,journal,fixture}) {
  const checks=[],clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
  const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const check=(value,message)=>{if(!value)throw Error(message);checks.push(message);};
  const record=async(revision,coins,profileId=globalThis.crypto.randomUUID())=>{
    const r={format:2,profileId,revision,createdAt:1,updatedAt:revision+10,payload:JSON.stringify({...JSON.parse(fixture),coins}),digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
    r.digest=await codec.hash(codec.fingerprint(r));return r;
  };
  const doc=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
  const fence={writerId:'00000000-0000-4000-8000-000000000010',writerEpoch:1};
  const owner={assertActive:()=>fence,snapshot:()=>({status:'active',serverOwnership:true}),close(){}};
  let account='legacy-cutover-synthetic',cloud=doc(await record(1,100)),deny=true,writes=0,time=100000;
  const originalCloud=clone(cloud),states=[];
  const remote={read:async()=>clone(cloud),compareAndSet:async(uid,base,next,guard)=>{
    guard();check(base===cloud.digest,'upload compares the unchanged cloud base');
    if(deny)throw Object.assign(Error('Synthetic rules refusal'),{code:'permission-denied'});
    cloud={...clone(next),...fence};writes++;
  }};
  const client=which=>which.createClient({uid:'legacy-cutover-synthetic',codec,remote,journal,currentUid:()=>account,status:s=>states.push(s),ownership:which===api?owner:null,now:()=>time});
  let c=client(legacy);check((await c.boot()).ok,'exact b8 legacy adapter boots synthetic cloud');
  const saved=await c.commit(JSON.stringify({...JSON.parse(fixture),coins:110}),1,cloud.profileId);
  check(saved.ok && saved.durable && !saved.cloudConfirmed,'legacy commit is durable locally without cloud confirmation');
  await c.sync();const pending=await journal.read(account);
  check(pending.pending && pending.record.revision===2 && JSON.parse(pending.record.payload).coins===110,'denied legacy upload retains latest pending revision and payload');
  check(equal(cloud,originalCloud) && writes===0 && states.at(-1)==='conflict','denied legacy upload never reports saved or changes cloud');
  check((await c.commit(pending.record.payload,2,pending.record.profileId)).code==='NOT_READY','legacy stopped client cannot keep claiming save success');
  c=client(legacy);const boot=await c.boot();
  check(!boot.ok && boot.code==='permission-denied' && equal(await journal.read(account),pending),'legacy re-entry rejects upload and preserves exact durable pending bytes');
  // Same-origin upgrade uses the same journal, never transfers an itch-origin save.
  deny=false;c=client(api);const upgraded=await c.boot();
  const upgradedEntry=await journal.read(account);
  check(upgraded.ok && upgraded.revision===2 && upgraded.profileId===pending.record.profileId && upgraded.payload===pending.record.payload,'compatible same-origin upgrade resumes the exact pending cafe');
  check(!upgradedEntry.pending && cloud.digest===pending.record.digest && cloud.writerId===fence.writerId,'compatible fenced upload acknowledges that pending revision without resetting it');
  deny=true;states.length=0;
  const receipt=await c.commit(JSON.stringify({...JSON.parse(fixture),coins:120}),2,pending.record.profileId);
  check(receipt.ok && receipt.durable && !receipt.cloudConfirmed,'compatible local commit remains durable before denied upload');
  time+=40000;await c.sync();
  check(states.at(-1)==='permission-denied' && c.recoverySnapshot().canExport && /refused/.test(c.recoverySnapshot().reason),'compatible denial is truthful and immediately offers protected export');
  check(c.ownershipSnapshot().ownershipPaused && !c.ownershipSnapshot().canRequestTakeover,'permission denial pauses ownership gameplay rather than pretending takeover fixes it');
  const exported=await c.exportRecovery();
  check(exported.ok && equal(JSON.parse(exported.text).pendingEntry,await journal.read(account)),'export contains the exact current pending journal without a cloud write');
  const preserved=await c.preserveRuntime(JSON.stringify({...JSON.parse(fixture),coins:125}),receipt.revision,pending.record.profileId);
  const latest=await journal.read(account),latestExport=await c.exportRecovery();
  check(preserved.ok && latestExport.ok && equal(JSON.parse(latestExport.text).pendingEntry,latest),'final paused native snapshot remains exportable as the latest durable copy');
  check(c.recoverySnapshot().pendingRevision===latest.record.revision,'recovery metadata identifies the latest native pending revision');
  const changed={...clone(latest),device:'Mac'};await journal.replace(account,latest,changed);
  check((await c.exportRecovery()).code==='REVISION_CONFLICT','another-tab change refuses stale export without replacing storage');
  account='different-synthetic-account';
  check(!c.recoverySnapshot().canExport && (await c.exportRecovery()).code==='NOT_READY','account change hides and blocks pending export');
  return {passed:true,checks,synthetic_only:true,production_read_or_write:false,legacy_pending_record:pending.record};
}
if(typeof module!=='undefined')module.exports=permissionCutover;
if(typeof window!=='undefined')window.permissionCutover=permissionCutover;
if(typeof require!=='undefined' && require.main===module)(async()=>{
  const fs=require('node:fs'),vm=require('node:vm'),{webcrypto,createHash}=require('node:crypto');
  const legacyBytes=fs.readFileSync('tests/fixtures/firebase-legacy-b8b80ee.js');
  if(createHash('sha256').update(legacyBytes).digest('hex')!=='04774d3495b891c95e00a5525b6d74fab93aa6eb2b84199e065a82369d0fa6bc')throw Error('Frozen legacy source changed');
  const root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
  vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_vault.js','utf8'),root);
  vm.runInNewContext(legacyBytes.toString(),root);const legacy=root.LittleLeafFirebase;
  vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase.js','utf8'),root);
  const data=new Map(),clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
  const journal={read:async id=>clone(data.get(id)||null),readRecoveryBackup:async()=>null,replace:async(id,old,next)=>{
    if(JSON.stringify(data.get(id)||null)!==JSON.stringify(old))throw Object.assign(Error('CAS conflict'),{code:'REVISION_CONFLICT'});data.set(id,clone(next));
  }};
  console.log(JSON.stringify(await permissionCutover({api:root.LittleLeafFirebase,legacy,codec:root.LittleLeafAuthorityCodec,journal,fixture:fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8')}),null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
