'use strict';
// Real browser IndexedDB + synthetic cloud records. No Firebase account, SDK,
// production save, IAM, or network writes are used by this regression suite.
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const source=['little_leaf_vault','little_leaf_firebase'].map(name=>fs.readFileSync(`web/${name}.js`,'utf8'));
const fixture=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
(async()=>{
  const server=http.createServer((_,res)=>{res.setHeader('content-type','text/html');res.end('<!doctype html><title>Disposable recovery tests</title>');});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    const options={headless:true,chromiumSandbox:true};
    if(process.env.PLAYWRIGHT_CHROMIUM_CHANNEL) options.channel=process.env.PLAYWRIGHT_CHROMIUM_CHANNEL;
    if(process.env.CHROMIUM_PATH) options.executablePath=process.env.CHROMIUM_PATH;
    browser=await chromium.launch(options);
    const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}`);
    for(const content of source) await page.addScriptTag({content});
    const results=await page.evaluate(async fixture=>{
      const codec=LittleLeafAuthorityCodec,api=LittleLeafFirebase,clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
      const fail=code=>Object.assign(Error(code),{code}),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
      const checks=[];
      function ok(value,message){if(!value)throw Error(message);checks.push(message);}
      const journal=await api.openJournal(indexedDB);
      async function record(revision,coins,profileId=crypto.randomUUID()) {
        const r={format:2,profileId,revision,createdAt:1,updatedAt:revision+10,payload:JSON.stringify({...JSON.parse(fixture),coins}),digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
        r.digest=await codec.hash(codec.fingerprint(r));return r;
      }
      const doc=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
      async function rawPut(key,value){
        const db=await new Promise((resolve,reject)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);});
        try {await new Promise((resolve,reject)=>{const tx=db.transaction('accounts','readwrite');tx.objectStore('accounts').put(value,key);tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});} finally {db.close();}
      }
      async function scenario({matching=false,backup=null,cloudOverride=undefined}={}) {
        const id=crypto.randomUUID(),profile=crypto.randomUUID(),base=await record(1,100,profile),uploading=await record(2,110,profile),pendingRecord=await record(3,120,profile),cloudRecord=await record(4,900,profile);
        const pending={base:base.digest,pending:true,record:pendingRecord,uploading:{base:base.digest,record:uploading}};
        let identity=id,cloud=cloudOverride===undefined?doc(matching?pendingRecord:cloudRecord):cloudOverride,writes=0,readHook=null;
        await journal.replace(id,null,pending);
        if(backup)await rawPut(['recovery-v1',id],backup===true?pending:backup);
        const remote={async read(){if(readHook)await readHook();return clone(cloud);},async compareAndSet(){writes++;throw Error('Unexpected cloud write during recovery');}};
        const states=[],make=()=>api.createClient({uid:id,codec,journal,remote,currentUid:()=>identity,status:s=>states.push(s)}),client=make();
        return {id,client,make,pending,cloudRecord,states,remote,setCloud:r=>cloud=r,setUid:u=>identity=u,readHook:f=>readHook=f,writes:()=>writes,cloud:()=>clone(cloud)};
      }
      let h=await scenario(),boot=await h.client.boot(),preview=h.client.recoverySnapshot();
      ok(boot.code==='REVISION_CONFLICT','foreign cloud blocks boot instead of reconciling by revision');
      ok(preview.available && preview.canExport && !preview.busy && preview.cloudRevision===4 && preview.pendingRevision===3 && preview.expectedCloudDigest===h.cloudRecord.digest,'recovery preview identifies both revisions and exact cloud digest');
      ok(!JSON.stringify(preview).includes(h.id),'preview contains no account UID');
      ok(equal(await journal.read(h.id),h.pending) && h.writes()===0,'preview preserves pending and performs no cloud write');
      let exported=await h.client.exportRecovery();ok(exported.ok && equal(JSON.parse(exported.text).pendingEntry,h.pending) && !exported.text.includes(h.id),'export preserves exact pending entry including uploading/base without UID');
      const cloudBefore=h.cloud(),loaded=await h.client.recoverCloud(preview.expectedCloudDigest);
      ok(loaded.ok && loaded.revision===4 && loaded.profileId===h.cloudRecord.profileId && loaded.payload===h.cloudRecord.payload,'recovery returns ordinary native boot result for selected cloud');
      ok(equal(await journal.readRecoveryBackup(h.id),h.pending),'pending backup is exact and durably retained');
      ok(equal(await journal.read(h.id),{base:h.cloudRecord.digest,pending:false,record:h.cloudRecord}),'active journal is replaced with acknowledged cloud');
      ok(equal(h.cloud(),cloudBefore) && h.writes()===0,'recovery never writes remote cloud');
      ok((await h.client.boot()).revision===4 && (await h.client.recoverCloud(preview.expectedCloudDigest)).ok,'repeated boot and identical recovery clicks are idempotent');
      ok(!h.client.recoverySnapshot().available && h.client.recoverySnapshot().canExport,'successful recovery remains exportable');
      exported=await h.client.exportRecovery();ok(exported.ok && equal(JSON.parse(exported.text).pendingEntry,h.pending),'export after success uses the protected pending copy');
      const reloaded=h.make();ok((await reloaded.boot()).ok && reloaded.recoverySnapshot().canExport,'protected copy remains exportable after reload');
      ok((await reloaded.exportRecovery()).ok,'reloaded client exports protected backup');
      const committed=await h.client.commit(h.cloudRecord.payload,loaded.revision,loaded.profileId);
      ok(committed.ok && committed.revision===5,'recovery unblocks correct revision for subsequent local saves');
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_UNAVAILABLE' && (await journal.read(h.id)).record.revision===5,'repeated recovery cannot rewind newer local edits');
      ok(equal(await journal.readRecoveryBackup(h.id),h.pending),'later saves do not overwrite protected backup');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      const newer=await record(5,999,h.cloudRecord.profileId);h.setCloud(doc(newer));
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_CHANGED','changed cloud requires fresh confirmation');
      ok(h.client.recoverySnapshot().expectedCloudDigest===newer.digest && h.client.recoverySnapshot().cloudRevision===5,'changed cloud refreshes the visible preview');
      ok(equal(await journal.read(h.id),h.pending) && await journal.readRecoveryBackup(h.id)===null,'changed cloud does not alter either local slot');
      ok((await h.client.recoverCloud(newer.digest)).ok,'fresh digest confirmation permits the refreshed cloud');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      ok((await h.client.recoverCloud('')).code==='RECOVERY_CONFIRMATION_REQUIRED','recovery requires a nonempty verified digest');
      ok(equal(await journal.read(h.id),h.pending),'missing confirmation does not mutate pending');
      let release;h.readHook(()=>new Promise(resolve=>{release=resolve;}));
      const inFlight=h.client.recoverCloud(preview.expectedCloudDigest);
      await new Promise(resolve=>setTimeout(resolve,0));
      ok(h.client.recoverySnapshot().busy && (await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_BUSY','double click is single flight');
      h.setUid('different-account');release();
      ok((await inFlight).code==='NOT_READY' && equal(await journal.read(h.id),h.pending) && await journal.readRecoveryBackup(h.id)===null,'account switch during cloud read blocks local replacement');
      ok(!h.client.recoverySnapshot().available && !h.client.recoverySnapshot().canExport && h.client.recoverySnapshot().cloudRevision===null && h.client.recoverySnapshot().pendingRevision===null && (await h.client.exportRecovery()).code==='NOT_READY','account switch disables preview and export');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      h.client.close();ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='NOT_READY','closed client cannot recover');
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      h.readHook(async()=>{throw fail('OFFLINE');});
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='OFFLINE' && equal(await journal.read(h.id),h.pending),'offline recovery preserves pending and reports offline');
      h.readHook(null);ok((await h.client.recoverCloud(preview.expectedCloudDigest)).ok,'online retry can complete same pending recovery');

      for(const cloud of [null,{schema:1,record:'not-json'}]) {
        h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();h.setCloud(cloud);
        const failure=await h.client.recoverCloud(preview.expectedCloudDigest);
        ok(failure.code===(cloud?'CORRUPT_AUTHORITY':'RECOVERY_MISSING') && !h.client.recoverySnapshot().available,'missing or corrupt cloud stays distinct and blocks loading');
        ok(equal(await journal.read(h.id),h.pending) && await journal.readRecoveryBackup(h.id)===null && (await h.client.exportRecovery()).ok,'missing or corrupt cloud keeps pending exportable without mutation');
        h.setCloud(doc(h.cloudRecord));
        ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_CHANGED','restored cloud requires refreshed confirmation after invalidation');
        ok((await h.client.recoverCloud(preview.expectedCloudDigest)).ok,'restored valid cloud can recover after reconfirmation');
      }
      for(const cloud of [null,{schema:1,record:'not-json'}]) {
        h=await scenario({cloudOverride:cloud});
        ok((await h.client.boot()).code==='CORRUPT_AUTHORITY' && !h.client.recoverySnapshot().available,'initial missing or corrupt cloud never starts recoverable conflict');
        ok((await h.client.exportRecovery()).ok && equal(await journal.read(h.id),h.pending),'initial missing or corrupt cloud still preserves exportable valid pending');
      }

      h=await scenario();const older={...h.pending,record:await record(2,105,h.pending.record.profileId),uploading:null};await rawPut(['recovery-v1',h.id],older);await h.client.boot();preview=h.client.recoverySnapshot();
      ok(!preview.available && preview.canExport && /different protected/.test(preview.reason),'different protected backup fails closed at preview');
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_ARCHIVE_FULL','full protected backup cannot be overwritten');
      exported=JSON.parse((await h.client.exportRecovery()).text);
      ok(equal(exported.pendingEntry,h.pending) && equal(exported.protectedBackup,older),'full-backup export includes both exact entries for review');
      ok(equal(await journal.read(h.id),h.pending) && equal(await journal.readRecoveryBackup(h.id),older),'full backup preserves both local entries');
      h=await scenario({backup:{damaged:true}});await h.client.boot();preview=h.client.recoverySnapshot();
      ok(!preview.available && preview.canExport && (await h.client.recoverCloud(preview.expectedCloudDigest)).code==='RECOVERY_ARCHIVE_DAMAGED','malformed backup blocks replacement without preventing current pending export');
      exported=JSON.parse((await h.client.exportRecovery()).text);ok(equal(exported.pendingEntry,h.pending) && !exported.protectedBackup && exported.note,'malformed backup is not represented as a verified export');
      h=await scenario({backup:{damaged:true},matching:true});ok((await h.client.boot()).ok && !h.client.recoverySnapshot().canExport && (await h.client.exportRecovery()).code==='RECOVERY_ARCHIVE_DAMAGED','malformed backup does not block ordinary valid cloud boot');
      h=await scenario({backup:true});await h.client.boot();preview=h.client.recoverySnapshot();
      ok(preview.available && (await h.client.recoverCloud(preview.expectedCloudDigest)).ok,'same pending backup permits idempotent recovery');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      const changedLocal={...h.pending,record:await record(6,456,h.pending.record.profileId)};
      await journal.replace(h.id,h.pending,changedLocal);
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).code==='REVISION_CONFLICT','local-tab race aborts atomic recovery');
      ok(equal(await journal.read(h.id),changedLocal) && await journal.readRecoveryBackup(h.id)===null,'local-tab race keeps latest active and creates no stale backup');
      ok((await h.client.exportRecovery()).code==='REVISION_CONFLICT','export refuses stale local preview after another-tab edit');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      const originalPut=IDBObjectStore.prototype.put;
      IDBObjectStore.prototype.put=function(value,key){
        const request=originalPut.call(this,value,key);
        if(Array.isArray(key) && key[0]==='recovery-v1' && key[1]===h.id) request.addEventListener('success',()=>this.transaction.abort());
        return request;
      };
      let aborted;
      try {aborted=await h.client.recoverCloud(preview.expectedCloudDigest);} finally {IDBObjectStore.prototype.put=originalPut;}
      ok(!aborted.ok && equal(await journal.read(h.id),h.pending) && await journal.readRecoveryBackup(h.id)===null,'real IndexedDB abort after backup put rolls back backup and active together');
      ok((await h.client.recoverCloud(preview.expectedCloudDigest)).ok,'same pending safely retries after atomic storage failure');

      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      let guardCalls=0;
      try {await journal.recover(h.id,h.pending,{base:h.cloudRecord.digest,pending:false,record:h.cloudRecord},()=>{if(++guardCalls===3)throw fail('NOT_READY');});throw Error('Expected guard failure');} catch(e){ok(e.code==='NOT_READY','account guard rechecked after queued backup write');}
      ok(equal(await journal.read(h.id),h.pending) && await journal.readRecoveryBackup(h.id)===null,'account switch in IDB transaction aborts both writes');
      await rawPut(['recovery-v1',h.id],{different:'racing-backup'});
      try {await journal.recover(h.id,h.pending,{base:h.cloudRecord.digest,pending:false,record:h.cloudRecord},()=>{});throw Error('Expected archive failure');} catch(e){ok(e.code==='RECOVERY_ARCHIVE_FULL','journal transaction independently checks protected-backup race');}
      ok(equal(await journal.read(h.id),h.pending),'backup race never changes active pending');

      h=await scenario();const next={base:h.cloudRecord.digest,pending:false,record:h.cloudRecord};
      await journal.recover(h.id,h.pending,next,()=>{});await journal.recover(h.id,h.pending,next,()=>{});
      ok(equal(await journal.read(h.id),next) && equal(await journal.readRecoveryBackup(h.id),h.pending),'direct journal retry is idempotent after uncertain completed response');
      const strangeId='["recovery-v1","'+h.id+'"]';await journal.replace(strangeId,null,{distinct:'account'});
      ok(equal(await journal.readRecoveryBackup(h.id),h.pending),'compound backup key cannot collide with a string UID');

      // Known lost-ack proof must still take the original acknowledgment path.
      h=await scenario({matching:true});
      ok((await h.client.boot()).ok && !h.client.recoverySnapshot().available && await journal.readRecoveryBackup(h.id)===null,'exact cloud/pending digest proves a lost acknowledgment without recovery');
      ok(!(await journal.read(h.id)).pending && h.writes()===0,'known lost acknowledgment is acknowledged without duplicate cloud write');
      // New two-choice protocol uses its own immutable exact-pair bundle.
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();
      let choice=await h.client.prepareChoice('cloud',preview.expectedLocalDigest,preview.expectedCloudDigest);
      ok(choice.ok && await journal.readChoiceBackup(h.id)===null,'choice prepare does not mutate real IndexedDB');
      const choicePut=IDBObjectStore.prototype.put;
      IDBObjectStore.prototype.put=function(value,key){const q=choicePut.call(this,value,key);if(Array.isArray(key)&&key[0]==='choice-v1'&&key[1]===h.id)q.addEventListener('success',()=>this.transaction.abort());return q;};
      try{aborted=await h.client.confirmChoice(choice.selectionToken);}finally{IDBObjectStore.prototype.put=choicePut;}
      ok(!aborted.ok && equal(await journal.read(h.id),h.pending) && await journal.readChoiceBackup(h.id)===null,'choice transaction abort rolls back protected pair and active replacement together');
      ok((await h.client.confirmChoice(choice.selectionToken)).ok,'same prepared choice safely retries after atomic abort');
      let pair=await journal.readChoiceBackup(h.id);
      ok(equal(pair.local,h.pending)&&equal(pair.cloud,h.cloudRecord),'choice bundle retains exact local journal including upload intent and exact cloud record');
      ok((await h.client.confirmChoice(choice.selectionToken)).ok,'completed choice is idempotent with unchanged active record');
      const protectedPair=pair;
      const nextPending={base:h.cloudRecord.digest,pending:true,record:await record(5,111,h.cloudRecord.profileId)};
      await journal.replace(h.id,await journal.read(h.id),nextPending);h.setCloud(doc(await record(6,222,h.cloudRecord.profileId)));
      const repeated=h.make();await repeated.boot();ok(!repeated.recoverySnapshot().choicesAvailable,'second distinct choice blocks without silently evicting earlier pair');
      ok(equal(await journal.readChoiceBackup(h.id),protectedPair)&&equal(await journal.read(h.id),nextPending),'archive-full keeps both old protected pair and latest pending data');
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();choice=await h.client.prepareChoice('cloud',preview.expectedLocalDigest,preview.expectedCloudDigest);
      await rawPut(['choice-v1',h.id],{damaged:'existing'});
      ok((await h.client.confirmChoice(choice.selectionToken)).code==='RECOVERY_ARCHIVE_FULL','new archive raced after prepare is checked inside real transaction');
      ok(equal(await journal.read(h.id),h.pending),'archive race leaves current pending unchanged');
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();choice=await h.client.prepareChoice('local',preview.expectedLocalDigest,preview.expectedCloudDigest);
      let selectedWrites=0;
      h.remote.compareAndSet=async(id,base,next,guard)=>{guard();const current=h.cloud();if(current.digest===next.digest)return;if(current.digest!==base)throw fail('REVISION_CONFLICT');h.setCloud(next);selectedWrites++;};
      const selected=await h.client.confirmChoice(choice.selectionToken);
      ok(selected.ok && selected.revision===choice.revision && selected.payload===choice.payload && selectedWrites===1,'explicit local choice publishes exact prevalidated candidate through CAS');
      pair=await journal.readChoiceBackup(h.id);ok(equal(pair.local,h.pending)&&equal(pair.cloud,h.cloudRecord),'local choice protects both source branches before remote replacement');
      ok(!(await journal.read(h.id)).pending,'selected local branch gets exact cloud acknowledgment');
      return checks;
    },fixture);
    const {createHash}=require('node:crypto');
    console.log('Recovery source SHA-256: '+JSON.stringify(Object.fromEntries(['web/little_leaf_vault.js','web/little_leaf_firebase.js','tests/firebase_recovery_browser.js','tests/fixtures/startup-retry-v15.json'].map(name=>[name,createHash('sha256').update(fs.readFileSync(name)).digest('hex')]))));
    assert(results.length>=45);console.log(`Firebase recovery: ${results.length} real-IndexedDB/synthetic-cloud assertions passed (${browser.version()}).`);
    for(const result of results)console.log(`PASS ${result}`);
  } finally {if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});
