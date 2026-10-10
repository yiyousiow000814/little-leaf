'use strict';
// Real boot source, synthetic Firebase Auth; every save/game boundary fails on access.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {sourcePath}=require('./source_paths');
const source=fs.readFileSync(sourcePath(process.cwd(),'web/little_leaf_firebase_boot.mjs'),'utf8').replace(/^import .*;\r?\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const origin='https://demo--itch-embed-test-fixture.web.app';
function fixture({restored=null,provider='google.com',popupProvider='google.com',failure=false,tokenFailure=false,noObserver=false}={}){
  const nodes=new Map(),callbacks=[];let forbidden=0,popupCalls=0,tokenCalls=0,resolved=false;
  const blocked=()=>{forbidden++;throw Error('Save/game boundary accessed');};
  const element=()=>({textContent:'',style:{},hidden:false,disabled:false,setAttribute(){},append(...children){this.children=children;}});
  nodes.set('status-label',element());nodes.set('status-progress',element());
  const auth={currentUser:restored,authStateReady:async()=>{}};
  const window={top:{},self:{}};
  for(const key of ['LittleLeafFirebaseSession','LittleLeafFirebase','LittleLeafUpdates','__littleLeafVault','sessionStorage'])Object.defineProperty(window,key,{get:blocked});
  const context={window,document:{createElement:element,getElementById:key=>nodes.get(key),body:{append(node){nodes.set(node.id,node);}}},location:{origin,ancestorOrigins:['https://html-classic.itch.zone','https://siowyiyou.itch.io']},initializeApp:()=>({}),getAuth:()=>auth,GoogleAuthProvider:class{},browserLocalPersistence:{},setPersistence:async()=>{},getIdTokenResult:async()=>{tokenCalls++;if(tokenFailure)throw Error('private token detail');return {claims:{firebase:{sign_in_provider:provider}},token:'DO-NOT-EXPOSE'};},onAuthStateChanged:(_,fn)=>{callbacks.push(fn);return()=>{};},signInWithPopup:async()=>{popupCalls++;if(failure)throw Error('private SDK detail');auth.currentUser={uid:'synthetic',isAnonymous:false};if(!noObserver)callbacks.forEach(fn=>fn(auth.currentUser));return {user:auth.currentUser,providerId:popupProvider};}};
  for(const key of ['getFirestore','doc','getDocFromServer','runTransaction','serverTimestamp','onSnapshot','setInterval','getRedirectResult','signInWithRedirect'])context[key]=blocked;
  for(const key of ['indexedDB','localStorage','Engine'])Object.defineProperty(context,key,{get:blocked});
  context.setTimeout=blocked;
  vm.createContext(context);vm.runInContext(source,context);
  return {nodes,context,notify(){callbacks.forEach(fn=>fn(auth.currentUser));},counts:()=>({forbidden,popupCalls,tokenCalls,resolved}),start(options={surface:'trusted-itch-frame',runtimeOrigin:origin,authVerificationOnly:true}){return context.start({projectId:'demo',authDomain:'demo.firebaseapp.com'},options).then(()=>{resolved=true;});}};
}
(async()=>{
  const fresh=fixture();fresh.start();await flush();
  assert.match(fresh.nodes.get('status-label').textContent,/Signed out/);
  const button=fresh.nodes.get('auth-verification').children[1];await button.onclick();await flush();
  assert.match(fresh.nodes.get('status-label').textContent,/Google popup completed: Google authenticated/);
  assert.equal(fresh.nodes.get('auth-verification').children[0].textContent,'Google sign-in confirmed.');
  assert.deepEqual(fresh.counts(),{forbidden:0,popupCalls:1,tokenCalls:1,resolved:false});
  assert(!fresh.nodes.get('status-label').textContent.includes('DO-NOT-EXPOSE'));
  for(const spec of [{restored:{uid:'restored',isAnonymous:false}},{provider:'password'},{popupProvider:'password'},{tokenFailure:true},{failure:true},{noObserver:true}]){
    const f=fixture(spec);f.start();await flush();
    if(spec.restored){f.notify();await flush();assert.match(f.nodes.get('status-label').textContent,/Restored Firebase session: Google authenticated/);assert.equal(f.counts().popupCalls,0);}
    else {await f.nodes.get('auth-verification').children[1].onclick();await flush();assert.match(f.nodes.get('status-label').textContent,spec.noObserver?/Google popup completed: Google authenticated/:/not verified|could not be verified|did not finish/);}
    assert.equal(f.counts().forbidden,0);assert.equal(f.counts().resolved,false);
    assert(!f.nodes.get('status-label').textContent.includes('private'));
  }
  for(const change of [{origin:'https://evil.test'},{ancestorOrigins:['https://evil.test','https://siowyiyou.itch.io']}]){
    const f=fixture();Object.assign(f.context.location,change);let initialized=0;f.context.initializeApp=()=>{initialized++;};await assert.rejects(f.start(),/approved itch preview/);assert.equal(initialized,0);
  }
  if(process.argv[2]){
    const html=fs.readFileSync(process.argv[2],'utf8'),manifest=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
    const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
    assert.equal(scripts.length,1);assert(!scripts[0][1].includes('src='));assert(!/new Engine|index\.js|GODOT_CONFIG|__littleLeafVault|__littleLeafPreferences/.test(html));
    const actualOptions=JSON.parse(scripts[0][2].match(/,"?\s*(\{"surface".*?\})\)\)/)[1]);
    assert.equal(actualOptions.runtimeOrigin,manifest.runtime_origin);assert.equal(actualOptions.runtimeOrigin,'https://little-leaf-41e5d--itch-embed-test-0b0pnaf7.web.app');
    for(const spec of [{},{failure:true},{tokenFailure:true},{restored:{uid:'restored',isAnonymous:false}},{noObserver:true}]){
      const f=fixture(spec);f.context.location.origin=manifest.runtime_origin;f.context.__authModule={start:f.context.start};
      vm.runInContext(scripts[0][2].replace('import("./little_leaf_firebase_boot.mjs")','Promise.resolve(__authModule)'),f.context);await flush();
      if(spec.restored){f.notify();await flush();assert.match(f.nodes.get('status-label').textContent,/Restored Firebase session/);}
      else {await f.nodes.get('auth-verification').children[1].onclick();await flush();}
      assert.equal(f.counts().forbidden,0);assert.equal(f.counts().resolved,false);
      let ready=false;f.context.window.__littleLeafFirebaseReady.then(()=>{ready=true;});await flush();assert.equal(ready,false);
    }
    // A rejected import/start must remain visible without exposing SDK/error details.
    const rejected=fixture(),visible={textContent:''};rejected.nodes.set('auth-verification-slot',visible);
    vm.runInContext(scripts[0][2].replace('import("./little_leaf_firebase_boot.mjs")','Promise.reject(new Error("private SDK detail"))'),rejected.context);await flush();
    assert.equal(visible.textContent,'Sign-in setup did not finish. Reload this page to retry.');
    assert(!visible.textContent.includes('private'));assert.equal(rejected.counts().forbidden,0);
    console.log('Packaged shell passed: exact manifest origin, no engine/adapter scripts, zero Engine/storage/Firestore/session/save/timer boundaries.');
  }
  for(const options of [{authVerificationOnly:true},{surface:'trusted-itch-frame',runtimeOrigin:origin,authVerificationOnly:false}]){
    const f=fixture();await assert.rejects(f.start(options),/Auth verification requires/);assert.equal(f.counts().forbidden,0);
  }
  console.log('Auth verification pause passed: zero Firestore, session, journal, vault, game or timer access; boot promise remains pending.');
})();
