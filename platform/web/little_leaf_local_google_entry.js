/* Same-origin entry/binding wiring. Ordinary local exports never receive account SDKs. */
(function(root){
  'use strict';
  const CLOUD_ONCE='little-leaf.google-binding-cloud-once.v1';
  async function readLocalRecord(){
    const vault=root.__littleLeafVault,identity=JSON.parse(vault.bootJson || '{}');
    if(!identity.ok)throw Error('Local save unavailable');
    const db=await new Promise((resolve,reject)=>{
      const request=root.indexedDB.open(root.LittleLeafVault.DB_NAME);
      request.onupgradeneeded=()=>{request.transaction.abort();};
      request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(Error('Local storage unavailable'));
    });
    let record,profile;
    try{
      await new Promise((resolve,reject)=>{
        const tx=db.transaction(root.LittleLeafVault.STORE,'readonly'),store=tx.objectStore(root.LittleLeafVault.STORE);
        const current=store.get('active'),owner=store.get('identity');current.onsuccess=()=>record=current.result;owner.onsuccess=()=>profile=owner.result;
        tx.oncomplete=resolve;tx.onabort=()=>reject(Error('Local snapshot failed'));tx.onerror=()=>{};
      });
    }finally{db.close();}
    await root.LittleLeafAuthorityCodec.verifyRecord(record);
    if(!profile || profile.profileId!==record.profileId || profile.createdAt!==record.createdAt || record.profileId!==identity.profileId || record.revision!==identity.revision)throw Error('Local save changed');
    return record;
  }
  function chooseMode({auth,document,storage}){
    try{
      const raw=storage.getItem(CLOUD_ONCE);storage.removeItem(CLOUD_ONCE);
      if(raw){const receipt=JSON.parse(raw);if(receipt.uid===auth.currentUser?.uid && receipt.cloudConfirmed===true)return Promise.resolve('cloud');}
    }catch(_){/* Explicit entry remains available if session storage is unavailable. */}
    return new Promise(resolve=>{
      const panel=document.createElement('section');panel.id='local-google-entry';panel.setAttribute('aria-label','Choose restaurant');
      panel.style.cssText='position:fixed;inset:12%;margin:auto;max-width:520px;height:max-content;background:#fffaf0;color:#493d2e;border-radius:16px;padding:24px;z-index:70;font:16px Arial;';
      const title=document.createElement('h2');title.textContent='Where would you like to play?';
      const copy=document.createElement('p');copy.textContent='Play on this device first, then bind its restaurant to Google from Settings. Signing in will never choose between your restaurants for you.';panel.append(title,copy);
      for(const [text,mode] of [['Play on this device','local'],['Open Google cloud restaurant','cloud']]){
        const button=document.createElement('button');button.textContent=text;button.style.cssText='min-height:48px;margin:6px;padding:12px;font:inherit;';button.onclick=()=>{panel.remove();resolve(mode);};panel.append(button);
      }
      document.body.append(panel);
    });
  }
  function install({auth,signIn,verifyGoogle,createTarget,storage=root.sessionStorage}){
    let returned=null,target=null,timer=null,ui=null;
    function release(){if(timer!==null)root.clearInterval(timer);timer=null;target?.ownership.close();target=null;}
    function resume(){release();const callback=returned;returned=null;callback?.(JSON.stringify({ok:true,localPreserved:true}));}
    ui=root.LittleLeafGoogleBindingUI.create({document:root.document,origin:root.location.origin,
      capture:async()=>{await readLocalRecord();return {ok:true};},
      signIn:async()=>{const credential=await signIn();await verifyGoogle(credential);return credential.user;},
      connect:async user=>{
        release();target=await createTarget(user);target.ownership.assertActive();
        timer=root.setInterval(()=>{target?.ownership.renew().catch(()=>{});},20000);
        return root.LittleLeafGoogleBinding.create({uid:user.uid,currentUid:()=>auth.currentUser?.uid,codec:root.LittleLeafAuthorityCodec,source:readLocalRecord,remote:target.remote,journal:target.journal,ownership:target.ownership});
      },
      continueCloud:async receipt=>{
        if(!receipt.cloudConfirmed || !target || auth.currentUser?.uid!==target.uid)throw Error('Account changed');
        target.ownership.assertActive();
        const ticket=target.ownership.reloadContinuation(receipt.digest,receipt.revision);
        if(!root.LittleLeafFirebaseSession.storeReload(storage,ticket))throw Error('Reload storage unavailable');
        storage.setItem(CLOUD_ONCE,JSON.stringify({uid:target.uid,cloudConfirmed:true}));
        release();root.location.reload();
      },resumeLocal:resume});
    root.LittleLeafLocalBinding=Object.freeze({open(callback){if(returned)return;returned=callback;void ui.open();},close(){ui.close();},snapshot(){return ui.snapshot?.() || {busy:returned!==null};}});
    root.LittleLeafCloudSettings=Object.freeze({snapshot(){const saved=JSON.parse(root.__littleLeafVault.bootJson || '{}');return JSON.stringify({status:saved.revision?'Saved':'Not saved',reason:'Local restaurant on '+root.location.origin+'. Bind Google without removing this device’s copy.',canSave:returned===null,reload:false,canBind:true,bindingBusy:returned!==null,local:true});},signOut(){},reload(){root.location.reload();}});
  }
  root.LittleLeafLocalGoogleEntry=Object.freeze({chooseMode,install,readLocalRecord});
})(globalThis);
