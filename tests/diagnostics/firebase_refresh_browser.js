'use strict';
// Manual, bounded real-browser acceptance. All Auth/cloud/journal data are synthetic.
const cp=require('node:child_process'),spawn=cp.spawn;
cp.spawn=(command,args,options)=>spawn(command,args,{...options,windowsHide:true});
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http'),path=require('node:path'),crypto=require('node:crypto');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const sessionSource=fs.readFileSync('platform/web/little_leaf_firebase_session.js','utf8');
const bootSource=fs.readFileSync('platform/web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\r?\n/gm,'').replace('export async function start','async function start');
const fixture=`
const auth={currentUser:{uid:new URL(location.href).searchParams.get('uid')||'synthetic-account',isAnonymous:false},authStateReady:async()=>{}};
const authListeners=[];
function initializeApp(){return{};}function getAuth(){return auth;}function getFirestore(){return{};}
async function setPersistence(){}async function getRedirectResult(){return null;}
function onAuthStateChanged(a,fn){authListeners.push(fn);fn(a.currentUser);return()=>{};}
const browserLocalPersistence={},GoogleAuthProvider=class{};
const signInWithRedirect=()=>{throw Error('Real sign-in forbidden');},signInWithPopup=signInWithRedirect,signOut=signInWithRedirect;
const doc=()=>{},getDocFromServer=()=>{},runTransaction=()=>{},serverTimestamp=()=>{},onSnapshot=()=>{};
window.switchSyntheticAccount=()=>{auth.currentUser={uid:'synthetic-changed',isAnonymous:false};authListeners.forEach(fn=>fn(auth.currentUser));};
async function readState(){return fetch('/state').then(r=>r.json());}
const original=LittleLeafFirebaseSession;
window.LittleLeafFirebaseSession={...original,createRemote:()=>({async read(){return (await readState()).value;},watch(){return()=>{};},async change(fn,guard){
 for(let i=0;i<4;i++){guard();const state=await readState();guard();const next=fn(state.value,null,()=>state.time);guard();
 if(next===state.value)return next;
 const result=await fetch('/state',{method:'POST',body:JSON.stringify({version:state.version,value:next})}).then(r=>r.json());guard();if(result.ok)return result.value;}
 throw Error('Synthetic contention');
}}),createSession:options=>(window.owner=original.createSession(options))};
window.LittleLeafFirebase={genericDevice:()=> 'Synthetic browser',createRemote:()=>({}),openJournal:async()=>({}),createClient:options=>({close(){window.clientClosed=true;},sync(){},renewOwnership(){return options.ownership.renew();},refreshOwnership(){return options.ownership.refresh();}})};
window.__littleLeafVault={close(){}};window.LittleLeafAuthorityCodec={};window.LittleLeafUpdates={create:()=>({close(){}})};
window.snapshot=()=>owner.snapshot();
`;
(async()=>{
 let value=null,version=0,time=100000,browser,context,cleaned=false,error;
 const checks=[];const check=(name,result)=>{assert(result,name);checks.push(name);};
 const server=http.createServer(async(req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(req.url==='/state'){
   if(req.method==='POST'){let body='';for await(const chunk of req)body+=chunk;const proposal=JSON.parse(body);
    if(proposal.version===version){value=proposal.value;version++;res.end(JSON.stringify({ok:true,value}));}else res.end(JSON.stringify({ok:false}));
   }else res.end(JSON.stringify({value,version,time}));return;
  }
  res.setHeader('Content-Type','text/html');
  res.end('<!doctype html><meta charset="utf-8"><title>Synthetic refresh acceptance</title><p>No Google sign-in or player saves.</p><script>'+sessionSource+'</script><script>'+fixture+'</script><script>'+bootSource+'\nwindow.started=start({authDomain:location.hostname}).then(()=>window.ready=true).catch(e=>{window.failure=e.code||e.message;});</script>');
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const origin='http://127.0.0.1:'+server.address().port;
 try{
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,chromiumSandbox:true,timeout:20000});
  context=await browser.newContext();await context.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
  const page=await context.newPage();page.setDefaultTimeout(10000);
  const ready=async p=>{await p.waitForFunction(()=>window.ready||window.failure);assert.equal(await p.evaluate(()=>window.failure),undefined);};
  await page.goto(origin);await ready(page);check('first synthetic runtime active',(await page.evaluate(()=>snapshot())).status==='active');
  const firstOwner=value.owner,firstEpoch=value.epoch;
  await page.reload();await ready(page);check('ordinary refresh retains active owner and epoch',value.owner===firstOwner&&value.epoch===firstEpoch&&(await page.evaluate(()=>snapshot())).status==='active');
  // A browser-created opener actually copies sessionStorage; no receipt injection.
  const popupWait=page.waitForEvent('popup');await page.evaluate(url=>window.open(url,'_blank'),origin);const copy=await popupWait;await ready(copy);
  check('copied tab uses fresh identity and remains paused',(await copy.evaluate(()=>snapshot())).status==='other-device');await copy.close();
  // A forced overlapping receipt observes the real exclusive WebLock.
  const overlap=await page.evaluate(async()=>{const api=LittleLeafFirebaseSession;
   try{await api.acquireRuntime({uid:auth.currentUser.uid,storage:sessionStorage,locks:navigator.locks,navigationType:'reload'});return 'unsafe';}catch(e){return e.code;}});
  check('overlapping reload identity refused',overlap==='SAVE_BUSY');
  // Actual renderer crash, then reload: browser releases the old lock itself.
  const cdp=await context.newCDPSession(page);const crashed=page.waitForEvent('crash');void cdp.send('Page.crash').catch(()=>{});await crashed;
  await page.reload();await ready(page);check('renderer crash recovery retains fenced tab',value.owner===firstOwner&&(await page.evaluate(()=>snapshot())).status==='active');await cdp.detach();
  await page.evaluate(()=>switchSyntheticAccount());
  check('account change closes writer',await page.evaluate(()=>{try{owner.assertActive();return false;}catch(e){return e.code==='NOT_READY'&&clientClosed;}}));
  await page.goto(origin+'/?uid=synthetic-changed');await ready(page);
  check('new account cannot reuse prior runtime receipt',(await page.evaluate(()=>snapshot())).status==='other-device');
  const noLocks=await browser.newContext();await noLocks.addInitScript(()=>Object.defineProperty(navigator,'locks',{value:undefined}));
  await noLocks.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
  const unsupported=await noLocks.newPage();await unsupported.goto(origin);await ready(unsupported);
  await unsupported.reload();await ready(unsupported);check('WebLock unavailable remains paused with fresh identity',(await unsupported.evaluate(()=>snapshot())).status==='other-device');await noLocks.close();
  // Strict update tickets still get a fresh requester instead of same-owner renewal.
  const fresh=await page.evaluate(async()=>{const receipt=JSON.parse(sessionStorage.getItem('little-leaf.runtime-session.v1'));
   const runtime=await LittleLeafFirebaseSession.acquireRuntime({uid:auth.currentUser.uid,storage:sessionStorage,locks:navigator.locks,navigationType:'reload',fresh:true});
   const result=runtime.sessionId!==receipt.sessionId;runtime.close();return result;});check('update continuation uses fresh identity',fresh);
 }catch(e){error=e;}finally{if(context)await context.close();if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));cleaned=true;}
 const output=path.resolve(process.env.REFRESH_EVIDENCE||'../ownership-refresh-browser');fs.mkdirSync(output,{recursive:true});
 const report={passed:!error,error:error?.message,checks,cleanup_complete:cleaned,real_browser:true,synthetic_auth_cloud_journal:true,real_google_sign_in:false,original_player_data_accessed:false,loopback_only:true,headless:true,chromium_sandbox:true,
  source_sha256:Object.fromEntries(['platform/web/little_leaf_firebase_session.js','platform/web/little_leaf_firebase_boot.mjs','tests/diagnostics/firebase_refresh_browser.js'].map(p=>[p,crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')]))};
 fs.writeFileSync(path.join(output,'receipt.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));if(error)throw error;
})().catch(error=>{console.error(error);process.exitCode=1;});
