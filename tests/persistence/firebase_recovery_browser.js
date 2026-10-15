'use strict';
// Real browser IndexedDB + synthetic cloud records. No Firebase account, SDK,
// production save, IAM, or network writes are used by this regression suite.
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http');
const {sourcePath}=require('../tooling/source_paths');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const source=['little_leaf_vault','little_leaf_firebase'].map(name=>fs.readFileSync(`platform/web/${name}.js`,'utf8'));
const fixture=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const modernFixture=fs.readFileSync('tests/fixtures/unified_building_candidate.json','utf8');
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
    const results=await page.evaluate(async ({fixture,modernFixture})=>{
      const codec=LittleLeafAuthorityCodec,api=LittleLeafFirebase,clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
      const fail=code=>Object.assign(Error(code),{code}),equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
      const checks=[];
      function ok(value,message){if(!value)throw Error(message);checks.push(message);}
      let connection,openCount=0;
      const factory={open(...args){openCount++;const request=indexedDB.open(...args);request.addEventListener('success',()=>{connection=request.result;});return request;}};
      const journal=await api.openJournal(factory);
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
      const repeated=h.make();await repeated.boot();ok(repeated.recoverySnapshot().choicesAvailable,'second distinct choice remains available without evicting earlier pair');
      ok(equal(await journal.readChoiceBackup(h.id),protectedPair)&&equal(await journal.read(h.id),nextPending),'preview keeps earlier pair and latest pending data');
      const secondPreview=repeated.recoverySnapshot(),secondChoice=await repeated.prepareChoice('cloud',secondPreview.expectedLocalDigest,secondPreview.expectedCloudDigest);
      ok(secondChoice.ok&&(await repeated.confirmChoice(secondChoice.selectionToken)).ok,'second conflict completes through real atomic journal');
      let pairs=(await journal.readChoiceBackup(h.id)).archives;
      ok(pairs.length===2&&equal(pairs[0],protectedPair),'second choice retains first pair byte-for-byte inside bounded archive');
      const pairExport=await repeated.exportRecovery();ok(pairExport.ok&&equal(JSON.parse(pairExport.text).protectedChoices,pairs),'export retains every protected pair');
      for(let i=2;i<8;i++){
        const active=await journal.read(h.id),pending={base:active.record.digest,pending:true,record:await record(10+i*2,100+i,h.cloudRecord.profileId)};
        await journal.replace(h.id,active,pending);h.setCloud(doc(await record(11+i*2,200+i,h.cloudRecord.profileId)));
        const current=h.make();await current.boot();const snapshot=current.recoverySnapshot(),selection=await current.prepareChoice('cloud',snapshot.expectedLocalDigest,snapshot.expectedCloudDigest);
        ok(selection.ok&&(await current.confirmChoice(selection.selectionToken)).ok,'bounded additional choice '+i+' preserves earlier data');
      }
      pairs=(await journal.readChoiceBackup(h.id)).archives;ok(pairs.length===8&&equal(pairs[0],protectedPair),'eight-pair bound retains original pair');
      const active=await journal.read(h.id);await journal.replace(h.id,active,{base:active.record.digest,pending:true,record:await record(50,111,h.cloudRecord.profileId)});h.setCloud(doc(await record(51,222,h.cloudRecord.profileId)));
      const full=h.make();await full.boot();ok(!full.recoverySnapshot().choicesAvailable&&(await full.exportRecovery()).ok,'full archive stops safely and all copies remain exportable');
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();choice=await h.client.prepareChoice('cloud',preview.expectedLocalDigest,preview.expectedCloudDigest);
      await rawPut(['choice-v1',h.id],{damaged:'existing'});
      ok((await h.client.confirmChoice(choice.selectionToken)).code==='RECOVERY_ARCHIVE_DAMAGED','damaged archive raced after prepare is checked inside real transaction');
      ok(equal(await journal.read(h.id),h.pending),'archive race leaves current pending unchanged');
      h=await scenario();await h.client.boot();preview=h.client.recoverySnapshot();choice=await h.client.prepareChoice('local',preview.expectedLocalDigest,preview.expectedCloudDigest);
      let selectedWrites=0;
      h.remote.compareAndSet=async(id,base,next,guard)=>{guard();const current=h.cloud();if(current.digest===next.digest)return;if(current.digest!==base)throw fail('REVISION_CONFLICT');h.setCloud(next);selectedWrites++;};
      const selected=await h.client.confirmChoice(choice.selectionToken);
      ok(selected.ok && selected.revision===choice.revision && selected.payload===choice.payload && selectedWrites===1,'explicit local choice publishes exact prevalidated candidate through CAS');
      pair=await journal.readChoiceBackup(h.id);ok(equal(pair.local,h.pending)&&equal(pair.cloud,h.cloudRecord),'local choice protects both source branches before remote replacement');
      ok(!(await journal.read(h.id)).pending,'selected local branch gets exact cloud acknowledgment');
      {
      // A closed connection must not turn every later autosave into a failure.
      let lifecycleCloud=null;
      const lifecycle=api.createClient({uid:'synthetic-journal-lifecycle',codec,journal,currentUid:()=> 'synthetic-journal-lifecycle',status(){},
        remote:{async read(){return lifecycleCloud;},async compareAndSet(id,base,next,guard){guard();lifecycleCloud=next;}}});
      let lifecycleResult=await lifecycle.boot();ok(lifecycleResult.ok,'lifecycle fixture boots in disposable account');
      for(let i=0;i<3;i++){
        connection.close();const beforeOpen=openCount;
        lifecycleResult=await lifecycle.commit(fixture,lifecycleResult.revision,lifecycleResult.profileId);
        ok(lifecycleResult.ok&&lifecycleResult.durable&&openCount===beforeOpen+1,'closed journal reopens once and durably saves '+i);
      }
      let lifecycleEntry=await journal.read('synthetic-journal-lifecycle');
      ok(lifecycleEntry.record.revision===3,'three consecutive recovered autosaves advance actual journal revision');
      connection.close();const other={...lifecycleEntry,record:await record(4,444,lifecycleEntry.record.profileId)};
      await rawPut('synthetic-journal-lifecycle',other);
      const stale=await lifecycle.commit(fixture,3,lifecycleEntry.record.profileId);
      ok(stale.code==='REVISION_CONFLICT'&&equal(await journal.read('synthetic-journal-lifecycle'),other),'reopened connection rechecks CAS and preserves another tab newer save');
      const lifecyclePut=IDBObjectStore.prototype.put,opensBeforeAbort=openCount;
      IDBObjectStore.prototype.put=function(...args){const request=lifecyclePut.apply(this,args),transaction=this.transaction;request.addEventListener('success',()=>transaction.abort());return request;};
      let aborted=false;
      try{await journal.replace('synthetic-journal-lifecycle',other,{...other,pending:false});}catch(_){aborted=true;}finally{IDBObjectStore.prototype.put=lifecyclePut;}
      ok(aborted&&openCount===opensBeforeAbort&&equal(await journal.read('synthetic-journal-lifecycle'),other),'created transaction abort is never reopened or replayed');
      }
      // Production Google policy, using this browser's real IndexedDB. Old
      // local recovery/provenance never becomes cloud-startup authority.
      {
        const active=await api.openJournal(factory,{cloudOnly:true}),id='cloud-'+crypto.randomUUID();
        const oldRecord=await record(90,110),cloudRecord=await record(7,900);
        oldRecord.payload=modernFixture;oldRecord.digest=await codec.hash(codec.fingerprint(oldRecord));
        cloudRecord.payload=modernFixture;cloudRecord.digest=await codec.hash(codec.fingerprint(cloudRecord));
        const pending={base:null,pending:true,record:oldRecord,uploading:{record:oldRecord}};
        await journal.replace(id,null,pending);await rawPut(['pre-grid-v1',id],'unverified old original');
        let cloud=doc(cloudRecord),writes=0,readFailure=false;
        const remote={async read(){if(readFailure)throw fail('OFFLINE');return clone(cloud);},async compareAndSet(uid,base,next,guard,verifyArchive){guard();if(verifyArchive)await verifyArchive();guard();if(base!==(cloud?.digest||null))throw fail('REVISION_CONFLICT');cloud=clone(next);writes++;}};
        const make=()=>api.createClient({uid:id,cloudStartup:true,codec,journal:active,remote,currentUid:()=>id,status(){}});
        const client=make(),boot=await client.boot();
        ok(boot.ok&&boot.profileId===cloudRecord.profileId&&boot.revision===7,'Google cloud starts despite missing old preGrid in real IDB');
        ok(equal(await journal.read(id),pending)&&await journal.readPreGrid(id)==='unverified old original','Google keeps old journal and archive bytes untouched');
        ok(!client.recoverySnapshot().choicesAvailable,'Google cloud startup has no local/cloud cards');
        await client.sync();ok(writes===0,'Google never uploads old pending/uploading during boot');
        const staged=await client.commit(modernFixture,boot.revision,boot.profileId);ok(staged.ok,'Google stages a new write against verified cloud revision');
        await client.sync();ok(writes===1&&cloud.revision===8,'Google uploads only the post-startup cloud-based write');
        ok(await active.readPreGrid(id)===null,'modern cloud baseline does not fabricate original archives');client.close();
        // A later unavailable read must not fall back to the staged local row.
        const before=await active.read(id);readFailure=true;const offline=make();
        ok((await offline.boot()).code==='OFFLINE','Google unavailable read is an explicit startup error');
        ok(equal(await active.read(id),before)&&writes===1,'failed Google read performs no adoption/upload');offline.close();
        readFailure=false;cloud=null;const fresh=make(),empty=await fresh.boot();
        ok(empty.ok&&empty.source==='fresh'&&empty.revision===0,'confirmed absent Google cloud is separate fresh-account case');
        ok(equal(await journal.read(id),pending),'absent cloud still preserves original journal bytes');fresh.close();
      }
      return checks;
    },{fixture,modernFixture});
    const {createHash}=require('node:crypto');
    console.log('Recovery source SHA-256: '+JSON.stringify(Object.fromEntries(['web/little_leaf_vault.js','web/little_leaf_firebase.js','tests/persistence/firebase_recovery_browser.js','tests/fixtures/startup-retry-v15.json','tests/fixtures/unified_building_candidate.json'].map(name=>[name,createHash('sha256').update(fs.readFileSync(sourcePath(process.cwd(),name))).digest('hex')]))));
    assert(results.length>=45);console.log(`Firebase recovery: ${results.length} real-IndexedDB/synthetic-cloud assertions passed (${browser.version()}).`);
    for(const result of results)console.log(`PASS ${result}`);
  } finally {if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});
