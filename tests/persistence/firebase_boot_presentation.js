'use strict';
// Execute the real boot module with synthetic SDK/DOM boundaries; no network or saves.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const source=fs.readFileSync('platform/web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\r?\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(user=null,options={}){
  const nodes=new Map(),listeners=[],events=new Map(),identityCalls=[];let runtimeOptions,sessionOptions,cloudOptions,journalOptions,runtimeClosed=0,ownershipClosed=0;let opened=0,closed=0,redirectError=null,statusCallback=null,clientClosed=0,signOutCalls=0,popupCalls=0,redirectCalls=0,redirectResults=0;
  const element=()=>({textContent:'',hidden:false,disabled:false,style:{},setAttribute(){},append(...x){this.children=x;}});
  nodes.set('status-label',element());nodes.set('status-progress',element());
  const auth={currentUser:user,authStateReady:async()=>{if(options.authReady)await options.authReady;}};
  let client={sync(){},close(){clientClosed++;}};
  const win={navigator:options.navigator || {},addEventListener(name,fn){events.set(name,fn);},__littleLeafVault:{close(){closed++;}},LittleLeafAuthorityCodec:options.codec || {},LittleLeafUpdates:{create(){return {close(){}};}},LittleLeafFirebaseSession:{async acquireRuntime(value){runtimeOptions=value;if(options.acquireWait)await options.acquireWait;return {sessionId:'synthetic-runtime',assertHeld(){if(runtimeClosed)throw Object.assign(Error('closed'),{code:'NOT_READY'});},close(){runtimeClosed++;}};},createRemote(){return options.sessionRemote || {};},createSession(value){sessionOptions=value;if(options.createSession){const session=options.createSession(value),close=session.close;session.close=()=>{if(!ownershipClosed){ownershipClosed++;close();}};return session;}return {async start(){},assertActive(){value.assertRuntime();if(ownershipClosed)throw Object.assign(Error('closed'),{code:'NOT_READY'});return {writerId:value.sessionId,writerEpoch:1};},close(){if(!ownershipClosed)ownershipClosed++;}};}},LittleLeafFirebase:{createRemote(){return options.remote || {};},async openJournal(_db,journalConfig){journalOptions=journalConfig;opened++;if(options.journalWait)await options.journalWait;if(options.journalError)throw Error("synthetic journal unavailable");return options.journal || {};},createClient(value){cloudOptions=value;statusCallback=value.status;if(options.createClient){client=options.createClient(value);const close=client.close;client.close=()=>{clientClosed++;close();};}return client;}}};win.top=win.self=win;if(options.iframe)win.top={};
  const document={createElement:element,getElementById:id=>nodes.get(id),body:{append(x){nodes.set(x.id,x);}}};
  const context={window:win,document,location:{hostname:options.hostname || 'demo.firebaseapp.com',protocol:options.protocol || 'https:',origin:options.origin || 'https://demo.firebaseapp.com',ancestorOrigins:options.ancestors,pathname:options.pathname || '/',reload(){}},indexedDB:{},initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),getFunctions:()=>({}),httpsCallable:(_functions,name)=>async data=>{identityCalls.push({name,data});if(options.publicUidWait)await options.publicUidWait;if(options.publicUidError)throw Error('synthetic identity refusal');return {data:{publicUid:Object.hasOwn(options,'publicUid')?options.publicUid:'100123456789'}};},getIdTokenResult:async()=>{if(options.tokenWait)await options.tokenWait;return {claims:{firebase:{sign_in_provider:options.authProvider || 'google.com'}}};},GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>{redirectResults++;if(options.redirectResultError)throw Error("sensitive SDK detail");return null;},signInWithRedirect:async()=>{redirectCalls++;if(redirectError)throw redirectError;},signInWithPopup:async()=>{popupCalls++;if(options.popupError)throw Error(options.popupError);if(options.popupWait)await options.popupWait;if(options.popupUser){auth.currentUser=options.popupUser;for(const fn of [...listeners])fn(auth.currentUser);}return {user:auth.currentUser};},signOut:async()=>{signOutCalls++;if(options.signOutError)throw Error("synthetic signout failure");if(options.signOutWait)await options.signOutWait;},onAuthStateChanged:(a,fn)=>{listeners.push(fn);return()=>{};},setTimeout:options.timers?.setTimeout || setTimeout,clearTimeout:options.timers?.clearTimeout || clearTimeout,setInterval(){},doc(){},getDocFromServer(){},runTransaction(){},serverTimestamp(){},onSnapshot(){},confirm:()=>!!options.confirm};
  vm.createContext(context);vm.runInContext(source,context);
  return {nodes,auth,win,events,identityCalls,runtimeState:()=>({runtimeOptions,sessionOptions,runtimeClosed,ownershipClosed,cloudStartup:cloudOptions?.cloudStartup,cloudOnly:journalOptions?.cloudOnly}),emitStatus(value){statusCallback(value);},start:()=>context.start({authDomain:'demo.firebaseapp.com',projectId:'demo'},options.surface?{surface:options.surface,runtimeOrigin:options.runtimeOrigin,runtimePath:options.runtimePath}:{}),authCounts:()=>({popupCalls,redirectCalls,redirectResults}),setUser(u){auth.currentUser=u;for(const fn of [...listeners])fn(u);},failRedirect(){redirectError=Error('synthetic cancelled sign-in');},counts:()=>({opened,closed}),accountCounts:()=>({clientClosed,signOutCalls}),get client(){return client;}};
}
async function uidSettings(){
  const uid='SyntheticFirebaseAuthUid',publicUid='100123456789',writes=[];let finishCopy;
  const ready=async f=>{await flush();await flush();return JSON.parse(f.win.LittleLeafCloudSettings.snapshot());};
  const f=fixture({uid,isAnonymous:false,email:'not-a-uid@example.invalid',accessToken:'not-a-uid-token'},{navigator:{clipboard:{writeText(text){writes.push(text);return new Promise(resolve=>{finishCopy=resolve;});}}}});
  await f.start();assert.equal((await ready(f)).publicUid,publicUid);
  assert.deepEqual(f.identityCalls,[{name:'ensureMyPublicUid',data:null}],'own identity has no target-UID argument');
  const api=f.win.LittleLeafCloudSettings,view=()=>JSON.parse(api.snapshot());
  assert.equal(view().publicUidStatus,'ready');assert(!api.snapshot().includes('not-a-uid'));
  let observed=[];api.watchUid(()=>observed.push(view()));
  const copying=api.copyUid();assert.equal(view().copyStatus,'copying');assert.deepEqual(writes,[publicUid]);
  await api.copyUid();assert.equal(writes.length,1,'repeat click cannot duplicate pending clipboard work');
  finishCopy();await copying;assert.equal(view().copyStatus,'copied');assert.equal(observed.at(-1).copyStatus,'copied');
  const changed=api.copyUid();f.setUser({uid:'SyntheticOtherAccount',isAnonymous:false});
  assert.equal(view().publicUid,'');assert.equal(view().copyStatus,'');assert.equal(observed.at(-1).publicUid,'');
  finishCopy();await changed;assert.equal(view().copyStatus,'','late clipboard completion cannot restore old identity feedback');
  f.setUser({uid,isAnonymous:false});assert.equal(view().publicUid,'','closed client cannot adopt an account that signs back in');
  await api.copyUid();assert.equal(writes.length,2);
  api.unwatchUid();const count=observed.length;f.setUser(null);assert.equal(observed.length,count);
  const broken=fixture({uid,isAnonymous:false});await broken.start();await ready(broken);
  broken.win.LittleLeafCloudSettings.watchUid(()=>{throw Error('synthetic observer failure');});broken.setUser(null);
  assert.equal(broken.accountCounts().clientClosed,1);assert.equal(broken.runtimeState().runtimeClosed,1);
  assert.equal(JSON.parse(broken.win.LittleLeafCloudSettings.snapshot()).publicUid,'','presentation failure cannot interrupt account closure');
  for(const navigator of [{},{clipboard:{writeText:async()=>{throw Error('synthetic denial');}}}]){
    const denied=fixture({uid,isAnonymous:false},{navigator});await denied.start();await ready(denied);await denied.win.LittleLeafCloudSettings.copyUid();
    const value=JSON.parse(denied.win.LittleLeafCloudSettings.snapshot());assert.equal(value.publicUid,publicUid);assert.equal(value.copyStatus,'failed');
  }
  for(const invalid of [100123456789,null,'','012345678901','10012345678','1001234567890','10012345678A','١٠٠١٢٣٤٥٦٧٨٩',...['\n','\r','\u2028'].map(suffix=>publicUid+suffix)]){
    const invalidId=fixture({uid:publicUid,isAnonymous:false},{publicUid:invalid});await invalidId.start();const value=await ready(invalidId);
    assert.equal(value.publicUid,'');assert.equal(value.publicUidStatus,'unavailable');await invalidId.win.LittleLeafCloudSettings.copyUid();assert.equal(value.copyStatus,'');
  }
  const unavailable=fixture({uid:publicUid,isAnonymous:false},{publicUidError:true});await unavailable.start();
  assert.equal((await ready(unavailable)).publicUid,'','an all-digit Auth UID is never a public-ID fallback');
  const nonGoogle=fixture({uid,isAnonymous:false},{authProvider:'password'});await nonGoogle.start();assert.equal((await ready(nonGoogle)).publicUidStatus,'unavailable');assert.equal(nonGoogle.identityCalls.length,0);
  for(const transition of ['ready','other-account','signed-out']){
    let release;const pending=fixture({uid,isAnonymous:false},{publicUidWait:new Promise(resolve=>{release=resolve;})});await pending.start();
    const before=await ready(pending);assert.equal(before.publicUidStatus,'loading');assert.equal(before.publicUid,'');
    await pending.win.LittleLeafCloudSettings.copyUid();assert.equal(JSON.parse(pending.win.LittleLeafCloudSettings.snapshot()).copyStatus,'');
    if(transition==='other-account')pending.setUser({uid:'SyntheticOtherAccount',isAnonymous:false});
    if(transition==='signed-out')pending.setUser(null);
    release();const after=await ready(pending);assert.equal(after.publicUid,transition==='ready'?publicUid:'');
  }
  let finishSignout;
  const leaving=fixture({uid,isAnonymous:false},{confirm:true,signOutWait:new Promise(resolve=>{finishSignout=resolve;})});await leaving.start();await ready(leaving);
  const out=leaving.win.LittleLeafCloudSettings;let cleared=false;out.watchUid(()=>{if(JSON.parse(out.snapshot()).publicUid==='')cleared=true;});
  const pending=out.signOut();assert(cleared);assert.equal(JSON.parse(out.snapshot()).publicUid,'');finishSignout();await pending;assert.equal(JSON.parse(out.snapshot()).publicUid,'');
  const failed=fixture({uid,isAnonymous:false},{confirm:true,signOutError:true});await failed.start();await ready(failed);await failed.win.LittleLeafCloudSettings.signOut();
  assert.equal((await ready(failed)).publicUid,publicUid,'failed sign-out re-confirms the same server-owned identity');assert.equal(failed.identityCalls.length,2);
  const guest=fixture();guest.start();await flush();assert.equal(JSON.parse(guest.win.LittleLeafCloudSettings.snapshot()).publicUid,'');
  const anonymous=fixture({uid,isAnonymous:true});await assert.rejects(anonymous.start());assert.equal(JSON.parse(anonymous.win.LittleLeafCloudSettings.snapshot()).publicUid,'');
  console.log('Public UID:12-digit string, own Google callable, unavailable/loading, clipboard settlement/denial, late account fencing and observer lifecycle passed');
}
async function ownershipStartupDeadline(){
  const root={crypto:webcrypto};root.globalThis=root;
  vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase_session.js','utf8'),root);
  const api=root.LittleLeafFirebaseSession;
  for(const stage of ['transaction','readback','account','pagehide']){
    const timers=new Map();let timerId=0,release,owner=null,transactions=0,writes=0,watches=0;
    const held=new Promise(resolve=>{release=resolve;});
    const sdk={doc(_db,...path){return path.join('/');},serverTimestamp:()=>100,
      async runTransaction(_db,action){
        const call=++transactions;
        if(call===1&&stage!=='readback')await held;
        return action({async get(ref){if(call===2)await held;const value=ref.endsWith('/owner')?owner:null;return {exists:()=>value!==null,data:()=>value};},set(_ref,next){owner=next;writes++;}});
      },onSnapshot(){watches++;return()=>{};}};
    const f=fixture({uid:'synthetic-startup',isAnonymous:false},{
      timers:{setTimeout(fn,ms){const id=++timerId;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}},
      sessionRemote:api.createRemote({},sdk,'synthetic-startup'),createSession:api.createSession
    });
    const pending=f.start();await flush();
    assert.equal(timers.size,1,'ownership startup must have a deadline before the journal/client exists');
    const timer=timers.values().next().value;assert.equal(timer.ms,15000);
    if(stage==='account')f.setUser({uid:'synthetic-other',isAnonymous:false});
    else if(stage==='pagehide')f.events.get('pagehide')();
    else timer.fn();
    await assert.rejects(pending,{code:['account','pagehide'].includes(stage)?'NOT_READY':'NETWORK_TIMEOUT'});
    assert.deepEqual(f.counts(),{opened:0,closed:0});assert.equal(f.accountCounts().clientClosed,0);
    assert.equal(f.runtimeState().ownershipClosed,1);assert.equal(f.runtimeState().runtimeClosed,1);
    assert.throws(()=>f.runtimeState().sessionOptions.assertRuntime(),{code:'NOT_READY'});
    assert.equal(timers.size,0);assert.equal(watches,0);
    const preservedOwner=owner;release();await flush();await flush();
    assert.equal(writes,stage==='readback'?1:0,'an already committed session write is preserved; a closed callback cannot start one');
    assert.equal(owner,preservedOwner);assert.equal(transactions,stage==='readback'?2:1,'timeout must not start a replacement takeover or readback');
    assert.equal(watches,0,'late startup cannot install an ownership listener');
    assert.deepEqual(f.counts(),{opened:0,closed:0});assert.equal(f.win.LittleLeafUpdate,undefined);
    assert.equal(f.runtimeState().runtimeClosed,1);assert.equal(f.runtimeState().ownershipClosed,1);
  }
  // Successful startup clears the timer and retains the active-page lifecycle.
  const timers=new Map();let timerId=0;
  const f=fixture({uid:'synthetic-startup-success',isAnonymous:false},{timers:{setTimeout(fn,ms){const id=++timerId;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}}});
  assert.equal(await f.start(),f.client);assert.equal(timers.size,0);assert.equal(f.runtimeState().runtimeClosed,0);
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
  await uidSettings();
  await ownershipStartupDeadline();
  const bridgeSource=fs.readFileSync('game/scripts/persistence/cafe_cloud_settings.gd','utf8');
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
  const existing=fixture({uid:'synthetic-existing',isAnonymous:false});assert.equal(await existing.start(),existing.client);assert.equal(existing.runtimeState().cloudStartup,true,'Google bootstrap always opts into cloud authority');assert.equal(existing.runtimeState().cloudOnly,true,'Google uses isolated account journal namespace');assert.equal(existing.nodes.get('status-progress').hidden,false);
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
