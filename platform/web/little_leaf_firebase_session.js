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
  // Keep Firestore nanoseconds in the identity comparison. Millisecond rounding
  // must not hide a same-epoch cancellation/renewal within one millisecond.
  const stampIdentity=value=>value&&Number.isInteger(value.seconds)&&Number.isInteger(value.nanoseconds)
    ? `${value.seconds}:${value.nanoseconds}` : Number.isFinite(value)?String(value):null;
  function unchangedSession(a,b){
    return !!a&&!!b&&a.schema===1&&b.schema===1&&a.owner===b.owner&&a.epoch===b.epoch&&a.device===b.device
      &&a.request===null&&b.request===null&&a.ack===null&&b.ack===null
      &&stampIdentity(a.updatedAt)!==null&&stampIdentity(a.updatedAt)===stampIdentity(b.updatedAt);
  }
  function elapsedProof(anchor,before,sealed,probe){
    // The unique request ID binds a server timestamp to this exact transaction.
    // Renewal readback alone is insufficient: another renewal/cancellation can
    // replace updatedAt before its independent confirmation read completes.
    if(!unchangedSession(anchor,before)||!probe||!sealed||!unchangedSession(anchor,{...sealed,request:null})
      ||sealed.request?.id!==probe.id||sealed.request.requester!==probe.requester||sealed.request.device!==anchor.device)
      throw fail('ELAPSED_CHANGED','The background ownership interval changed. No elapsed progress was granted.');
    const start=millis(anchor.updatedAt),end=millis(sealed.request.at);
    if(!Number.isFinite(start)||!Number.isFinite(end)||end<start)throw fail('ELAPSED_TIME','Server elapsed time is unavailable.');
    // Only the original server lease is covered. A late same-owner renewal
    // establishes future authority; it never grants the expired tail.
    return {seconds:Math.min(end-start,LEASE_MS)/1000,discardedSeconds:Math.max(0,end-start-LEASE_MS)/1000,
      fromServerMs:start,toServerMs:Math.min(end,start+LEASE_MS),writerId:anchor.owner,writerEpoch:anchor.epoch};
  }
  function createRemote(db,sdk,uid){
    const sessionRef=sdk.doc(db,'players',uid,'session','owner');
    const saveRef=sdk.doc(db,'players',uid,'saves','cafe');
    const certificateRef=sdk.doc(db,'players',uid,'background','interval');
    return {
      ref:sessionRef,certificateRef,
      async readCertificate(){const s=await sdk.getDocFromServer(certificateRef);return s.exists()?s.data():null;},
      async changeCertificate(transition,guard){
        await sdk.runTransaction(db,async tx=>{
          guard();const owner=await tx.get(sessionRef),saved=await tx.get(saveRef),certificate=await tx.get(certificateRef);guard();
          const result=transition({session:owner.exists()?owner.data():null,save:saved.exists()?saved.data():null,certificate:certificate.exists()?certificate.data():null},sdk.serverTimestamp);guard();
          if(result.session)tx.set(sessionRef,result.session);
          if(result.certificate)tx.set(certificateRef,result.certificate);
        });
        return sdk.runTransaction(db,async tx=>{
          guard();const owner=await tx.get(sessionRef),certificate=await tx.get(certificateRef);guard();
          return {session:owner.exists()?owner.data():null,certificate:certificate.exists()?certificate.data():null};
        });
      },
      async read(){const s=await sdk.getDocFromServer(sessionRef);return s.exists()?s.data():null;},
      async change(transition,guard){
        await sdk.runTransaction(db,async tx=>{
          guard();const snapshot=await tx.get(sessionRef),saved=await tx.get(saveRef);guard();
          const current=snapshot.exists()?snapshot.data():null;
          const next=transition(current,saved.exists()?saved.data():null,sdk.serverTimestamp);guard();
          if(next!==current)tx.set(sessionRef,next);
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
  function createSession({remote,uid,currentUid,deviceLabel='Unknown device',sessionId=root.crypto.randomUUID(),now=Date.now,onChange=()=>{},elapsedStorage}){
    if(elapsedStorage===undefined){try{elapsedStorage=root.localStorage;}catch(_){elapsedStorage=null;}}
    let current=null,status='offline',closed=false,initialized=false,requestId=null,waitingSince=null,unsubscribe=null,requestGeneration=0;
    let elapsedWindow=null,elapsedGeneration=0,elapsedSeal=null,elapsedFenceTask=null;
    const guard=()=>{if(closed||currentUid()!==uid)throw fail('NOT_READY','Account changed. Current progress remains paused.');};

    const certificateKey='little-leaf.elapsed-certificate.v1:'+uid;
    const intentKey='little-leaf.elapsed-probe.v1:'+uid;
    function certificateIntent(){
      if(!elapsedStorage)return null;const raw=elapsedStorage.getItem(certificateKey);if(!raw)return null;
      const intent=JSON.parse(raw);
      if(intent.schema!==1||intent.uid!==uid||!identifier(intent.id)||!identifier(intent.owner)||!identifier(intent.profileId)||!Number.isSafeInteger(intent.epoch)||intent.epoch<1||typeof intent.anchorStamp!=='string'||!/^[a-f0-9]{64}$/.test(intent.baseDigest)||!Number.isSafeInteger(intent.baseRevision)||intent.baseRevision<1||!['starting','open','sealing','sealed'].includes(intent.phase))
        throw fail('ELAPSED_RECOVERY','Stored interval intent is damaged. It remains protected.');
      return intent;
    }
    function persistCertificate(intent){
      if(!elapsedStorage)throw fail('ELAPSED_STORAGE','Durable interval storage is unavailable.');
      elapsedStorage.setItem(certificateKey,JSON.stringify(intent));
      if(JSON.stringify(certificateIntent())!==JSON.stringify(intent))throw fail('ELAPSED_STORAGE','Interval intent could not be protected.');
    }
    function removeCertificate(intent){if(certificateIntent()?.id===intent.id)elapsedStorage.removeItem(certificateKey);}
    async function fenceCertificate(intent){
      // This transaction competes with seal/consume on the same certificate.
      // A confirmed terminal outcome fences all earlier retries, unlike a read.
      const result=await remote.changeCertificate(({certificate,session},stamp)=>{
        if(!certificate||certificate.id!==intent.id){
          // An absent document is not a terminal start result. Changing the
          // captured session anchor makes a still-running start retry/fail.
          if(session?.owner===intent.owner&&session.epoch===intent.epoch&&stampIdentity(session.updatedAt)===intent.anchorStamp)
            return {session:{...session,updatedAt:stamp()}};
          return {};
        }
        if(['consumed','cancelled'].includes(certificate.state))return {};
        return {certificate:{...certificate,state:'cancelled',resultDigest:null,resultRevision:null}};
      },guard);guard();
      if(result.certificate?.id===intent.id&&!['consumed','cancelled'].includes(result.certificate.state))
        throw fail('ELAPSED_UNCERTAIN','The interval has not been fenced.');
      receive(result.session);removeCertificate(intent);return result.certificate;
    }
    async function recoverCertificate(){const intent=certificateIntent();if(intent)await fenceCertificate(intent);}
    async function beginCertificate(base){
      if(certificateIntent())throw fail('ELAPSED_RECOVERY','An interrupted interval must be fenced before another save.');
      if(elapsedWindow)throw fail('ELAPSED_BUSY','An interval is already open.');
      const fence=assertActive(),id=root.crypto.randomUUID(),generation=elapsedGeneration;
      const intent={schema:1,id,uid,owner:fence.writerId,epoch:fence.writerEpoch,anchorStamp:stampIdentity(current.updatedAt),profileId:base.profileId,baseDigest:base.digest,baseRevision:base.revision,phase:'starting'};
      persistCertificate(intent);const window=elapsedWindow={token:id,state:'arming',generation};
      const operationGuard=()=>{guard();if(root.navigator?.onLine===false||elapsedWindow!==window||generation!==elapsedGeneration)throw fail('ELAPSED_CANCELLED','Interval cancelled.');};
      try{
        const result=await remote.changeCertificate(({session,save,certificate},stamp)=>{
          operationGuard();if(session?.owner!==fence.writerId||session.epoch!==fence.writerEpoch||stampIdentity(session.updatedAt)!==intent.anchorStamp||session.request!==null||session.ack!==null||save?.digest!==base.digest||save.revision!==base.revision||save.profileId!==base.profileId)
            throw fail('ELAPSED_CHANGED','Interval baseline changed.');
          if(certificate&&!['consumed','cancelled'].includes(certificate.state)&&certificate.epoch>=session.epoch)throw fail('ELAPSED_BUSY','An interval is unresolved.');
          const at=stamp();return {session:{...session,updatedAt:at},certificate:{schema:1,id,profileId:base.profileId,owner:session.owner,epoch:session.epoch,device:session.device,anchorAt:at,startAt:at,state:'open',baseDigest:base.digest,baseRevision:base.revision,endAt:null,resultDigest:null,resultRevision:null}};
        },operationGuard);operationGuard();
        const c=result.certificate;
        if(c?.id!==id||c.state!=='open'||!unchangedSession(result.session,{...result.session,updatedAt:c.anchorAt}))throw fail('ELAPSED_CHANGED','No exact interval confirmation.');
        receive(result.session);window.state='ready';window.certificate=c;
        persistCertificate({...intent,phase:'open'});return {token:id};
      }catch(e){status='offline';onChange(snapshot());throw e;}
    }
    async function finishCertificate(token){
      guard();const window=elapsedWindow;
      if(!window||window.token!==token||window.state!=='ready')throw fail('ELAPSED_CONSUMED','Interval unavailable or consumed.');
      const intent=certificateIntent();window.state='sealing';persistCertificate({...intent,phase:'sealing'});
      const operationGuard=()=>{guard();if(root.navigator?.onLine===false||elapsedWindow!==window||window.generation!==elapsedGeneration||status!=='active')throw fail('ELAPSED_CHANGED','Interval authority changed.');};
      try{
        const result=await remote.changeCertificate(({session,save,certificate},stamp)=>{
          operationGuard();const c=window.certificate;
          if(certificate?.id!==token||certificate.state!=='open'||!unchangedSession(session,{...session,owner:c.owner,epoch:c.epoch,device:c.device,updatedAt:c.anchorAt,request:null,ack:null})||save?.digest!==c.baseDigest||save.revision!==c.baseRevision||save.profileId!==c.profileId)
            throw fail('ELAPSED_CHANGED','Server interval changed.');
          const endAt=stamp();return {session:{...session,updatedAt:endAt},certificate:{...certificate,state:'sealed',endAt}};
        },operationGuard);operationGuard();
        const c=result.certificate;
        if(c?.id!==token||c.state!=='sealed'||stampIdentity(result.session.updatedAt)!==stampIdentity(c.endAt)||result.session.owner!==c.owner||result.session.epoch!==c.epoch||result.session.request||result.session.ack)
          throw fail('ELAPSED_CHANGED','No exact sealed confirmation.');
        const seconds=(millis(c.endAt)-millis(c.startAt))/1000;
        if(!Number.isFinite(seconds)||seconds<0)throw fail('ELAPSED_TIME','Invalid server duration.');
        receive(result.session);window.state='proved';persistCertificate({...intent,phase:'sealed'});
        return {token,certificateId:token,seconds,discardedSeconds:0,writerId:c.owner,writerEpoch:c.epoch,commitServerStamp:stampIdentity(result.session.updatedAt),baseDigest:c.baseDigest,baseRevision:c.baseRevision};
      }catch(e){status='offline';onChange(snapshot());throw e;}
    }
    function storedProbe(){if(!elapsedStorage)return null;const text=elapsedStorage.getItem(intentKey);return text?JSON.parse(text):null;}
    function persistProbe(intent){
      if(!elapsedStorage)throw fail('ELAPSED_STORAGE','Durable checkpoint storage is unavailable.');
      elapsedStorage.setItem(intentKey,JSON.stringify(intent));
      if(JSON.stringify(storedProbe())!==JSON.stringify(intent))throw fail('ELAPSED_STORAGE','Checkpoint intent could not be protected.');
    }
    function removeProbe(intent){if(storedProbe()?.id===intent.id)elapsedStorage.removeItem(intentKey);}
    async function recoverProbe(){
      const intent=storedProbe();if(!intent)return;
      const matches=value=>value?.owner===intent.owner&&value.epoch===intent.epoch&&value.device===intent.device
        &&stampIdentity(value.updatedAt)===intent.anchorStamp&&!value.ack&&value.request?.id===intent.id&&value.request.requester===intent.requester;
      const latest=await remote.read();guard();
      if(latest?.request?.id===intent.id&&latest.request.requester===intent.requester&&!matches(latest))
        throw fail('ELAPSED_RECOVERY','Interrupted checkpoint changed or was acknowledged. Progress stays paused; its request was not cleared.');
      if(matches(latest))await change((value,save,stamp)=>{
        if(!matches(value))throw fail('ELAPSED_CHANGED','Interrupted checkpoint changed; no request was cleared.');
        return {...value,updatedAt:stamp(),request:null,ack:null};
      });
      // Changed/real handoffs remain untouched. The abandoned interval earns zero.
      removeProbe(intent);
    }
    function receive(value){
      if(closed||currentUid()!==uid)return;
      // A server listener can deliver a queued pre-takeover observation after
      // the transaction's explicit server readback. Epochs only increase under
      // the rules: never regress a confirmed fence to an older epoch.
      if(current && value && value.epoch<current.epoch)return;
      current=value;initialized=true;
      if(!current)status='offline';
      else if(current.owner===sessionId)status=current.request&&!(elapsedSeal&&current.request.id===elapsedSeal.id
        &&current.request.requester===elapsedSeal.requester&&!current.ack)?'handoff-requested':'active';
      else if(current.request?.requester===sessionId){requestId=current.request.id;waitingSince=millis(current.request.at);status=current.ack?'takeover-ready':'waiting';}
      else status='other-device';
      const interrupted=storedProbe();
      if(!elapsedSeal&&interrupted&&current?.request?.id===interrupted.id&&current.request.requester===interrupted.requester
        &&current.owner===interrupted.owner&&current.epoch===interrupted.epoch)status='offline';
      if(status!=='active')elapsedGeneration++;
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
      guard();if(remote.changeCertificate)await recoverCertificate();await recoverProbe();if(reloadTicket)await continueReload(reloadTicket);
      await change((value,save,stamp)=>{
        if(value?.owner===sessionId)return {...value,updatedAt:stamp()};
        if(value && now()-millis(value.updatedAt)<LEASE_MS)return value;
        return {schema:1,owner:sessionId,epoch:value?value.epoch+1:1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
      });
      if(!unsubscribe)unsubscribe=remote.watch(receive,()=>{if(!closed){elapsedGeneration++;status='offline';onChange(snapshot());}});
      return snapshot();
    }
    function assertActive(allowHandoff=false){
      guard();
      if(!current || current.owner!==sessionId || status!=='active'&&!(allowHandoff&&status==='handoff-requested'&&!current.ack))throw fail('OWNERSHIP_LOST','Your game was opened on another device. Current changes stay on this device.');
      return {writerId:sessionId,writerEpoch:current.epoch};
    }
    async function renew(){
      // Do not erase an open interval's immutable server timestamp. Visible
      // reconciliation seals it through the existing rule-checked renewal.
      if(elapsedWindow)return snapshot();
      guard();if(!current||current.owner!==sessionId)return snapshot();const epoch=current.epoch;
      try{await change((value,save,stamp)=>{if(value?.owner!==sessionId||value.epoch!==epoch)throw fail('OWNERSHIP_LOST','Another device owns this café.');return {...value,updatedAt:stamp()};});}
      catch(e){
        // A renewal can race the acknowledged takeover. Read back a confirmed
        // competing owner rather than relabeling a valid fence as an outage.
        let fenced=false;
        if(e.code==='OWNERSHIP_LOST'||e.code==='permission-denied'){
          try{const observed=await remote.read();guard();if(observed && observed.owner!==sessionId){receive(observed);fenced=true;}}catch(_){/* Unconfirmed ownership remains paused offline. */}
        }
        if(!fenced){status='offline';onChange(snapshot());}throw e;
      }return snapshot();
    }
    async function beginElapsed(base){
      if(remote.changeCertificate)return beginCertificate(base);
      if(storedProbe())throw fail('ELAPSED_RECOVERY','An interrupted checkpoint must be recovered before another interval.');
      if(elapsedWindow)throw fail('ELAPSED_BUSY','An elapsed interval is already open.');
      const fence=assertActive(),token=root.crypto.randomUUID();
      const arming={token,state:'arming',generation:elapsedGeneration};elapsedWindow=arming;
      try{
        const anchor=await change((value,save,stamp)=>{
          if(value?.owner!==fence.writerId||value.epoch!==fence.writerEpoch||value.request!==null||value.ack!==null)
            throw fail('ELAPSED_CHANGED','Background ownership changed before its checkpoint.');
          return {...value,updatedAt:stamp()};
        });
        if(elapsedWindow!==arming||arming.generation!==elapsedGeneration||!unchangedSession(anchor,anchor)||status!=='active')throw fail('ELAPSED_CHANGED','No active server checkpoint.');
        elapsedWindow={token,state:'ready',anchor,generation:elapsedGeneration};return {token};
      }catch(e){if(elapsedWindow?.token===token)elapsedWindow=null;throw e;}
    }
    async function finishElapsed(token){
      if(remote.changeCertificate)return finishCertificate(token);
      guard();const window=elapsedWindow;
      if(!window||window.token!==token||window.state!=='ready')throw fail('ELAPSED_CONSUMED','Background interval is unavailable or already consumed.');
      // Consume before the network wait. Duplicate visibility/retry callbacks
      // cannot issue a second claim, including an uncertain transaction result.
      window.state='consumed';
      if(window.generation!==elapsedGeneration||status!=='active'){elapsedWindow=null;throw fail('ELAPSED_CHANGED','Background authority became unavailable.');}
      let before=null;const probe={id:token,requester:root.crypto.randomUUID()};
      const intent={...probe,owner:window.anchor.owner,epoch:window.anchor.epoch,device:window.anchor.device,anchorStamp:stampIdentity(window.anchor.updatedAt)};
      persistProbe(intent);elapsedSeal=probe;
      try{
        const sealed=await change((value,save,stamp)=>{
          if(window.generation!==elapsedGeneration||!unchangedSession(window.anchor,value))
            throw fail('ELAPSED_CHANGED','The server session changed during the background interval.');
          before=value;return {...value,request:{...probe,device:deviceLabel,at:stamp()}};
        });
        const proof=elapsedProof(window.anchor,before,sealed,probe);
        const requestAt=stampIdentity(sealed.request.at);
        const cleared=await change((value,save,stamp)=>{
          if(!unchangedSession(window.anchor,{...value,request:null})||value.request?.id!==probe.id
            ||value.request.requester!==probe.requester||stampIdentity(value.request.at)!==requestAt)
            throw fail('ELAPSED_CHANGED','The elapsed checkpoint changed before its request was cleared.');
          return {...value,updatedAt:stamp(),request:null,ack:null};
        });
        if(window.generation!==elapsedGeneration||status!=='active')throw fail('ELAPSED_CHANGED','Background authority changed before confirmation.');
        removeProbe(intent);return {...proof,token,commitServerStamp:stampIdentity(cleared.updatedAt)};
      }finally{elapsedWindow=null;if(storedProbe()?.id===intent.id){status='offline';onChange(snapshot());}elapsedSeal=null;}
    }
    function cancelElapsed(){
      elapsedGeneration++;elapsedWindow=null;
      const intent=remote.changeCertificate&&certificateIntent();
      if(elapsedSeal){elapsedSeal=null;status='offline';onChange(snapshot());}
      if(!intent)return Promise.resolve(snapshot());
      status='offline';onChange(snapshot());
      if(!elapsedFenceTask){
        elapsedFenceTask=fenceCertificate(intent).then(()=>snapshot()).finally(()=>{elapsedFenceTask=null;});
        // Fire-and-forget callers retain the durable intent on failure. Binding
        // callers can await the same terminal transaction; no second fence races.
        elapsedFenceTask.catch(()=>{});
      }
      return elapsedFenceTask;
    }
    function completeElapsed(token){const intent=certificateIntent();if(intent?.id===token)removeCertificate(intent);elapsedWindow=null;}
    const offlineListener=()=>{cancelElapsed();status='offline';onChange(snapshot());};
    root.addEventListener?.('offline',offlineListener);

    async function requestTakeover(){
      guard();const generation=++requestGeneration,id=root.crypto.randomUUID();requestId=id;
      const requestGuard=()=>{guard();if(generation!==requestGeneration)throw fail('REQUEST_CANCELLED','The device switch request was canceled. Progress remains paused.');};
      let attempted=null;
      const requestChange=async action=>{requestGuard();const result=await remote.change(action,requestGuard);requestGuard();receive(result);return result;};
      try {await requestChange((value,save,stamp)=>{
        attempted=null;
        if(!value)throw fail('OWNERSHIP_UNAVAILABLE','Save ownership is unavailable.');
        if(value.owner===sessionId)return {...value,updatedAt:stamp(),request:null,ack:null};
        // Explicit retry can recover an abandoned request after the server
        // lease expires. Rules, not the device clock, decide if it is expired.
        if(now()-millis(value.updatedAt)>=LEASE_MS)return {schema:1,owner:sessionId,epoch:value.epoch+1,device:deviceLabel,updatedAt:stamp(),request:null,ack:null};
        if(value.request && value.request.requester!==sessionId)throw fail('HANDOFF_BUSY','Another device is already waiting. No progress was replaced.');
        if(value.request)return value;
        attempted={owner:value.owner,epoch:value.epoch,device:value.device,updatedAt:millis(value.updatedAt)};
        return {...value,request:{id,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
      });}catch(error){
        requestGuard();
        // Firestore may reject a request racing an owner's renewal rather than
        // retrying its transaction. Permission denial alone is never retryable.
        if(error.code!=='permission-denied'||!attempted)throw error;
        const latest=await remote.read();requestGuard();
        const renewed=value=>value&&value.owner===attempted.owner&&value.epoch===attempted.epoch&&value.device===attempted.device
          &&Number.isFinite(attempted.updatedAt)&&Number.isFinite(millis(value.updatedAt))&&millis(value.updatedAt)>attempted.updatedAt&&value.request===null&&value.ack===null;
        if(!renewed(latest))throw error;
        const confirmedAt=millis(latest.updatedAt);
        // At most one fresh request transaction for the same explicit intent.
        // Never reuse the stale timestamp, acquire an expired lease or force
        // transfer here. A second race/denial stays paused for player retry.
        await requestChange((value,save,stamp)=>{
          requestGuard();if(!renewed(value)||millis(value.updatedAt)!==confirmedAt)throw fail('HANDOFF_CHANGED','The device switch changed. Review it and try again.');
          return {...value,request:{id,requester:sessionId,device:deviceLabel,at:stamp()},ack:null};
        });
      }return snapshot();
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
    return {start,snapshot,assertActive,renew,beginElapsed,finishElapsed,cancelElapsed,completeElapsed,
      get hasElapsedIntent(){return !!certificateIntent();},get certificateRef(){return remote.certificateRef;},requestTakeover,acknowledge,takeOver,reloadContinuation,
      async refresh(){guard();receive(await remote.read());return snapshot();},
      get fence(){return assertActive(true);},get sessionRef(){return remote.ref;},
      close(){cancelElapsed();requestGeneration++;closed=true;status='offline';root.removeEventListener?.('offline',offlineListener);if(unsubscribe)unsubscribe();}};
  }
  root.LittleLeafFirebaseSession=Object.freeze({createRemote,createSession,LEASE_MS,HANDOFF_WAIT_MS,consumeReload,storeReload,elapsedProof});
})(globalThis);
