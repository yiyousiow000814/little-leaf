'use strict';
// Generated identities and in-memory server/storage only; no Auth, browser or saves.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto};root.globalThis=root;
vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase_session.js','utf8'),root);
const api=root.LittleLeafFirebaseSession;
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function storage(initial=[]){const values=new Map(initial);return {values,getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v)};}
function locks(){const active=new Set();return {active,async request(key,options,callback){
  assert.equal(options.ifAvailable,true);assert.equal(options.mode,'exclusive');
  if(active.has(key))return callback(null);active.add(key);
  try{return await callback({name:key});}finally{active.delete(key);}
}};}
(async()=>{
  let time=100000,server=null;
  const saved=Object.freeze({digest:'a'.repeat(64),revision:3,writerId:'previous-writer',writerEpoch:1});
  const saveBefore=JSON.stringify(saved);
  const remote={async change(transition,guard){guard();server=transition(server,saved,()=>time);guard();return server;},async read(){return server;},watch(){return()=>{};}};
  const lockManager=locks(),tab=storage();let uid='synthetic-account';
  async function boot(store,type,fresh=false){
    const runtime=await api.acquireRuntime({uid,storage:store,locks:lockManager,navigationType:type,fresh});
    const session=api.createSession({remote,uid,currentUid:()=>uid,sessionId:runtime.sessionId,assertRuntime:()=>runtime.assertHeld(),now:()=>time});
    await session.start();return {runtime,session,close(){session.close();runtime.close();}};
  }
  const abandoned=await boot(storage(),'navigate');abandoned.close();await flush();
  const current=await boot(tab,'navigate');assert.equal(current.session.snapshot().status,'other-device');
  await current.session.requestTakeover();time+=10001;await current.session.takeOver(true);
  assert.equal(current.session.snapshot().status,'active');const owner=server.owner,epoch=server.epoch;
  // An overlapping same-tab reload or copied receipt cannot become a second writer.
  await assert.rejects(boot(tab,'reload'),{code:'SAVE_BUSY'});
  const copied=storage([...tab.values]);await assert.rejects(boot(copied,'reload'),{code:'SAVE_BUSY'});
  current.close();await flush();
  const refreshed=await boot(tab,'reload');assert.equal(refreshed.session.snapshot().status,'active');
  assert.equal(server.owner,owner);assert.equal(server.epoch,epoch);
  assert.equal(refreshed.session.fence.writerId,owner);
  // A newly navigated tab always discards a copied receipt.
  const other=await boot(copied,'navigate');assert.notEqual(other.runtime.sessionId,owner);
  assert.equal(other.session.snapshot().status,'other-device');other.close();
  // Closing fences callbacks immediately, before asynchronous lock release.
  refreshed.runtime.close();assert.throws(()=>refreshed.session.assertActive(),{code:'NOT_READY'});
  await assert.rejects(refreshed.session.renew(),{code:'NOT_READY'});refreshed.close();await flush();
  // Existing update continuation needs a fresh requester, never self-handoff.
  const update=await boot(tab,'reload',true);assert.notEqual(update.runtime.sessionId,owner);
  assert.equal(update.session.snapshot().status,'other-device');update.close();await flush();
  uid='synthetic-different-account';const account=await boot(tab,'reload');assert.notEqual(account.runtime.sessionId,owner);account.close();await flush();
  // A released/crashed runtime can resume its tab, but never a competing server fence.
  uid='synthetic-account';const crash=await boot(tab,'navigate');time+=60001;
  await crash.session.start();assert.equal(crash.session.snapshot().status,'active');
  const crashOwner=server.owner;crash.runtime.close();await flush();
  const recovered=await boot(tab,'reload');assert.equal(recovered.session.snapshot().status,'active');
  assert.equal(server.owner,crashOwner);recovered.close();await flush();
  server={...server,owner:webcrypto.randomUUID(),epoch:server.epoch+1};
  const displaced=await boot(tab,'reload');assert.equal(displaced.session.snapshot().status,'other-device');
  assert.throws(()=>displaced.session.assertActive(),{code:'OWNERSHIP_LOST'});displaced.close();await flush();
  const rejected={request(){return Promise.reject(Error('lock unavailable'));}};
  await assert.rejects(api.acquireRuntime({uid,storage:tab,locks:rejected,navigationType:'reload'}),/lock unavailable/);
  // No lock API: preserve fresh-ID behavior rather than trust a stored receipt.
  const unsupported=await api.acquireRuntime({uid:'synthetic-account',storage:copied,navigationType:'reload'});
  assert.notEqual(unsupported.sessionId,owner);unsupported.close();
  const unavailable={getItem(){throw Error('storage unavailable');},setItem(){throw Error('storage unavailable');}};
  const isolated=await api.acquireRuntime({uid,storage:unavailable,locks:lockManager,navigationType:'reload'});isolated.assertHeld();isolated.close();await flush();
  assert.equal(lockManager.active.size,0);assert.equal(JSON.stringify(saved),saveBefore);
  console.log('Firebase ordinary refresh: takeover then refresh active; overlapping/copy/new-tab/account/closed/update/unsupported paths remain fenced; no save writes');
})().catch(error=>{console.error(error);process.exitCode=1;});
