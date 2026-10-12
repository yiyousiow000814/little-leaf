'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const root={crypto:webcrypto};root.globalThis=root;
vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase_session.js','utf8'),root);
const clone=x=>JSON.parse(JSON.stringify(x)),failure=code=>Object.assign(Error(code),{code});
const owner='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',requester='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',digest='b'.repeat(64);
function harness({first='permission-denied',mutate=x=>({...x,updatedAt:x.updatedAt+10}),second=null}={}){
 let value={schema:1,owner,epoch:1,device:'Mac',updatedAt:100000,request:{id:requester,requester,device:'iPhone',at:100010},ack:null};
 let save={digest,revision:2,writerId:owner,writerEpoch:1},uid='synthetic',armed=false,calls=0,reads=0,hook=null,inside=null;
 const proposed=[];
 const remote={watch(){return()=>{};},async read(){reads++;if(hook)await hook();return clone(value);},async change(fn,guard){
  guard();if(armed){calls++;if(calls===2&&inside)inside();}
  const next=fn(clone(value),clone(save),()=>100100);guard();
  if(armed){proposed.push(clone(next));if(calls===1&&first){value=mutate(value);throw failure(first);}if(calls===2&&second)throw failure(second);}
  value=clone(next);return clone(value);
 }};
 const session=root.LittleLeafFirebaseSession.createSession({uid:'synthetic',currentUid:()=>uid,sessionId:owner,deviceLabel:'Mac',now:()=>100100,remote});
 return {session,async start(){await session.refresh();armed=true;},get:()=>clone(value),set:x=>value=clone(x),saved:()=>clone(save),setSave:x=>save=clone(x),calls:()=>calls,reads:()=>reads,proposed,onRead:f=>hook=f,onSecond:f=>inside=f,setUid:x=>uid=x};
}
async function run(){
 let checks=0;const check=(ok,label)=>{assert(ok,label);checks++;};
 let h=harness({first:null});await h.start();await h.session.acknowledge(digest,2);check(h.calls()===1&&h.reads()===1,'ordinary ACK needs no recovery reread');
 h=harness();await h.start();const before=h.saved();await h.session.acknowledge(digest,2);
 check(h.calls()===2&&h.reads()===2,'one independently confirmed reread and one fresh CAS only');
 check(h.get().owner===owner&&h.get().epoch===1&&h.get().updatedAt===100010,'ACK preserves renewed owner and epoch');
 check(h.proposed[0].ack.requestId===h.proposed[1].ack.requestId&&h.get().ack.digest===digest&&h.get().ack.revision===2,'same final save and request intent');
 assert.deepEqual(h.saved(),before);checks++;
 for(const [label,mutate] of Object.entries({same:x=>x,older:x=>({...x,updatedAt:x.updatedAt-1}),schema:x=>({...x,updatedAt:x.updatedAt+10,schema:2}),owner:x=>({...x,updatedAt:x.updatedAt+10,owner:requester}),epoch:x=>({...x,updatedAt:x.updatedAt+10,epoch:2}),device:x=>({...x,updatedAt:x.updatedAt+10,device:'Windows PC'}),request:x=>({...x,updatedAt:x.updatedAt+10,request:null}),id:x=>({...x,updatedAt:x.updatedAt+10,request:{...x.request,id:owner}}),requester:x=>({...x,updatedAt:x.updatedAt+10,request:{...x.request,requester:owner}}),requestDevice:x=>({...x,updatedAt:x.updatedAt+10,request:{...x.request,device:'Mac'}}),requestAt:x=>({...x,updatedAt:x.updatedAt+10,request:{...x.request,at:x.request.at+1}}),ack:x=>({...x,updatedAt:x.updatedAt+10,ack:{requestId:requester,digest,revision:2}})})){
  h=harness({mutate});await h.start();await assert.rejects(h.session.acknowledge(digest,2),e=>e.code==='permission-denied');check(h.calls()===1,label+' cannot authorize a retry');
 }
 // A one-nanosecond renewal is real; a one-nanosecond request change is a
 // different intent even though both would collapse to the same millisecond.
 for(const requestChanged of [false,true]){
  h=harness({mutate:x=>({...x,updatedAt:{seconds:100,nanoseconds:1},request:{...x.request,at:{seconds:100,nanoseconds:requestChanged?1:0}}})});h.set({...h.get(),updatedAt:{seconds:100,nanoseconds:0},request:{...h.get().request,at:{seconds:100,nanoseconds:0}}});await h.start();
  if(requestChanged){await assert.rejects(h.session.acknowledge(digest,2),e=>e.code==='permission-denied');check(h.calls()===1,'submillisecond request change is fenced');}
  else {await h.session.acknowledge(digest,2);check(h.calls()===2,'full precision server renewal is recognized');}
 }
 for(const code of ['unavailable','unauthenticated','deadline-exceeded']){h=harness({first:code});await h.start();await assert.rejects(h.session.acknowledge(digest,2),e=>e.code===code);check(h.calls()===1&&h.reads()===1,code+' cannot authorize a retry');}
 h=harness({second:'permission-denied'});await h.start();await assert.rejects(h.session.acknowledge(digest,2),e=>e.code==='permission-denied');check(h.calls()===2&&h.reads()===2&&h.get().ack===null,'second denial stays paused, no loop');
 for(const field of ['digest','revision','writerId','writerEpoch']){
  h=harness();await h.start();h.onSecond(()=>h.setSave({...h.saved(),[field]:field==='digest'?'c'.repeat(64):field==='writerId'?requester:3}));
  await assert.rejects(h.session.acknowledge(digest,2),e=>e.code==='HANDOFF_NOT_SAVED');check(h.proposed.length===1,field+' rechecked in fresh transaction before ACK');
 }
 for(const mode of ['renew-again','request','close','account']){
  h=harness();await h.start();h.onSecond(()=>{if(mode==='close')h.session.close();else if(mode==='account')h.setUid('other');else h.set({...h.get(),...(mode==='renew-again'?{updatedAt:h.get().updatedAt+1}:{request:null})});});
  await assert.rejects(h.session.acknowledge(digest,2),e=>['HANDOFF_CHANGED','NOT_READY'].includes(e.code));check(h.proposed.length===1,mode+' fenced inside retry transaction');
 }
 for(const mode of ['close','account','reread-failure']){
  h=harness();await h.start();h.onRead(()=>{if(mode==='close')h.session.close();if(mode==='account')h.setUid('other');if(mode==='reread-failure')throw failure('unavailable');});
  await assert.rejects(h.session.acknowledge(digest,2),e=>e.code===(mode==='reread-failure'?'unavailable':'NOT_READY'));check(h.calls()===1,mode+' cannot continue an old account intent');
 }
 for(const field of ['writerId','writerEpoch']){
  h=harness();h.setSave({...h.saved(),[field]:field==='writerId'?requester:2});await h.start();await assert.rejects(h.session.acknowledge(digest,2),e=>e.code==='HANDOFF_NOT_SAVED');check(h.proposed.length===0,'mismatched '+field+' rejected before first ACK');
 }
 console.log('Bounded ACK retry: '+checks+' checks passed; final-save fence and request retained.');
}
module.exports=run();if(require.main===module)module.exports.catch(e=>{console.error(e);process.exitCode=1;});
