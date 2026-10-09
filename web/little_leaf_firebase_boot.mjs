import {initializeApp} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import {getAuth,GoogleAuthProvider,signInWithRedirect,getRedirectResult,signOut,onAuthStateChanged,browserLocalPersistence,setPersistence} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js';
import {getFirestore,doc,getDocFromServer,runTransaction} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';
export async function start(config) {
  if(window.top!==window.self || location.hostname!==config.authDomain) throw Error('Open the full game on its Firebase Hosting address to sign in.');
  const app=initializeApp(config),auth=getAuth(app),db=getFirestore(app);
  const panel=document.createElement('div');panel.id='cloud-account';panel.setAttribute('aria-live','polite');
  panel.style.cssText='position:fixed;right:8px;top:8px;z-index:40;background:#fffaf0;color:#493d2e;border-radius:8px;padding:7px;font:12px Arial;max-width:80vw';
  const label=document.createElement('span'),button=document.createElement('button');button.disabled=true;button.style.marginLeft='8px';panel.append(label,button);document.body.append(panel);
  let client,uid,loginBusy=false;
  function startup(message,waiting=false){
    const caption=document.getElementById('status-label'),progress=document.getElementById('status-progress');
    if(caption)caption.textContent=message;
    if(progress)progress.hidden=waiting;
  }
  const signInPrompt='Sign in with Google to open your café.';
  startup('Checking your sign-in…');
  let saveState='ready',accountError='';
  const primary={ready:'Not saved',saved:'Saved',pending:'Saving…',offline:'Not saved',conflict:'Not saved',blocked:'Not saved','signed-out':'Not saved'};
  const reasons={offline:'Offline. Progress on this device will sync when connected.',conflict:'Another save changed. Your pending progress is preserved. Reload to review.',blocked:'Saving is unavailable. Keep this page open and try again.'};
  function state(value){saveState=value;accountError='';label.textContent=primary[value] || 'Not saved';}
  window.LittleLeafCloudSettings=Object.freeze({
    snapshot(){return JSON.stringify({status:primary[saveState] || 'Not saved',reason:accountError || reasons[saveState] || '',reload:saveState==='conflict',canSave:!['conflict','signed-out'].includes(saveState)});},
    signOut(){return button.onclick();},
    reload(){location.reload();}
  });
  button.textContent='Sign in with Google';label.textContent='Sign in to load your café across devices';
  button.onclick=async()=>{if(loginBusy)return;loginBusy=true;button.disabled=true;accountError='';try{if(auth.currentUser){if(!confirm('Sign out now? Changes not yet saved on this device may be lost. Cloud-pending saves stay on this device for this account.'))return;await signOut(auth);client?.close();location.reload();}else{startup('Opening Google sign-in…',true);await signInWithRedirect(auth,new GoogleAuthProvider());if(!auth.currentUser)startup(signInPrompt,true);}}catch(e){if(auth.currentUser){accountError='Sign out did not finish. You are still signed in. Try again.';}else{state('signed-out');startup('Sign-in did not finish. Try Sign in with Google again.',true);}}finally{loginBusy=false;button.disabled=false;}};
  try {
    await setPersistence(auth,browserLocalPersistence);
    await getRedirectResult(auth);
    await auth.authStateReady();
  } catch (_) {
    throw Error('Sign-in could not finish. Reload Little Leaf and try Sign in with Google again.');
  }
  button.disabled=false;
  if(!auth.currentUser){
    startup(signInPrompt,true);
    await new Promise(resolve=>{const stop=onAuthStateChanged(auth,user=>{if(user){stop();resolve();}});});
  }
  startup('Loading your saved café…');
  if(auth.currentUser.isAnonymous)throw Error('Sign in with Google for cross-device progress.');
  uid=auth.currentUser.uid;button.textContent='Sign out';panel.hidden=true;
  const remote=window.LittleLeafFirebase.createRemote(db,{doc,getDocFromServer,runTransaction});
  const journal=await window.LittleLeafFirebase.openJournal(indexedDB);
  client=window.LittleLeafFirebase.createClient({uid,codec:window.LittleLeafAuthorityCodec,remote,journal,currentUid:()=>auth.currentUser?.uid,status:state});
  window.__littleLeafVault.close();window.__littleLeafVault=client;
  let recoveryBusy=false,recoveryMessage='';
  const recoveryFailure=(code)=>({ok:false,code,error:code==='RECOVERY_CHANGED'?'The cloud café changed. Review the updated recovery details and confirm again.':code==='RECOVERY_ARCHIVE_FULL'?'A different pending café is already preserved. Export the recovery bundle for review. Exporting does not remove the backup or replace either café.':'Recovery could not finish. Your progress is unchanged. Keep this page open and try again.'});
  function recoverySnapshot(){
    const sameAccount=auth.currentUser?.uid===uid && !loginBusy;
    const value=sameAccount && typeof client.recoverySnapshot==='function'?client.recoverySnapshot():{};
    const verified=value?.available===true && /^[a-f0-9]{64}$/.test(value.expectedCloudDigest || '');
    return {available:verified && sameAccount,busy:recoveryBusy || value?.busy===true,
      canExport:sameAccount && value?.canExport===true,
      cloudRevision:Number.isSafeInteger(value?.cloudRevision)?value.cloudRevision:0,
      pendingRevision:Number.isSafeInteger(value?.pendingRevision)?value.pendingRevision:0,
      expectedCloudDigest:verified?value.expectedCloudDigest:'',
      reason:sameAccount?(recoveryMessage || (typeof value?.reason==='string'?value.reason:'')):'Account changed. Reload to load its progress.'};
  }
  async function recoverCloud(callback){
    const preview=recoverySnapshot();
    if(recoveryBusy || !preview.available || typeof client.recoverCloud!=='function')return callback(JSON.stringify(recoveryFailure('RECOVERY_UNAVAILABLE')));
    if(!confirm('Load cloud café (save '+preview.cloudRevision+') on this device? Your pending café will first be preserved in a local recovery copy. The cloud save will not be overwritten. You can export the pending café before continuing.'))return callback(JSON.stringify({ok:false,code:'RECOVERY_CANCELLED'}));
    recoveryBusy=true;recoveryMessage='';
    let result;
    try {
      if(auth.currentUser?.uid!==uid)throw Error('account changed');
      result=await client.recoverCloud(preview.expectedCloudDigest);
      if(auth.currentUser?.uid!==uid)throw Error('account changed');
      if(result?.ok!==true){result=recoveryFailure(result?.code || 'RECOVERY_FAILED');recoveryMessage=result.error;}
      else if(result.source!=='authority' || typeof result.profileId!=='string' || !result.profileId || !Number.isSafeInteger(result.revision) || result.revision<1 || typeof result.payload!=='string' || !result.payload){result=recoveryFailure('INVALID_ACK');recoveryMessage=result.error;}
      else recoveryMessage=''; // Native validation owns the final loaded acknowledgment.
    }catch(_){result=recoveryFailure('RECOVERY_FAILED');recoveryMessage=result.error;}
    finally{recoveryBusy=false;}
    callback(JSON.stringify(result));
  }
  async function exportRecovery(callback){
    const preview=recoverySnapshot();
    if(recoveryBusy || !preview.canExport || typeof client.exportRecovery!=='function')return callback(JSON.stringify(recoveryFailure('RECOVERY_UNAVAILABLE')));
    recoveryBusy=true;recoveryMessage='';let result;
    try {
      const exported=await client.exportRecovery();
      if(auth.currentUser?.uid!==uid || !exported?.ok || typeof exported.text!=='string' || !exported.text)throw Error('export unavailable');
      const url=URL.createObjectURL(new Blob([exported.text],{type:'application/json'}));
      const link=document.createElement('a');link.href=url;link.download='little-leaf-pending-cafe.json';link.hidden=true;document.body.append(link);link.click();link.remove();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
      recoveryMessage='Pending café export prepared.';result={ok:true,message:recoveryMessage};
    }catch(_){result=recoveryFailure('RECOVERY_EXPORT_FAILED');recoveryMessage=result.error;}
    finally{recoveryBusy=false;}
    callback(JSON.stringify(result));
  }
  window.LittleLeafVault=Object.freeze({retry(){if(!recoveryBusy)location.reload();},recoverySnapshot(){return JSON.stringify(recoverySnapshot());},recoverCloud,exportRecovery});
  onAuthStateChanged(auth,user=>{if(user?.uid!==uid){client.close();location.reload();}});
  // A hard minimum interval bounds sustained play to <=120 writes/hour/account.
  // No unload upload: asynchronous unload completion cannot be promised.
  setInterval(()=>client.sync(),30000);
  window.addEventListener('online',()=>client.sync());
  return client;
}
