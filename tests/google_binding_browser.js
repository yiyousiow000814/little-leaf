'use strict';
// Real disposable browser/IndexedDB + synthetic Auth/cloud only. Never accesses a user profile.
const cp=require('node:child_process'),spawn=cp.spawn;cp.spawn=function(command,args,options){return spawn.call(this,command,args,{...options,windowsHide:true});};
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http'),path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async()=>{
 const server=http.createServer((_,res)=>{res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Synthetic local binding</title><body style="background:#e8ddc5"><p>Disposable synthetic restaurant. No Google account or player storage.</p>');});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
 try{
  console.log('Launching owned headless browser.');
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,chromiumSandbox:true,timeout:20000});const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();page.setDefaultTimeout(10000);
  console.log('Opening disposable loopback fixture.');
  await page.goto('http://127.0.0.1:'+server.address().port);
  for(const name of ['little_leaf_vault.js','little_leaf_firebase.js','little_leaf_google_binding.js','little_leaf_google_binding_ui.js','little_leaf_local_google_entry.js'])await page.addScriptTag({content:fs.readFileSync('platform/web/'+name,'utf8')});
  console.log('Preparing synthetic records.');
  await page.evaluate(async payload=>{
   const codec=LittleLeafAuthorityCodec,clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
   async function record(coins,revision){const r={format:2,profileId:crypto.randomUUID(),revision,createdAt:1,updatedAt:Date.UTC(2026,9,10,18,0,revision),origin:{source:'fresh',legacyDigest:null,importedAt:1},payload:JSON.stringify({...JSON.parse(payload),coins}),previous:null,campaigns:{}};r.digest=await codec.hash(codec.fingerprint(r));return r;}
   const source=await record(17,2),original=clone(source),cloudRecord=await record(999,5),previous=clone(cloudRecord),journal=await LittleLeafFirebase.openJournal(indexedDB);let cloud={schema:1,profileId:cloudRecord.profileId,revision:5,digest:cloudRecord.digest,record:JSON.stringify(cloudRecord)},writes=0,returns=0,activations=0;
   const remote={async read(){return clone(cloud);},async compareAndSet(uid,base,next,guard){guard();if(cloud.digest!==next.digest){if(cloud.digest!==base)throw Error('changed');cloud=clone(next);writes++;}}};
   const ownership={assertActive(){},snapshot(){return {elapsedPending:false};},get hasElapsedIntent(){return false;},close(){},async renew(){}};
   const db=await new Promise((resolve,reject)=>{const request=indexedDB.open(LittleLeafVault.DB_NAME,1);request.onupgradeneeded=()=>request.result.createObjectStore(LittleLeafVault.STORE);request.onsuccess=()=>resolve(request.result);request.onerror=reject;});
   await new Promise((resolve,reject)=>{const tx=db.transaction(LittleLeafVault.STORE,'readwrite'),store=tx.objectStore(LittleLeafVault.STORE);store.put(source,'active');store.put({profileId:source.profileId,createdAt:source.createdAt},'identity');tx.oncomplete=resolve;tx.onabort=reject;});db.close();
   window.__littleLeafVault={bootJson:JSON.stringify({ok:true,profileId:source.profileId,revision:source.revision})};
   const snapshot=await LittleLeafLocalGoogleEntry.readLocalRecord();if(JSON.stringify(snapshot)!==JSON.stringify(source))throw Error('Incomplete local snapshot');
   const auth={currentUser:null};
   LittleLeafLocalGoogleEntry.install({auth,signIn:async()=>{auth.currentUser={uid:'synthetic-account'};return {user:auth.currentUser};},verifyGoogle:async()=>{},createTarget:async()=>({uid:'synthetic-account',ownership,remote,journal})});
   window.bindingFixture={open:()=>LittleLeafLocalBinding.open(()=>returns++),snapshot:()=>({source,original,cloud,previous,writes,returns,activations})};bindingFixture.open();
  },fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8'));
  console.log('Checking binding interactions.');
  const output=path.resolve(process.env.BINDING_EVIDENCE || '../google-binding-evidence');fs.mkdirSync(output,{recursive:true});
  await page.getByRole('button',{name:'Sign in with Google',exact:true}).click();await page.getByRole('heading',{name:'Google cloud',exact:true}).waitFor();
  await page.screenshot({path:path.join(output,'synthetic-choice-mobile.png')});
  assert.equal(await page.getByRole('button').count(),3);assert.equal((await page.evaluate(()=>bindingFixture.snapshot())).writes,0);
  await page.getByRole('button',{name:'Cancel â€” return to local play',exact:true}).click();assert.equal(await page.locator('#google-binding').count(),0);assert.equal((await page.evaluate(()=>bindingFixture.snapshot())).returns,1);
  await page.evaluate(()=>bindingFixture.open());await page.getByRole('button',{name:'Sign in with Google',exact:true}).click();await page.getByRole('button',{name:'Keep this device restaurant',exact:true}).click();
  await page.getByRole('button',{name:'Continue with Google',exact:true}).waitFor();await page.screenshot({path:path.join(output,'synthetic-verified-mobile.png')});
  let result=await page.evaluate(()=>bindingFixture.snapshot());assert.equal(result.writes,1);assert.deepEqual(result.source,result.original);assert.equal(JSON.parse(JSON.parse(result.cloud.record).payload).coins,17);
  await page.getByRole('button',{name:'Return to local play',exact:true}).click();await page.evaluate(()=>bindingFixture.open());await page.getByRole('button',{name:'Sign in with Google',exact:true}).click();await page.getByRole('button',{name:'Verify existing binding',exact:true}).click();await page.getByRole('button',{name:'Continue with Google',exact:true}).waitFor();result=await page.evaluate(()=>bindingFixture.snapshot());assert.equal(result.writes,1);
  assert.deepEqual(await page.evaluate(()=>LittleLeafLocalGoogleEntry.readLocalRecord()),result.original);
  const popupEvent=page.waitForEvent('popup');await page.evaluate(()=>{sessionStorage.setItem('little-leaf.google-binding-cloud-once.v1',JSON.stringify({uid:'synthetic-account',cloudConfirmed:true}));window.open(location.href,'binding-clone');});const popup=await popupEvent;await popup.waitForLoadState();await popup.addScriptTag({content:fs.readFileSync('platform/web/little_leaf_local_google_entry.js','utf8')});
  await popup.evaluate(()=>{window.entryChoice=LittleLeafLocalGoogleEntry.chooseMode({auth:{currentUser:{uid:'synthetic-account'}},document,storage:sessionStorage});});await popup.getByRole('button',{name:'Play on this device',exact:true}).waitFor();assert.equal(await popup.evaluate(()=>sessionStorage.getItem('little-leaf.google-binding-owner.v1')),null);await popup.close();
  const other=await context.newPage();await other.goto('http://localhost:'+server.address().port);
  for(const name of ['little_leaf_vault.js','little_leaf_local_google_entry.js'])await other.addScriptTag({content:fs.readFileSync('platform/web/'+name,'utf8')});
  assert.equal(await other.evaluate(async identity=>{window.__littleLeafVault={bootJson:JSON.stringify({ok:true,...identity})};try{await LittleLeafLocalGoogleEntry.readLocalRecord();return false;}catch(_){return (await indexedDB.databases()).length===0;}},{profileId:result.original.profileId,revision:result.original.revision}),true);
  await context.close();fs.writeFileSync(path.join(output,'browser-receipt.json'),JSON.stringify({scope:'synthetic browser binding panel and actual IndexedDB; no game/Google acceptance',checks:['explicit two-state presentation','no write before choice','cancel resumes local','complete selected payload','original unchanged','persisted retry no duplicate write','read-only complete local snapshot','other origin fails without creating authority database','opener clone cannot reuse binding owner or cloud continuation'],origin:'disposable loopback',player_storage_access:false},null,2));
  console.log('Binding browser: real IndexedDB, mobile choice/cancel/verified presentation, local retention and repeated bind passed.');
 }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exit(1);});
