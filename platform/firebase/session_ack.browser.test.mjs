import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const address=process.env.FIRESTORE_EMULATOR_HOST;
assert(/^127\.0\.0\.1:\d+$/.test(address||''),'explicit local emulator required');
const port=Number(address.split(':')[1]);assert(port>0&&port<=65535);
const projectId=process.env.FIREBASE_TEST_PROJECT || 'demo-little-leaf';
assert(/^demo-little-leaf(?:-[a-z-]+)?$/.test(projectId),'disposable demo project only');
const env=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port,rules:fs.readFileSync('firestore.rules','utf8')}});
const sdkRoot=path.dirname(require.resolve('firebase/package.json'));
const server=http.createServer((req,res)=>{
 res.setHeader('Content-Type','text/javascript');
 if(req.url==='/'){res.setHeader('Content-Type','text/html');return res.end('<!doctype html><title>Isolated synthetic handoff probe</title>');}
 if(req.url==='/session.js')return res.end(fs.readFileSync('../web/little_leaf_firebase_session.js'));
 if(['/firebase-app.js','/firebase-firestore.js'].includes(req.url))return res.end(fs.readFileSync(path.join(sdkRoot,req.url.slice(1))));
 res.writeHead(404);res.end();
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin='http://127.0.0.1:'+server.address().port;
let browser;
try {
 browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{})});const context=await browser.newContext();
 await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.origin===origin||url.origin==='http://'+address)return route.continue();
  if(url.href==='https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js')return route.fulfill({status:200,contentType:'text/javascript',body:fs.readFileSync(path.join(sdkRoot,'firebase-app.js'))});
  return route.abort();
 });
 const page=await context.newPage();await page.goto(origin);await page.addScriptTag({url:origin+'/session.js'});
 const result=await page.evaluate(async ({origin,port,projectId})=>{
  const app=await import('https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js'),sdk=await import(origin+'/firebase-firestore.js');const results=[];
  for(const mode of ['normal','renew-race','second-renew-race']) {
   const uid='browser-probe-'+mode+'-'+crypto.randomUUID(),config={projectId,apiKey:'synthetic',appId:'synthetic'};
   const database=name=>{const db=sdk.initializeFirestore(app.initializeApp(config,uid+name),{experimentalForceLongPolling:true});sdk.connectFirestoreEmulator(db,'127.0.0.1',port,{mockUserToken:{sub:uid,firebase:{sign_in_provider:'google.com'}}});return db;};
   const db=database('a'),other=database('b'),ref=sdk.doc(db,'players',uid,'session','owner'),saveRef=sdk.doc(db,'players',uid,'saves','cafe');
   let arm=false,injections=0,attempts=[];
   // Inject an authenticated concurrent renewal after both transaction reads.
   const hooked={...sdk,async runTransaction(database,action){return sdk.runTransaction(database,async tx=>{
    let next;
    const result=await action({get:tx.get.bind(tx),set(ref,value){next=value;attempts.push(value);}});
    if(arm && next?.ack && mode!=='normal' && injections<(mode==='renew-race'?1:2)){injections++;await sdk.runTransaction(other,async rival=>{const r=sdk.doc(other,'players',uid,'session','owner'),s=await rival.get(r);rival.set(r,{...s.data(),updatedAt:sdk.serverTimestamp()});});}
    if(next)tx.set(ref,next);return result;
   });}};
   const a=LittleLeafFirebaseSession.createSession({uid,currentUid:()=>uid,deviceLabel:'Linux device',remote:LittleLeafFirebaseSession.createRemote(db,hooked,uid)});
   const b=LittleLeafFirebaseSession.createSession({uid,currentUid:()=>uid,deviceLabel:'Linux device',remote:LittleLeafFirebaseSession.createRemote(other,sdk,uid)});
   try{
    await a.start();await b.start();await sdk.setDoc(saveRef,{schema:1,profileId:'12345678-1234-1234-1234-123456789012',revision:2,digest:'b'.repeat(64),record:'synthetic',...a.fence});await b.requestTakeover();await a.refresh();arm=true;attempts=[];
    let failure=null;
    try{await a.acknowledge('b'.repeat(64),2);}catch(e){failure={code:e.code,error:e.message};}
    const latest=(await sdk.getDocFromServer(ref)).data(),save=(await sdk.getDocFromServer(saveRef)).data();
    const observation={mode,acknowledged:!failure,injections,attempts,latest,save,...failure};
    if(!failure){await b.refresh();await b.takeOver();observation.newOwner=(await sdk.getDocFromServer(ref)).data();try{await sdk.setDoc(saveRef,{...save,revision:3});observation.staleWriterRejected=false;}catch(e){observation.staleWriterRejected=e.code==='permission-denied';}}
    results.push(observation);
   }finally{a.close();b.close();await sdk.terminate(db);await sdk.terminate(other);}
  }return results;
 },{origin,port,projectId});
 const receipt={probe:'browser SDK controlled renewal after transaction reads',sdk:'12.19.0',synthetic_only:true,real_google_sign_in:false,production_access:false,source_sha256:Object.fromEntries(['../web/little_leaf_firebase_session.js','firestore.rules','session_ack.browser.test.mjs'].map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync(name)).digest('hex')])),results:result};
 if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(receipt,null,2)+'\n');
 for(const value of result){
  assert.equal(value.injections,value.mode==='normal'?0:value.mode==='renew-race'?1:2);
  assert.equal(value.attempts.length,value.mode==='normal'?1:2,'bounded ACK write attempts');
  assert.equal(value.save.writerId,value.latest.owner);assert.equal(value.save.writerEpoch,value.latest.epoch);
  if(value.mode==='second-renew-race'){assert.equal(value.acknowledged,false);assert.equal(value.code,'permission-denied');assert.equal(value.latest.ack,null);}
  else {assert(value.acknowledged,JSON.stringify(value));assert.equal(value.latest.ack.digest,value.save.digest);assert.equal(value.latest.ack.revision,value.save.revision);assert.equal(value.newOwner.epoch,value.latest.epoch+1);assert(value.staleWriterRejected);}
 }
 receipt.passed=true;if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(receipt,null,2)+'\n');
 console.log('Actual browser/Firestore ACK rules: normal handoff, one verified renewal recovery, second race paused and stale writer rejected.');
} finally {if(browser)await browser.close();await new Promise(r=>server.close(r));await env.cleanup();}
