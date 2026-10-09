'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto};root.globalThis=root;vm.runInNewContext(fs.readFileSync('web/little_leaf_firebase_session.js','utf8'),root);
const clone=x=>JSON.parse(JSON.stringify(x)),failure=code=>Object.assign(Error(code),{code});
const owner='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
function harness({first='permission-denied',mutate=x=>({...x,updatedAt:x.updatedAt+10}),second=null}={}){
 let value={schema:1,owner,epoch:1,device:'Mac',updatedAt:100000,request:null,ack:null},uid='synthetic',armed=false,calls=0,reads=0,hook=null,inside=null;
 const proposed=[];
 const remote={watch(){return()=>{};},async read(){reads++;if(hook)await hook();return clone(value);},async change(fn,guard){
  guard();if(armed){calls++;if(calls===2&&inside)inside();}
  const next=fn(clone(value),null,()=>100100);guard();
  if(armed){proposed.push(clone(next));if(calls===1&&first){value=mutate(value);throw failure(first);}if(calls===2&&second)throw failure(second);}
  value=clone(next);return clone(value);
 }};
 const session=root.LittleLeafFirebaseSession.createSession({uid:'synthetic',currentUid:()=>uid,deviceLabel:'iPhone',now:()=>100100,remote});
 return {session,async start(){await session.start();armed=true;},get:()=>clone(value),set:x=>value=clone(x),calls:()=>calls,reads:()=>reads,proposed,onRead:f=>hook=f,onSecond:f=>inside=f,setUid:x=>uid=x};
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
 console.log('Bounded request retry: '+checks+' checks passed; no save/journal interface involved.');
}
module.exports=run();if(require.main===module)module.exports.catch(e=>{console.error(e);process.exitCode=1;});
