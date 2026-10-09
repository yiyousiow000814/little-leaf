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
  window.LittleLeafVault=Object.freeze({retry(){location.reload();}});
  onAuthStateChanged(auth,user=>{if(user?.uid!==uid){client.close();location.reload();}});
  // A hard minimum interval bounds sustained play to <=120 writes/hour/account.
  // No unload upload: asynchronous unload completion cannot be promised.
  setInterval(()=>client.sync(),30000);
  window.addEventListener('online',()=>client.sync());
  return client;
}
