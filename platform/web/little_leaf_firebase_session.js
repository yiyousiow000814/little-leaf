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
  function timestamp(value){
    if(typeof value==='number')return Number.isFinite(value)?[value]:null;
    if(!value||typeof value!=='object')return null;
    const seconds=value.seconds,nanoseconds=value.nanoseconds;
    return Number.isSafeInteger(seconds)&&Number.isInteger(nanoseconds)&&nanoseconds>=0&&nanoseconds<1000000000?[seconds,nanoseconds]:null;
  }
  function compareTimestamp(a,b){
    if(!a||!b||a.length!==b.length)return null;
    for(let i=0;i<a.length;i++)if(a[i]!==b[i])return a[i]>b[i]?1:-1;
    return 0;
  }
  // A reload may retain this tab's writer ID only while its exclusive browser
  // lock is held. Copied sessionStorage alone never grants writer authority.
  async function acquireRuntime({uid,storage,locks,navigationType,fresh=false}){
    const key='little-leaf.runtime-session.v1';
    let sessionId=root.crypto.randomUUID();
    if(!locks?.request)return {sessionId,assertHeld(){},close(){}};
    try{
      const value=JSON.parse(storage.getItem(key));
      if(!fresh&&navigationType==='reload'&&value?.schema===1&&value.uid===uid&&identifier(value.sessionId))sessionId=value.sessionId;
    }catch(_){/* Storage unavailable: acquire a fresh, non-continuing identity. */}
    let held=false,closed=false,release;
    const lifetime=new Promise(resolve=>{release=resolve;});
    let acquired,rejected;
    const ready=new Promise((resolve,reject)=>{acquired=resolve;rejected=reject;});
    const task=locks.request('little-leaf.runtime:'+uid+':'+sessionId,{mode:'exclusive',ifAvailable:true},async lock=>{
      if(!lock){rejected(fail('SAVE_BUSY','This tab is still closing. Progress remains paused.'));return;}
      held=true;acquired();
      try{await lifetime;}finally{held=false;}
    });
    Promise.resolve(task).catch(error=>{held=false;rejected(error);});
    await ready;
    try{storage.setItem(key,JSON.stringify({schema:1,uid,sessionId}));}catch(_){/* No continuity receipt; next boot uses a fresh identity. */}
    return {sessionId,
      assertHeld(){if(!held||closed)throw fail('NOT_READY','This runtime has closed. Progress remains paused.');},
      close(){closed=true;release();}
    };
  }
  function createRemote(db,sdk,uid){
    const sessionRef=sdk.doc(db,'players',uid,'session','owner');
    const saveRef=sdk.doc(db,'players',uid,'saves','cafe');
    return {
      ref:sessionRef,
      async read(){const s=await sdk.getDocFromServer(sessionRef);return s.exists()?s.data():null;},
      async change(transition,guard,ackOnly=false){
        await sdk.runTransaction(db,async tx=>{
          guard();const snapshot=await tx.get(sessionRef),saved=await tx.get(saveRef);guard();
          const current=snapshot.exists()?snapshot.data():null;
          const next=transition(current,saved.exists()?saved.data():null,sdk.serverTimestamp);guard();
          if(next!==current){
            // ACK does not renew the lease. Preserve a concurrent renewal's
            // timestamp; the transaction still fences both owner and save reads.
            if(ackOnly)tx.update(sessionRef,{ack:next.ack});
            // A new ASK changes only the request. Preserve a concurrent lease
            // renewal, while keeping the original transaction read precondition.
            else if(current?.request===null&&current.ack===null&&next.request
              &&Object.keys(next).length===Object.keys(current).length
              &&Object.keys(current).every(key=>Object.hasOwn(next,key)&&(key==='request'||next[key]===current[key])))tx.update(sessionRef,{request:next.request});
            else tx.set(sessionRef,next);
          }
        });
        // Confirm through a server transaction read, independent of queued
        // document-listener/cache observations. This second transaction has
        // no writes and cannot grant a fence from the intended local value.
        return sdk.runTransaction(db,async tx=>{
          guard();const confirmed=await tx.get(sessionRef);guard();
          return confirmed.exists()?confirmed.data():null;
        });
      },
      watch(receive,onError){return sdk.onSnapshot(sessionRef,{includeMetadataChanges:true},s=>{
        if(!s.metadata.fromCache && !s.metadata.hasPendingWrites)receive(s.exists()?s.data():null);
      },onError);}
    };
  }
  function createSession({remote,uid,currentUid,deviceLabel='Unknown device',sessionId=root.crypto.randomUUID(),now=Date.now,onChange=()=>{},assertRuntime=()=>{}}){
    let current=null,status='offline',closed=false,initialized=false,requestId=null,waitingSince=null,unsubscribe=null,requestGeneration=0,pendingRenewal=null,renewalGeneration=0;
    const guard=()=>{assertRuntime();if(closed||currentUid()!==uid)throw fail('NOT_READY','Account changed. Current progress remains paused.');};
    function receive(value){
      if(closed||currentUid()!==uid)return;
      // A server listener can deliver a queued pre-takeover observation after
      // the transaction's explicit server readback. Epochs only increase under
      // the rules: never regress a confirmed fence to an older epoch.
      if(current && value && value.epoch<current.epoch)return;
      // Restoring an earlier key (A -> B -> A) does not revive its old work.
      if(renewalKey(current)!==renewalKey(value))renewalGeneration++;
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
    async function change(action,ackOnly=false){guard();const result=await remote.change(action,guard,ackOnly);guard();receive(result);return result;}
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
    function handoffReceipt(){
      const fence=assertActive(true);
      if(!current.request)throw fail('HANDOFF_CHANGED','The device switch request changed.');
      return Object.freeze({...fence,requestId:current.request.id,requester:current.request.requester});
    }
    const sameHandoff=(value,receipt)=>value?.owner===receipt.writerId&&value.epoch===receipt.writerEpoch&&value.request?.id===receipt.requestId&&value.request.requester===receipt.requester;
    function assertHandoff(receipt){
      assertActive(true);
      if(!sameHandoff(current,receipt))throw fail('HANDOFF_CHANGED','The device switch request changed.');
    }
    async function confirmHandoff(receipt,digest,revision){
      guard();const value=await remote.read();guard();receive(value);
      if(value?.owner===receipt.requester&&value.epoch===receipt.writerEpoch+1&&value.request===null&&value.ack===null)return 'transferred';
      if(!sameHandoff(value,receipt))throw fail('HANDOFF_CHANGED','The device switch request changed.');
      if(value.ack===null)return 'pending';
      if(value.ack.requestId===receipt.requestId&&value.ack.digest===digest&&value.ack.revision===revision)return 'acknowledged';
      throw fail('HANDOFF_CHANGED','The device switch acknowledgment changed.');
    }
    function renewalKey(value){
      const at=value?.request?.at;
      const stamp=Number.isInteger(at?.seconds)&&Number.isInteger(at?.nanoseconds)?[at.seconds,at.nanoseconds]:at;
      return JSON.stringify([value?.schema,value?.owner,value?.epoch,value?.device,
        value?.request?[value.request.id,value.request.requester,value.request.device,stamp]:null,
        value?.ack?[value.ack.requestId,value.ack.digest,value.ack.revision]:null]);
    }
    async function renew(){
      guard();if(!current||current.owner!==sessionId)return snapshot();const epoch=current.epoch,key=renewalKey(current),generation=renewalGeneration;
      const renewalGuard=()=>{
        guard();if(current?.owner!==sessionId||current.epoch!==epoch)throw fail('OWNERSHIP_LOST','Another device owns this café.');
        if(renewalGeneration!==generation||renewalKey(current)!==key)throw fail('HANDOFF_CHANGED','The device switch changed during renewal.');
      };
      renewalGuard();
      let work=pendingRenewal;
      if(!work||work.key!==key||work.generation!==generation){
        work={key,generation};pendingRenewal=work;
        const operationGuard=()=>{renewalGuard();if(pendingRenewal!==work)throw fail('HANDOFF_CHANGED','This renewal was superseded.');};
        const stillCurrent=()=>{try{operationGuard();return true;}catch(_){return false;}};
        work.promise=(async()=>{
          try{
            const result=await remote.change((value,save,stamp)=>{
              operationGuard();if(value?.owner!==sessionId||value.epoch!==epoch)throw fail('OWNERSHIP_LOST','Another device owns this café.');
              if(renewalKey(value)!==key)throw fail('HANDOFF_CHANGED','The device switch changed during renewal.');
              return {...value,updatedAt:stamp()};
            },operationGuard);
            operationGuard();
            // A held confirmation response cannot publish an older same-epoch
            // request/ACK over a newer server-confirmed local observation.
            if(renewalKey(result)!==key)throw fail('HANDOFF_CHANGED','The confirmed renewal intent changed.');
            receive(result);
          }catch(e){
            let fenced=false;
            if(stillCurrent()&&(e.code==='OWNERSHIP_LOST'||e.code==='permission-denied')){
              try{const observed=await remote.read();guard();if(stillCurrent()&&observed&&renewalKey(observed)!==key){receive(observed);fenced=true;}}
              catch(_){/* Unconfirmed ownership remains paused offline. */}
            }
            if(!fenced&&stillCurrent()){status='offline';onChange(snapshot());}throw e;
          }finally{if(pendingRenewal===work)pendingRenewal=null;}
        })();
      }
      try{await work.promise;}catch(e){
        // Rejected shared work grants no authority. Check this caller again,
        // retaining the original permission/network failure rather than masking it.
        try{renewalGuard();}catch(_){/* The caller still rejects the shared failure. */}throw e;
      }
      renewalGuard();return snapshot();
    }
    async function requestTakeover(){
      guard();const generation=++requestGeneration,id=root.crypto.randomUUID();requestId=id;
      const requestGuard=()=>{guard();if(generation!==requestGeneration)throw fail('REQUEST_CANCELLED','The device switch request was canceled. Progress remains paused.');};
      let attempted=null,target=null;
      const requestChange=async action=>{requestGuard();const result=await remote.change(action,requestGuard);requestGuard();receive(result);return result;};
      try {await requestChange((value,save,stamp)=>{
        attempted=null;
        if(!value)throw fail('OWNERSHIP_UNAVAILABLE','Save ownership is unavailable.');
        if(target&&(value.owner!==target.owner||value.epoch!==target.epoch||value.device!==target.device))throw fail('HANDOFF_CHANGED','The requested device changed. Review it and try again.');
        if(value.owner===sessionId)return {...value,updatedAt:stamp(),request:null,ack:null};
        // Explicit retry can recover an abandoned request after the server
        // lease expires. Rules, not the device clock, decide if it is expired.
        if(!target&&now()-millis(value.updatedAt)>=LEASE_MS)return {schema:1,owner:sessionId,epoch:value.epoch+1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
        if(value.request && value.request.requester!==sessionId)throw fail('HANDOFF_BUSY','Another device is already waiting. No progress was replaced.');
        if(value.request)return value;
        // SDK contention retries retain the first ASK's target and operation;
        // a renewal may advance its lease, but cannot turn it into a takeover.
        if(!target)target={owner:value.owner,epoch:value.epoch,device:value.device};
        attempted={owner:value.owner,epoch:value.epoch,device:value.device,updatedAt:timestamp(value.updatedAt)};
        return {...value,request:{id,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
      });}catch(error){
        requestGuard();
        // Firestore may reject a request racing an owner's renewal rather than
        // retrying its transaction. Permission denial alone is never retryable.
        if(error.code!=='permission-denied'||!attempted)throw error;
        const latest=await remote.read();requestGuard();
        const renewed=value=>value&&value.owner===attempted.owner&&value.epoch===attempted.epoch&&value.device===attempted.device
          &&compareTimestamp(timestamp(value.updatedAt),attempted.updatedAt)===1&&value.request===null&&value.ack===null;
        if(!renewed(latest))throw error;
        const confirmedAt=timestamp(latest.updatedAt);
        // At most one fresh request transaction for the same explicit intent.
        // Never reuse the stale timestamp, acquire an expired lease or force
        // transfer here. A second race/denial stays paused for player retry.
        await requestChange((value,save,stamp)=>{
          requestGuard();if(!renewed(value)||compareTimestamp(timestamp(value.updatedAt),confirmedAt)!==0)throw fail('HANDOFF_CHANGED','The device switch changed. Review it and try again.');
          return {...value,request:{id,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
        });
      }return snapshot();
    }
    async function acknowledge(digest,revision,expected=null){
      const fence=assertActive(true),id=current.request?.id;
      if(!id)throw fail('HANDOFF_CHANGED','The device switch request changed.');
      if(expected)assertHandoff(expected);
      // Compare server timestamps without reducing them to milliseconds. A
      // fresh transaction may only recover an independently observed renewal
      // of this exact owner, request and final save; denial alone is no proof.
      const compareStamp=(a,b)=>{
        if(Number.isInteger(a?.seconds)&&Number.isInteger(a?.nanoseconds)&&Number.isInteger(b?.seconds)&&Number.isInteger(b?.nanoseconds))
          return Math.sign(a.seconds-b.seconds)||Math.sign(a.nanoseconds-b.nanoseconds);
        return typeof a==='number'&&Number.isFinite(a)&&typeof b==='number'&&Number.isFinite(b)?Math.sign(a-b):NaN;
      };
      const sameRequest=(a,b)=>a&&b&&a.id===b.id&&a.requester===b.requester&&a.device===b.device&&compareStamp(a.at,b.at)===0;
      const nextAck=(value,save)=>{
        if(save?.digest!==digest||save.revision!==revision||save.writerId!==fence.writerId||save.writerEpoch!==fence.writerEpoch)throw fail('HANDOFF_NOT_SAVED','The final cloud save has not been confirmed.');
        if(value?.owner!==sessionId||value.epoch!==fence.writerEpoch||value.request?.id!==id)throw fail('OWNERSHIP_LOST','The device switch changed before acknowledgment.');
        if(expected&&!sameHandoff(value,expected))throw fail('HANDOFF_CHANGED','The device switch request changed.');
        if(value.ack!==null)throw fail('HANDOFF_CHANGED','The device switch acknowledgment changed.');
        return {...value,ack:{requestId:id,digest,revision}};
      };
      let attempted=null;
      try {await change((value,save)=>{
        attempted=null;const next=nextAck(value,save);
        attempted={...value,request:{...value.request}};return next;
      },true);}catch(error){
        guard();if(error.code!=='permission-denied'||!attempted)throw error;
        const latest=await remote.read();guard();
        const renewed=value=>value&&value.schema===attempted.schema&&value.owner===attempted.owner&&value.epoch===attempted.epoch&&value.device===attempted.device
          &&sameRequest(value.request,attempted.request)&&value.ack===null&&compareStamp(value.updatedAt,attempted.updatedAt)>0;
        if(!renewed(latest))throw error;
        const confirmedAt=latest.updatedAt;
        // One fresh CAS only. A second race, changed request/save, account
        // change or uncertain outcome remains paused with the durable journal.
        await change((value,save)=>{
          if(!renewed(value)||compareStamp(value.updatedAt,confirmedAt)!==0)throw fail('HANDOFF_CHANGED','The device switch changed. Progress remains paused.');
          return nextAck(value,save);
        },true);
      }return snapshot();
    }
    async function takeOver(force=false){
      guard();const id=current?.request?.id,generation=requestGeneration;
      // Retain only this acknowledged intent, not permission to take a newer
      // owner's café. A transient response failure gets one proven retry.
      const expected=current&&{owner:current.owner,epoch:current.epoch,
        request:current.request&&{...current.request,at:timestamp(current.request.at)},ack:current.ack&&{...current.ack}};
      const takeoverGuard=()=>{guard();if(generation!==requestGeneration)throw fail('HANDOFF_CHANGED','The device switch request changed.');};
      const sameIntent=value=>expected?.ack&&value?.owner===expected.owner&&value.epoch===expected.epoch
        &&value.request?.id===expected.request?.id&&value.request?.requester===sessionId&&value.request.device===expected.request.device
        &&compareTimestamp(timestamp(value.request.at),expected.request.at)===0
        &&value.ack?.requestId===expected.ack.requestId&&value.ack?.digest===expected.ack.digest&&value.ack?.revision===expected.ack.revision;
      const committed=value=>expected?.ack&&value?.owner===sessionId&&value.epoch===expected.epoch+1
        &&value.device===deviceLabel&&value.request===null&&value.ack===null;
      const perform=async retry=>{
        const result=await remote.change((value,save,stamp)=>{
          takeoverGuard();
          if(retry&&!sameIntent(value)&&!committed(value))throw fail('HANDOFF_CHANGED','The acknowledged device switch changed. Progress remains paused.');
          if(value?.owner===sessionId)return value;
          if(!value||value.request?.requester!==sessionId||value.request.id!==id)throw fail('HANDOFF_CHANGED','The device switch request changed.');
          if(!value.ack&&!(force&&now()-millis(value.request.at)>=HANDOFF_WAIT_MS))throw fail('HANDOFF_WAITING','The other device has not confirmed its final save.');
          return {schema:1,owner:sessionId,epoch:value.epoch+1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
        },takeoverGuard);
        takeoverGuard();receive(result);return snapshot();
      };
      try{return await perform(false);}catch(error){
        takeoverGuard();
        if(force||!expected?.ack||!['OFFLINE','NETWORK_TIMEOUT','unavailable','deadline-exceeded'].includes(error.code))throw error;
        const latest=await remote.read();takeoverGuard();
        // Read back an uncertain success before issuing another transaction.
        // Only the exact next epoch without a subsequent request can resume.
        if(committed(latest)){receive(latest);return snapshot();}
        if(!sameIntent(latest))throw fail('HANDOFF_CHANGED','The acknowledged device switch changed. Progress remains paused.');
        return perform(true);
      }
    }
    return {start,snapshot,assertActive,renew,requestTakeover,acknowledge,takeOver,reloadContinuation,handoffReceipt,assertHandoff,confirmHandoff,
      async refresh(){guard();receive(await remote.read());return snapshot();},
      get fence(){return assertActive(true);},get sessionRef(){return remote.ref;},
      close(){requestGeneration++;closed=true;status='offline';if(unsubscribe)unsubscribe();}};
  }
  root.LittleLeafFirebaseSession=Object.freeze({createRemote,createSession,LEASE_MS,HANDOFF_WAIT_MS,consumeReload,storeReload,acquireRuntime});
})(globalThis);
