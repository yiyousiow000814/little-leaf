'use strict';
// Execute the real boot module with synthetic SDK/DOM boundaries; no network or saves.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(user=null,options={}){
  const nodes=new Map(),listeners=[];let opened=0,closed=0,redirectError=null;
  const element=()=>({textContent:'',hidden:false,disabled:false,style:{},setAttribute(){},append(...x){this.children=x;}});
  nodes.set('status-label',element());nodes.set('status-progress',element());
  const auth={currentUser:user,authStateReady:async()=>{if(options.authReady)await options.authReady;}};
  const client={sync(){},close(){}};
  const win={addEventListener(){},__littleLeafVault:{close(){closed++;}},LittleLeafAuthorityCodec:{},LittleLeafFirebase:{createRemote(){return{};},async openJournal(){opened++;return{};},createClient(){return client;}}};win.top=win.self=win;
  const document={createElement:element,getElementById:id=>nodes.get(id),body:{append(x){nodes.set(x.id,x);}}};
  const context={window:win,document,location:{hostname:'demo.firebaseapp.com',reload(){}},indexedDB:{},initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>{if(options.redirectResultError)throw Error("sensitive SDK detail");return null;},signInWithRedirect:async()=>{if(redirectError)throw redirectError;},signOut:async()=>{},onAuthStateChanged:(a,fn)=>{listeners.push(fn);return()=>{};},setInterval(){},doc(){},getDocFromServer(){},runTransaction(){},confirm:()=>false};
  vm.createContext(context);vm.runInContext(source,context);
  return {nodes,auth,start:()=>context.start({authDomain:'demo.firebaseapp.com'}),setUser(u){auth.currentUser=u;for(const fn of [...listeners])fn(u);},failRedirect(){redirectError=Error('synthetic cancelled sign-in');},counts:()=>({opened,closed}),client};
}
(async()=>{
  const f=fixture();let ready=false;const pending=f.start().then(x=>{ready=true;return x;});await flush();
  assert.equal(ready,false);assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(f.nodes.get('status-progress').hidden,true);assert.deepEqual(f.counts(),{opened:0,closed:0});
  const button=f.nodes.get('cloud-account').children[1];assert.equal(button.disabled,false);
  await button.onclick();assert.equal(f.nodes.get('status-label').textContent,'Sign in with Google to open your café.');assert.equal(ready,false);
  f.failRedirect();await button.onclick();assert.match(f.nodes.get('status-label').textContent,/did not finish/);assert.equal(button.disabled,false);assert.equal(ready,false);assert.deepEqual(f.counts(),{opened:0,closed:0});
  f.setUser({uid:'synthetic-user',isAnonymous:false});assert.equal(await pending,f.client);assert.equal(f.nodes.get('status-label').textContent,'Loading your saved café…');assert.equal(f.nodes.get('status-progress').hidden,false);assert.deepEqual(f.counts(),{opened:1,closed:1});
  const initialFailure=fixture(null,{redirectResultError:true});await assert.rejects(initialFailure.start(),error=>/Reload Little Leaf.*Sign in with Google/.test(error.message)&&!error.message.includes('SDK'));assert.deepEqual(initialFailure.counts(),{opened:0,closed:0});
  let releaseAuth;const authReady=new Promise(resolve=>{releaseAuth=resolve;});const delayed=fixture(null,{authReady});let delayedReady=false;const delayedStart=delayed.start().then(()=>{delayedReady=true;});await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Checking your sign-in…');assert.equal(delayed.nodes.get('cloud-account').children[1].disabled,true);assert.equal(delayedReady,false);releaseAuth();await flush();assert.equal(delayed.nodes.get('status-label').textContent,'Sign in with Google to open your café.');delayed.setUser({uid:'synthetic-delay',isAnonymous:false});await delayedStart;
  const existing=fixture({uid:'synthetic-existing',isAnonymous:false});assert.equal(await existing.start(),existing.client);assert.equal(existing.nodes.get('status-progress').hidden,false);
  const anonymous=fixture({uid:'synthetic-anonymous',isAnonymous:true});await assert.rejects(anonymous.start(),/Sign in with Google/);assert.deepEqual(anonymous.counts(),{opened:0,closed:0});
  console.log('Firebase boot presentation: signed-out, redirect return/failure, authenticated resume and isolation checks passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
