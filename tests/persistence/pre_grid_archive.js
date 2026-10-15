'use strict';
// Pure generated-fixture contracts. No user profile, real SDK or cloud writes.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const source=fs.readFileSync('platform/web/little_leaf_vault.js','utf8'),adapter=fs.readFileSync('platform/web/little_leaf_crazygames.js','utf8');
const old=fs.readFileSync('tests/fixtures/unified_building/public_closed.json','utf8');
const legacy=' \n'+JSON.stringify({...JSON.parse(old),synthetic_note:'白色 tiles café'},null,2)+'\n\t';
const modern=fs.readFileSync('tests/fixtures/unified_building_candidate.json','utf8');
const c=vm.createContext({crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout});vm.runInContext(source,c);const codec=c.LittleLeafAuthorityCodec;
let checks=0;const ok=(v,m)=>{assert(v,m);checks++;},clone=x=>JSON.parse(JSON.stringify(x));
async function record(payload=legacy,revision=7,id=webcrypto.randomUUID()){
 const r={format:2,profileId:id,revision,createdAt:1,updatedAt:2,payload:revision?payload:null,digest:null,origin:revision?{source:'fresh',legacyDigest:null,importedAt:1}:null,previous:null,campaigns:{}};
 if(revision)r.digest=await codec.hash(codec.fingerprint(r));return r;
}
function archiveStore(){const state={text:null,writes:0,reads:0,mode:'',closed:false};return {state,guard(){if(state.closed)throw Error('scope changed');},async read(){state.reads++;if(state.mode==='bad-readback'&&state.reads===2)return 'wrong';return state.text;},async install(before,text){assert.equal(state.text,before);if(state.mode==='throw')throw Error('quota');if(state.mode!=='discard'){state.text=text;state.writes++;}if(state.mode==='close')state.closed=true;}};}
const KEY='little-leaf.cg.profile.v1',PREFS='little-leaf.cg.preferences.v1',ARCHIVE=KEY+'.pre-grid.v1';
async function cg(){
 const r=await record(),map=new Map([[KEY,JSON.stringify(r)]]),state={mode:'',archiveReads:0,writes:[],scope:'same',hook:null};
 const sdk={environment:'local',init:async()=>{},user:{isUserAccountAvailable:true,getUser:async()=>({__dangerousUserId:state.scope,username:'synthetic'}),addAuthListener(fn){state.auth=fn;}},game:{settings:{},loadingStart(){},gameplayStop(){}},data:{getItem(key){assert([KEY,PREFS,ARCHIVE].includes(key));if(key===ARCHIVE){state.archiveReads++;if(state.hook)state.hook(state.archiveReads);if(state.mode==='bad-readback'&&state.archiveReads===3)return 'wrong';}return map.get(key)??null;},setItem(key,text){state.writes.push(key);if(key===ARCHIVE){if(state.mode==='throw')throw Error('quota');if(state.mode==='discard')return;if(state.mode==='scope')state.scope='changed';}map.set(key,text);}}};
 const context=vm.createContext({CrazyGames:{SDK:sdk},crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout,location:{reload(){}}});
 for(const key of ['indexedDB','localStorage','sessionStorage'])Object.defineProperty(context,key,{get(){throw Error('Forbidden fallback');}});
 vm.runInContext(source,context);vm.runInContext(adapter,context);const client=context.__littleLeafVault;const b=await client.boot();ok(b.ok,'CG fixture boots old authority');
 return {r,map,state,client,context,save:()=>client.commit(modern,r.revision,r.profileId)};
}
(async()=>{
 const r=await record();let store=archiveStore();let proof=await codec.ensurePreGridArchive(store,r,modern,store.guard);
 let list=JSON.parse(proof.text);ok(list[0].payload===legacy,'original whitespace/Unicode payload bytes retained');ok(list[0].profileId===r.profileId&&list[0].revision===7&&list[0].digest===r.digest,'original identity retained');ok(list[0].recordText===JSON.stringify(r),'complete source envelope retained');ok(list[0].payloadDigest===await codec.hash(legacy),'exact payload SHA256');ok(store.state.reads===2,'independent read after archive installation');
 const text=proof.text;proof=await codec.ensurePreGridArchive(store,r,modern,store.guard);ok(proof.text===text&&JSON.parse(text).length===1,'same source is idempotent');
 const next=await record(modern,8,r.profileId);ok(await codec.ensurePreGridArchive(store,next,modern,store.guard)===null&&store.state.text===text,'later grid save never overwrites original');
 ok(await codec.ensurePreGridArchive(store,await record(null,0),modern,store.guard)===null,'fresh profile needs no invented backup');
 for(const mode of ['throw','discard','bad-readback','close']){store=archiveStore();store.state.mode=mode;await assert.rejects(()=>codec.ensurePreGridArchive(store,r,modern,store.guard));checks++;}
 store=archiveStore();store.state.text='bad';await assert.rejects(()=>codec.ensurePreGridArchive(store,r,modern,store.guard));ok(store.state.text==='bad'&&!store.state.writes,'corrupt archive never overwritten');
 const v13=JSON.parse(legacy);v13.version=13;delete v13.layout_motion_format;const v13text=' \n'+JSON.stringify(v13)+'\t';store=archiveStore();const empty=await record(null,0);
 proof=await codec.ensurePreGridArchive(store,empty,modern,store.guard,{payload:v13text,digest:await codec.hash(v13text)});list=JSON.parse(proof.text);ok(list[0].payload===v13text&&list[0].revision===0&&list[0].legacyDigest===await codec.hash(v13text),'legacy-v13 bytes bound to existing revision-zero profile');
 const bad=JSON.parse(modern);delete bad.building_format;await assert.rejects(()=>codec.ensurePreGridArchive(store,r,JSON.stringify(bad),store.guard));checks++;
 store=archiveStore();for(let i=0;i<8;i++)await codec.ensurePreGridArchive(store,await record(),modern,store.guard);const full=store.state.text;await assert.rejects(async()=>codec.ensurePreGridArchive(store,await record(),modern,store.guard));ok(store.state.text===full&&JSON.parse(full).length===8,'bounded archive full never evicts originals');
 let h=await cg();const result=await h.save();ok(result.ok&&result.platformAccepted&&result.durable===false&&result.cloudConfirmed===false,'CG migration reports only SDK acceptance');ok(h.state.writes.join('|')===ARCHIVE+'|'+KEY,'CG archive written before active');const original=h.map.get(ARCHIVE);ok(JSON.parse(original)[0].payload===legacy,'CG keeps exact old bytes');ok((await h.client.commit(modern,8,h.r.profileId)).ok&&h.map.get(ARCHIVE)===original,'CG ordinary save retains first archive');
 for(const mode of ['throw','discard','bad-readback','scope']){h=await cg();h.state.mode=mode;const before=h.map.get(KEY);ok(!(await h.save()).ok,'CG refuses '+mode);ok(h.map.get(KEY)===before&&!h.state.writes.includes(KEY),'CG '+mode+' cannot publish active');}
 h=await cg();h.map.set(ARCHIVE,'bad');const before=h.map.get(KEY);ok(!(await h.save()).ok&&h.map.get(KEY)===before&&h.map.get(ARCHIVE)==='bad','CG preserves corrupt archive and active');
 h=await cg();h.state.hook=n=>{if(n===3)h.map.set(KEY,'newer authority');};ok(!(await h.save()).ok&&h.map.get(KEY)==='newer authority','CG final cache CAS rejects race after archive readback');
 h=await cg();h.map.set(PREFS,JSON.stringify({format:1,text:'x'.repeat(65000)}));
 const large=JSON.stringify({...JSON.parse(modern),syntheticPadding:'x'.repeat(930000)});const protectedActive=h.map.get(KEY);const over=await h.client.commit(large,h.r.revision,h.r.profileId);ok(over.code==='PLATFORM_DATA_LIMIT'&&h.map.get(KEY)===protectedActive,'CG capacity includes archive and active UTF-8 bytes');
 // Exercise the production journal's archive and final CAS transactions with
 // the established atomic IDB fixture. Browser atomicity is a separate suite.
 const {FixtureIDB}=require('../fixtures/save_log_idb_fixture');
 const idb=new FixtureIDB(),context=vm.createContext({crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout});
 vm.runInContext(source,context);vm.runInContext(fs.readFileSync('platform/web/little_leaf_firebase.js','utf8'),context);
 const api=context.LittleLeafFirebase,journal=await api.openJournal(idb),firebaseCodec=context.LittleLeafAuthorityCodec;
 for(const mode of ['success','throw','discard','bad-readback','race','archive-race','account','paused']){
  const uid='synthetic-'+webcrypto.randomUUID(),r=await record(),initial={base:r.digest,pending:false,record:r};await journal.replace(uid,null,initial);
  let identity=uid,paused=false,uploads=0;const ownership={assertActive(){if(paused)throw Object.assign(Error('paused'),{code:'OWNERSHIP_LOST'});return{};},async renew(){},close(){}};
  const client=api.createClient({uid,codec:firebaseCodec,journal,currentUid:()=>identity,status(){},ownership:mode==='paused'?ownership:null,remote:{async read(){return{schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)};},async compareAndSet(){uploads++;throw Error('Unexpected cloud write');}}});
  const b=await client.boot();ok(b.ok,'Firebase fixture boots '+mode);const before=clone(await journal.read(uid)),newer={...before,pending:true,record:await record(legacy,8,r.profileId)};
  const read=journal.readPreGrid,install=journal.archivePreGrid;let reads=0;
  journal.readPreGrid=async id=>{const text=await read(id);if(id===uid&&++reads===2){if(mode==='bad-readback')return'bad';if(mode==='race')await journal.replace(uid,before,newer);if(mode==='archive-race'){const rows=idb.databases.get('little-leaf.firebase-journal.v1').stores.get('accounts');rows.set(JSON.stringify(['pre-grid-v1',uid]),'racing archive');}if(mode==='account')identity='other';}return text;};
  journal.archivePreGrid=async(id,...args)=>{if(id===uid&&mode==='throw')throw Error('quota');if(id===uid&&mode==='discard')return;return install(id,...args);};
  let result;try{if(mode==='paused'){paused=true;result=await client.preserveRuntime(modern,b.revision,b.profileId);}else result=await client.commit(modern,b.revision,b.profileId);}finally{journal.readPreGrid=read;journal.archivePreGrid=install;}
  const after=clone(await journal.read(uid));ok(!uploads,'Firebase '+mode+' has zero cloud writes');
  if(mode==='success'||mode==='paused'){ok(result.ok&&result.durable,'Firebase '+mode+' preserves locally');const saved=await read(uid),list=JSON.parse(saved);ok(list[0].payload===legacy&&list[0].digest===r.digest,'Firebase '+mode+' exact archive');ok(after.pending&&after.base===r.digest&&after.record.payload===modern,'Firebase '+mode+' only stages after archive');if(mode==='success')ok((await client.commit(modern,8,r.profileId)).ok&&await read(uid)===saved,'Firebase subsequent save preserves original');}
  else{ok(!result.ok,'Firebase refuses '+mode);ok(JSON.stringify(after)===JSON.stringify(mode==='race'?newer:before),'Firebase '+mode+' preserves authoritative journal');}
  client.close();
 }
 console.log(JSON.stringify({passed:true,checks,synthetic_only:true,real_browser:false,real_sdk:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
