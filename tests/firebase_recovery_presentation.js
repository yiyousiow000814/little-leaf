'use strict';
// Real Firebase boot bridge, synthetic SDK/DOM and account-scoped fake client only.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('web/little_leaf_firebase_boot.mjs','utf8').replace(/^import .*;\n/gm,'').replace('export async function start','async function start');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
let checks=0;function check(value,message){checks++;assert(value,message);}
function fixture(options={}){
 const nodes=new Map(),downloads=[],blobs=[],confirms=[],calls=[];
 const auth={currentUser:{uid:'synthetic-current-account',isAnonymous:false},authStateReady:async()=>{}};
 let snapshot={available:true,choicesAvailable:true,busy:false,expectedLocalDigest:'b'.repeat(64),expectedCloudDigest:'a'.repeat(64),choices:[{id:'local',coins:42000,lastSavedAt:1791510000000,device:'Android phone'},{id:'cloud',coins:37000,lastSavedAt:1791500000000,device:'Unknown device'}],reason:''};
 const client={sync(){},close(){},recoverySnapshot:()=>snapshot,ownershipSnapshot:()=>options.owner || {serverOwnership:false},
  async requestTakeover(){calls.push(["request"]);return {ok:true,status:"waiting"};},
  async finishTakeover(){calls.push(["finish"]);return {ok:true,source:"authority",payload:"server snapshot",profileId:"profile",revision:9};},
  async forceTakeover(){calls.push(["force"]);return {ok:true,source:"authority",payload:"cloud snapshot",profileId:"profile",revision:9};},
  async prepareChoice(choice,local,cloud){calls.push(['prepare',choice,local,cloud]);if(options.wait)await options.wait;return options.result || {ok:true,source:'authority',profileId:'synthetic-profile',revision:8,payload:'synthetic payload',selectionToken:'prepared-token'};},
  async confirmChoice(token){calls.push(['confirm',token]);return {ok:true,source:'authority',profileId:'synthetic-profile',revision:8,payload:'synthetic payload'};},
  async preserveRuntime(...args){calls.push(['preserve',...args]);return {ok:true,durable:true,revision:9};}};
 const element=tag=>({tag,textContent:'',hidden:false,disabled:false,style:{},children:[],setAttribute(){},append(...children){this.children.push(...children);},click(){downloads.push({name:this.download,href:this.href});},remove(){}});
 nodes.set('status-label',element('span'));nodes.set('status-progress',element('progress'));
 const win={addEventListener(){},__littleLeafVault:{close(){}},LittleLeafAuthorityCodec:{},LittleLeafUpdates:{create(){return{};}},LittleLeafFirebaseSession:{createRemote(){return{};},createSession(){return {async start(){}};}},LittleLeafFirebase:{createRemote(){return{};},async openJournal(){return{};},createClient(){return client;}}};win.top=win.self=win;
 const document={createElement:element,getElementById:id=>nodes.get(id),body:{append(node){if(node.id)nodes.set(node.id,node);}}};
 const context={window:win,document,location:{hostname:'demo.firebaseapp.com',reload(){calls.push(['reload']);}},indexedDB:{},initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>null,signInWithRedirect:async()=>{},signOut:async()=>{},onAuthStateChanged:()=>()=>{},setInterval(){},setTimeout(fn){fn();},doc(){},getDocFromServer(){},runTransaction(){},serverTimestamp(){},onSnapshot(){},confirm(text){confirms.push(text);if(options.onConfirm)options.onConfirm();return options.confirm!==false;},Blob:class{constructor(parts,type){this.parts=parts;this.type=type;}},URL:{createObjectURL(blob){blobs.push(blob);return 'blob:synthetic-only';},revokeObjectURL(){}}};
 vm.createContext(context);vm.runInContext(source,context);
 return {start:()=>context.start({authDomain:'demo.firebaseapp.com'}),win,client,auth,calls,confirms,downloads,blobs,setSnapshot(value){snapshot=value;},getSnapshot:()=>snapshot};
}
const invoke=(f,name,...args)=>new Promise(resolve=>f.win.LittleLeafVault[name](...args,json=>resolve(JSON.parse(json))));
(async()=>{
 const f=fixture();await f.start();const snapshot=JSON.parse(f.win.LittleLeafVault.recoverySnapshot());
 check(snapshot.available && snapshot.choices.length===2,'verified two-choice preview');
 check(snapshot.choices[1].device==='Unknown device','legacy device remains unknown');
 check(snapshot.choices[0].coins===42000 && snapshot.choices[0].lastSavedLabel!=='Unknown','coins and local save time shown');
 check(!('recoverCloud' in f.win.LittleLeafVault) && !('exportRecovery' in f.win.LittleLeafVault),'generic load/export flow removed');
 const prepared=await invoke(f,'prepareChoice','local','b'.repeat(64),'a'.repeat(64));
 check(prepared.selectionToken==='prepared-token' && f.confirms.length===0,'prepare has no player confirmation or mutation');
 check(f.calls[0][2]==='b'.repeat(64) && f.calls[0][3]==='a'.repeat(64),'both digests forwarded');
 check((await invoke(f,'confirmChoice','wrong-token')).code==='RECOVERY_CHANGED','wrong candidate cannot confirm');
 check((await invoke(f,'confirmChoice',prepared.selectionToken)).ok,'native validated candidate can commit');
 check(f.confirms.length===1 && f.confirms[0].includes('protected recovery copy'),'confirmation discloses preservation');
 check(!(await invoke(f,'confirmChoice',prepared.selectionToken)).ok && f.calls.length===2,'duplicate token cannot commit twice');
 const cancelled=fixture({confirm:false});await cancelled.start();await invoke(cancelled,'prepareChoice','cloud','b'.repeat(64),'a'.repeat(64));
 check((await invoke(cancelled,'confirmChoice','prepared-token')).code==='RECOVERY_CANCELLED','cancellation explicit');check(cancelled.calls.length===1,'cancel cannot mutate');
 const stale=fixture({result:{ok:false,code:'RECOVERY_CHANGED',error:'raw secret'}});await stale.start();const failure=await invoke(stale,'prepareChoice','local','b'.repeat(64),'a'.repeat(64));check(!failure.ok && failure.error.includes('choose again') && !failure.error.includes('secret'),'stale preview safely requires review');
 const malformed=fixture();await malformed.start();malformed.setSnapshot({...malformed.getSnapshot(),expectedCloudDigest:'bad'});check(!JSON.parse(malformed.win.LittleLeafVault.recoverySnapshot()).available,'invalid digest suppresses choices');
 let finish;const waiting=fixture({wait:new Promise(resolve=>finish=resolve)});await waiting.start();const first=invoke(waiting,'prepareChoice','local','b'.repeat(64),'a'.repeat(64));await flush();
 check(JSON.parse(waiting.win.LittleLeafVault.recoverySnapshot()).busy,'pending prepare shown busy');await invoke(waiting,'prepareChoice','cloud','b'.repeat(64),'a'.repeat(64));waiting.win.LittleLeafVault.retry();check(waiting.calls.length===1,'busy prepare and reload guarded');finish();await first;
 const switched=fixture();await switched.start();await invoke(switched,'prepareChoice','cloud','b'.repeat(64),'a'.repeat(64));switched.auth.currentUser={uid:'other'};check(!(await invoke(switched,'confirmChoice','prepared-token')).ok && switched.confirms.length===0,'account change blocks confirmation');
 check((await invoke(f,'preserveRuntime','latest model',8,'profile')).durable,'runtime durable snapshot bridge');
 const noOwner=fixture();await noOwner.start();check(!(await invoke(noOwner,'forceTakeover')).ok && noOwner.confirms.length===0,'no server capability means no force control');
 const owner={serverOwnership:true,ownershipPaused:true,status:'other-device',canRequestTakeover:true,canForceTakeover:false};
 const handoff=fixture({owner});await handoff.start();check(JSON.parse(handoff.win.LittleLeafVault.recoverySnapshot()).ownershipPaused,'ownership pause reaches native');
 check((await invoke(handoff,'requestTakeover')).status==='waiting' && handoff.confirms.length===0,'normal handoff starts without force confirmation');
 check((await invoke(handoff,'finishTakeover')).payload==='server snapshot','acknowledged takeover returns validation payload without reload');
 owner.canForceTakeover=true;check((await invoke(handoff,'forceTakeover')).ok && handoff.confirms[0].includes('not confirmed its latest save'),'force warns about unconfirmed progress');
 const cancelledForce=fixture({owner,confirm:false});await cancelledForce.start();check((await invoke(cancelledForce,'forceTakeover')).code==='RECOVERY_CANCELLED' && cancelledForce.calls.length===0,'cancel force leaves ownership unchanged');
 const divergent=fixture({owner});divergent.client.finishTakeover=async()=>({ok:false,code:'REVISION_CONFLICT',error:'raw private detail'});await divergent.start();const conflict=await invoke(divergent,'finishTakeover');check(conflict.code==='REVISION_CONFLICT'&&conflict.error.includes('Choose which progress')&&!conflict.error.includes('Could not finish')&&!conflict.error.includes('private'),'expected reconnect conflict gives clear safe choice guidance');
 console.log(JSON.stringify({passed:true,checks,player_save_used:false,real_browser:false}));
})().catch(error=>{console.error(error);process.exitCode=1;});
