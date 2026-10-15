"use strict";
// Real adapter + atomic generated IDB fixture. No player profile or production network.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const {FixtureIDB}=require('../fixtures/save_log_idb_fixture');
const root={crypto:webcrypto,TextEncoder,TextDecoder,setTimeout,clearTimeout};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
const api=root.LittleLeafFirebase,codec=root.LittleLeafAuthorityCodec;
const modern=fs.readFileSync('tests/fixtures/unified_building_candidate.json','utf8'),legacy=fs.readFileSync('tests/fixtures/unified_building/public_closed.json','utf8');
const clone=structuredClone,fail=code=>Object.assign(Error(code),{code});let checks=0;
function check(value,message){assert(value,message);checks++;}
async function record(payload=modern,revision=7,profileId=webcrypto.randomUUID()){
 const r={format:2,profileId,revision,createdAt:1,updatedAt:2,payload,digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:1},previous:null,campaigns:{}};
 r.digest=await codec.hash(codec.fingerprint(r));return r;
}
const document=r=>({schema:1,profileId:r.profileId,revision:r.revision,digest:r.digest,record:JSON.stringify(r)});
async function fixture(){
 const idb=new FixtureIDB(),old=await api.openJournal(idb),active=await api.openJournal(idb,{cloudOnly:true});
 let identity='alice',reads=0,writes=0,readHook=null,owner=true;const cloud=new Map(),events=[];
 const journal={...active,async read(uid){events.push('journal');return active.read(uid);}};
 const ownership={assertActive(){if(!owner)throw fail('OWNERSHIP_LOST');return{writerId:'synthetic-owner',writerEpoch:7};},async renew(){},close(){}};
 const remote={async read(uid){reads++;events.push('cloud');if(readHook)await readHook();return clone(cloud.get(uid)??null);},async compareAndSet(uid,base,next,guard,verifyArchive){guard();if(verifyArchive)await verifyArchive();guard();if((cloud.get(uid)?.digest??null)!==base)throw fail('REVISION_CONFLICT');cloud.set(uid,clone(next));writes++;}};
 const make=(uid=identity)=>api.createClient({uid,cloudStartup:true,codec,remote,journal,ownership,currentUid:()=>identity,status(){}});
 const rows=()=>idb.databases.get('little-leaf.firebase-journal.v1').stores.get('accounts');
 return{idb,old,active,cloud,make,rows,events,reads:()=>reads,writes:()=>writes,setUid:x=>identity=x,setOwner:x=>owner=x,onRead:x=>readHook=x};
}
(async()=>{
 // The exact incident: unverified modern old journal and damaged old archives.
 for(const raw of [{pending:true,base:null,record:await record(),uploading:{record:await record()}},'unparseable old journal',false]){
  const h=await fixture(),r=await record();await h.old.replace('alice',null,raw);
  h.rows().set(JSON.stringify(['pre-grid-v1','alice']),'damaged original archive');h.rows().set(JSON.stringify(['recovery-v1','alice']),'damaged old recovery');
  const originals=clone([...h.rows()]);h.cloud.set('alice',document(r));const c=h.make(),boot=await c.boot();
  check(boot.ok&&boot.profileId===r.profileId&&boot.revision===r.revision,'valid cloud starts despite missing local preGrid');
  check(h.events.join(',')==='cloud,journal','server validates before local staging read');
  for(const [key,value]of originals)assert.deepEqual(h.rows().get(key),value);checks++;
  check(!c.recoverySnapshot().choicesAvailable,'Google startup offers no local/cloud choice');
  await c.sync();check(h.writes()===0,'old pending/uploading never uploads');
  assert.deepEqual((await h.active.read('alice')).preGrid,{format:'little-leaf.pre-grid-requirement.v1',archiveDigests:[]});checks++;c.close();
 }
 // Every boot ignores even the new namespace's unconfirmed pending branch.
 {
  const h=await fixture(),r=await record(),stale={pending:true,base:'0'.repeat(64),record:await record(modern,90),uploading:{record:await record(modern,89)}};
  await h.active.replace('alice',null,stale);h.cloud.set('alice',document(r));const c=h.make(),b=await c.boot();
  check(b.ok&&b.revision===r.revision&&b.profileId===r.profileId,'new cloud baseline wins over active stale pending');
  await c.sync();check(h.writes()===0,'no stale upload on subsequent boot');
  check((await h.active.read('alice')).uploading===undefined,'captured stale upload not carried into new session');
  const saved=await c.commit(modern,b.revision,b.profileId);check(saved.ok,'new write stages on validated cloud baseline');await c.sync();
  check(h.writes()===1&&h.cloud.get('alice').revision===r.revision+1,'only new revision reaches cloud CAS');
  check(await h.active.readPreGrid('alice')===null,'modern cloud origin never fabricates an original archive');c.close();
 }
 for(const mode of ['OFFLINE','NETWORK_TIMEOUT','CORRUPT_AUTHORITY']){
  const h=await fixture(),r=await record();await h.active.replace('alice',null,{pending:true,record:r});const before=h.idb.snapshot();
  if(mode==='CORRUPT_AUTHORITY')h.cloud.set('alice',{...document(r),digest:'f'.repeat(64)});else h.onRead(()=>{throw fail(mode);});
  const c=h.make(),b=await c.boot();check(!b.ok&&b.code===mode,'unavailable/corrupt cloud fails explicitly');
  check(h.idb.snapshot()===before,'cloud failure performs no journal adoption');check(!h.events.includes('journal'),'failed cloud never consults local fallback');
  check(h.writes()===0&&!c.recoverySnapshot().choicesAvailable,'failed read offers neither fresh state nor old choice');c.close();
 }
 {
  const h=await fixture();await h.old.replace('alice',null,{pending:true,record:await record()});const c=h.make(),b=await c.boot();
  check(b.ok&&b.source==='fresh'&&b.revision===0,'confirmed absent cloud is distinct from read failure');
  check(h.writes()===0,'fresh startup does not create server progress');check((await h.old.read('alice')).pending,'old local bytes remain untouched for absent cloud');c.close();
 }
 for(const change of ['account','owner']){
  const h=await fixture(),r=await record();h.cloud.set('alice',document(r));let release;h.onRead(()=>new Promise(resolve=>release=resolve));const c=h.make(),pending=c.boot();
  await new Promise(resolve=>setImmediate(resolve));if(change==='account')h.setUid('bob');else h.setOwner(false);release();const b=await pending;
  check(!b.ok&&b.code===(change==='account'?'NOT_READY':'OWNERSHIP_LOST'),'account/epoch change fences cloud adoption');check(!h.events.includes('journal')&&h.writes()===0,'late old account result cannot adopt/write');c.close();
 }
 // Actual cloud legacy -> modern migration retains exact original cloud provenance.
 {
  const h=await fixture(),r=await record(legacy);h.cloud.set('alice',document(r));h.rows().set(JSON.stringify(['pre-grid-v1','alice']),'untouched old archive');
  const c=h.make(),b=await c.boot();check((await c.commit(modern,b.revision,b.profileId)).ok,'real cloud migration stages normally');
  const archives=await codec.verifyPreGridArchives(await h.active.readPreGrid('alice'));
  check(archives.length===1&&archives[0].digest===r.digest,'migration protects the real loaded cloud record');
  check(h.rows().get(JSON.stringify(['pre-grid-v1','alice']))==='untouched old archive','migration does not mutate old archive namespace');await c.sync();check(h.writes()===1,'migration upload retains archive checks');c.close();
 }
 {
  const h=await fixture(),a=await record(),b=await record();h.cloud.set('alice',document(a));h.cloud.set('bob',document(b));const ca=h.make(),ba=await ca.boot();h.setUid('bob');const cb=h.make(),bb=await cb.boot();
  check(bb.profileId===b.profileId&&ba.profileId===a.profileId,'each account loads its own cloud identity');
  check((await ca.commit(modern,ba.revision,ba.profileId)).code==='NOT_READY','old account cannot write after switch');
  check((await h.active.read('alice')).record.profileId===a.profileId&&(await h.active.read('bob')).record.profileId===b.profileId,'active staging is UID-scoped');ca.close();cb.close();
 }
 console.log(JSON.stringify({passed:true,checks,synthetic_only:true,real_indexeddb:false,real_firebase:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
