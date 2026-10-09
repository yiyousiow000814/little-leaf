/* Server-authoritative single-writer handoff. No client-only ownership claim. */
(function(root){
  'use strict';
  const LEASE_MS=60000,HANDOFF_WAIT_MS=10000;
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
    async function start(){
      guard();await change((value,save,stamp)=>{
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
    return {start,snapshot,assertActive,renew,requestTakeover,acknowledge,takeOver,
      async refresh(){guard();receive(await remote.read());return snapshot();},
      get fence(){return assertActive(true);},get sessionRef(){return remote.ref;},
      close(){closed=true;status='offline';if(unsubscribe)unsubscribe();}};
  }
  root.LittleLeafFirebaseSession=Object.freeze({createRemote,createSession,LEASE_MS,HANDOFF_WAIT_MS});
})(globalThis);
