/* Server-authoritative single-writer handoff. No client-only ownership claim. */
(function(root){
  'use strict';
  const LEASE_MS=60000,HANDOFF_WAIT_MS=10000,RELOAD_MS=30000,RELOAD_KEY="little-leaf.reload-continuation.v1";
  const identifier=value=>typeof value==='string'&&/^[a-f0-9-]{36}$/i.test(value);
  function consumeReload(storage,navigationType,uid,now=Date.now()){
    try{const raw=storage.getItem(RELOAD_KEY);storage.removeItem(RELOAD_KEY);if(navigationType!=='reload'||!raw)return null;const value=JSON.parse(raw);
      return validReload(value,uid,now)?value:null;
    }catch(_){return null;}
  }
  function validReload(t,uid,time){return t?.schema===1&&t.uid===uid&&identifier(t.owner)&&identifier(t.nonce)&&Number.isSafeInteger(t.epoch)&&t.epoch>0&&Number.isSafeInteger(t.revision)&&t.revision>0&&/^[a-f0-9]{64}$/.test(t.digest||'')&&Number.isFinite(t.leaseAt)&&Number.isFinite(t.createdAt)&&Number.isFinite(t.expiresAt)&&t.expiresAt===t.createdAt+RELOAD_MS&&time>=t.createdAt&&time<=t.expiresAt;}
  function storeReload(storage,ticket){try{storage.setItem(RELOAD_KEY,JSON.stringify(ticket));return storage.getItem(RELOAD_KEY)===JSON.stringify(ticket);}catch(_){return false;}}
  const fail=(code,message)=>Object.assign(Error(message),{code});
  const millis=value=>typeof value?.toMillis==='function'?value.toMillis():Number(value);
  function createRemote(db,sdk,uid){
    const sessionRef=sdk.doc(db,'players',uid,'session','owner');
    const saveRef=sdk.doc(db,'players',uid,'saves','cafe');
    return {
      ref:sessionRef,
      async read(){const s=await sdk.getDocFromServer(sessionRef);return s.exists()?s.data():null;},
      async change(transition,guard){
        await sdk.runTransaction(db,async tx=>{
          guard();const snapshot=await tx.get(sessionRef),saved=await tx.get(saveRef);guard();
          const current=snapshot.exists()?snapshot.data():null;
          const next=transition(current,saved.exists()?saved.data():null,sdk.serverTimestamp);guard();
          if(next!==current)tx.set(sessionRef,next);
        });
        // Server-generated times must be read back, never inferred from local time.
        return this.read();
      },
      watch(receive,onError){return sdk.onSnapshot(sessionRef,{includeMetadataChanges:true},s=>{
        if(!s.metadata.fromCache && !s.metadata.hasPendingWrites)receive(s.exists()?s.data():null);
      },onError);}
    };
  }
  function createSession({remote,uid,currentUid,deviceLabel='Unknown device',sessionId=root.crypto.randomUUID(),now=Date.now,onChange=()=>{}}){
    let current=null,status='offline',closed=false,initialized=false,requestId=null,waitingSince=null,unsubscribe=null;
    const guard=()=>{if(closed||currentUid()!==uid)throw fail('NOT_READY','Account changed. Current progress remains paused.');};
    function receive(value){
      if(closed||currentUid()!==uid)return;
      current=value;initialized=true;
      if(!current)status='offline';
      else if(current.owner===sessionId)status=current.request?'handoff-requested':'active';
      else if(current.request?.requester===sessionId){requestId=current.request.id;waitingSince=millis(current.request.at);status=current.ack?'takeover-ready':'waiting';}
      else status='other-device';
      onChange(snapshot());
    }
    function snapshot(){
      const timedOut=status==='waiting'&&Number.isFinite(waitingSince)&&now()-waitingSince>=HANDOFF_WAIT_MS;
      return {serverOwnership:true,status:timedOut?'takeover-ready':status,ownershipPaused:status!=='active',
        canRequestTakeover:initialized&&['other-device','handoff-requested'].includes(status),canForceTakeover:timedOut,
        reason:status==='handoff-requested'?'Saving and pausing for another device.':status==='other-device'?'Your game was opened on another device.':status==='offline'?'Connection to save ownership is unavailable. Progress is paused.':status==='waiting'?'Waiting for the other device to save and pause.':''};
    }
    async function change(action){guard();const result=await remote.change(action,guard);guard();receive(result);return result;}
    function reloadContinuation(digest,revision){
      const fence=assertActive();
      if(!/^[a-f0-9]{64}$/.test(digest)||!Number.isSafeInteger(revision)||revision<1)throw fail('UPDATE_CHANGED','No confirmed save for reload.');
      const time=now();return {schema:1,uid,owner:fence.writerId,epoch:fence.writerEpoch,digest,revision,nonce:root.crypto.randomUUID(),leaseAt:millis(current.updatedAt),createdAt:time,expiresAt:time+RELOAD_MS};
    }
    async function continueReload(ticket){
      if(!validReload(ticket,uid,now()))return false;
      const matches=(value,save)=>value?.owner===ticket.owner&&value.epoch===ticket.epoch&&millis(value.updatedAt)===ticket.leaseAt&&save?.digest===ticket.digest&&save.revision===ticket.revision&&save.writerId===ticket.owner&&save.writerEpoch===ticket.epoch;
      try{
        // The receipt is not writer authority. Three existing rule-checked CAS
        // transitions consume the old epoch and grant a fresh runtime identity.
        await change((value,save,stamp)=>{
          if(!matches(value,save)||value.request||!validReload(ticket,uid,now()))throw fail('RELOAD_CHANGED','Reload continuation no longer matches.');
          return {...value,request:{id:ticket.nonce,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
        });
        await change((value,save)=>{
          if(!matches(value,save)||value.request?.id!==ticket.nonce||value.request.requester!==sessionId||value.ack)throw fail('RELOAD_CHANGED','Reload continuation changed.');
          // request.at and updatedAt both came from the server. A shifted local
          // clock cannot extend an expired server lease into a reload grant.
          if(millis(value.request.at)<ticket.leaseAt||millis(value.request.at)>=ticket.leaseAt+LEASE_MS||!validReload(ticket,uid,now()))throw fail('RELOAD_CHANGED','Reload continuation expired.');
          return {...value,ack:{requestId:ticket.nonce,digest:ticket.digest,revision:ticket.revision}};
        });
        await takeOver();return true;
      }catch(e){
        if(e.code==='RELOAD_CHANGED')return false;
        // A competing valid CAS can make Firestore reject a stale transition
        // with permission-denied rather than retrying it as a contention error.
        // Only an independently observed competing owner/request permits the
        // ordinary paused-device fallback; never mask a same-state rule failure.
        if(e.code==='permission-denied'){
          guard();const latest=await remote.read();guard();receive(latest);
          if(latest&&(latest.owner!==ticket.owner||latest.epoch!==ticket.epoch||latest.request&&latest.request.requester!==sessionId))return false;
        }
        throw e;
      }
    }
    async function start(reloadTicket=null){
      guard();if(reloadTicket)await continueReload(reloadTicket);
      await change((value,save,stamp)=>{
        if(value?.owner===sessionId)return {...value,updatedAt:stamp()};
        if(value && now()-millis(value.updatedAt)<LEASE_MS)return value;
        return {schema:1,owner:sessionId,epoch:value?value.epoch+1:1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
      });
      if(!unsubscribe)unsubscribe=remote.watch(receive,()=>{if(!closed){status='offline';onChange(snapshot());}});
      return snapshot();
    }
    function assertActive(allowHandoff=false){
      guard();
      if(!current || current.owner!==sessionId || status!=='active'&&!(allowHandoff&&status==='handoff-requested'&&!current.ack))throw fail('OWNERSHIP_LOST','Your game was opened on another device. Current changes stay on this device.');
      return {writerId:sessionId,writerEpoch:current.epoch};
    }
    async function renew(){
      guard();if(!current||current.owner!==sessionId)return snapshot();const epoch=current.epoch;
      try{await change((value,save,stamp)=>{if(value?.owner!==sessionId||value.epoch!==epoch)throw fail('OWNERSHIP_LOST','Another device owns this café.');return {...value,updatedAt:stamp()};});}
      catch(e){status='offline';onChange(snapshot());throw e;}return snapshot();
    }
    async function requestTakeover(){
      guard();requestId=root.crypto.randomUUID();
      await change((value,save,stamp)=>{
        if(!value)throw fail('OWNERSHIP_UNAVAILABLE','Save ownership is unavailable.');
        if(value.owner===sessionId)return {...value,updatedAt:stamp(),request:null,ack:null};
        if(value.request && value.request.requester!==sessionId)throw fail('HANDOFF_BUSY','Another device is already waiting. No progress was replaced.');
        if(value.request)return value;
        return {...value,request:{id:requestId,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
      });return snapshot();
    }
    async function acknowledge(digest,revision){
      const fence=assertActive(true),id=current.request?.id;
      if(!id)throw fail('HANDOFF_CHANGED','The device switch request changed.');
      await change((value,save)=>{
        if(save?.digest!==digest||save.revision!==revision)throw fail('HANDOFF_NOT_SAVED','The final cloud save has not been confirmed.');
        if(value?.owner!==sessionId||value.epoch!==fence.writerEpoch||value.request?.id!==id)throw fail('OWNERSHIP_LOST','The device switch changed before acknowledgment.');
        return {...value,ack:{requestId:id,digest,revision}};
      });return snapshot();
    }
    async function takeOver(force=false){
      guard();const id=current?.request?.id;
      await change((value,save,stamp)=>{
        if(value?.owner===sessionId)return value;
        if(!value||value.request?.requester!==sessionId||value.request.id!==id)throw fail('HANDOFF_CHANGED','The device switch request changed.');
        if(!value.ack&&!(force&&now()-millis(value.request.at)>=HANDOFF_WAIT_MS))throw fail('HANDOFF_WAITING','The other device has not confirmed its final save.');
        return {schema:1,owner:sessionId,epoch:value.epoch+1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
      });return snapshot();
    }
    return {start,snapshot,assertActive,renew,requestTakeover,acknowledge,takeOver,reloadContinuation,
      async refresh(){guard();receive(await remote.read());return snapshot();},
      get fence(){return assertActive(true);},get sessionRef(){return remote.ref;},
      close(){closed=true;status='offline';if(unsubscribe)unsubscribe();}};
  }
  root.LittleLeafFirebaseSession=Object.freeze({createRemote,createSession,LEASE_MS,HANDOFF_WAIT_MS,consumeReload,storeReload});
})(globalThis);
