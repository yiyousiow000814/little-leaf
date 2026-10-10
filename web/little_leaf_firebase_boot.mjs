import {initializeApp} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import {getAuth,getIdTokenResult,GoogleAuthProvider,signInWithRedirect,signInWithPopup,getRedirectResult,signOut,onAuthStateChanged,browserLocalPersistence,setPersistence} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js';
import {getFirestore,doc,getDocFromServer,runTransaction,serverTimestamp,onSnapshot} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';
export async function start(config,options={}) {
  const popup=options.surface==='trusted-itch-frame';
  if(options.surface!==undefined && !popup)throw Error('Unknown account entry surface.');
  if(options.authVerificationOnly!==undefined && (options.authVerificationOnly!==true || !popup))throw Error('Auth verification requires the trusted itch preview.');
  if(popup){
    // Options are baked into the reviewed own-origin preview, never supplied by its parent.
    const expected=options.runtimeOrigin;
    const prefix='https://'+config.projectId+'--itch-embed-test-';
    const suffix=typeof expected==='string' && expected.startsWith(prefix)?expected.slice(prefix.length):'';
    const ancestors=location.ancestorOrigins;
    if(!/^[a-z0-9]+\.web\.app$/.test(suffix) || location.origin!==expected || window.top===window.self
      || !ancestors || ancestors.length!==2 || ancestors[0]!=='https://html-classic.itch.zone'
      || ancestors[1]!=='https://siowyiyou.itch.io')throw Error('Open the approved itch preview page to sign in.');
  }else if(window.top!==window.self || location.hostname!==config.authDomain)throw Error('Open the full game on its Firebase Hosting address to sign in.');
  const app=initializeApp(config),auth=getAuth(app);
  if(options.authVerificationOnly===true)return verifyAuthOnly(auth);
  const db=getFirestore(app);
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
  const reasons={offline:'Offline. Progress on this device will sync when connected.',conflict:'Two saves need your choice. Open Help to review them.',blocked:'Saving is unavailable. Keep this page open and try again.'};
  function state(value){saveState=value;accountError='';label.textContent=primary[value] || 'Not saved';}
  window.LittleLeafCloudSettings=Object.freeze({
    snapshot(){return JSON.stringify({status:primary[saveState] || 'Not saved',reason:accountError || reasons[saveState] || '',reload:false,canSave:!['conflict','signed-out'].includes(saveState)});},
    signOut(){return button.onclick();},
    reload(){location.reload();}
  });
  button.textContent='Sign in with Google';label.textContent='Sign in to load your café across devices';
  button.onclick=async()=>{if(loginBusy)return;loginBusy=true;button.disabled=true;accountError='';try{if(auth.currentUser){if(!confirm('Sign out now? Changes not yet saved on this device may be lost. Cloud-pending saves stay on this device for this account.'))return;await signOut(auth);client?.close();window.LittleLeafUpdate?.close();location.reload();}else{startup('Opening Google sign-in…',true);await (popup?signInWithPopup:signInWithRedirect)(auth,new GoogleAuthProvider());if(!auth.currentUser)startup(signInPrompt,true);}}catch(e){if(auth.currentUser){accountError='Sign out did not finish. You are still signed in. Try again.';}else{state('signed-out');startup('Sign-in did not finish. Try Sign in with Google again.',true);}}finally{loginBusy=false;button.disabled=false;}};
  try {
    await setPersistence(auth,browserLocalPersistence);
    if(!popup)await getRedirectResult(auth);
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
  if(!window.LittleLeafFirebaseSession)throw Error('Device switching support is missing. Reload the full game package.');
  const deviceLabel=window.LittleLeafFirebase.genericDevice?.(window.navigator) || 'Unknown device';
  const sessionRemote=window.LittleLeafFirebaseSession.createRemote(db,{doc,getDocFromServer,runTransaction,serverTimestamp,onSnapshot},uid);
  const ownership=window.LittleLeafFirebaseSession.createSession({remote:sessionRemote,uid,deviceLabel,currentUid:()=>auth.currentUser?.uid});
  let reloadTicket=null;
  try{reloadTicket=window.LittleLeafFirebaseSession.consumeReload(window.sessionStorage,performance.getEntriesByType('navigation')[0]?.type,uid);}catch(_){}
  await ownership.start(reloadTicket);
  const remote=window.LittleLeafFirebase.createRemote(db,{doc,getDocFromServer,runTransaction},ownership);
  const journal=await window.LittleLeafFirebase.openJournal(indexedDB);
  client=window.LittleLeafFirebase.createClient({uid,codec:window.LittleLeafAuthorityCodec,remote,journal,ownership,deviceLabel,prepareReload:ticket=>{try{return window.LittleLeafFirebaseSession.storeReload(window.sessionStorage,ticket);}catch(_){return false;}},currentUid:()=>auth.currentUser?.uid,status:state});
  if(!window.LittleLeafUpdates || typeof window.LittleLeafUpdates.create!=='function')throw Error('Update support is missing. Reload the full game package.');
  window.LittleLeafUpdate=window.LittleLeafUpdates.create({checkUpdateReady:(...args)=>client.checkUpdateReady(...args),canReloadUpdate:(...args)=>client.canReloadUpdate(...args)});
  window.__littleLeafVault.close();window.__littleLeafVault=client;
  let recoveryBusy=false,recoveryMessage='',preparedChoice=null;
  const failure=code=>({ok:false,code,error:code==='REVISION_CONFLICT'?'Two different saves are available. Choose which progress to continue.':code==='RECOVERY_CHANGED'?'A save changed. Review both saves and choose again.':'Could not finish safely. Your progress is preserved. Keep this page open and try again.'});
  const sameAccount=()=>auth.currentUser?.uid===uid && !loginBusy;
  function recoverySnapshot(){
    const value=sameAccount() && typeof client.recoverySnapshot==='function'?client.recoverySnapshot():{};
    const digest=x=>/^[a-f0-9]{64}$/.test(x || '');
    const choices=Array.isArray(value.choices)?value.choices.filter(c=>['local','cloud'].includes(c.id)).map(c=>({
      id:c.id,coins:Number.isSafeInteger(c.coins)?c.coins:null,
      lastSavedAt:c.lastSavedAt,timeSource:c.timeSource,
      lastSavedLabel:Number.isFinite(c.lastSavedAt)?new Date(c.lastSavedAt).toLocaleString():'Unknown',
      device:typeof c.device==='string' && c.device?c.device:'Unknown device'
    })):[];
    const owner=sameAccount() && typeof client.ownershipSnapshot==='function'?client.ownershipSnapshot():{serverOwnership:false};
    return {...value,...owner,accountChanged:auth.currentUser?.uid!==uid,available:sameAccount() && owner.ownershipPaused!==true && value.choicesAvailable===true && digest(value.expectedLocalDigest) && digest(value.expectedCloudDigest) && choices.length===2,
      busy:recoveryBusy || value.busy===true,choices,
      reason:sameAccount()?(recoveryMessage || owner.reason || (typeof value.choiceReason==='string'?value.choiceReason:value.reason) || ''):'Account changed. Your current café is paused.'};
  }
  async function invoke(method,args,callback){
    if(recoveryBusy || !sameAccount() || typeof client[method]!=='function')return callback(JSON.stringify(failure('RECOVERY_UNAVAILABLE')));
    recoveryBusy=true;recoveryMessage='';let result;
    try{result=await client[method](...args);if(!sameAccount())throw Error('account changed');if(!result?.ok){result=failure(result?.code || 'RECOVERY_FAILED');recoveryMessage=result.error;}}
    catch(_){result=failure('RECOVERY_FAILED');recoveryMessage=result.error;}
    finally{recoveryBusy=false;}
    callback(JSON.stringify(result));
  }
  function prepareChoice(choice,localDigest,cloudDigest,callback){
    preparedChoice=null;
    return invoke('prepareChoice',[choice,localDigest,cloudDigest],raw=>{
      const result=JSON.parse(raw);
      if(result.ok)preparedChoice={choice,token:result.selectionToken};
      callback(raw);
    });
  }
  function confirmChoice(token,callback){
    if(!preparedChoice || preparedChoice.token!==token || !sameAccount())return callback(JSON.stringify(failure('RECOVERY_CHANGED')));
    const selected=preparedChoice.choice==='local'?'This device':'Cloud';
    if(!confirm('Keep '+selected+' save? This becomes your active café and will sync across devices. The other save will be kept in a protected recovery copy on this device.')){
      preparedChoice=null;return callback(JSON.stringify({ok:false,code:'RECOVERY_CANCELLED'}));
    }
    preparedChoice=null;return invoke('confirmChoice',[token],callback);
  }
  window.LittleLeafVault=Object.freeze({
    retry(){if(!recoveryBusy && saveState!=='conflict')location.reload();},
    recoverySnapshot(){return JSON.stringify(recoverySnapshot());},prepareChoice,confirmChoice,
    preserveRuntime(payload,revision,profileId,callback){return invoke('preserveRuntime',[payload,revision,profileId],callback);},
    preserveOwnerRuntime(payload,revision,profileId,callback){return invoke('preserveOwnerRuntime',[payload,revision,profileId],callback);},
    requestTakeover(callback){return invoke('requestTakeover',[],callback);},
    saveForUpdate(payload,revision,profileId,callback){return invoke('saveForUpdate',[payload,revision,profileId],callback);},
    checkUpdateReady(profileId,revision,token,callback){return invoke('checkUpdateReady',[profileId,revision,token],callback);},
    finishTakeover(callback){return invoke('finishTakeover',[false],callback);},
    forceTakeover(callback){
      const owner=recoverySnapshot();
      if(!owner.serverOwnership || !owner.canForceTakeover)return callback(JSON.stringify(failure('HANDOFF_WAITING')));
      if(!confirm('The other device has not confirmed its latest save. Continue with the last cloud save? Unsynced progress stays on the other device and may need your choice when it reconnects.'))return callback(JSON.stringify({ok:false,code:'RECOVERY_CANCELLED'}));
      return invoke('forceTakeover',[],callback);
    }
  });
  onAuthStateChanged(auth,user=>{if(user?.uid!==uid){client.close();window.LittleLeafUpdate?.close();state('signed-out');}});
  // A hard minimum interval bounds sustained play to <=120 writes/hour/account.
  // No unload upload: asynchronous unload completion cannot be promised.
  setInterval(()=>client.sync(),30000);
  setInterval(()=>client.renewOwnership?.(),20000);
  window.addEventListener('focus',()=>client.refreshOwnership?.());
  window.addEventListener('online',()=>client.sync());
  return client;
}

// Deliberately never resolves: the existing shell promise must not boot the vault/game.
// Firebase Auth persistence is permitted; no Firestore, journal or game APIs are used.
async function verifyAuthOnly(auth){
  const caption=document.getElementById('status-label'),progress=document.getElementById('status-progress');
  const panel=document.createElement('div');panel.id='auth-verification';panel.setAttribute('aria-live','polite');
  const result=document.createElement('p'),button=document.createElement('button');
  button.textContent='Verify Google sign-in';button.disabled=true;panel.append(result,button);(document.getElementById('auth-verification-slot') || document.body).append(panel);
  function status(text){
    // Presentation only: retain exact internal outcome text for the existing checks.
    const copy=text.startsWith('Google popup completed: Google authenticated.')?'Google sign-in confirmed.'
      :text.startsWith('Restored Firebase session: Google authenticated.')?'Google session restored. Verify a fresh sign-in below.'
      :text.startsWith('Firebase session changed: Google authenticated.')?'Google session updated. Verify a fresh sign-in below.'
      :text.startsWith('Signed out.')?'Ready when you are. Sign in with Google below.'
      :text.startsWith('Opening Google sign-in.')?'Choose your account in the Google popup.'
      :text.startsWith('Auth verification only.')?'Checking your sign-in…'
      :text.startsWith('Auth setup did not finish.')?'Sign-in setup did not finish. Reload this page to retry.'
      :text.includes('did not finish')?'Sign-in did not finish. Please try again.'
      :'Google sign-in could not be confirmed. Please try again.';
    result.textContent=copy;if(caption)caption.textContent=text;if(progress)progress.hidden=true;
  }
  status('Auth verification only. Game and saves are paused. Checking sign-in.');
  let busy=false,generation=0,shownUser=null;
  async function show(user,source,popupProvider=null){
    shownUser=user;
    const current=++generation;
    if(!user){status('Signed out. Verify Google sign-in; game and saves stay paused.');return;}
    try{
      const token=await getIdTokenResult(user);
      if(current!==generation || auth.currentUser!==user)return;
      const google=!user.isAnonymous && token.claims?.firebase?.sign_in_provider==='google.com'
        && (source!=='Google popup completed' || popupProvider==='google.com');
      status(source+': '+(google?'Google authenticated.':'Google authentication not verified.')+' Game and saves remain paused.');
    }catch(_){if(current===generation)status('Auth result could not be verified. Game and saves remain paused.');}
  }
  button.onclick=async()=>{
    if(busy)return;busy=true;button.disabled=true;status('Opening Google sign-in. Game and saves stay paused.');
    try{const credential=await signInWithPopup(auth,new GoogleAuthProvider());await show(credential.user,'Google popup completed',credential.providerId);}
    catch(_){status('Google sign-in did not finish. Game and saves remain paused. Try again.');}
    finally{busy=false;button.disabled=false;}
  };
  try{
    await setPersistence(auth,browserLocalPersistence);await auth.authStateReady();
    await show(auth.currentUser,'Restored Firebase session');
    onAuthStateChanged(auth,user=>{if(!busy && user!==shownUser)void show(user,'Firebase session changed');});
    button.disabled=false;
  }catch(_){status('Auth setup did not finish. Game and saves remain paused. Reload to retry.');}
  return new Promise(()=>{});
}
