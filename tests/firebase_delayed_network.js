'use strict';
// Synthetic delayed-server/ack tests. No real account or production writes.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto,TextEncoder};root.globalThis=root;
for(const name of ['little_leaf_vault','little_leaf_firebase'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const changed=JSON.stringify({...JSON.parse(payload),coins:345});
const clone=x=>x==null?null:JSON.parse(JSON.stringify(x));
const fail=code=>Object.assign(Error(code),{code});
const tick=()=>new Promise(r=>setImmediate(r));
function harness(){
  let uid='alice',time=0,mode='',calls=0;const local=new Map(),cloud=new Map(),requests=[];
  const journal={read:async id=>clone(local.get(id)),replace:async(id,old,next)=>{if(JSON.stringify(old)!==JSON.stringify(clone(local.get(id))))throw fail('REVISION_CONFLICT');local.set(id,clone(next));}};
  const remote={read:async id=>clone(cloud.get(id)),compareAndSet:async(id,base,next,guard)=>{
    calls++;guard();if(mode==='before')await new Promise(r=>requests.push(r));guard();
    const old=cloud.get(id);if(old?.digest!==next.digest){if((old?.digest||null)!==base)throw fail('REVISION_CONFLICT');cloud.set(id,clone(next));}
    // Models server commit followed by a lost/delayed response to this browser.
    if(mode==='after')await new Promise(r=>requests.push(r));
  }};
  const make=(deviceLabel='Unknown device')=>{const states=[],c=root.LittleLeafFirebase.createClient({deviceLabel,uid,currentUid:()=>uid,codec:root.LittleLeafAuthorityCodec,journal,remote,now:()=>time,status:s=>states.push(s)});c.states=states;return c;};
  return {make,local,cloud,requests,setMode:x=>mode=x,setUid:x=>uid=x,tick:()=>time+=30001,calls:()=>calls};
}
async function waiting(h){for(let i=0;i<100&&!h.requests.length;i++)await tick();assert(h.requests.length,'network request started');}
(async()=>{
  // New edits and hide-save can become locally durable during a long upload.
  let h=harness(),c=h.make(),b=await c.boot();await c.commit(payload,0,b.profileId);h.setMode('before');let sync=c.sync();await waiting(h);
  const newer=await c.commit(changed,1,b.profileId);assert(newer.ok);assert.equal(h.local.get('alice').record.payload,changed);assert.equal(h.local.get('alice').record.revision,2);
  h.requests.shift()();await sync;assert.equal(h.cloud.get('alice').revision,1);assert.equal(h.local.get('alice').record.revision,2);assert.equal(h.local.get('alice').pending,true);assert.equal(c.states.at(-1),'pending');
  h.setMode('');h.tick();await c.sync();assert.equal(h.cloud.get('alice').revision,2);assert.equal(h.local.get('alice').pending,false);
  // Close after durable hide-save but before server acknowledgment. Reload must
  // recognize our uploaded ancestor rather than erase data or false-conflict.
  h=harness();c=h.make();b=await c.boot();await c.commit(payload,0,b.profileId);h.setMode('after');sync=c.sync();await waiting(h);
  assert((await c.commit(changed,1,b.profileId)).ok);c.close();h.requests.shift()();await sync;
  assert.equal(h.local.get('alice').record.payload,changed);assert.equal(h.local.get('alice').pending,true);assert.equal(h.cloud.get('alice').revision,1);
  h.setMode('');let reopened=h.make(),loaded=await reopened.boot();assert(loaded.ok);assert.equal(loaded.payload,changed);assert.equal(h.cloud.get('alice').revision,2);
  // Boot replay lasts >30 seconds. Interval/online triggers may not duplicate it.
  h=harness();c=h.make();b=await c.boot();await c.commit(payload,0,b.profileId);c.close();h.setMode('before');reopened=h.make();const boot=reopened.boot();await waiting(h);h.tick();await reopened.sync();await reopened.sync();assert.equal(h.requests.length,1);assert.equal(h.calls(),1);h.requests.shift()();loaded=await boot;assert(loaded.ok);assert(!reopened.states.includes('conflict'));assert((await reopened.commit(changed,1,b.profileId)).ok);
  // Account switches during an in-flight acknowledgment never alter the new UID.
  h=harness();c=h.make();b=await c.boot();await c.commit(payload,0,b.profileId);h.setMode('after');sync=c.sync();await waiting(h);assert((await c.commit(changed,1,b.profileId)).ok);h.setUid('bob');h.requests.shift()();await sync;
  assert.equal(h.local.has('bob'),false);assert.equal(h.cloud.has('bob'),false);assert.equal((await c.commit(payload,2,b.profileId)).code,'NOT_READY');assert.equal(h.local.get('alice').record.payload,changed);
  h.setUid('alice');h.setMode('');assert.equal((await h.make().boot()).payload,changed);
  // A genuinely different remote revision must still block old pending edits.
  h=harness();c=h.make();b=await c.boot();await c.commit(payload,0,b.profileId);h.setMode('after');sync=c.sync();await waiting(h);await c.commit(changed,1,b.profileId);const savedLocal=clone(h.local.get('alice'));const server=clone(h.cloud.get('alice')),serverRecord=JSON.parse(server.record);serverRecord.revision=3;serverRecord.payload=JSON.stringify({...JSON.parse(payload),coins:999});serverRecord.digest=await root.LittleLeafAuthorityCodec.hash(root.LittleLeafAuthorityCodec.fingerprint(serverRecord));h.cloud.set('alice',{...server,revision:3,digest:serverRecord.digest,record:JSON.stringify(serverRecord)});c.close();h.requests.shift()();await sync;h.setMode('');assert.equal((await h.make().boot()).code,'REVISION_CONFLICT');assert.deepEqual(h.local.get('alice'),savedLocal);
  // Replaying another device's durable snapshot does not relabel its origin.
  h=harness();c=h.make('iPhone');b=await c.boot();await c.commit(payload,0,b.profileId);h.setMode('after');sync=c.sync();await waiting(h);
  assert.equal(h.cloud.get('alice').device,'iPhone');await c.commit(changed,1,b.profileId);c.close();h.requests.shift()();await sync;h.setMode('');reopened=h.make('Mac');loaded=await reopened.boot();assert(loaded.ok);assert.equal(h.cloud.get('alice').device,'iPhone','replay retains the original device label');assert(!Object.hasOwn(JSON.parse(h.cloud.get('alice').record),'saveDevice'),'legacy record fingerprint is untouched');
  await reopened.commit(payload,loaded.revision,loaded.profileId);h.tick();await reopened.sync();assert.equal(h.cloud.get('alice').device,'Mac','new commit uses current actual generic platform');
  console.log('Delayed upload/hide-save, lost acknowledgment reload, slow boot, account switch and foreign-cloud conflict regressions passed.');
})().catch(e=>{console.error(e);process.exit(1);});
