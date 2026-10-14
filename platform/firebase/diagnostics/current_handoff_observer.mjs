// Diagnostic-only observer for one synthetic current-source ownership transfer.
// Preserve frozen API descriptors, original promises/receivers and all arguments.
export function installHandoffObservation(){
  const evidence={events:[],dropped:0};globalThis.__qaHandoffObservation=evidence;
  let api,enabled=false;
  const codes=new Set(['NETWORK_TIMEOUT','OWNERSHIP_LOST','NOT_READY','HANDOFF_CHANGED','HANDOFF_NOT_SAVED','REVISION_CONFLICT','permission-denied','firestore/permission-denied','unavailable','deadline-exceeded']);
  function observe(phase,invoke){
    const event={phase,startedAt:Date.now(),finishedAt:null,outcome:'pending'};
    if(evidence.events.length<96)evidence.events.push(event);else evidence.dropped++;
    const finish=(outcome,error)=>{event.finishedAt=Date.now();event.outcome=outcome;if(error)event.code=codes.has(error.code)?error.code:'other';};
    try{const result=invoke();Promise.resolve(result).then(()=>finish('fulfilled'),error=>finish('rejected',error));return result;}
    catch(error){finish('thrown',error);throw error;}
  }
  function instrument(target,phases){
    if(!target)return target;
    const methods=new Map();
    return new Proxy(target,{get(object,key){
      const value=Reflect.get(object,key,object);
      if(!Object.hasOwn(phases,key)||typeof value!=='function')return value;
      if(!methods.has(key))methods.set(key,function(...args){const invoke=()=>Reflect.apply(value,object,args);return enabled?observe(phases[key],invoke):invoke();});
      return methods.get(key);
    }});
  }
  Object.defineProperty(globalThis,'LittleLeafFirebase',{configurable:true,enumerable:true,get:()=>api,set(original){
    const descriptors=Object.getOwnPropertyDescriptors(original),create=original.createClient;
    if(typeof create!=='function')throw Error('Current fixture client factory required');
    descriptors.createClient={...descriptors.createClient,value:function(options){
      const client=Reflect.apply(create,original,[{...options,
        journal:instrument(options.journal,{replace:'journal-replace'}),
        remote:instrument(options.remote,{read:'save-read',compareAndSet:'save-upload'}),
        ownership:instrument(options.ownership,{renew:'owner-renew',acknowledge:'owner-ack',confirmHandoff:'owner-confirm'})}]);
      const preserve=client.preserveOwnerRuntime;
      client.preserveOwnerRuntime=function(...args){enabled=true;return observe('preserve-owner',()=>Reflect.apply(preserve,this,args));};
      // Observation continues after the bounded preservation result, so the
      // existing renewal/focus continuation and late operations remain visible.
      const close=client.close;
      if(close)client.close=function(...args){try{return Reflect.apply(close,this,args);}finally{enabled=false;}};
      return client;
    }};
    api=Object.freeze(Object.create(Object.getPrototypeOf(original),descriptors));
  }});
}

export function proxyCategory(error){
  const first=String(error?.message||error).split('\n',1)[0].toLowerCase();
  if(error?.name==='TimeoutError'||/^route\.fetch: timeout \d+ms exceeded(?:\.|$)/.test(first))return 'timeout';
  if(/target page, context or browser has been closed/.test(first))return 'target-closed';
  if(/local.network|private.network/.test(first))return 'local-network';
  if(/cors|cross.origin|access.control/.test(first))return 'cross-origin';
  return 'other';
}

export function operationLabel(value,method){
  const u=new URL(value),pathname=u.pathname;
  if(u.origin!=='https://firestore.fullflow.test'||u.username||u.password||u.hash||!['GET','POST'].includes(method))throw Error('Nonfixture operation');
  if(/^\/v1\/projects\/demo-little-leaf\/databases\/\(default\)\/documents:(batchGet|commit)$/.test(pathname))return pathname.endsWith(':batchGet')?'read':'commit';
  const match=/^\/google\.firestore\.v1\.Firestore\/(Listen|Write)\/channel$/.exec(pathname);
  if(!match||u.searchParams.getAll('database').length!==1||u.searchParams.get('database')!=='projects/demo-little-leaf/databases/(default)')throw Error('Nonfixture operation');
  return match[1].toLowerCase()+(method==='GET'?'-poll':'-send');
}
