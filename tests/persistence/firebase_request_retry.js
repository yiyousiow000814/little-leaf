'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto};root.globalThis=root;vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase_session.js','utf8'),root);
const clone=x=>JSON.parse(JSON.stringify(x),(_,value)=>{
 if(value&&typeof value==='object'&&Object.hasOwn(value,'seconds')&&Object.hasOwn(value,'nanoseconds'))
  Object.defineProperty(value,'toMillis',{value(){return this.seconds*1000+this.nanoseconds/1000000;}});
 return value;
}),failure=code=>Object.assign(Error(code),{code});
const owner='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
function harness({first='permission-denied',mutate=x=>({...x,updatedAt:x.updatedAt+10}),second=null,updatedAt=100000,clock=100100}={}){
 let value={schema:1,owner,epoch:1,device:'Mac',updatedAt,request:null,ack:null},uid='synthetic',armed=false,calls=0,reads=0,hook=null,inside=null;
 const proposed=[];
 const remote={watch(){return()=>{};},async read(){reads++;if(hook)await hook();return clone(value);},async change(fn,guard){
  guard();if(armed){calls++;if(calls===2&&inside)inside();}
  const next=fn(clone(value),null,()=>clock);guard();
  if(armed){proposed.push(clone(next));if(calls===1&&first){value=mutate(value);throw failure(first);}if(calls===2&&second)throw failure(second);}
  value=clone(next);return clone(value);
 }};
 const session=root.LittleLeafFirebaseSession.createSession({uid:'synthetic',currentUid:()=>uid,deviceLabel:'iPhone',now:()=>clock,remote});
 return {session,async start(){await session.start();armed=true;},get:()=>clone(value),set:x=>value=clone(x),calls:()=>calls,reads:()=>reads,proposed,onRead:f=>hook=f,onSecond:f=>inside=f,setUid:x=>uid=x};
}
async function timestampChecks(check){
 const at=(seconds,nanoseconds)=>clone({seconds,nanoseconds}),seconds=1791981670,clock=seconds*1000;
 const cases=[
  ['one-nanosecond',at(seconds,100),at(seconds,101),'waiting'],
  ['rollover',at(seconds,999999999),at(seconds+1,0),'waiting'],
  ['same',at(seconds,100),at(seconds,100),'permission-denied'],
  ['older',at(seconds,100),at(seconds,99),'permission-denied'],
  ['invalid-nanoseconds',at(seconds,100),at(seconds,1000000000),'permission-denied'],
  ['invalid-attempt',at(seconds,0.5),at(seconds,101),'permission-denied'],
  ['finite-number',100000.25,100000.5,'waiting'],
  ['mixed-representation',at(seconds,100),clock+1,'permission-denied']
 ];
 const failures=[];
 for(const [label,before,after,expected] of cases){
  const h=harness({updatedAt:before,clock:typeof before==='number'?100100:clock,mutate:x=>({...x,updatedAt:after})});
  try{
   await h.start();
   if(expected==='waiting'){const result=await h.session.requestTakeover();check(result.status==='waiting'&&h.calls()===2&&h.reads()===1,label+' has one verified request retry');}
   else{await assert.rejects(h.session.requestTakeover(),e=>e.code==='permission-denied');check(h.calls()===1,label+' refuses an unproved renewal');}
  }catch(error){failures.push(Object.assign(Error(label+': '+error.message),{cause:error}));}
  finally{h.session.close();}
 }
 const changed=harness({updatedAt:at(seconds,100),clock,mutate:x=>({...x,updatedAt:at(seconds,1000100)})});
 try{
  await changed.start();changed.onSecond(()=>changed.set({...changed.get(),updatedAt:at(seconds,1000101)}));
  await assert.rejects(changed.session.requestTakeover(),e=>e.code==='HANDOFF_CHANGED');
  check(changed.proposed.length===1,'a further one-nanosecond change refuses the stale retry before its write');
 }catch(error){failures.push(Object.assign(Error('changed-inside-retry: '+error.message),{cause:error}));}
 finally{changed.session.close();}
 if(failures.length)throw new AggregateError(failures,'Full Timestamp request regressions');
}
async function requestLeaseChecks(check){
 const requester='cccccccc-cccc-4ccc-8ccc-cccccccccccc',foreign='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
 async function fixture({renewals=0,denied=false,mutation=null}={}){
  let value={schema:1,owner,epoch:1,device:'Mac',updatedAt:100000,request:null,ack:null};
  const initial=clone(value),saved={digest:'a'.repeat(64),revision:3};
  let uid='request-write',held=true,version=0,remaining=renewals,armed=false,attempts=0,retries=0,updates=0,sets=0,reads=0;
  const sdk={doc:(db,...parts)=>parts.join('/'),serverTimestamp:()=>100100,onSnapshot:()=>()=>{},
   // A delayed listener snapshot cannot prove that a denied write raced a
   // renewal. The actual transaction read below always sees the server value.
   getDocFromServer:async()=>{reads++;return {exists:()=>true,data:()=>clone(initial)};},
   async runTransaction(db,callback){
    for(let attempt=0;attempt<5;attempt++){
     const readVersion=version;let write=null;
     const result=await callback({get:async ref=>({exists:()=>true,data:()=>clone(ref.endsWith('/owner')?value:saved)}),
      set:(ref,next)=>write={kind:'set',value:clone(next)},update:(ref,next)=>write={kind:'update',value:clone(next)}});
     if(!write)return result;
     if(armed){
      attempts++;
      if(remaining>0){remaining--;value={...value,updatedAt:value.updatedAt+1};version++;}
      if(mutation){mutation({value,setUid:x=>uid=x,release:()=>held=false});mutation=null;version++;}
      if(denied)throw failure('permission-denied');
      const next=write.kind==='update'?{...value,...write.value}:write.value;
      // Model the unchanged Rules ask predicate before Firestore evaluates
      // its read precondition. No write is authorized by this fixture retry.
      if(Object.keys(next).length!==7||!Object.hasOwn(next,'device')||next.owner!==value.owner||next.epoch!==value.epoch||next.device!==value.device
       ||next.updatedAt!==value.updatedAt||value.request!==null||value.ack!==null||!next.request||next.ack!==null)throw failure('permission-denied');
      if(readVersion!==version){retries++;continue;}
      if(write.kind==='update'){assert.deepEqual(Object.keys(write.value),['request']);updates++;}
      else sets++;
      value=next;version++;return result;
     }
     throw Error('Unexpected startup write');
    }
    throw failure('aborted');
   }};
  const remote=root.LittleLeafFirebaseSession.createRemote({},sdk,'request-write');
  const session=root.LittleLeafFirebaseSession.createSession({remote,uid:'request-write',currentUid:()=>uid,
   sessionId:requester,deviceLabel:'iPhone',now:()=>100100,assertRuntime:()=>{if(!held)throw failure('NOT_READY');}});
  await session.start();armed=true;
  return {session,remote,run:()=>session.requestTakeover(),get:()=>clone(value),
   facts:()=>({remaining,attempts,retries,updates,sets,reads,saved:clone(saved)}),close:()=>session.close()};
 }
 for(const renewals of [2,0,1]){
  const f=await fixture({renewals});try{
   const result=await f.run(),facts=f.facts(),value=f.get();
   check(result.status==='waiting','request survives '+renewals+' legal concurrent renewals');
   check(facts.remaining===0&&facts.retries===renewals,'only SDK contention retries were exercised');
   check(facts.updates===1&&facts.sets===0&&facts.reads===0,'one request-field write; no permission fallback');
   check(value.owner===owner&&value.epoch===1&&value.updatedAt===100000+renewals&&value.ack===null,'owner epoch lease and ACK preserved');
   check(value.request.requester===requester&&result.ownershipPaused,'a request never grants writer authority');
   check(facts.saved.digest==='a'.repeat(64)&&facts.saved.revision===3,'saved document remains unchanged');
  }finally{f.close();}
 }
 for(const [label,options] of Object.entries({
  denial:{denied:true},request:{mutation:({value})=>value.request={id:foreign,requester:foreign,device:'Mac',at:100100}},
  ack:{mutation:({value})=>value.ack={requestId:foreign,digest:'b'.repeat(64),revision:2}},
  account:{renewals:1,mutation:({setUid})=>setUid('other')},runtime:{renewals:1,mutation:({release})=>release()},
  owner:{mutation:({value})=>value.owner=foreign},epoch:{mutation:({value})=>value.epoch++},device:{mutation:({value})=>value.device='Windows PC'}
 })){
  const f=await fixture(options);try{
   await assert.rejects(f.run(),e=>e.code===(label==='account'||label==='runtime'?'NOT_READY':['owner','epoch','device'].includes(label)?'HANDOFF_CHANGED':'permission-denied'));
   check(f.facts().updates===0&&f.facts().sets===0,label+' refuses the stale request');
   check(f.facts().attempts===1,label+' does not retry a permission denial');
  }finally{f.close();}
 }
 for(const kind of ['extra-field','missing-field']){
  const f=await fixture();try{
   await assert.rejects(f.remote.change(value=>{
    const next={...value,request:{id:foreign,requester,device:'iPhone',at:100100}};
    if(kind==='extra-field')next.extra=true;else delete next.device;
    return next;
   },()=>{}),e=>e.code==='permission-denied');
   check(f.facts().updates===0&&f.get().request===null,kind+' is not silently projected into a valid partial write');
  }finally{f.close();}
 }
}
async function run(){
 let checks=0;const check=(ok,label)=>{assert(ok,label);checks++;};
 let h=harness();await h.start();const result=await h.session.requestTakeover();check(result.status==='waiting','verified renewal contention retries request');check(h.calls()===2&&h.reads()===1,'one server reread and one retry only');check(h.proposed[0].request.id===h.proposed[1].request.id,'same explicit request id');check(h.get().owner===owner&&h.get().epoch===1&&h.get().updatedAt===100010&&!h.get().ack,'retry preserves owner epoch renewed time and no ack');
 const other='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
 for(const [label,mutate] of Object.entries({same:x=>x,older:x=>({...x,updatedAt:x.updatedAt-1}),owner:x=>({...x,updatedAt:x.updatedAt+10,owner:other}),epoch:x=>({...x,updatedAt:x.updatedAt+10,epoch:2}),device:x=>({...x,updatedAt:x.updatedAt+10,device:'Windows PC'}),request:x=>({...x,updatedAt:x.updatedAt+10,request:{id:other,requester:other,device:'Mac',at:100100}}),ack:x=>({...x,updatedAt:x.updatedAt+10,ack:{requestId:other,digest:'a'.repeat(64),revision:1}})})){
  h=harness({mutate});await h.start();await assert.rejects(h.session.requestTakeover(),e=>e.code==='permission-denied');check(h.calls()===1,label+' denial cannot trigger a write retry');
 }
 for(const code of ['unavailable','unauthenticated','deadline-exceeded']){h=harness({first:code});await h.start();await assert.rejects(h.session.requestTakeover(),e=>e.code===code);check(h.calls()===1&&h.reads()===0,code+' is not renewal contention');}
 h=harness({second:'permission-denied'});await h.start();await assert.rejects(h.session.requestTakeover(),e=>e.code==='permission-denied');check(h.calls()===2&&h.reads()===1,'second denial never loops');check(h.get().request===null,'failed retry creates no request');
 for(const mode of ['close','account','new-request','reread-failure']){
  h=harness();await h.start();let newer;
  h.onRead(async()=>{h.onRead(null);if(mode==='close')h.session.close();if(mode==='account')h.setUid('other');if(mode==='new-request')newer=await h.session.requestTakeover();if(mode==='reread-failure')throw failure('unavailable');});
  await assert.rejects(h.session.requestTakeover(),e=>e.code===(mode==='new-request'?'REQUEST_CANCELLED':mode==='reread-failure'?'unavailable':'NOT_READY'));
  check(h.calls()===(mode==='new-request'?2:1),mode+' invalidates old retry across asynchronous read');
  if(mode==='new-request')check(newer.status==='waiting'&&h.proposed[0].request.id!==h.proposed[1].request.id,'only newer explicit request remains');
 }
 for(const mode of ['renew-again','epoch','request','close','account']){
  h=harness();await h.start();h.onSecond(()=>{if(mode==='close')h.session.close();else if(mode==='account')h.setUid('other');else {const v=h.get();h.set({...v,...(mode==='renew-again'?{updatedAt:v.updatedAt+1}:mode==='epoch'?{epoch:2}:{request:{id:other,requester:other,device:'Mac',at:100100}})});}});
  await assert.rejects(h.session.requestTakeover(),e=>['HANDOFF_CHANGED','NOT_READY'].includes(e.code));check(h.proposed.length===1,mode+' checked inside retry transaction before set');
 }
 console.log('Original bounded request retry: '+checks+' checks passed.');
 if(!process.argv.includes('--lease-only'))await timestampChecks(check);
 await requestLeaseChecks(check);
 console.log('Bounded request retry: '+checks+' checks passed; no save/journal interface involved.');
}
module.exports=run();if(require.main===module)module.exports.catch(e=>{console.error(e);process.exitCode=1;});
