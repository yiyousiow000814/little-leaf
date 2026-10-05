'use strict';
// Disposable deterministic IDB tests. Real-browser forced-close coverage is separate.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const {webcrypto} = require('node:crypto');
const {FixtureIDB} = require('./fixtures/save_log_idb_fixture');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/little_leaf_vault.js'), 'utf8');
const oldSource = execFileSync('git', ['show', '9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc:web/little_leaf_vault.js'], {cwd:root, encoding:'utf8'});
const logSource = fs.readFileSync(path.join(root, 'web/little_leaf_save_log.js'), 'utf8');
const payload = fs.readFileSync(path.join(__dirname, 'fixtures/startup-retry-v15.json'), 'utf8');
const report = {synthetic_only:true, real_browser:false, checks:[], cases:[]};
function check(ok, label) {assert(ok,label);report.checks.push(label);}
async function harness(code = source, legacy = false) {
  const factory = new FixtureIDB(), connections=[];
  const control = {onConnection:null};
  if(legacy) {
    const old=JSON.parse(payload);old.version=13;delete old.layout_motion_format;
    factory.databases.set('/userfs',{version:1,queue:[],stores:new Map([['FILE_DATA',new Map([['/userfs/synthetic/little_leaf_cafe_v13.json',{contents:new Int8Array(new TextEncoder().encode(JSON.stringify(old)).buffer)}]])]])});
  }
  const open=factory.open.bind(factory);
  factory.open=(...args)=>{
    const q=open(...args);let handler;
    Object.defineProperty(q,'onsuccess',{set(value){handler=value;},get(){return event=>{
      if(q.result.name==='little-leaf.authoritative.v1'){connections.push(q.result);control.onConnection?.(q.result,connections.length);}
      handler?.(event);
    };}});return q;
  };
  const context=vm.createContext({indexedDB:factory,crypto:webcrypto,TextEncoder,TextDecoder,Uint8Array,Int8Array,TypeError,DOMException,URL,setTimeout,clearTimeout});
  vm.runInContext(logSource,context);vm.runInContext(code,context);
  const api=context.LittleLeafVault,client=context.__littleLeafVault,boot=await client.boot();
  assert(boot.ok);
  return {factory,connections,control,context,api,client,boot,events:()=>context.LittleLeafSaveLog.snapshot(),active:()=>factory.databases.get(api.DB_NAME)?.stores.get('profiles')?.get('active'),close:()=>connections.at(-1).close(),save:(text=payload)=>{const current=JSON.parse(client.bootJson);return client.commit(text,current.revision,current.profileId);}};
}
(async()=>{
  let h=await harness(oldSource);h.close();const before=h.factory.snapshot();
  for(let i=0;i<3;i++) {const result=await h.save();check(!result.ok&&result.code==='InvalidStateError','baseline closed handle repeatedly fails before write');}
  check(h.connections.length===1&&h.factory.snapshot()===before,'baseline neither reopens nor changes revision-zero authority');h.client.close();
  h=await harness();h.close();const saved=await h.save();
  check(saved.ok&&saved.durable&&saved.revision===1,'closed handle reopens and completes one durable save');
  check(h.connections.length===2&&h.events().filter(e=>e.event==='connection_reopen_requested').length===1,'one commit performs exactly one reconnect');
  check(h.active().profileId===h.boot.profileId&&h.active().payload===payload,'reconnect preserves original identity and exact pending payload');
  const writes=h.factory.trace.filter(row=>row[0]==='transaction'&&row[1]===h.api.DB_NAME&&row[3]==='readwrite');
  check(writes.length===2&&writes.every(row=>row[4]?.durability==='strict'),'failed and retried write attempts retain strict durability');
  check(h.factory.commits===1&&h.events().filter(e=>e.event==='save_confirmed').length===1,'only one real transaction completion confirms saving');
  check(h.events().some(e=>e.event==='connection_opened'&&e.connectionGeneration===2&&e.stage==='reopen_existing'),'successful reconnect has a new sanitized connection generation');
  const reopened=h.api.createClient(), restored=await reopened.boot();
  check(restored.source==='authority'&&restored.profileId===h.boot.profileId&&restored.payload===payload,'independent reopen reads exact committed identity and payload');reopened.close();h.client.close();
  report.cases.push('baseline red; closed-connection recovery green');
  for(const mutation of ['missing_database','missing_store','missing_identity','missing_active','changed_identity','changed_fingerprint','unsupported_version','corrupt_payload']) {
    h=await harness();
    if(mutation==='corrupt_payload') check((await h.save()).ok,'damage fixture starts with a committed authority');
    h.close();
    const state=h.factory.databases.get(h.api.DB_NAME),rows=state.stores.get('profiles');
    if(mutation==='missing_database')h.factory.databases.delete(h.api.DB_NAME);
    if(mutation==='missing_store')state.stores.delete('profiles');
    if(mutation==='missing_identity')rows.delete('identity');
    if(mutation==='missing_active')rows.delete('active');
    if(mutation==='changed_identity')for(const value of rows.values())value.profileId='22222222-2222-4222-8222-222222222222';
    if(mutation==='changed_fingerprint')for(const value of rows.values())value.createdAt+=1;
    if(mutation==='unsupported_version')state.version=2;
    if(mutation==='corrupt_payload')rows.get('active').payload=rows.get('active').payload.replace('42000','42001');
    const baseline=h.factory.snapshot(),puts=h.factory.trace.filter(row=>row[0]==='put').length;
    const result=await h.save();
    check(!result.ok&&['CORRUPT_AUTHORITY','REVISION_CONFLICT'].includes(result.code),mutation+': reopen refuses a different or unusable authority');
    check(h.factory.snapshot()===baseline&&h.factory.trace.filter(row=>row[0]==='put').length===puts,mutation+': no repair/reset/write changes existing evidence');
    check(h.events().filter(e=>e.event==='connection_reopen_requested').length===1,mutation+': only one reopen attempt');
    const opens=h.factory.trace.filter(row=>row[0]==='open'&&row[1]===h.api.DB_NAME);
    check(opens.at(-1)[2]===undefined,mutation+': reopen never specifies a create/upgrade version');
    h.client.close();
  }
  report.cases.push('missing/changed/corrupt/unsupported authority never replaced');
  h=await harness();
  const newer=h.api.createClient(),newerBoot=await newer.boot();
  const newerPayload=JSON.stringify({...JSON.parse(payload),coins:42111});
  check((await newer.commit(newerPayload,newerBoot.revision,newerBoot.profileId)).ok,'concurrent fixture saves a newer head');
  h.connections[0].close();let preserved=h.factory.snapshot();
  let result=await h.save();
  check(!result.ok&&result.code==='REVISION_CONFLICT'&&h.factory.snapshot()===preserved,'newer revision already present at reopen cannot be overwritten');
  newer.close();h.client.close();
  h=await harness();const racing=h.api.createClient(),racingBoot=await racing.boot();let raceResult;
  h.connections[0].close();
  h.control.onConnection=(db,count)=>{
    if(count!==3)return;const transaction=db.transaction.bind(db);
    db.transaction=(...args)=>{
      const tx=transaction(...args);
      if(args[1]==='readonly') {
        let complete;
        Object.defineProperty(tx,'oncomplete',{set(fn){complete=fn;},get(){return event=>{
          racing.commit(newerPayload,racingBoot.revision,racingBoot.profileId).then(value=>{raceResult=value;complete(event);});
        };}});
      }return tx;
    };
  };
  result=await h.save();
  check(raceResult?.ok&&!result.ok&&result.code==='REVISION_CONFLICT','newer head between reopen-read and final write is caught by the repeated atomic CAS');
  check(h.active().payload===newerPayload&&h.factory.commits===1,'only the concurrent winner commits; reconnect never rebases the pending payload');
  racing.close();h.client.close();report.cases.push('concurrent CAS before and after reopen verification');
  for(const stage of ['object_store','get_identity','get_active','async_identity_get','async_active_get','active_result','identity_result','put','put_enqueued_throw','put_enqueued_abort']) {
    h=await harness();const db=h.connections[0],transaction=db.transaction.bind(db);
    const invalid=()=>new DOMException('Synthetic post-create failure','InvalidStateError');
    db.transaction=(...args)=>{
      const tx=transaction(...args);if(args[1]!=='readwrite')return tx;
      const objectStore=tx.objectStore.bind(tx);
      tx.objectStore=name=>{
        if(stage==='object_store')throw invalid();const store=objectStore(name),get=store.get.bind(store),put=store.put.bind(store);
        store.get=key=>{
          if(stage===(key==='identity'?'get_identity':'get_active'))throw invalid();
          if(stage===(key==='identity'?'async_identity_get':'async_active_get'))return store.request('get',[key],()=>{throw invalid();});
          const q=get(key);let value;
          Object.defineProperty(q,'result',{set(next){value=next;},get(){if(stage===(key==='identity'?'identity_result':'active_result'))throw invalid();return value;}});return q;
        };
        store.put=(...values)=>{
          if(stage==='put')throw invalid();const q=put(...values);
          if(stage==='put_enqueued_throw')throw invalid();
          if(stage==='put_enqueued_abort')q.onsuccess=()=>{tx.error=invalid();tx.abort();};
          return q;
        };return store;
      };return tx;
    };
    const baseline=h.factory.snapshot();result=await h.save();
    check(!result.ok&&result.code==='InvalidStateError',stage+': original failure is preserved');
    check(h.connections.length===1&&!h.events().some(e=>e.event==='connection_reopen_requested'),stage+': post-create error cannot trigger replay');
    check(h.factory.snapshot()===baseline&&!h.events().some(e=>e.event==='save_confirmed'),stage+': failed/uncertain transaction is never reported durable');
    const failure=h.events().findLast(e=>e.event==='save_failure');
    check(failure.stage!=='transaction_create',stage+': diagnostic distinguishes it from a safe creation-only retry');h.client.close();
  }
  report.cases.push('object/get/result/put/after-put failures never replay');
  h=await harness();h.close();
  h.control.onConnection=(db,count)=>{if(count===2){const transaction=db.transaction.bind(db);db.transaction=(...args)=>{if(args[1]==='readwrite')throw new DOMException('Synthetic second creation failure','InvalidStateError');return transaction(...args);};}};
  result=await h.save();
  check(!result.ok&&result.code==='InvalidStateError'&&h.connections.length===2,'a second creation failure stops after the single allowed reconnect');
  check(h.factory.commits===0&&!h.events().some(e=>e.event==='save_submitted'),'bounded retry never enqueues a write when both connections fail');h.client.close();
  h=await harness(source,true);h.close();result=await h.save();
  check(result.ok&&result.creditedCoins===1000&&JSON.parse(h.active().payload).coins===43000,'legacy compensation and exact pending wallet survive reconnect once');
  const receipt=JSON.stringify(h.active().campaigns);h.close();result=await h.save(h.active().payload);
  check(result.ok&&result.creditedCoins===0&&JSON.parse(h.active().payload).coins===43000&&JSON.stringify(h.active().campaigns)===receipt,'later reconnect preserves the immutable receipt and cannot award twice');
  check(h.factory.commits===2,'each legacy retry episode has only one committed write');h.client.close();
  report.cases.push('retry bounded to once; legacy award exactly once');
  h=await harness();const oldConnection=h.connections[0];oldConnection.onversionchange();
  check(oldConnection.closed&&h.events().some(e=>e.event==='connection_closed'&&e.stage==='versionchange'&&e.connectionGeneration===1),'version-change closure is observable with its own generation');
  check((await h.save()).ok,'a closed version-change handle can reconnect if the same schema and authority still exist');
  oldConnection.onclose();oldConnection.onversionchange();result=await h.save(h.active().payload);
  check(result.ok&&h.connections.length===2&&h.events().filter(e=>e.event==='connection_reopen_requested').length===1,'late events from an old handle cannot close or replace the current connection');
  check(h.events().some(e=>e.event==='connection_closed'&&e.stage==='forced_close'&&e.connectionGeneration===1),'forced-close diagnostics use a static stage and the affected generation');h.client.close();
  h=await harness();let release,settled=false;const heldDb=h.connections[0],heldTransaction=heldDb.transaction.bind(heldDb);
  heldDb.transaction=(...args)=>{
    const tx=heldTransaction(...args);
    if(args[1]==='readwrite'){let complete;Object.defineProperty(tx,'oncomplete',{set(fn){complete=fn;},get(){return event=>{release=()=>complete(event);};}});}
    return tx;
  };
  const pending=h.save().then(value=>{settled=true;return value;});
  for(let i=0;i<50&&!release;i++)await new Promise(resolve=>setImmediate(resolve));
  check(!!release&&!settled&&h.active().revision===1,'native completion can precede its delivered acknowledgement');
  heldDb.close();const busy=await h.save();
  check(!busy.ok&&busy.code==='SAVE_BUSY'&&h.connections.length===1,'an unknown pending write outcome is not reopened or replayed');
  release();result=await pending;
  check(result.ok&&h.factory.commits===1&&h.events().filter(e=>e.event==='save_confirmed').length===1,'delayed completion acknowledges the original transaction exactly once');h.client.close();
  report.cases.push('generation-safe close events; unknown pending outcome never replayed');
  report.passed=true;report.total_checks=report.checks.length;
  console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
