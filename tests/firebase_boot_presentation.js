'use strict';
// Execute the real boot module with synthetic SDK/DOM boundaries; no network or saves.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(user=null,options={}){
  const nodes=new Map(),listeners=[];let opened=0,closed=0,redirectError=null,statusCallback=null,clientClosed=0,signOutCalls=0;
  const element=()=>({textContent:'',hidden:false,disabled:false,style:{},setAttribute(){},append(...x){this.children=x;}});
  nodes.set('status-label',element());nodes.set('status-progress',element());
  const auth={currentUser:user,authStateReady:async()=>{if(options.authReady)await options.authReady;}};
  const client={sync(){},close(){clientClosed++;}};
  const win={addEventListener(){},__littleLeafVault:{close(){closed++;}},LittleLeafAuthorityCodec:{},LittleLeafFirebase:{createRemote(){return{};},async openJournal(){opened++;return{};},createClient(options){statusCallback=options.status;return client;}}};win.top=win.self=win;
  const document={createElement:element,getElementById:id=>nodes.get(id),body:{append(x){nodes.set(x.id,x);}}};
  const context={window:win,document,location:{hostname:'demo.firebaseapp.com',reload(){}},indexedDB:{},initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>{if(options.redirectResultError)throw Error("sensitive SDK detail");return null;},signInWithRedirect:async()=>{if(redirectError)throw redirectError;},signOut:async()=>{signOutCalls++;if(options.signOutError)throw Error("synthetic signout failure");if(options.signOutWait)await options.signOutWait;},onAuthStateChanged:(a,fn)=>{listeners.push(fn);return()=>{};},setInterval(){},doc(){},getDocFromServer(){},runTransaction(){},confirm:()=>!!options.confirm};
  vm.createContext(context);vm.runInContext(source,context);
  return {nodes,auth,win,emitStatus(value){statusCallback(value);},start:()=>context.start({authDomain:'demo.firebaseapp.com'}),setUser(u){auth.currentUser=u;for(const fn of [...listeners])fn(u);},failRedirect(){redirectError=Error('synthetic cancelled sign-in');},counts:()=>({opened,closed}),accountCounts:()=>({clientClosed,signOutCalls}),client};
}
(async()=>{
  const bridgeSource=fs.readFileSync('scripts/cafe_cloud_settings.gd','utf8');
  const presence=bridgeSource.match(/if not JavaScriptBridge\.eval\("([^"\n]+)"\):return null/)[1];
  assert(bridgeSource.indexOf('if not JavaScriptBridge.eval')<bridgeSource.indexOf('api=JavaScriptBridge.get_interface'));
  for(const [window,expected] of [[{},false],[{LittleLeafCloudSettings:null},false],[{LittleLeafCloudSettings:{}},true]])assert.equal(vm.runInNewContext(presence,{window}),expected,'optional bridge presence for ordinary/Firebase Web');
  const f=fixture();let ready=false;const pending=f.start().then(x=>{ready=true;return x;});await flush();
  assert.equal(ready,false);assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(f.nodes.get('status-progress').hidden,true);assert.deepEqual(f.counts(),{opened:0,closed:0});
  const button=f.nodes.get('cloud-account').children[1];assert.equal(button.disabled,false);
  await button.onclick();assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(ready,false);
  f.failRedirect();await button.onclick();assert.match(f.nodes.get('status-label').textContent,/did not finish/);assert.equal(button.disabled,false);assert.equal(ready,false);assert.deepEqual(f.counts(),{opened:0,closed:0});
  f.setUser({uid:'synthetic-user',isAnonymous:false});assert.equal(await pending,f.client);assert.equal(f.nodes.get('status-label').textContent,'Loading your saved café…');assert.equal(f.nodes.get('status-progress').hidden,false);assert.deepEqual(f.counts(),{opened:1,closed:1});
  const initialFailure=fixture(null,{redirectResultError:true});await assert.rejects(initialFailure.start(),error=>/Reload Little Leaf.*Sign in with Google/.test(error.message)&&!error.message.includes('SDK'));assert.deepEqual(initialFailure.counts(),{opened:0,closed:0});
  let releaseAuth;const authReady=new Promise(resolve=>{releaseAuth=resolve;});const delayed=fixture(null,{authReady});let delayedReady=false;const delayedStart=delayed.start().then(()=>{delayedReady=true;});await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Checking your sign-in…');assert.equal(delayed.nodes.get('cloud-account').children[1].disabled,true);assert.equal(delayedReady,false);releaseAuth();await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Sign in with Google to open your café.');delayed.setUser({uid:'synthetic-delay',isAnonymous:false});await delayedStart;
  assert.equal(f.nodes.get('cloud-account').hidden,true,'signed-in gameplay has no account strip');
  for(const [state,status] of [['ready','Not saved'],['pending','Saving…'],['saved','Saved'],['offline','Not saved'],['conflict','Not saved'],['blocked','Not saved']]){
    f.emitStatus(state);const view=JSON.parse(f.win.LittleLeafCloudSettings.snapshot());assert.equal(view.status,status);assert(!JSON.stringify(view).includes('first save'));assert.equal(view.reload,state==='conflict');if(['offline','conflict','blocked'].includes(state))assert(view.reason.length>0);
  }
  f.emitStatus('conflict');assert.equal(JSON.parse(f.win.LittleLeafCloudSettings.snapshot()).canSave,false);
  const existing=fixture({uid:'synthetic-existing',isAnonymous:false});assert.equal(await existing.start(),existing.client);assert.equal(existing.nodes.get('status-progress').hidden,false);
  const cancelled=fixture({uid:'synthetic-cancel',isAnonymous:false});await cancelled.start();await cancelled.win.LittleLeafCloudSettings.signOut();assert.deepEqual(cancelled.accountCounts(),{clientClosed:0,signOutCalls:0});
  const failedSignout=fixture({uid:'synthetic-failure',isAnonymous:false},{confirm:true,signOutError:true});await failedSignout.start();failedSignout.emitStatus('saved');await failedSignout.win.LittleLeafCloudSettings.signOut();assert.deepEqual(failedSignout.accountCounts(),{clientClosed:0,signOutCalls:1});let failedView=JSON.parse(failedSignout.win.LittleLeafCloudSettings.snapshot());assert.equal(failedView.status,'Saved');assert.match(failedView.reason,/still signed in/);assert.equal(failedSignout.nodes.get('cloud-account').children[1].disabled,false);
  let finishSignout;const signingOut=fixture({uid:'synthetic-repeat',isAnonymous:false},{confirm:true,signOutWait:new Promise(resolve=>{finishSignout=resolve;})});await signingOut.start();const signing=signingOut.win.LittleLeafCloudSettings.signOut();await signingOut.win.LittleLeafCloudSettings.signOut();assert.equal(signingOut.accountCounts().signOutCalls,1);finishSignout();await signing;assert.equal(signingOut.accountCounts().clientClosed,1);
  const anonymous=fixture({uid:'synthetic-anonymous',isAnonymous:true});await assert.rejects(anonymous.start(),/Sign in with Google/);assert.deepEqual(anonymous.counts(),{opened:0,closed:0});
  console.log('Firebase boot presentation: signed-out, redirect return/failure, authenticated resume and isolation checks passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
