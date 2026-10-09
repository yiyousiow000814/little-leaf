'use strict';
// Pure synthetic contract tests, not Firebase/iOS device verification.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto,TextEncoder,setTimeout,clearTimeout};root.globalThis=root;
vm.runInNewContext(fs.readFileSync('web/little_leaf_vault.js','utf8'),root);
vm.runInNewContext(fs.readFileSync('web/little_leaf_firebase.js','utf8'),root);
const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8'),clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
const fail=code=>Object.assign(Error(code),{code});
function harness(){
  let uid='alice',offline=false,time=1000,writes=0;const cloud=new Map(),local=new Map();
  const remote={async read(id){if(offline)throw fail('OFFLINE');return clone(cloud.get(id));},async compareAndSet(id,base,next,guard){guard();if(offline)throw fail('OFFLINE');let old=cloud.get(id);if(old?.digest===next.digest)return;if((old?.digest||null)!==base)throw fail('REVISION_CONFLICT');cloud.set(id,clone(next));writes++;}};
  const journal={async read(id){return clone(local.get(id));},async replace(id,old,next){assert.equal(JSON.stringify(clone(local.get(id))),JSON.stringify(old),'atomic journal CAS');local.set(id,clone(next));}};
  function client(id=uid){const states=[];let c=root.LittleLeafFirebase.createClient({uid:id,codec:root.LittleLeafAuthorityCodec,remote,journal,currentUid:()=>uid,status:s=>states.push(s),now:()=>time});c.states=states;return c;}
  return {client,cloud,local,setUid:x=>uid=x,setOffline:x=>offline=x,tick:()=>time+=30001,writes:()=>writes};
}
async function save(c,p=payload){let b=JSON.parse(c.bootJson);return c.commit(p,b.revision,b.profileId);}
(async()=>{
  let h=harness(),c=h.client();assert.equal((await c.commit(payload,0,'x')).code,'NOT_READY');
  c=h.client();let b=await c.boot();assert.equal(b.source,'fresh');assert.equal(h.writes(),0,'boot never creates cloud doc');
  let r=await save(c);assert.equal(r.durable,true);assert.equal(r.cloudConfirmed,false);assert(c.states.includes('pending'));await c.sync();assert.equal(h.writes(),1);assert.equal(c.states.at(-1),'saved');
  let reload=h.client();assert.equal((await reload.boot()).payload,payload,'cloud reload');
  h.setOffline(true);assert.equal((await save(reload)).ok,true);await reload.sync();assert.equal(reload.states.at(-1),'offline');assert.equal(h.cloud.get('alice').revision,1);
  let off=h.client();assert.equal((await off.boot()).revision,2,'offline same UID resumes journal');h.setUid('bob');let bob=h.client();assert.equal((await bob.boot()).ok,false,'other UID cannot borrow offline profile');assert.equal(h.local.has('bob'),false);
  h.setUid('alice');h.setOffline(false);let online=h.client();assert.equal((await online.boot()).revision,2);assert.equal(h.cloud.get('alice').revision,2);assert.equal(online.states.at(-1),'saved');
  assert.equal((await online.commit(payload,1,b.profileId)).code,'REVISION_CONFLICT','stale local revision');
  h=harness();c=h.client();b=await c.boot();await save(c);await c.sync();const oldJournal=clone(h.local.get('alice'));h.setOffline(true);let stale=h.client();await stale.boot();await save(stale);const pending=clone(h.local.get('alice'));h.setOffline(false);h.local.set('alice',oldJournal);let other=h.client();await other.boot();let changed=JSON.stringify({...JSON.parse(payload),coins:987});await save(other,changed);await other.sync();h.local.set('alice',pending);let conflict=h.client();assert.equal((await conflict.boot()).code,'REVISION_CONFLICT');assert.deepEqual(h.local.get('alice'),pending,'conflict preserves pending');assert.equal(JSON.parse(h.cloud.get('alice').record).payload,changed,'conflict preserves remote');
  h=harness();c=h.client();b=await c.boot();h.setUid('bob');assert.equal((await save(c)).code,'NOT_READY');assert.equal(h.local.get('alice').record.revision,0,'auth changed before write');
  assert.throws(()=>root.LittleLeafFirebase.capacity({text:'界'.repeat(300001)}),/limit/,'UTF-8 not UTF-16 size');
  h=harness();c=h.client();await c.boot();await save(c);await c.sync();let fresh=h.client();await fresh.boot();await save(fresh);await fresh.sync();let next=await fresh.commit(payload,2,JSON.parse(fresh.bootJson).profileId);assert(next.ok);await fresh.sync();assert.equal(h.writes(),2,'rate limited');h.tick();await fresh.sync();assert.equal(h.writes(),3);
  h=harness();c=h.client();await c.boot();await save(c);await c.sync();h.cloud.delete('alice');assert.equal((await h.client().boot()).code,'CORRUPT_AUTHORITY','missing remote is not new-player evidence');
  console.log('Firebase synthetic adapter: all contract assertions passed (no real Firebase or device)');
})().catch(e=>{console.error(e);process.exit(1);});
