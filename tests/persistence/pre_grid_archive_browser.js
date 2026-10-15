'use strict';
// Real disposable Chromium IndexedDB; generated saves and synthetic cloud only.
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const sources=['little_leaf_vault','little_leaf_firebase'].map(n=>fs.readFileSync(`platform/web/${n}.js`,'utf8'));
const fixtures={legacy:fs.readFileSync('tests/fixtures/unified_building/public_closed.json','utf8'),modern:fs.readFileSync('tests/fixtures/unified_building_candidate.json','utf8'),centered:fs.readFileSync('tests/fixtures/unified_building_v2_candidate-modern.json','utf8')};
(async()=>{
 const server=http.createServer((_,res)=>{res.setHeader('content-type','text/html');res.end('<!doctype html><title>Generated pre-grid archive test</title>');});await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const options={headless:true,chromiumSandbox:true};if(process.env.CHROMIUM_PATH)options.executablePath=process.env.CHROMIUM_PATH;if(process.env.PLAYWRIGHT_CHROMIUM_CHANNEL)options.channel=process.env.PLAYWRIGHT_CHROMIUM_CHANNEL;
  browser=await chromium.launch(options);const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}`);for(const content of sources)await page.addScriptTag({content});
  const report=await page.evaluate(async({legacy,modern,centered})=>{
   const codec=LittleLeafAuthorityCodec,api=LittleLeafFirebase,checks=[],clone=x=>JSON.parse(JSON.stringify(x)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);const ok=(v,m)=>{if(!v)throw Error(m);checks.push(m);};
   legacy=' \n'+JSON.stringify({...JSON.parse(legacy),synthetic_note:'白色 tiles café'},null,2)+'\t';
   const fail=code=>Object.assign(Error(code),{code});
   async function record(payload,revision=7,id=crypto.randomUUID()){const r={format:2,profileId:id,revision,createdAt:1,updatedAt:2,payload,digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};r.digest=await codec.hash(codec.fingerprint(r));return r;}
   const doc=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
   async function open(name){return new Promise((resolve,reject)=>{const q=indexedDB.open(name,1);q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);});}
   async function raw(db,store,key,value,write=false){return new Promise((resolve,reject)=>{let result;const tx=db.transaction(store,write?'readwrite':'readonly'),s=tx.objectStore(store),q=write?s.put(value,key):s.get(key);q.onsuccess=()=>{result=q.result??null;};tx.oncomplete=()=>resolve(result);tx.onabort=()=>reject(tx.error);});}
   for(const mode of ['success','quota','discard','bad-readback','corrupt','race','archive-race','close']){
    const suffix='-test-'+crypto.randomUUID(),factory={open:(name,...args)=>indexedDB.open(name+suffix,...args)};let c=LittleLeafVault.createClient({indexedDB:factory,campaigns:[]});let b=await c.boot();ok(b.ok,'local '+mode+' fresh synthetic boot');ok((await c.commit(legacy,0,b.profileId)).ok,'local '+mode+' seeds legacy authority');c.close();c=LittleLeafVault.createClient({indexedDB:factory,campaigns:[]});b=await c.boot();
    const db=await open(LittleLeafVault.DB_NAME+suffix),key='pre-grid-v1/'+b.profileId,before=await raw(db,'profiles','active'),newer=await record(legacy,2,b.profileId);newer.createdAt=before.createdAt;newer.digest=await codec.hash(codec.fingerprint(newer));
    if(mode==='corrupt')await raw(db,'profiles',key,'damaged',true);
    const get=IDBObjectStore.prototype.get,put=IDBObjectStore.prototype.put;let reads=0,raced=null;
    IDBObjectStore.prototype.get=function(k){
     if(this.transaction.db.name===db.name&&k===key){reads++;if(mode==='bad-readback'&&reads===3)return get.call(this,'absent-test-key');const q=get.call(this,k);if(reads===3)q.addEventListener('success',()=>{if(mode==='race')raced=raw(db,'profiles','active',newer,true);if(mode==='archive-race')raced=raw(db,'profiles',key,'racing damaged archive',true);if(mode==='close')c.close();});return q;}
     return get.call(this,k);
    };
    IDBObjectStore.prototype.put=function(value,k){if(this.transaction.db.name===db.name&&k===key){if(mode==='quota')throw new DOMException('synthetic quota','QuotaExceededError');if(mode==='discard')return get.call(this,'absent-test-key');}return put.call(this,value,k);};
    let result;try{result=await c.commit(modern,b.revision,b.profileId);}finally{IDBObjectStore.prototype.get=get;IDBObjectStore.prototype.put=put;}if(raced)await raced;
    const after=await raw(db,'profiles','active'),archive=await raw(db,'profiles',key);
    if(mode==='success'){
     ok(result.ok&&result.durable,'local migration confirmed after real transaction');const list=await codec.verifyPreGridArchives(archive);ok(list[0].payload===legacy&&list[0].digest===before.digest&&list[0].revision===1,'local exact old payload/profile/revision/digest archive');ok(reads===4,'local has separate archive readback and final proof read');ok((await c.commit(modern,result.revision,b.profileId)).ok&&await raw(db,'profiles',key)===archive,'later local save keeps immutable original');
    }else{ok(!result.ok,'local rejects '+mode);ok(same(after,mode==='race'?newer:before),'local '+mode+' leaves authority unchanged/newer winner intact');if(mode==='corrupt')ok(archive==='damaged','corrupt original never repaired');}
    c.close();db.close();
   }
   // The original v13 bytes remain separate from the revision-zero identity.
   {
    const suffix='-test-'+crypto.randomUUID(),v13=JSON.parse(legacy);v13.version=13;delete v13.layout_motion_format;const text='\n '+JSON.stringify(v13)+'\t';
    await new Promise((resolve,reject)=>{const q=indexedDB.open('/userfs'+suffix,1);q.onupgradeneeded=()=>q.result.createObjectStore('FILE_DATA').put({contents:new Int8Array(new TextEncoder().encode(text).buffer)},'/userfs/synthetic/little_leaf_cafe_v13.json');q.onsuccess=()=>{q.result.close();resolve();};q.onerror=()=>reject(q.error);});
    const c=LittleLeafVault.createClient({indexedDB:{open:(name,...args)=>indexedDB.open(name+suffix,...args)},campaigns:[]}),b=await c.boot();ok(b.source==='legacy-v13','legacy-v13 selected as original source');ok((await c.commit(modern,0,b.profileId)).ok,'legacy-v13 modern save succeeds after archive');const db=await open(LittleLeafVault.DB_NAME+suffix),list=await codec.verifyPreGridArchives(await raw(db,'profiles','pre-grid-v1/'+b.profileId));ok(list[0].payload===text&&list[0].revision===0&&list[0].legacyDigest===await codec.hash(text),'legacy-v13 exact source bytes/digest bound to revision zero');c.close();db.close();
   }
   const journal=await api.openJournal(indexedDB),db=await open('little-leaf.firebase-journal.v1');
   for(const mode of ['success','quota','discard','bad-readback','corrupt','race','archive-race','account','paused']){
    const uid='synthetic-'+crypto.randomUUID(),r=await record(legacy),entry={base:r.digest,pending:false,record:r},key=['pre-grid-v1',uid];await journal.replace(uid,null,entry);let currentUid=uid,uploads=0,paused=false;const states=[];
    const ownership={assertActive(){if(paused)throw fail('OWNERSHIP_LOST');return{};},async renew(){},close(){}};
    const c=api.createClient({uid,codec,journal,remote:{async read(){return doc(r);},async compareAndSet(){uploads++;throw Error('No upload allowed in archive fixture');}},currentUid:()=>currentUid,status:s=>states.push(s),ownership:mode==='paused'?ownership:null});const b=await c.boot();ok(b.ok,'Firebase '+mode+' boot old acknowledged authority');
    const before=await journal.read(uid),newer={...before,record:await record(legacy,8,r.profileId),pending:true};if(mode==='corrupt')await raw(db,'accounts',key,'damaged',true);
    const originalRead=journal.readPreGrid,originalArchive=journal.archivePreGrid;let reads=0;
    journal.readPreGrid=async id=>{const value=await originalRead(id);if(id===uid&&++reads===2){if(mode==='bad-readback')return 'wrong';if(mode==='race')await journal.replace(uid,before,newer);if(mode==='archive-race')await raw(db,'accounts',key,'racing damaged archive',true);if(mode==='account')currentUid='another';}return value;};
    journal.archivePreGrid=async(id,...args)=>{if(id===uid&&mode==='quota')throw fail('QuotaExceededError');if(id===uid&&mode==='discard')return;return originalArchive(id,...args);};
    let result;try{if(mode==='paused'){paused=true;result=await c.preserveRuntime(modern,b.revision,b.profileId);}else result=await c.commit(modern,b.revision,b.profileId);}finally{journal.readPreGrid=originalRead;journal.archivePreGrid=originalArchive;}
    const after=await journal.read(uid),archive=await journal.readPreGrid(uid);ok(uploads===0,'Firebase '+mode+' makes no cloud write');
    if(mode==='success'||mode==='paused'){
     ok(result.ok&&result.durable,'Firebase '+mode+' local durability succeeds');const list=await codec.verifyPreGridArchives(archive);ok(list[0].payload===legacy&&list[0].digest===r.digest&&list[0].profileId===r.profileId,'Firebase '+mode+' retains exact pre-grid source');ok(after.pending&&after.record.payload===modern&&after.base===r.digest,'Firebase '+mode+' preserves base CAS and stages only after archive');
     if(mode==='success')ok((await c.commit(modern,result.revision,b.profileId)).ok&&await journal.readPreGrid(uid)===archive,'Firebase later save retains original archive');
    }else{ok(!result.ok,'Firebase refuses '+mode);ok(same(after,mode==='race'?newer:before),'Firebase '+mode+' cannot replace journal or create pending');}
    c.close();
   }
   // Recovery choices may re-key selected local metadata. Archive the true
   // local/cloud source objects before selecting, not nextRecord's hybrid.
   for(const choice of ['local','cloud']){
    const uid='choice-'+crypto.randomUUID(),legacyRecord=await record(legacy),modernRecord=await record(modern,9),localRecord=choice==='local'?modernRecord:legacyRecord,cloudRecord=choice==='local'?legacyRecord:modernRecord;
    const entry={base:'0'.repeat(64),pending:true,record:localRecord,...(choice==='local'?{preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}}:{})};await journal.replace(uid,null,entry);let cloud=doc(cloudRecord),uploads=0;
    const c=api.createClient({uid,codec,journal,currentUid:()=>uid,status(){},remote:{async read(){return clone(cloud);},async compareAndSet(id,base,next,guard){guard();if(base!==cloud.digest)throw fail('REVISION_CONFLICT');cloud=clone(next);uploads++;}}});
    ok((await c.boot()).code==='REVISION_CONFLICT','choice '+choice+' requires review');const view=c.recoverySnapshot(),prepared=await c.prepareChoice(choice,view.expectedLocalDigest,view.expectedCloudDigest);ok(prepared.ok,'choice '+choice+' prepares without active write');ok(await journal.readPreGrid(uid)===null,'choice preparation does not archive or publish');
    const selected=await c.confirmChoice(prepared.selectionToken);ok(selected.ok,'choice '+choice+' confirms after backup');const list=await codec.verifyPreGridArchives(await journal.readPreGrid(uid));ok(list.length===1&&list[0].profileId===legacyRecord.profileId&&list[0].digest===legacyRecord.digest&&list[0].payload===legacy,'choice '+choice+' archives true original identity');ok(uploads===(choice==='local'?1:0),'choice '+choice+' retains upload semantics');c.close();
   }
   // Real IndexedDB v1-to-v2 upgrade keeps the exact v1 source, not just
   // the older non-grid original, and rechecks proof before pending upload.
   {
    const suffix='-v2-'+crypto.randomUUID(),factory={open:(name,...args)=>indexedDB.open(name+suffix,...args)},c=LittleLeafVault.createClient({indexedDB:factory,campaigns:[]}),b=await c.boot();
    const first=await c.commit(modern,0,b.profileId);ok(first.ok,'real local v1 authority seeded');
    const store=await open(LittleLeafVault.DB_NAME+suffix),source=await raw(store,'profiles','active');
    const result=await c.commit(centered,first.revision,b.profileId);ok(result.ok&&result.durable,'real local v1-to-v2 transaction is durable');
    const archive=await raw(store,'profiles','pre-grid-v1/'+b.profileId),list=await codec.verifyPreGridArchives(archive);
    ok(list.length===1&&list[0].payload===modern&&list[0].digest===source.digest,'real local archive retains exact v1 source before v2');
    c.close();const reopened=LittleLeafVault.createClient({indexedDB:factory,campaigns:[]}),boot=await reopened.boot();ok(boot.ok&&boot.payload===centered,'real local centered payload survives reopen');reopened.close();store.close();
   }
   for(const mode of ['success','missing']){
    const uid='v1-v2-'+crypto.randomUUID(),source=await record(modern),entry={base:source.digest,pending:false,record:source,preGrid:{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]}};await journal.replace(uid,null,entry);
    let cloud=doc(source),writes=0;const make=()=>api.createClient({uid,codec,journal,currentUid:()=>uid,status(){},remote:{async read(){return clone(cloud);},async compareAndSet(id,base,next,guard){guard();if(base!==cloud.digest)throw fail('REVISION_CONFLICT');cloud=clone(next);writes++;}}});
    const c=make(),boot=await c.boot();ok((await c.commit(centered,boot.revision,boot.profileId)).ok,'real Firebase journal stages centered payload');
    const pending=await journal.read(uid),list=await codec.verifyPreGridArchives(await journal.readPreGrid(uid));ok(list.length===1&&list[0].payload===modern&&list[0].digest===source.digest,'real Firebase journal archives exact v1 source');
    ok(pending.preGrid.archiveDigests[0]===list[0].archiveDigest,'real centered pending journal binds the v1 archive identity');c.close();
    if(mode==='missing')await new Promise((resolve,reject)=>{const tx=db.transaction('accounts','readwrite');tx.objectStore('accounts').delete(['pre-grid-v1',uid]);tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});
    const reopened=make(),result=await reopened.boot();ok(result.ok===(mode==='success'),'real centered reopen respects required v1 archive');
    ok(writes===(mode==='success'?1:0),'real centered upload cannot pass a missing v1 archive');
    if(mode==='missing')ok(same(await journal.read(uid),pending),'missing v1 archive preserves exact centered pending journal');reopened.close();
   }
   db.close();return {passed:true,total_checks:checks.length,checks,real_indexeddb:true,synthetic_cloud:true,player_saves_used:false};
  },fixtures);assert(report.passed);console.log(JSON.stringify(report,null,2));
 }finally{if(browser)await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
