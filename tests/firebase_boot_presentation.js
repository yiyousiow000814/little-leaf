'use strict';
// Execute the real boot module with synthetic SDK/DOM boundaries; no network or saves.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const source=fs.readFileSync('platform/web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\r?\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(user=null,options={}){
  const nodes=new Map(),listeners=[],events=new Map();let runtimeOptions,sessionOptions,runtimeClosed=0,ownershipClosed=0;let opened=0,closed=0,redirectError=null,statusCallback=null,clientClosed=0,signOutCalls=0,popupCalls=0,redirectCalls=0,redirectResults=0;
  const element=()=>({textContent:'',hidden:false,disabled:false,style:{},setAttribute(){},append(...x){this.children=x;}});
  nodes.set('status-label',element());nodes.set('status-progress',element());
  const auth={currentUser:user,authStateReady:async()=>{if(options.authReady)await options.authReady;}};
  let client={sync(){},close(){clientClosed++;}};
  const win={addEventListener(name,fn){events.set(name,fn);},__littleLeafVault:{close(){closed++;}},LittleLeafAuthorityCodec:options.codec || {},LittleLeafUpdates:{create(){return {close(){}};}},LittleLeafFirebaseSession:{async acquireRuntime(value){runtimeOptions=value;if(options.acquireWait)await options.acquireWait;return {sessionId:'synthetic-runtime',assertHeld(){if(runtimeClosed)throw Object.assign(Error('closed'),{code:'NOT_READY'});},close(){runtimeClosed++;}};},createRemote(){return{};},createSession(value){sessionOptions=value;return {async start(){},assertActive(){value.assertRuntime();if(ownershipClosed)throw Object.assign(Error('closed'),{code:'NOT_READY'});return {writerId:value.sessionId,writerEpoch:1};},close(){if(!ownershipClosed)ownershipClosed++;}};}},LittleLeafFirebase:{createRemote(){return options.remote || {};},async openJournal(){opened++;if(options.journalWait)await options.journalWait;if(options.journalError)throw Error("synthetic journal unavailable");return options.journal || {};},createClient(value){statusCallback=value.status;if(options.createClient){client=options.createClient(value);const close=client.close;client.close=()=>{clientClosed++;close();};}return client;}}};win.top=win.self=win;if(options.iframe)win.top={};
  const document={createElement:element,getElementById:id=>nodes.get(id),body:{append(x){nodes.set(x.id,x);}}};
  const context={window:win,document,location:{hostname:options.hostname || 'demo.firebaseapp.com',protocol:options.protocol || 'https:',origin:options.origin || 'https://demo.firebaseapp.com',ancestorOrigins:options.ancestors,pathname:options.pathname || '/',reload(){}},indexedDB:{},initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>{redirectResults++;if(options.redirectResultError)throw Error("sensitive SDK detail");return null;},signInWithRedirect:async()=>{redirectCalls++;if(redirectError)throw redirectError;},signInWithPopup:async()=>{popupCalls++;if(options.popupError)throw Error(options.popupError);if(options.popupWait)await options.popupWait;if(options.popupUser){auth.currentUser=options.popupUser;for(const fn of [...listeners])fn(auth.currentUser);}return {user:auth.currentUser};},signOut:async()=>{signOutCalls++;if(options.signOutError)throw Error("synthetic signout failure");if(options.signOutWait)await options.signOutWait;},onAuthStateChanged:(a,fn)=>{listeners.push(fn);return()=>{};},setInterval(){},doc(){},getDocFromServer(){},runTransaction(){},serverTimestamp(){},onSnapshot(){},confirm:()=>!!options.confirm};
  vm.createContext(context);vm.runInContext(source,context);
  return {nodes,auth,win,events,runtimeState:()=>({runtimeOptions,sessionOptions,runtimeClosed,ownershipClosed}),emitStatus(value){statusCallback(value);},start:()=>context.start({authDomain:'demo.firebaseapp.com',projectId:'demo'},options.surface?{surface:options.surface,runtimeOrigin:options.runtimeOrigin,runtimePath:options.runtimePath}:{}),authCounts:()=>({popupCalls,redirectCalls,redirectResults}),setUser(u){auth.currentUser=u;for(const fn of [...listeners])fn(u);},failRedirect(){redirectError=Error('synthetic cancelled sign-in');},counts:()=>({opened,closed}),accountCounts:()=>({clientClosed,signOutCalls}),get client(){return client;}};
}
async function activePagehideSave(){
  // Exercise the real codec/client and an intentionally deferred journal write.
  // The native capture listener starts save before the boot bubble listener;
  // neither the asynchronous hash nor the journal may finish in that event turn.
  const root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
  for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
  const clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
  async function bounded(promise){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Lifecycle journal did not finish')),5000);})]);}finally{clearTimeout(timer);}}
  let local=null,releaseWrite,enteredWrite,holdWrite=true,cloudWrites=0;
  const waiting=new Promise(resolve=>{releaseWrite=resolve;}),entered=new Promise(resolve=>{enteredWrite=resolve;});
  const journal={async read(){return clone(local);},async replace(uid,expected,next){
    assert.equal(uid,'synthetic-lifecycle');assert.deepEqual(local,clone(expected));
    if(next.pending&&holdWrite){enteredWrite();await waiting;holdWrite=false;}
    local=clone(next);
  }};
  const remote={async read(){return null;},async compareAndSet(){cloudWrites++;throw Error('Unexpected cloud write');}};
  const f=fixture({uid:'synthetic-lifecycle',isAnonymous:false},{codec:root.LittleLeafAuthorityCodec,journal,remote,createClient:root.LittleLeafFirebase.createClient});
  await f.start();const boot=await f.client.boot();assert(boot.ok);
  const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
  const saved=new Promise(resolve=>f.client.save(payload,boot.revision,boot.profileId,raw=>resolve(JSON.parse(raw))));
  f.events.get('pagehide')({persisted:false});
  assert.equal(f.accountCounts().clientClosed,0,'pagehide must not close an installed client');
  await bounded(entered);
  assert.equal(local.record.revision,0,'deferred lifecycle save has not committed yet');
  assert.equal(f.runtimeState().runtimeClosed,0,'writer lock stays held through the pending snapshot');
  f.runtimeState().sessionOptions.assertRuntime();releaseWrite();
  const receipt=await bounded(saved);assert(receipt.ok&&receipt.durable&&!receipt.cloudConfirmed);
  assert.equal(local.record.revision,1);assert.equal(local.record.payload,payload);assert(local.pending);
  f.events.get('pagehide')({persisted:true});
  assert.equal(f.runtimeState().runtimeClosed,0,'retained document keeps exclusive authority');
  const next=await f.client.commit(payload,receipt.revision,boot.profileId);
  assert(next.ok&&next.durable);assert.equal(local.record.revision,2);assert.equal(cloudWrites,0);
  const preserved=clone(local);
  f.setUser({uid:'synthetic-different-account',isAnonymous:false});
  f.events.get('pagehide')();f.setUser(null);
  assert.equal(f.accountCounts().clientClosed,1,'account closure remains immediate and idempotent');
  assert.equal(f.runtimeState().runtimeClosed,1);assert.equal(f.runtimeState().ownershipClosed,1);
  assert.throws(()=>f.runtimeState().sessionOptions.assertRuntime(),{code:'NOT_READY'});
  assert.equal((await f.client.commit(payload,2,boot.profileId)).code,'NOT_READY');
  assert.deepEqual(local,preserved,'closed/account-changed callbacks cannot replace the last journal');
}
(async()=>{
  const bridgeSource=fs.readFileSync('game/scripts/cafe_cloud_settings.gd','utf8');
  const presence=bridgeSource.match(/if not JavaScriptBridge\.eval\("([^"\n]+)"\):return null/)[1];
  assert(bridgeSource.indexOf('if not JavaScriptBridge.eval')<bridgeSource.indexOf('api=JavaScriptBridge.get_interface'));
  for(const [window,expected] of [[{},false],[{LittleLeafCloudSettings:null},false],[{LittleLeafCloudSettings:{}},true]])assert.equal(vm.runInNewContext(presence,{window}),expected,'optional bridge presence for ordinary/Firebase Web');
  const f=fixture();let ready=false;const pending=f.start().then(x=>{ready=true;return x;});await flush();
  assert.equal(ready,false);assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(f.nodes.get('status-progress').hidden,true);assert.deepEqual(f.counts(),{opened:0,closed:0});
  const button=f.nodes.get('cloud-account').children[1];assert.equal(button.disabled,false);
  assert.equal(f.nodes.get('cloud-account').className,'leaf-entry-card leaf-account','production sign-in reuses the shared entry theme');
  assert.equal(button.style.marginLeft,undefined,'responsive action is not offset by the old inline strip spacing');
  await button.onclick();assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(ready,false);
  f.failRedirect();await button.onclick();assert.match(f.nodes.get('status-label').textContent,/did not finish/);assert.equal(button.disabled,false);assert.equal(ready,false);assert.deepEqual(f.counts(),{opened:0,closed:0});
  f.setUser({uid:'synthetic-user',isAnonymous:false});assert.equal(await pending,f.client);assert.equal(f.nodes.get('status-label').textContent,'Loading your saved café…');assert.equal(f.nodes.get('status-progress').hidden,false);assert.deepEqual(f.counts(),{opened:1,closed:1});
  const initialFailure=fixture(null,{redirectResultError:true});await assert.rejects(initialFailure.start(),error=>/Reload Little Leaf.*Sign in with Google/.test(error.message)&&!error.message.includes('SDK'));assert.deepEqual(initialFailure.counts(),{opened:0,closed:0});
  let releaseAuth;const authReady=new Promise(resolve=>{releaseAuth=resolve;});const delayed=fixture(null,{authReady});let delayedReady=false;const delayedStart=delayed.start().then(()=>{delayedReady=true;});await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Checking your sign-in…');assert.equal(delayed.nodes.get('cloud-account').children[1].disabled,true);assert.equal(delayedReady,false);releaseAuth();await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Sign in with Google to open your café.');delayed.setUser({uid:'synthetic-delay',isAnonymous:false});await delayedStart;
  assert.equal(f.nodes.get('cloud-account').hidden,true,'signed-in gameplay has no account strip');
  for(const [state,status] of [['ready','Not saved'],['pending','Saving…'],['saved','Saved'],['offline','Not saved'],['conflict','Not saved'],['blocked','Not saved']]){
    f.emitStatus(state);const view=JSON.parse(f.win.LittleLeafCloudSettings.snapshot());assert.equal(view.status,status);assert(!JSON.stringify(view).includes('first save'));assert.equal(view.reload,false);if(['offline','conflict','blocked'].includes(state))assert(view.reason.length>0);
  }
  f.emitStatus('conflict');assert.equal(JSON.parse(f.win.LittleLeafCloudSettings.snapshot()).canSave,false);
  const existing=fixture({uid:'synthetic-existing',isAnonymous:false});assert.equal(await existing.start(),existing.client);assert.equal(existing.nodes.get('status-progress').hidden,false);
  const cancelled=fixture({uid:'synthetic-cancel',isAnonymous:false});await cancelled.start();await cancelled.win.LittleLeafCloudSettings.signOut();assert.deepEqual(cancelled.accountCounts(),{clientClosed:0,signOutCalls:0});
  const failedSignout=fixture({uid:'synthetic-failure',isAnonymous:false},{confirm:true,signOutError:true});await failedSignout.start();failedSignout.emitStatus('saved');await failedSignout.win.LittleLeafCloudSettings.signOut();assert.deepEqual(failedSignout.accountCounts(),{clientClosed:0,signOutCalls:1});let failedView=JSON.parse(failedSignout.win.LittleLeafCloudSettings.snapshot());assert.equal(failedView.status,'Saved');assert.match(failedView.reason,/still signed in/);assert.equal(failedSignout.nodes.get('cloud-account').children[1].disabled,false);failedSignout.emitStatus('pending');assert.equal(JSON.parse(failedSignout.win.LittleLeafCloudSettings.snapshot()).reason,'');failedSignout.emitStatus('offline');const offlineView=JSON.parse(failedSignout.win.LittleLeafCloudSettings.snapshot());assert.equal(offlineView.status,'Not saved');assert.match(offlineView.reason,/Offline/);assert(!offlineView.reason.includes('Sign out'));
  let finishSignout;const signingOut=fixture({uid:'synthetic-repeat',isAnonymous:false},{confirm:true,signOutWait:new Promise(resolve=>{finishSignout=resolve;})});await signingOut.start();const signing=signingOut.win.LittleLeafCloudSettings.signOut();await signingOut.win.LittleLeafCloudSettings.signOut();assert.equal(signingOut.accountCounts().signOutCalls,1);finishSignout();await signing;assert.equal(signingOut.accountCounts().clientClosed,1);
  const reloading=fixture({uid:'synthetic-reload',isAnonymous:false});await reloading.start();
  assert.equal(reloading.runtimeState().runtimeOptions.uid,'synthetic-reload');
  assert.equal(reloading.runtimeState().sessionOptions.sessionId,'synthetic-runtime');
  assert.equal(typeof reloading.runtimeState().sessionOptions.assertRuntime,'function');
  reloading.events.get('pagehide')();assert.equal(reloading.accountCounts().clientClosed,0);
  assert.equal(reloading.runtimeState().runtimeClosed,0);assert.equal(reloading.runtimeState().ownershipClosed,0);
  reloading.setUser(null);reloading.setUser(null);
  assert.equal(reloading.accountCounts().clientClosed,1);
  assert.equal(reloading.runtimeState().runtimeClosed,1);assert.equal(reloading.runtimeState().ownershipClosed,1);
  await activePagehideSave();
  let releaseJournal;const closing=fixture({uid:'synthetic-closing',isAnonymous:false},{journalWait:new Promise(resolve=>{releaseJournal=resolve;})});
  const closingStart=closing.start();await flush();closing.events.get('pagehide')();releaseJournal();
  await assert.rejects(closingStart,{code:'NOT_READY'});assert.equal(closing.accountCounts().clientClosed,0);
  for(const exit of ['pagehide','account']){
    let releaseLock;const early=fixture({uid:'synthetic-early',isAnonymous:false},{acquireWait:new Promise(resolve=>{releaseLock=resolve;})});
    const earlyStart=early.start();await flush();
    if(exit==='pagehide')early.events.get('pagehide')();else early.setUser({uid:'synthetic-other',isAnonymous:false});
    releaseLock();await assert.rejects(earlyStart,{code:'NOT_READY'});
    assert.equal(early.counts().opened,0);assert.equal(early.runtimeState().runtimeClosed,1);
  }
  const brokenJournal=fixture({uid:'synthetic-journal-failure',isAnonymous:false},{journalError:true});
  await assert.rejects(brokenJournal.start(),/synthetic journal unavailable/);
  assert.equal(brokenJournal.runtimeState().runtimeClosed,1);assert.equal(brokenJournal.runtimeState().ownershipClosed,1);
  const anonymous=fixture({uid:'synthetic-anonymous',isAnonymous:true});await assert.rejects(anonymous.start(),/Sign in with Google/);assert.deepEqual(anonymous.counts(),{opened:0,closed:0});
  const trustedFrame={surface:'trusted-itch-frame',runtimeOrigin:'https://demo--itch-embed-test-abc123.web.app',origin:'https://demo--itch-embed-test-abc123.web.app',iframe:true,ancestors:['https://html-classic.itch.zone','https://siowyiyou.itch.io']};
  const popupFixture=fixture(null,{...trustedFrame,popupUser:{uid:'synthetic-popup',isAnonymous:false}});
  let popupReady=false;const popupStart=popupFixture.start().then(value=>{popupReady=true;return value;});await flush();
  assert.equal(popupReady,false);assert.deepEqual(popupFixture.counts(),{opened:0,closed:0});
  assert.deepEqual(popupFixture.authCounts(),{popupCalls:0,redirectCalls:0,redirectResults:0});
  await popupFixture.nodes.get('cloud-account').children[1].onclick();assert.equal(await popupStart,popupFixture.client);
  assert.deepEqual(popupFixture.authCounts(),{popupCalls:1,redirectCalls:0,redirectResults:0});assert.deepEqual(popupFixture.counts(),{opened:1,closed:1});
  const stableFrame={...trustedFrame,runtimeOrigin:'https://demo.firebaseapp.com',origin:'https://demo.firebaseapp.com',runtimePath:'/itch/',pathname:'/itch/'};
  for(const pathname of ['/itch/','/itch/index.html']){
    const stable=fixture(null,{...stableFrame,pathname,popupUser:{uid:'synthetic-stable',isAnonymous:false}});
    const started=stable.start();await flush();await stable.nodes.get('cloud-account').children[1].onclick();
    assert.equal(await started,stable.client);assert.deepEqual(stable.authCounts(),{popupCalls:1,redirectCalls:0,redirectResults:0});
    assert.equal(stable.runtimeState().sessionOptions.sessionId,'synthetic-runtime');
  }
  for(const changed of [{pathname:'/'},{pathname:'/itch/other'},{runtimePath:'/other/'},{runtimePath:undefined},{iframe:false},{hostname:'evil.example'},{ancestors:['https://html-classic.itch.zone','https://another.itch.io']}]){
    const rejected=fixture(null,{...stableFrame,...changed});await assert.rejects(rejected.start(),/approved itch preview/);
    assert.deepEqual(rejected.counts(),{opened:0,closed:0});
  }
  for(const code of ['auth/popup-blocked','auth/popup-closed-by-user','auth/unauthorized-domain']){
    const denied=fixture(null,{...trustedFrame,popupError:code});denied.start();await flush();
    await denied.nodes.get('cloud-account').children[1].onclick();assert.deepEqual(denied.counts(),{opened:0,closed:0});assert.match(denied.nodes.get('status-label').textContent,/did not finish/);assert(!denied.nodes.get('status-label').textContent.includes(code));assert.equal(denied.nodes.get('cloud-account').children[1].disabled,false);
  }
  for(const options of [{iframe:true},{surface:'itch-popup',hostname:'html-classic.itch.zone'},
    {...trustedFrame,origin:'https://html-classic.itch.zone'},
    {...trustedFrame,runtimeOrigin:'https://evil.example',origin:'https://evil.example'},
    {...trustedFrame,origin:'https://demo--itch-embed-test-other.web.app'},
    {...trustedFrame,iframe:false},{...trustedFrame,ancestors:undefined},
    {...trustedFrame,ancestors:['https://html-classic.itch.zone','https://another.itch.io']},
    {...trustedFrame,ancestors:['https://siowyiyou.itch.io','https://html-classic.itch.zone']},
    {...trustedFrame,ancestors:['https://html-classic.itch.zone','https://siowyiyou.itch.io','https://evil.example']},
    {surface:'unknown'}]){
    const rejected=fixture(null,options);await assert.rejects(rejected.start());assert.deepEqual(rejected.counts(),{opened:0,closed:0});assert.deepEqual(rejected.authCounts(),{popupCalls:0,redirectCalls:0,redirectResults:0});
  }
  let releasePopup;const slow=fixture(null,{...trustedFrame,popupWait:new Promise(resolve=>{releasePopup=resolve;}),popupUser:{uid:'synthetic-slow-popup',isAnonymous:false}});
  const slowStart=slow.start();await flush();const popupButton=slow.nodes.get('cloud-account').children[1];const opening=popupButton.onclick();await popupButton.onclick();assert.equal(slow.authCounts().popupCalls,1);assert.deepEqual(slow.counts(),{opened:0,closed:0});releasePopup();await opening;await slowStart;
  console.log('Firebase boot presentation: signed-out, redirect return/failure, authenticated resume and isolation checks passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
