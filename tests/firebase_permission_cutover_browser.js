'use strict';
// One isolated browser and a demo-project emulator. No engine, SSO or production data.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const sdkRoot=path.dirname(require.resolve('firebase/package.json'));
const legacy=fs.readFileSync('tests/fixtures/firebase-legacy-b8b80ee.js','utf8');
assert.equal(crypto.createHash('sha256').update(legacy).digest('hex'),'04774d3495b891c95e00a5525b6d74fab93aa6eb2b84199e065a82369d0fa6bc');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
(async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync('platform/firebase/firestore.rules','utf8')}});
  const server=http.createServer((req,res)=>{
    if(req.url.startsWith('/sdk/')){const name=path.basename(req.url);if(!['firebase-app.js','firebase-firestore.js'].includes(name)){res.writeHead(404);return res.end();}res.setHeader('Content-Type','text/javascript');return res.end(fs.readFileSync(path.join(sdkRoot,name),'utf8').replaceAll('https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js','/sdk/firebase-app.js'));}
    res.setHeader('Content-Type','text/html');res.end('<!doctype html><title>Disposable cutover preservation test</title>');
  });
  let browser;
  try{
    await env.clearFirestore();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const origin='http://127.0.0.1:'+server.address().port;
    browser=await chromium.launch({headless:true,chromiumSandbox:true,...(process.env.PLAYWRIGHT_CHROMIUM_CHANNEL?{channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL}:{})});
    const context=await browser.newContext(),page=await context.newPage(),errors=[];
    page.on('pageerror',e=>{errors.push(e.message);console.error('Browser module error:',e.message);});
    await context.route('**/*',async route=>{
      const url=new URL(route.request().url());
      if(url.origin===origin || url.origin==='http://127.0.0.1:8080')return route.continue();
      if(url.href.startsWith('https://www.gstatic.com/firebasejs/12.19.0/')){
        const name=path.basename(url.pathname);assert(['firebase-app.js','firebase-firestore.js'].includes(name));
        return route.fulfill({status:200,contentType:'text/javascript',headers:{'Access-Control-Allow-Origin':'*'},body:fs.readFileSync(path.join(sdkRoot,name))});
      }
      return route.abort('blockedbyclient');
    });
    async function load(){
      await page.goto(origin);
      await page.addScriptTag({content:fs.readFileSync('platform/web/little_leaf_vault.js','utf8')});
      await page.addScriptTag({content:legacy});await page.evaluate(()=>globalThis.legacyApi=LittleLeafFirebase);
      await page.addScriptTag({content:fs.readFileSync('platform/web/little_leaf_firebase.js','utf8')});
      await page.addScriptTag({type:'module',content:`import {initializeApp} from '/sdk/firebase-app.js';import * as sdk from '/sdk/firebase-firestore.js';const db=sdk.initializeFirestore(initializeApp({projectId:'demo-little-leaf',apiKey:'synthetic-only',appId:'synthetic-only'}),{experimentalForceLongPolling:true});sdk.connectFirestoreEmulator(db,'127.0.0.1',8080,{mockUserToken:{sub:'legacy-idb-cutover',firebase:{sign_in_provider:'google.com'}}});globalThis.qa={db,sdk};`});
      await page.waitForFunction(()=>globalThis.qa);
    }
    await load();
    const fixture=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
    const first=await page.evaluate(async fixture=>{
      const {db,sdk}=qa,codec=LittleLeafAuthorityCodec,uid='legacy-idb-cutover',checks=[];
      const check=(v,m)=>{if(!v)throw Error(m);checks.push(m);};
      const fence={writerId:'00000000-0000-4000-8000-000000000020',writerEpoch:1};
      const r={format:2,profileId:crypto.randomUUID(),revision:1,createdAt:1,updatedAt:1,payload:fixture,digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};r.digest=await codec.hash(codec.fingerprint(r));
      await sdk.setDoc(sdk.doc(db,'players',uid,'session','owner'),{schema:1,owner:fence.writerId,epoch:1,device:'Windows PC',updatedAt:sdk.serverTimestamp(),request:null,ack:null});
      const ref=sdk.doc(db,'players',uid,'saves','cafe');
      await sdk.setDoc(ref,{schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r),...fence});
      const journal=await legacyApi.openJournal(indexedDB),states=[];
      const old=legacyApi.createClient({uid,codec,remote:legacyApi.createRemote(db,sdk),journal,currentUid:()=>uid,status:s=>states.push(s)});
      check((await old.boot()).ok,'exact legacy bytes boot against candidate rules and real SDK');
      const committed=await old.commit(JSON.stringify({...JSON.parse(fixture),coins:110}),1,r.profileId);
      check(committed.durable && !committed.cloudConfirmed,'legacy commit is durable in actual IndexedDB');
      await old.sync();const pending=await journal.read(uid),cloud=(await sdk.getDocFromServer(ref)).data();
      check(pending.pending && pending.record.revision===2 && JSON.parse(pending.record.payload).coins===110,'real permission refusal keeps latest pending cafe in IndexedDB');
      check(cloud.digest===r.digest && states.at(-1)==='conflict','real SDK rejection never changes cloud or claims saved');
      return {checks,pending,fence};
    },fixture);
    // Full navigation discards the old JavaScript runtime but preserves this context's IDB.
    await load();
    const second=await page.evaluate(async first=>{
      const {db,sdk}=qa,codec=LittleLeafAuthorityCodec,uid='legacy-idb-cutover',checks=[];
      const check=(v,m)=>{if(!v)throw Error(m);checks.push(m);};
      const journal=await LittleLeafFirebase.openJournal(indexedDB);
      check(JSON.stringify(await journal.read(uid))===JSON.stringify(first.pending),'real navigation retains exact pending bytes without storage clearing');
      const owner={sessionRef:sdk.doc(db,'players',uid,'session','owner'),assertActive:()=>first.fence,snapshot:()=>({status:'active',serverOwnership:true}),close(){}};
      let time=Date.now(),account=uid;const states=[];
      const compatible=LittleLeafFirebase.createClient({uid,codec,ownership:owner,remote:LittleLeafFirebase.createRemote(db,sdk,owner),journal,currentUid:()=>account,status:s=>states.push(s),now:()=>time});
      const resumed=await compatible.boot(),ack=await journal.read(uid),cloud=(await sdk.getDocFromServer(sdk.doc(db,'players',uid,'saves','cafe'))).data();
      check(resumed.ok && resumed.payload===first.pending.record.payload && resumed.revision===2,'same-origin compatible upgrade resumes actual legacy pending progress');
      check(!ack.pending && cloud.digest===first.pending.record.digest && cloud.writerId===first.fence.writerId,'real candidate rules accept fenced recovery without replacing cafe identity');
      // Deliberately omit the fence to cause a genuine SDK permission denial after boot.
      const refused=LittleLeafFirebase.createClient({uid,codec,ownership:owner,remote:LittleLeafFirebase.createRemote(db,sdk),journal,currentUid:()=>account,status:s=>states.push(s),now:()=>time});
      check((await refused.boot()).ok,'compatible client can boot acknowledged progress before denial');
      const local=await refused.commit(JSON.stringify({...JSON.parse(resumed.payload),coins:120}),2,resumed.profileId);time+=40000;await refused.sync();
      const pending=await journal.read(uid),copy=await refused.exportRecovery();
      check(local.durable && !local.cloudConfirmed && pending.pending && states.at(-1)==='permission-denied','current denied SDK write pauses and keeps actual durable pending progress');
      check(refused.ownershipSnapshot().ownershipPaused && refused.recoverySnapshot().canExport && copy.ok,'current denied SDK write immediately exposes protected recovery export');
      check(JSON.stringify(JSON.parse(copy.text).pendingEntry)===JSON.stringify(pending),'export contains exact IndexedDB pending bytes without overwriting them');
      account='different-account';check(!refused.recoverySnapshot().canExport && (await refused.exportRecovery()).code==='NOT_READY','real IDB pending export remains account guarded');
      return {checks};
    },first);
    assert.deepEqual(errors,[]);
    const result={passed:true,synthetic_only:true,real_indexeddb:true,real_firestore_rules:true,production_read_or_write:false,browser_sandbox:true,legacy_source_sha256:crypto.createHash('sha256').update(legacy).digest('hex'),checks:[...first.checks,...second.checks]};
    const output=process.argv[2];if(output)fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
    await context.close();
  }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));await env.clearFirestore();await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
