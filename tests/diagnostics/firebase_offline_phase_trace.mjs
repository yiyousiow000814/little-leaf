// Synthetic fullflow-offline observation only; never installed in ordinary play.
export function installOfflineTrace({uid}, root=globalThis) {
  if(uid!=='fullflow-offline')throw Error('Only the synthetic offline account may be traced');
  const rows=[],limit=512;
  let sequence=0,callSequence=0,dropped=0;
  const codes=new Set(['unavailable','NETWORK_TIMEOUT','OWNERSHIP_LOST','REVISION_CONFLICT','NOT_READY','HANDOFF_WAITING','HANDOFF_CHANGED','permission-denied']);
  const clock=()=>Math.round(root.performance.now()*1000)/1000;
  const mark=(phase,event,call=0,code=null,epoch=null,own=null)=>{
    if(rows.length>=limit){dropped++;return;}
    rows.push({sequence:++sequence,ms:clock(),phase,event,call,code,epoch,own});
  };
  const observe=(phase,fn,receiver,args)=>{
    const call=++callSequence;
    mark(phase,'enter',call);
    let result;
    try{result=Reflect.apply(fn,receiver,args);}
    catch(error){mark(phase,'reject',call,codes.has(error?.code)?error.code:'other');throw error;}
    if(result && typeof result.then==='function') {
      // Observe settlement; return the ORIGINAL promise, without a replacement.
      result.then(()=>mark(phase,'resolve',call),error=>mark(phase,'reject',call,codes.has(error?.code)?error.code:'other'));
    } else mark(phase,'return',call);
    return result;
  };
  const methods=(target,prefix,names,overrides={})=>{
    const cache=new Map();
    return new Proxy(Object.create(target),{get(object,key){
      if(Object.hasOwn(overrides,key))return overrides[key];
      const value=Reflect.get(target,key,target);
      if(typeof value!=='function')return value;
      const saved=cache.get(key);
      if(saved?.original===value)return saved.wrapper;
      const wrapper=function(...args){return names.includes(key)?observe(prefix+key,value,target,args):Reflect.apply(value,target,args);};
      cache.set(key,{original:value,wrapper});return wrapper;
    }});
  };
  const intercept=(name,decorate)=>{
    let current;
    Object.defineProperty(root,name,{configurable:true,enumerable:true,
      get(){return current;},set(value){current=decorate(value);}});
  };
  intercept('LittleLeafFirebaseSession',api=>Object.freeze({...api,
    createRemote(db,sdk,account){
      const remote=api.createRemote(db,methods(sdk,'session.sdk.',['runTransaction','getDocFromServer']),account);
      return remote;
    },
    createSession(options){
      const original=options.remote;
      const remote=methods(original,'session.remote.',['change','read'],{
        watch(receive,onError){
          return original.watch(function(value){
            'use strict';
            mark('session.server-observation','receive',0,null,Number.isSafeInteger(value?.epoch)?value.epoch:null,value?.owner===options.sessionId);
            return Reflect.apply(receive,this,arguments);
          },onError);
        }
      });
      const session=api.createSession({...options,remote});
      return methods(session,'ownership.',['requestTakeover','takeOver','acknowledge']);
    }
  }));
  intercept('LittleLeafFirebase',api=>Object.freeze({...api,
    createClient(options){
      const client=api.createClient({...options,
        journal:methods(options.journal,'journal.',['read','replace','readRecoveryBackup','readChoiceBackup']),
        remote:methods(options.remote,'cloud.',['read','compareAndSet']),
        codec:methods(options.codec,'codec.',['verifyRecord','hash'])
      });
      for(const name of ['boot','requestTakeover','finishTakeover','forceTakeover','preserveOwnerRuntime']){
        const original=client[name];
        client[name]=function(...args){return observe('client.'+name,original,this,args);};
      }
      return client;
    }
  }));
  Object.defineProperty(root,'__littleLeafOfflinePhaseTrace',{configurable:true,value:Object.freeze({
    snapshot(){return {schema:1,syntheticOnly:true,timeOriginMs:root.performance.timeOrigin,limit,dropped,rows:rows.map(row=>({...row}))};}
  })});
}
