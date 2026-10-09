// Synthetic QA only. Observes the actual SDK transaction; never changes its result or retries.
const stamp=v=>typeof v?.toMillis==='function'?v.toMillis():null;
const id=v=>typeof v==='string'&&/^[a-f0-9-]{36}$/i.test(v)?v:null;
const digest=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v)?v:null;
export function summary(d){
 if(!d)return null;
 return {owner:id(d.owner),epoch:Number.isSafeInteger(d.epoch)?d.epoch:null,updatedAt:stamp(d.updatedAt),
  request:d.request?{id:id(d.request.id),requester:id(d.request.requester),at:stamp(d.request.at)}:null,
  ack:d.ack?{requestId:id(d.ack.requestId),revision:Number.isSafeInteger(d.ack.revision)?d.ack.revision:null,digest:digest(d.ack.digest)}:null,
  revision:Number.isSafeInteger(d.revision)?d.revision:null,digest:digest(d.digest),writerId:id(d.writerId),writerEpoch:Number.isSafeInteger(d.writerEpoch)?d.writerEpoch:null};
}
export function observeTransactions(runTransaction,events,{afterCallback=async()=>{}}={}){
 let sequence=0;
 const emit=x=>{if(events.length<240)events.push(x);};
 return async function(db,callback,...options){
  if(db.app.options.projectId!=='demo-little-leaf')throw Error('Synthetic emulator project required');
  const transaction=++sequence;let attempt=0;
  try{
   const value=await runTransaction(db,async tx=>{
    const n=++attempt;const reads=[];const writes=[];
    const proxy=new Proxy(tx,{get(target,key){
     if(key==='get')return async ref=>{const s=await target.get(ref);if(reads.length<8)reads.push({kind:ref.id==='owner'?'owner':ref.id==='cafe'?'save':'other',value:summary(s.exists()?s.data():null)});return s;};
     if(key==='set')return(ref,data,...rest)=>{if(writes.length<8)writes.push({kind:ref.id==='owner'?'owner':ref.id==='cafe'?'save':'other',value:summary(data)});target.set(ref,data,...rest);return proxy;};
     const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
    }});
    try{const result=await callback(proxy);emit({transaction,attempt:n,event:'callback',reads,writes});await afterCallback({transaction,attempt:n,reads,writes});return result;}
    catch(e){emit({transaction,attempt:n,event:'callback-error',code:safeCode(e?.code)});throw e;}
   },...options);emit({transaction,event:'settled',result:'success'});return value;
  }catch(e){emit({transaction,event:'settled',result:'failure',code:safeCode(e?.code)});throw e;}
 };
}
function safeCode(code){return ['permission-denied','aborted','unavailable','deadline-exceeded','OWNERSHIP_LOST','HANDOFF_BUSY','HANDOFF_CHANGED','NOT_READY'].includes(code)?code:'other';}
export function boundedFailure(error){return {name:error?.name==='AssertionError'?'AssertionError':'Error',code:['ERR_ASSERTION','permission-denied','aborted','unavailable','deadline-exceeded'].includes(error?.code)?error.code:null,operator:['==','===','deepStrictEqual','strictEqual','fail'].includes(error?.operator)?error.operator:null};}
