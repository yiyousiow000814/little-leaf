/* Optional Firebase-hosted update notice. Reload requires an exact confirmed save. */
(function(root){
  'use strict';
  function version(value){
    const match=/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:([a-z])|-pre\.([a-f0-9]{8}))?$/.exec(String(value));
    if(!match)return null;
    const parts=[Number(match[1]),Number(match[2]),Number(match[3])];
    if(!parts.every(Number.isSafeInteger))return null;
    return {parts,hotfix:match[4]?match[4].charCodeAt(0)-96:0,pre:match[5]||''};
  }
  function order(data){const item=data?.release_order;return item?.target==='siowyiyou/little-leaf:html5'&&Number.isSafeInteger(item.channel_version)&&item.channel_version>0?item.channel_version:null;}
  function identity(data){const parsed=version(data?.version);return parsed&&/^[a-f0-9]{40}$/.test(data.source_commit||'')&&(!parsed.pre||data.source_commit.startsWith(parsed.pre))?{...parsed,commit:data.source_commit,order:order(data)}:null;}
  function newer(a,b){
    for(let i=0;i<3;i++){if(a.parts[i]!==b.parts[i])return a.parts[i]>b.parts[i];}
    if(!!a.pre!==!!b.pre)return !a.pre;
    if(!a.pre)return a.hotfix>b.hotfix;
    return a.commit!==b.commit&&a.order!==null&&b.order!==null&&a.order>b.order;
  }
  function same(a,b){return a.version===b.version&&a.commit===b.commit&&a.order===b.order;}
  function create(options={}){
    const fetcher=options.fetch || root.fetch?.bind(root);
    const reload=options.reload || (()=>root.location.reload());
    const schedule=options.setTimeout||root.setTimeout, cancel=options.clearTimeout||root.clearTimeout;
    function bounded(promise){
      let timeout;const limit=new Promise((_,reject)=>{timeout=schedule(()=>reject(Error('The connection timed out. Your progress stays on this page.')),15000);});
      return Promise.race([promise,limit]).finally(()=>cancel(timeout));
    }
    let storage=options.storage;try{if(!storage)storage=root.sessionStorage;}catch(_){}
    let current=null, latest=null, busy=false, reason='', timer=null, started=false, reloaded=false, closed=false;
    let polling=null, generation=0;
    const dismissed=new Set();
    function readDismissed(v){try{return dismissed.has(v)||storage?.getItem('little-leaf-update-dismissed')===v;}catch(_){return dismissed.has(v);}}
    function snapshot(){return JSON.stringify({available:!!latest&&!readDismissed(latest.version),version:latest?.version||'',busy,reason});}
    async function manifest(){
      if(!fetcher)throw Error('Update checking is unavailable.');
      const response=await bounded(fetcher('./hosting-release.json',{cache:'no-store',credentials:'same-origin'}));
      if(!response.ok)throw Error('Could not check the latest version.');
      const data=await bounded(response.json());
      const parsed=identity(data);
      if(data.schema_version!==1||!parsed)throw Error('The update information is not ready.');
      return {version:data.version,...parsed};
    }
    async function poll(){
      if(closed||!current||busy||reloaded)return;
      if(polling)return polling;
      polling=(async()=>{try{const data=await manifest();if(closed)return;if(newer(data,current)){latest=data;reason='';}else{latest=null;reason='';}}catch(_){/* Quiet while offline. Never interrupt play. */}})();
      try{await polling;}finally{polling=null;}
    }
    function start(currentVersion){
      if(closed||started)return;current=version(currentVersion);
      if(current?.pre){const bound=identity(options.currentRelease);current=options.currentRelease?.version===currentVersion&&bound?bound:null;}
      if(!current||(typeof options.checkUpdateReady!=='function'||typeof options.canReloadUpdate!=='function'))return;
      started=true;void poll();
      timer=(options.setInterval||root.setInterval)(poll,120000);
      root.document?.addEventListener('visibilitychange',onVisible);
    }
    function onVisible(){if(!root.document.hidden)void poll();}
    function dismiss(v){if(latest?.version!==v||busy)return;dismissed.add(v);try{storage?.setItem('little-leaf-update-dismissed',v);}catch(_){}}
    async function reloadForUpdate(v,profileId,revision,token,callback){
      const reply=result=>{if(typeof callback==='function')callback(JSON.stringify(result));return result;};
      if(closed||busy||reloaded)return reply({ok:false,code:'UPDATE_BUSY',message:'An update is already in progress.'});
      if(!latest||latest.version!==v||!profileId||!Number.isInteger(revision)||typeof token!=='string'||!token)return reply({ok:false,code:'UPDATE_CHANGED',message:'Save your current café before updating.'});
      busy=true;reason='';const operation=++generation;
      try{
        const fresh=await manifest();
        if(!same(fresh,latest))throw Error('The available update changed. Please try again.');
        if(operation!==generation)throw Error('This update was cancelled.');
        const checked=await bounded(options.checkUpdateReady(profileId,revision,token));
        if(operation!==generation||!checked?.ok||checked.cloudConfirmed!==true||checked.profileId!==profileId||checked.revision!==revision||checked.updateToken!==token)throw Error(checked?.message||'Your save could not be confirmed. Keep this page open.');
        const finalManifest=await manifest();
        if(operation!==generation||!same(finalManifest,fresh))throw Error('The available update changed. Please try again.');
        if(options.canReloadUpdate(profileId,revision,token)!==true)throw Error('Your active save or device changed. Keep this page open.');
        reloaded=true;reply({ok:true,profileId,revision,cloudConfirmed:true});reload();
        return {ok:true};
      }catch(e){reason=e.message||'Could not safely update. Please try again.';return reply({ok:false,code:'UPDATE_NOT_READY',message:reason});}
      finally{busy=false;}
    }
    function close(){closed=true;latest=null;generation++;if(timer!==null)(options.clearInterval||root.clearInterval)(timer);root.document?.removeEventListener('visibilitychange',onVisible);}
    return Object.freeze({start,snapshot,dismiss,reloadForUpdate,close,poll});
  }
  root.LittleLeafUpdates=Object.freeze({create});
  if(typeof module==='object'&&module.exports)module.exports={create};
})(typeof window==='object'?window:globalThis);
