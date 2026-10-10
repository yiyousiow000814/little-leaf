/* Optional Firebase vault. No default Web/CG database is opened or migrated. */
(function(root) {
  'use strict';
  const MAX_BYTES = 900000; // leaves >140 KiB for Firestore document/path overhead
  const error = (code, message) => Object.assign(new Error(message), {code});
  const failure = e => ({ok:false, code:e.code || 'CLOUD_ERROR', error:e.message});
  const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
  const recoveryBackupKey = uid => ['recovery-v1',uid];
  const choiceBackupKey = uid => ['choice-v1',uid];
  const DEVICE_LABELS = ['Unknown device','iPhone','iPad','Android device','Mac','Windows PC','ChromeOS device','Linux device'];
  const displayDevice=value=>DEVICE_LABELS.includes(value)?value:'Unknown device';
  // Coarse platform description only: never store a full UA, ID or location.
  function genericDevice(navigator) {
    const ua=String(navigator?.userAgent || ''),platform=String(navigator?.platform || '');
    if(/iPad/.test(ua) || platform==='MacIntel' && navigator?.maxTouchPoints>1)return 'iPad';
    if(/iPhone/.test(ua))return 'iPhone';
    if(/Android/.test(ua))return 'Android device';
    if(/CrOS/.test(ua))return 'ChromeOS device';
    if(/Win/.test(platform))return 'Windows PC';
    if(/Mac/.test(platform))return 'Mac';
    if(/Linux/.test(platform))return 'Linux device';
    return 'Unknown device';
  }
  const offline = e => ['unavailable','deadline-exceeded','resource-exhausted','OFFLINE','NETWORK_TIMEOUT'].includes(e.code);
  function capacity(record) {
    const text = JSON.stringify(record);
    if (new TextEncoder().encode(text).length > MAX_BYTES) throw error('SAVE_TOO_LARGE','This café exceeds the cloud save limit. Previous progress is unchanged.');
    return text;
  }
  function createRemote(db, sdk, ownership=null) {
    const ref=uid=>sdk.doc(db,'players',uid,'saves','cafe');
    return {
      async read(uid) { const snapshot=await sdk.getDocFromServer(ref(uid));return snapshot.exists()?snapshot.data():null; },
      async compareAndSet(uid,base,next,guard,elapsedFence=null) {
        await sdk.runTransaction(db,async tx=>{
          guard();let fence=null;
          if(ownership){
            fence=ownership.assertActive(true);
            const ownerSnapshot=await tx.get(ownership.sessionRef),owner=ownerSnapshot.exists()?ownerSnapshot.data():null;
            if(!owner||owner.owner!==fence.writerId||owner.epoch!==fence.writerEpoch||owner.ack)throw error('OWNERSHIP_LOST','Your game was opened on another device.');
            if(elapsedFence){
              const stamp=owner.updatedAt&&Number.isInteger(owner.updatedAt.seconds)&&Number.isInteger(owner.updatedAt.nanoseconds)
                ? `${owner.updatedAt.seconds}:${owner.updatedAt.nanoseconds}` : String(owner.updatedAt);
              if(owner.request!==null||owner.owner!==elapsedFence.writerId||owner.epoch!==elapsedFence.writerEpoch||stamp!==elapsedFence.commitServerStamp)
                throw error('ELAPSED_CHANGED','Background authority changed before its snapshot commit.');
            }
          }
          const snapshot=await tx.get(ref(uid)),old=snapshot.exists()?snapshot.data():null;guard();
          if(old?.digest===next.digest)return;
          if((old?.digest || null)!==base)throw error('REVISION_CONFLICT','Another device has newer progress. Pending progress is preserved.');
          tx.set(ref(uid),fence?{...next,...fence}:next);
        });
      }
    };
  }
  function createClient({uid, codec, remote, journal, currentUid, status, now=Date.now, deviceLabel=genericDevice(root.navigator),ownership=null,networkTimeoutMs=15000,prepareReload=null}) {
    let entry, opened, busy=false, syncing=false, bootReady=false, stopped=false, closed=false, lastAttempt=-Infinity;
    let recovery=null, recoveryBackup=null, recoveryBusy=false, recoveredDigest=null, recoveredRevision=null, pendingExport=null, backupProblem='';
    let choiceArchive=null,choiceProblem='',choiceOperation=null,handoffMode=false,uploadTask=null,updateTicket=null,updateInProgress=false;
    const savedDevice=displayDevice(deviceLabel),recordDevices=new Map();
    let localQueue=Promise.resolve();
    let elapsedClaim=null;
    function elapsedGuard(claim){guard();if(elapsedClaim!==claim||claim.cancelled)throw error('ELAPSED_CANCELLED','Background interval was cancelled.');}
    function clearElapsed(claim){if(elapsedClaim===claim){elapsedClaim=null;ownership?.cancelElapsed?.();}}
    // Network waits never hold this queue. Only local journal transitions serialize.
    function serial(action) { const result=localQueue.then(action);localQueue=result.catch(()=>{});return result; }
    const accountGuard = () => { if(closed || currentUid() !== uid) throw error('NOT_READY','Account changed. Reload to load its progress.'); };
    const ordinaryWriteGuard=()=>{accountGuard();if(elapsedClaim||entry?.elapsedPending)throw error('ELAPSED_UNCERTAIN','The exact background intent must be reconciled before another save.');};
    const recoveryRecord=local=>local?.elapsedPending?.record || local?.record;
    const guard = () => { accountGuard(); if(ownership)ownership.assertActive(handoffMode); if(stopped) throw error('NOT_READY','Progress is blocked. Reload or review recovery before continuing.'); };
    const token = doc => doc ? doc.digest : null;
    function state(value) { status(value); }
    async function validate(doc) {
      if (!doc) return null;
      if(doc.schema !== 1 || typeof doc.record !== 'string') throw error('CORRUPT_AUTHORITY','Cloud save is damaged.');
      let record;
      try { record=JSON.parse(doc.record); await codec.verifyRecord(record); capacity(record); }
      catch (_) { throw error('CORRUPT_AUTHORITY','Cloud save is damaged. Pending progress is preserved.'); }
      if(!record.revision || !/^[a-f0-9]{64}$/.test(record.digest)) throw error('CORRUPT_AUTHORITY','Cloud save has no committed progress.');
      if(doc.digest!==record.digest || doc.revision!==record.revision || doc.profileId!==record.profileId) throw error('CORRUPT_AUTHORITY','Cloud save identity is damaged.');
      recordDevices.set(record.digest,displayDevice(doc.device));
      return record;
    }
    async function validateLocal(local) {
      if(!local) return;
      if(typeof local.pending!=='boolean' || !(local.base===null || /^[a-f0-9]{64}$/.test(local.base))) throw error('CORRUPT_AUTHORITY','Local account journal is damaged.');
      await codec.verifyRecord(local.record); capacity(local.record);
      if(local.pending && !local.record.revision) throw error('CORRUPT_AUTHORITY','Pending local progress is damaged.');
      if(!local.pending && local.base!==local.record.digest) throw error('CORRUPT_AUTHORITY','Local cloud acknowledgment is damaged.');
      if(local.elapsedPending){
          const intent=local.elapsedPending;
          await codec.verifyRecord(intent.record);capacity(intent.record);
          if(intent.uid!==uid||local.pending||local.uploading||intent.base!==local.base||intent.record.profileId!==local.record.profileId||intent.record.revision!==local.record.revision+1
            ||typeof intent.writerId!=='string'||intent.writerId.length!==36||!Number.isSafeInteger(intent.writerEpoch)||intent.writerEpoch<1||typeof intent.commitServerStamp!=='string')
            throw error('CORRUPT_AUTHORITY','Protected elapsed intent is damaged.');
        }
        if(local.uploading) {
        await codec.verifyRecord(local.uploading.record); capacity(local.uploading.record);
        if(!local.pending || local.uploading.base!==local.base || local.uploading.record.profileId!==local.record.profileId || local.uploading.record.revision<1 || local.uploading.record.revision>local.record.revision)
          throw error('CORRUPT_AUTHORITY','Pending cloud upload is damaged.');
      }
    }
    function acceptedBoot() {
      const r=entry.record,result={ok:true,source:r.revision?'authority':'fresh',profileId:r.profileId,revision:r.revision,payload:r.payload};
      bootReady=true;pendingExport=null;client.bootJson=JSON.stringify(result);return result;
    }
    async function refreshBackup() {
      recoveryBackup=null;backupProblem='';
      if(!journal.readRecoveryBackup) return;
      let saved;
      try {saved=await journal.readRecoveryBackup(uid);accountGuard();}
      catch (_) {accountGuard();backupProblem='The protected pending backup could not be read. It will not be replaced. Export any current pending copy and review recovery options.';return;}
      if(saved===null) return;
      try {
        await validateLocal(saved);
        if(!saved?.pending) throw error('CORRUPT_AUTHORITY','Protected backup is not pending progress.');
        accountGuard();recoveryBackup=saved;
      } catch (_) {accountGuard();backupProblem='The protected pending backup could not be verified. It will not be replaced. Export any current pending copy and review recovery options.';}
    }
    async function previewRecovery(local, record) {
      accountGuard();
      recovery={local,record,reason:'Cloud progress differs from this device’s pending copy. Export it or choose the cloud save; the pending copy will be kept on this device.'};
      await refreshChoiceArchive();accountGuard();
      if(!journal.readRecoveryBackup || !journal.recover) {
        recovery.blocked='Recovery storage is unavailable. Keep this device’s pending progress and reload.';recovery.blockedCode='RECOVERY_UNAVAILABLE';return;
      }
      await refreshBackup();accountGuard();
      if(backupProblem) {recovery.blocked=backupProblem;recovery.blockedCode='RECOVERY_ARCHIVE_DAMAGED';}
      else if(recoveryBackup && !same(recoveryBackup,local)) {
        recovery.blocked='A different protected pending backup already exists. Export both copies for review; neither will be replaced.';
        recovery.blockedCode='RECOVERY_ARCHIVE_FULL';
      }
    }

    // One protected choice bundle per account. Never evict a different bundle.
    // Legacy recovery backup remains untouched in its original, separate slot.
    async function refreshChoiceArchive() {
      choiceArchive=null;choiceProblem='';
      if(!journal.readChoiceBackup || !journal.choose) {choiceProblem='Protected choice storage is unavailable. Your progress is unchanged.';return;}
      try {
        const saved=await journal.readChoiceBackup(uid);accountGuard();if(saved===null)return;
        if(saved?.format!=='little-leaf.choice.v1' || !['local','cloud'].includes(saved.choice) || typeof saved.selectionToken!=='string')throw Error('invalid archive');
        await validateLocal(saved.local);await codec.verifyRecord(saved.cloud);await codec.verifyRecord(saved.selected);
        if(saved.cloudDocument && (await validate(saved.cloudDocument))?.digest!==saved.cloud.digest)throw Error('archive cloud document mismatch');
        if(!saved.local.pending)throw Error('not a pending branch');
        accountGuard();choiceArchive=saved;
        choiceProblem='A previous pair of different saves is already protected. Both current saves are unchanged. More protected storage is needed before another choice.';
      } catch(e) {accountGuard();choiceProblem='The protected save copies could not be verified. They will not be replaced.';}
    }
    function summary(id,record,device) {
      const data=codec.parsePayload(record.payload,15);
      return {id,coins:Number.isSafeInteger(data.coins)?data.coins:null,lastSavedAt:record.updatedAt,
        timeSource:'device-local-save',device:displayDevice(device)};
    }
    function receipt(record) {return {ok:true,source:'authority',profileId:record.profileId,revision:record.revision,payload:record.payload};}
    async function nextRecord(previous,payload,revision=previous.revision+1) {
      codec.parsePayload(payload,15);
      if(!Number.isSafeInteger(revision) || revision<1)throw error('REVISION_LIMIT','Save revision limit reached.');
      const time=now(),record={...previous,revision,payload,updatedAt:time,
        previous:null,origin:previous.origin || {source:'fresh',legacyDigest:null,importedAt:time}};
      record.digest=await codec.hash(codec.fingerprint(record));await codec.verifyRecord(record);capacity(record);return record;
    }
    // Bound network waits only. A local storage transaction has an unknown
    // outcome until its receipt; never unfreeze by guessing that revision.
    function networkWait(promise) {
      if(typeof root.setTimeout!=='function')return promise; // injected synthetic environments
      return new Promise((resolve,reject)=>{
        const timer=root.setTimeout(()=>reject(error('NETWORK_TIMEOUT','The connection did not respond. Progress is protected on this device.')),networkTimeoutMs);
        promise.then(value=>{root.clearTimeout(timer);resolve(value);},problem=>{root.clearTimeout(timer);reject(problem);});
      });
    }
    async function durableSnapshot(payload,revision,profileId){
      return serial(async()=>{
        ordinaryWriteGuard();if(!entry || !bootReady || entry.record.profileId!==profileId || entry.record.revision!==revision)
          throw error('REVISION_CONFLICT','The active save changed before it could be preserved. Keep this page open.');
        const record=await nextRecord(entry.record,payload);ordinaryWriteGuard();const next={...entry,record,pending:true,device:savedDevice};
        await journal.replace(uid,entry,next);accountGuard();entry=next;
        return {ok:true,durable:true,profileId,revision:record.revision};
      });
    }
    async function verifyChoiceInputs(localDigest,cloudDigest) {
      accountGuard();
      if(!recovery || recoveryRecord(recovery.local).digest!==localDigest || recovery.record?.digest!==cloudDigest)throw error('RECOVERY_CHANGED','The saves changed. Review both current saves again.');
      const local=await journal.read(uid);accountGuard();
      if(!same(local,recovery.local))throw error('REVISION_CONFLICT','This device changed in another tab. Its newer progress is preserved.');
      const cloudDocument=await remote.read(uid);accountGuard();const record=await validate(cloudDocument);accountGuard();
      if(!record)throw error('RECOVERY_MISSING','The synced save is missing. Neither save has been changed.');
      if(record.digest!==cloudDigest) {await previewRecovery(local,record);throw error('RECOVERY_CHANGED','The synced save changed. Review both current saves again.');}
      return {local,record,cloudDocument};
    }
    function upload() {
      if(uploadTask)return uploadTask;
      uploadTask=performUpload().finally(()=>{uploadTask=null;});return uploadTask;
    }
    async function performUpload() {
      guard();
      if(entry?.elapsedPending)throw error('ELAPSED_UNCERTAIN','A background snapshot needs reconciliation.');
      if(!entry?.pending) return;
      lastAttempt=now();
      let snapshot;
      await serial(async()=>{
        guard();
        // Persist the exact upload before touching the network. If acknowledgment
        // is lost, replay this same snapshot; never mistake it for another device.
        if(!entry.uploading) {
          const next={...entry,uploading:{base:entry.base,record:entry.record,device:displayDevice(entry.device)}};
          await journal.replace(uid,entry,next);entry=next;
        }
        snapshot=entry.uploading;
      });
      const candidate={schema:1, profileId:snapshot.record.profileId, revision:snapshot.record.revision, digest:snapshot.record.digest, record:capacity(snapshot.record),device:displayDevice(snapshot.device)};
      state('pending');
      await remote.compareAndSet(uid,snapshot.base,candidate,guard);
      await serial(async()=>{
        guard();
        if(entry.base!==snapshot.base || entry.record.profileId!==snapshot.record.profileId || entry.record.revision<snapshot.record.revision)
          throw error('REVISION_CONFLICT','Account progress changed during upload. Reload.');
        // A hide-save or later edit may have committed during the network wait.
        // Acknowledge only the uploaded snapshot; preserve newer durable data.
        const next={...entry,base:candidate.digest,pending:entry.record.digest!==candidate.digest,uploading:null};
        await journal.replace(uid,entry,next);entry=next;state(next.pending?'pending':'saved');
      });
    }
    const client={storageKind:'firebase-firestore',bootJson:'',creditForSave(){return 0;},
      async boot() {
        if(opened) return opened;
        opened=(async()=>{ try {
          guard(); let local=await journal.read(uid); guard();
          await validateLocal(local); guard();pendingExport=local?.pending || local?.elapsedPending ? local : null;
          await refreshBackup();guard();
          try {
            const cloud=await remote.read(uid); guard(); const record=await validate(cloud);
            if(local?.elapsedPending){
              const intent=local.elapsedPending,fence=ownership?.assertActive();
              // A read of the baseline alone cannot rule out a late CAS. Only
              // a confirmed different epoch makes the original transaction dead.
              if(token(cloud)!==intent.record.digest && (!fence||fence.writerEpoch<=intent.writerEpoch))
                throw error('ELAPSED_UNCERTAIN','The previous background transaction is not yet fenced out. Progress stays paused.');
              if(token(cloud)===intent.record.digest){
                const next={...local,record:intent.record,base:intent.record.digest,pending:false,uploading:null,elapsedPending:null};
                await journal.replace(uid,local,next);local=next;
              }else if(token(cloud)===intent.base){
                const next={...local,elapsedPending:null};await journal.replace(uid,local,next);local=next;
              }else{
                pendingExport=local;
                if(record)await previewRecovery(local,record);
                throw error('REVISION_CONFLICT','Background confirmation differs from the current cloud save. Both exact copies are preserved.');
              }
            }
            if(local && !local.pending && local.base && !cloud) throw error('CORRUPT_AUTHORITY','Previously saved cloud progress is missing. Local progress is preserved.');
            if(local?.pending) {
              if(token(cloud)===local.record.digest) { const next={...local,base:token(cloud),pending:false,uploading:null}; await journal.replace(uid,local,next); local=next; }
              else if(local.uploading && token(cloud)===local.uploading.record.digest) { const next={...local,base:token(cloud),uploading:null};await journal.replace(uid,local,next);local=next; }
              else if(token(cloud)!==local.base) {
                if(!record) throw error('CORRUPT_AUTHORITY','Previously saved cloud progress is missing. Pending progress is preserved.');
                await previewRecovery(local,record);
                throw error('REVISION_CONFLICT','Cloud progress differs from this device’s pending copy. Review recovery to load the cloud save while keeping the pending copy.');
              }
              entry=local;
            } else {
              const time=now();
              entry={base:token(cloud),pending:false,...(cloud && Object.hasOwn(cloud,'device')?{device:displayDevice(cloud.device)}:{}),record:record || {format:2,profileId:root.crypto.randomUUID(),revision:0,createdAt:time,updatedAt:time,payload:null,digest:null,origin:null,previous:null,campaigns:{}}};
              await journal.replace(uid,local,entry);
            }
            if(entry.pending) { try { await upload(); } catch(e) { if(!offline(e)){if(e.code==='REVISION_CONFLICT'){const record=await validate(await remote.read(uid));accountGuard();if(record)await previewRecovery(entry,record);}throw e;} state('offline'); } }
            else state(entry.record.revision ? 'saved':'ready');
          } catch(e) {
            if(!offline(e) || !local || local.elapsedPending) throw e;
            entry=local; state('offline');
          }
          guard(); return acceptedBoot();
        } catch(e) { stopped=true;state(e.code==='REVISION_CONFLICT'?'conflict':'blocked');const result=failure(e);client.bootJson=JSON.stringify(result);return result; }})();return opened;
      },
      recoverySnapshot() {
        const allowed=!closed && currentUid()===uid;
        return {
          available:!!(allowed && recovery?.record && !recovery.blocked),busy:recoveryBusy,
          canExport:!!(allowed && (pendingExport || recoveryBackup)),
          cloudRevision:allowed ? recovery?.record?.revision ?? recoveredRevision : null,
          pendingRevision:allowed ? recoveryRecord(pendingExport || recoveryBackup)?.revision ?? null : null,
          reason:allowed ? recovery?.blocked || backupProblem || recovery?.reason || (recoveryBackup ? 'The pending copy is protected on this device and can be exported.' : '') : 'Account changed. Reload to load its progress.',
          expectedCloudDigest:allowed ? recovery?.record?.digest || recoveredDigest || null : null,
          expectedLocalDigest:allowed ? recoveryRecord(recovery?.local)?.digest || null : null,
          choicesAvailable:!!(allowed && recovery?.record && !choiceProblem),
          needsRuntimeSnapshot:!!(allowed && bootReady && stopped && entry),
          choiceReason:allowed ? choiceProblem || (recovery?'Two different saves are available. Choose which progress to continue. Neither will be replaced before confirmation.':'') : 'Account changed. Your current café is paused.',
          choices:allowed && recovery?.record ? [...(recovery.local.elapsedPending?[]:[summary('local',recoveryRecord(recovery.local),recovery.local.device)]),summary('cloud',recovery.record,recordDevices.get(recovery.record.digest))] : [],
          elapsedTrial:allowed && recovery?.local?.elapsedPending ? summary('local',recoveryRecord(recovery.local),recovery.local.device) : null
        };
      },
      async saveForUpdate(payload,revision,profileId){
        if(updateInProgress)return failure(error('SAVE_BUSY','An update save is already in progress.'));
        if(!ownership)return failure(error('OWNERSHIP_UNAVAILABLE','Server ownership must be confirmed before updating.'));
        updateInProgress=true;updateTicket=null;let saved=null;
        try {
          accountGuard();ownership.assertActive();
          saved=await durableSnapshot(payload,revision,profileId);
          ownership.assertActive();stopped=false;
          while(entry.pending)await networkWait(upload());
          accountGuard();ownership.assertActive();
          if(entry.record.profileId!==saved.profileId || entry.record.revision!==saved.revision || entry.pending)
            throw error('RECOVERY_CHANGED','Progress changed during the update save. Keep this page open.');
          updateTicket={token:root.crypto.randomUUID(),digest:entry.record.digest,profileId:saved.profileId,revision:saved.revision,consumed:false};
          const {reconciliationError,...durableSaved}=saved;return {...durableSaved,cloudConfirmed:true,updateToken:updateTicket.token};
        }catch(e){
          stopped=!offline(e);state(offline(e)?'offline':'blocked');
          if(saved?.durable && e.code==='REVISION_CONFLICT'){
            try{const record=await validate(await networkWait(remote.read(uid)));accountGuard();if(record)await previewRecovery(entry,record);}catch(_){/* Keep the native snapshot and surface resume-needed. */}
          }
          return saved?.durable?{...saved,cloudConfirmed:false,updateError:failure(e)}:failure(e);
        }
        finally{updateInProgress=false;}
      },
      async checkUpdateReady(profileId,revision,updateToken){
        try {
          accountGuard();const ticket=updateTicket;
          if(!ticket || ticket.consumed || ticket.token!==updateToken || ticket.profileId!==profileId || ticket.revision!==revision)
            throw error('UPDATE_CHANGED','Save and confirm the current café before updating.');
          if(!ownership)throw error('OWNERSHIP_UNAVAILABLE','Server ownership is unavailable.');
          const cloud=await networkWait((async()=>{await ownership.refresh();accountGuard();ownership.assertActive();return validate(await remote.read(uid));})());accountGuard();ownership.assertActive();
          if(cloud?.digest!==ticket.digest)throw error('UPDATE_CHANGED','Synced progress changed. Keep this page open and review it.');
          return await serial(async()=>{
            ordinaryWriteGuard();ownership.assertActive();const current=await journal.read(uid);ordinaryWriteGuard();ownership.assertActive();
            if(updateTicket!==ticket || ticket.consumed || !same(current,entry) || entry.pending || entry.record.digest!==ticket.digest)
              throw error('UPDATE_CHANGED','This device changed after saving. Keep this page open.');
            ticket.consumed=true;ticket.readyEntry=entry;return {ok:true,profileId,revision,cloudConfirmed:true,updateToken};
          });
        }catch(e){return failure(e);}
      },
      canReloadUpdate(profileId,revision,token){
        try{
          ordinaryWriteGuard();if(!ownership)return false;ownership.assertActive();const ticket=updateTicket;
          const ready=!!(ticket?.consumed && ticket.token===token && ticket.profileId===profileId && ticket.revision===revision
            && ticket.readyEntry===entry && !entry.pending && entry.record.digest===ticket.digest && !updateInProgress);
          if(!ready)return false;
          return !prepareReload || prepareReload(ownership.reloadContinuation(ticket.digest,ticket.revision))===true;
        }catch(_){return false;}
      },
      ownershipSnapshot(){
        if(!ownership)return {serverOwnership:false};
        const state=ownership.snapshot();
        if(state.status==='active' && stopped && !recovery && !updateInProgress && !recoveryBusy)
          return {...state,status:'resume-needed',ownershipPaused:true,canRequestTakeover:true,reason:'Your café could not be opened yet. Retry on this device; current progress is preserved.'};
        return state;
      },
      async refreshOwnership(){
        if(!ownership)return failure(error('OWNERSHIP_UNAVAILABLE','Server ownership is unavailable.'));
        try {accountGuard();await ownership.refresh();return {ok:true,...ownership.snapshot()};}catch(e){return failure(e);}
      },
      async renewOwnership(){if(!ownership||elapsedClaim)return;try {accountGuard();await ownership.renew();}catch(_){/* Native observes the paused ownership snapshot. */}},
      async beginBackground(revision,profileId){
        if(elapsedClaim||entry?.elapsedPending||busy||updateInProgress||recoveryBusy)return failure(error('SAVE_BUSY','A save operation is pending.'));
        const claim=elapsedClaim={phase:'arming',cancelled:false};
        try{
          elapsedGuard(claim);if(!ownership?.beginElapsed||!bootReady||!entry||entry.record.revision!==revision||entry.record.profileId!==profileId)
            throw error('ELAPSED_UNAVAILABLE','No matching account save is available for elapsed progress.');
          while(entry.pending){await networkWait(upload());elapsedGuard(claim);}
          const baseline=entry.record.digest;elapsedGuard(claim);
          const checkpoint=await networkWait(ownership.beginElapsed());elapsedGuard(claim);
          if(entry.record.digest!==baseline||entry.pending)throw error('ELAPSED_CHANGED','The save changed while opening the background interval.');
          Object.assign(claim,{phase:'armed',token:checkpoint.token,baseline,revision,profileId});
          return {ok:true,token:checkpoint.token,revision,profileId};
        }catch(e){clearElapsed(claim);return failure(e);}
      },
      async finishBackground(token){
        const claim=elapsedClaim;
        if(!claim||claim.phase!=='armed'||claim.token!==token)return failure(error('ELAPSED_CONSUMED','Background interval already consumed.'));
        claim.phase='sealing';
        try{
          elapsedGuard(claim);const proof=await networkWait(ownership.finishElapsed(token));elapsedGuard(claim);
          const local=await journal.read(uid);elapsedGuard(claim);
          if(entry.record.digest!==claim.baseline||entry.pending||!same(local,entry))throw error('REVISION_CONFLICT','The background save baseline changed.');
          const latest=await networkWait(remote.read(uid));elapsedGuard(claim);
          if(latest?.digest!==claim.baseline)throw error('REVISION_CONFLICT','Another tab changed the background save.');
          claim.phase='proved';claim.proof=proof;return {ok:true,...proof,revision:claim.revision,profileId:claim.profileId};
        }catch(e){clearElapsed(claim);return failure(e);}
      },
      async commitBackground(payload,token){
        const claim=elapsedClaim;
        if(!claim||claim.phase!=='proved'||claim.token!==token)return failure(error('ELAPSED_CONSUMED','Background interval already consumed.'));
        claim.phase='consumed';let committed=false,record=null;
        try{
          elapsedGuard(claim);if(entry.record.digest!==claim.baseline||entry.pending)throw error('REVISION_CONFLICT','The elapsed save baseline changed.');
          record=await nextRecord(entry.record,payload);elapsedGuard(claim);
          claim.record=record;
          await serial(async()=>{
            elapsedGuard(claim);
            const next={...entry,elapsedPending:{uid,state:'prepared',base:entry.base,record,writerId:claim.proof.writerId,writerEpoch:claim.proof.writerEpoch,commitServerStamp:claim.proof.commitServerStamp,token:claim.token}};
            await journal.replace(uid,entry,next);entry=next;claim.expected=next;
          });
          elapsedGuard(claim);
          const candidate={schema:1,profileId:record.profileId,revision:record.revision,digest:record.digest,record:capacity(record),device:savedDevice};
          claim.dispatched=true;
          // Do not race this transaction with a local timeout: a rejected race
          // cannot cancel a Firestore write. Keep the exact trial and block new
          // claims until the actual transaction settles, including after cancel.
          await remote.compareAndSet(uid,entry.base,candidate,()=>elapsedGuard(claim),claim.proof);committed=true;
          const next={...claim.expected,base:record.digest,pending:false,uploading:null,elapsedPending:null,record,device:savedDevice};
          await serial(async()=>{accountGuard();await journal.replace(uid,claim.expected,next);entry=next;});
          if(claim.cancelled){stopped=true;state('blocked');}else state('saved');
          return {ok:true,durable:true,cloudConfirmed:true,reloadRequired:claim.cancelled,profileId:record.profileId,revision:record.revision,creditedCoins:0};
        }catch(e){
          if(claim.dispatched||entry?.elapsedPending){stopped=true;state('blocked');}
          if(committed)return {ok:true,cloudConfirmed:true,durable:false,reloadRequired:true,profileId:record.profileId,revision:record.revision,localError:failure(e)};
          return failure(e);
        }finally{clearElapsed(claim);}
      },
      cancelBackground(){
        const claim=elapsedClaim;if(!claim)return;
        claim.cancelled=true;
        if(claim.dispatched){stopped=true;state('blocked');return;}
        clearElapsed(claim);
      },
      async requestTakeover(){
        if(!ownership)return failure(error('OWNERSHIP_UNAVAILABLE','Server ownership is unavailable.'));
        try {accountGuard();const state=await ownership.requestTakeover();if(state.status==='active')return client.finishTakeover();return {ok:true,...state};}catch(e){return failure(e);}
      },
      async finishTakeover(force=false){
        if(!ownership)return failure(error('OWNERSHIP_UNAVAILABLE','Server ownership is unavailable.'));
        try {accountGuard();await ownership.takeOver(force);accountGuard();stopped=false;bootReady=false;opened=null;recovery=null;choiceOperation=null;return client.boot();}catch(e){return failure(e);}
      },
      async forceTakeover(){return client.finishTakeover(true);},
      async preserveOwnerRuntime(payload,revision,profileId){
        if(!ownership)return failure(error('OWNERSHIP_UNAVAILABLE','Server ownership is unavailable.'));
        // Always keep the native snapshot. Only the still-current owner flushes.
        const saved=await client.preserveRuntime(payload,revision,profileId);if(!saved.ok)return saved;
        if(ownership.snapshot().status!=='handoff-requested')return {...saved,cloudConfirmed:false};
        try {handoffMode=true;stopped=false;while(entry.pending)await networkWait(upload());await networkWait(ownership.acknowledge(entry.record.digest,entry.record.revision));accountGuard();const {reconciliationError,...durableSaved}=saved;return {...durableSaved,cloudConfirmed:true};}
        catch(e){return {...saved,cloudConfirmed:false,handoffError:failure(e)};}
        finally{handoffMode=false;stopped=true;}
      },
      // Read-only phase. Native validates the full candidate in isolation,
      // then asks the player to confirm before any active-save replacement.
      async prepareChoice(choice,localDigest,cloudDigest) {
        if(recoveryBusy)return failure(error('RECOVERY_BUSY','A save choice is already in progress.'));recoveryBusy=true;
        try {
          if(!['local','cloud'].includes(choice))throw error('INVALID_CHOICE','Choose one of the two saves.');
          const retry=choiceOperation;
          if(retry?.staged && !retry.complete && retry.choice===choice && retry.localDigest===localDigest && retry.cloudDigest===cloudDigest){
            accountGuard();const current=await journal.read(uid);accountGuard();
            if(!same(current,entry)||entry.record.digest!==retry.selected.digest)throw error('RECOVERY_CHANGED','Selected progress changed. Keep this page open.');
            return {...receipt(retry.selected),selectionToken:retry.selectionToken};
          }
          const {local,record,cloudDocument}=await verifyChoiceInputs(localDigest,cloudDigest);
          if(local.elapsedPending&&choice==='local')throw error('ELAPSED_UNCERTAIN','An unconfirmed background trial may be exported, but cannot be uploaded under a new writer. Choose the confirmed cloud snapshot.');
          await refreshChoiceArchive();accountGuard();if(choiceProblem)throw error(choiceArchive?'RECOVERY_ARCHIVE_FULL':'RECOVERY_UNAVAILABLE',choiceProblem);
          let selected=record;
          if(choice==='local')selected=await nextRecord({...local.record,profileId:record.profileId,createdAt:record.createdAt},local.record.payload,Math.max(local.record.revision,record.revision)+1);
          accountGuard();const selectionToken=await codec.hash(JSON.stringify({choice,localDigest,cloudDigest,selected:selected.digest}));accountGuard();
          choiceOperation={choice,localDigest,cloudDigest,selectionToken,local,cloud:record,cloudDocument,selected,device:choice==='local'?savedDevice:displayDevice(cloudDocument.device),staged:false,complete:false};
          return {...receipt(selected),selectionToken};
        } catch(e) {return failure(e);} finally {recoveryBusy=false;}
      },
      async confirmChoice(selectionToken) {
        if(recoveryBusy)return failure(error('RECOVERY_BUSY','A save choice is already in progress.'));recoveryBusy=true;
        try {
          accountGuard();if(ownership)ownership.assertActive();const operation=choiceOperation;
          if(!operation || operation.selectionToken!==selectionToken)throw error('RECOVERY_CONFIRMATION_REQUIRED','Review and confirm the current save choice.');
          if(operation.complete) {
            const current=await journal.read(uid);accountGuard();
            if(!same(current,entry) || entry.pending || entry.record.digest!==operation.selected.digest)throw error('RECOVERY_CHANGED','Progress changed after this choice. It will not be replaced.');
            if(ownership)ownership.assertActive();return receipt(entry.record);
          }
          if(!operation.staged) {
            await verifyChoiceInputs(operation.localDigest,operation.cloudDigest);accountGuard();
            const next={base:operation.cloudDigest,pending:operation.choice==='local',record:operation.selected,device:operation.device};
            const backup={format:'little-leaf.choice.v1',selectionToken,choice:operation.choice,local:operation.local,cloud:operation.cloud,cloudDocument:operation.cloudDocument,selected:operation.selected};
            await serial(async()=>{const selectionGuard=()=>{accountGuard();const fence=ownership?.assertActive();if(elapsedClaim||operation.local.elapsedPending&&(!fence||fence.writerEpoch<=operation.local.elapsedPending.writerEpoch))throw error('ELAPSED_UNCERTAIN','The original transaction must be fenced out before selecting another save.');};selectionGuard();await journal.choose(uid,operation.local,next,backup,selectionGuard);selectionGuard();entry=next;operation.staged=true;});
          }
          // Durable intent permits exact replay after a lost network response.
          stopped=false;if(operation.choice==='local')await upload();
          accountGuard();if(ownership)ownership.assertActive();operation.complete=true;recovery=null;state('saved');const result=acceptedBoot();opened=Promise.resolve(result);return result;
        } catch(e) {stopped=true;state(offline(e)?'offline':'conflict');return failure(e);}finally {recoveryBusy=false;}
      },
      // Native freezes input/simulation and waits for existing save receipts.
      // Remote conflict does not reject its final LOCAL snapshot; account and
      // local-tab CAS protections still apply. Never auto-reload the live model.
      async preserveRuntime(payload,revision,profileId) {
        if(elapsedClaim||entry?.elapsedPending)return failure(error('ELAPSED_UNCERTAIN','The exact background snapshot is protected. Reload to reconcile before saving the old runtime.'));
        if(recoveryBusy)return failure(error('RECOVERY_BUSY','A save choice is already in progress.'));recoveryBusy=true;let preserved=null;
        try {
          accountGuard();preserved=await durableSnapshot(payload,revision,profileId);
          stopped=true;const cloud=await validate(await networkWait(remote.read(uid)));accountGuard();
          if(!cloud)throw error('RECOVERY_MISSING','Synced progress is unavailable. This device’s snapshot is preserved.');
          if(cloud.digest!==entry.base && cloud.digest!==entry.record.digest && cloud.digest!==entry.uploading?.record?.digest)await previewRecovery(entry,cloud);else recovery=null;
          return preserved;
        }catch(e){return preserved?{...preserved,reconciliationError:failure(e)}:failure(e);}finally{recoveryBusy=false;}
      },
      async exportRecovery() {
        try {
          accountGuard();
          // Always read protected storage again. Never export another account or
          // silently substitute a stale in-memory copy after another tab writes.
          await refreshBackup();accountGuard();const backup=recoveryBackup;
          const pending=pendingExport ? await journal.read(uid) : null;accountGuard();
          if(pendingExport && !same(pending,pendingExport)) throw error('REVISION_CONFLICT','Pending progress changed in another tab. Reload before exporting.');
          const saved=pending || backup;
          if(!saved) throw error(backupProblem?'RECOVERY_ARCHIVE_DAMAGED':'RECOVERY_UNAVAILABLE',backupProblem || 'There is no preserved pending copy to export.');
          await validateLocal(saved);accountGuard();
          const bundle={format:'little-leaf.firebase-recovery.v1',pendingEntry:saved};
          if(saved.elapsedPending){bundle.baselineRecord=saved.record;bundle.elapsedTrialRecord=saved.elapsedPending.record;bundle.note='The exact trial is unconfirmed and must not be uploaded under a new epoch. Both copies are preserved.';}
          if(pending && backup && !same(pending,backup)) bundle.protectedBackup=backup;
          if(backupProblem) bundle.note='The protected backup could not be verified and remains untouched on this device.';
          const text=JSON.stringify(bundle,null,2);accountGuard();
          return {ok:true,fileName:`little-leaf-pending-recovery-r${recoveryRecord(saved)?.revision || 0}.json`,text};
        } catch(e) { return failure(e); }
      },
      async recoverCloud(expectedCloudDigest) {
        if(recoveryBusy) return failure(error('RECOVERY_BUSY','Recovery is already in progress.'));
        recoveryBusy=true;
        try {
          accountGuard();
          if(!/^[a-f0-9]{64}$/.test(expectedCloudDigest || '')) throw error('RECOVERY_CONFIRMATION_REQUIRED','Review the current cloud save before choosing it.');
          if(!recovery) {
            // A repeated click after success is harmless only while that exact
            // recovered save is still active. Never rewind later local edits.
            if(recoveredDigest!==expectedCloudDigest || entry?.pending || entry?.record?.digest!==expectedCloudDigest) throw error('RECOVERY_UNAVAILABLE','No cloud recovery is ready. Reload to review progress.');
            const cloud=await remote.read(uid);accountGuard();const record=await validate(cloud);accountGuard();
            if(!record || record.digest!==expectedCloudDigest) throw error('RECOVERY_CHANGED','Cloud progress changed again. Reload to review the latest save.');
            const local=await journal.read(uid);accountGuard();
            if(!same(local,entry)) throw error('REVISION_CONFLICT','Another tab changed this account’s progress. Reload.');
            return acceptedBoot();
          }
          const pending=recovery.local;
          const recoveryGuard=()=>{accountGuard();const fence=ownership?.assertActive();if(elapsedClaim||pending.elapsedPending&&(!fence||fence.writerEpoch<=pending.elapsedPending.writerEpoch))throw error('ELAPSED_UNCERTAIN','The original transaction is not yet fenced out.');};
          recoveryGuard();
          const cloud=await remote.read(uid);accountGuard();const record=await validate(cloud);accountGuard();
          if(!record) throw error('RECOVERY_MISSING','Cloud progress is missing. The pending copy has not been changed.');
          if(record.digest!==expectedCloudDigest || recovery.record?.digest!==expectedCloudDigest) {
            await previewRecovery(pending,record);
            throw error('RECOVERY_CHANGED','Cloud progress changed since your preview. Review the updated cloud save and choose again.');
          }
          await previewRecovery(pending,record);accountGuard();
          if(recovery.blocked) throw error(recovery.blockedCode || 'RECOVERY_UNAVAILABLE',recovery.blocked);
          const next={base:record.digest,pending:false,record};
          await serial(async()=>{
            accountGuard();
            // The journal checks both active and backup entries, then archives
            // and replaces atomically. No remote write or local/cloud merge.
            recoveryGuard();await journal.recover(uid,pending,next,recoveryGuard);
            recoveryGuard();entry=next;recoveryBackup=pending;
          });
          recoveredDigest=record.digest;recoveredRevision=record.revision;recovery=null;stopped=false;state('saved');
          const result=acceptedBoot();opened=Promise.resolve(result);return result;
        } catch(e) {
          if(recovery && e.code==='RECOVERY_ARCHIVE_FULL') {
            recovery={...recovery,blocked:'A different protected pending backup already exists. Export both copies for review; neither will be replaced.',blockedCode:e.code};
          }
          if(recovery && e.code==='REVISION_CONFLICT') {
            recovery={...recovery,blocked:'Pending progress changed in another tab. Reload to review its latest copy.',blockedCode:e.code};
          }
          if(recovery && ['RECOVERY_MISSING','CORRUPT_AUTHORITY'].includes(e.code)) {
            recovery={...recovery,record:null,blocked:e.message};
          }
          state(offline(e)?'offline':'conflict');
          const result=failure(e);client.bootJson=JSON.stringify(result);return result;
        } finally { recoveryBusy=false; }
      },
      async commit(payload,revision,profileId) {
        if(elapsedClaim||entry?.elapsedPending)return failure(error('SAVE_BUSY','An elapsed interval is being reconciled.'));
        if(updateInProgress)return failure(error('SAVE_BUSY','The café is being saved for an update.'));
        if(busy) return failure(error('SAVE_BUSY','A save is pending.')); busy=true;
        try {
          return await serial(async()=>{
          guard(); if(!bootReady || !entry) throw error('NOT_READY','Load progress before saving.');
          codec.parsePayload(payload,15);
          const r=entry.record;
          if(revision!==r.revision || profileId!==r.profileId) throw error('REVISION_CONFLICT','This page has older progress. Reload before continuing.');
          if(revision>=Number.MAX_SAFE_INTEGER) throw error('REVISION_LIMIT','Save revision limit reached.');
          const time=now(),record={...r,revision:revision+1,payload,updatedAt:time,previous:null,origin:r.origin || {source:'fresh',legacyDigest:null,importedAt:time}};
          record.digest=await codec.hash(codec.fingerprint(record));capacity(record);guard();
          const next={...entry,pending:true,record,device:savedDevice};await journal.replace(uid,entry,next);entry=next;accountGuard();state('pending');
          return {ok:true,durable:true,cloudConfirmed:false,profileId,revision:record.revision,creditedCoins:0};
          });
        } catch(e) { if(['REVISION_CONFLICT','NOT_READY'].includes(e.code)){stopped=true;state('conflict');}else state('blocked');return failure(e); }
        finally {busy=false;}
      },
      async sync() { if(syncing || !bootReady || stopped || !entry?.pending || now()-lastAttempt<30000)return;syncing=true;try {await upload();}catch(e){if(offline(e))state('offline');else {stopped=true;state('conflict');if(e.code==='REVISION_CONFLICT'){try{const record=await validate(await remote.read(uid));accountGuard();if(record)await previewRecovery(entry,record);}catch(_){/* Keep current model and journal; never reload an unavailable preview. */}}}}finally{syncing=false;} },
      save(payload,revision,profileId,callback){client.commit(payload,revision,profileId).then(r=>callback(JSON.stringify(r)));},
      close(){closed=true;stopped=true;ownership?.close();state('signed-out');}
    };return client;
  }
  // Each read/compare/write is a single IDB transaction; concurrent tabs fail closed.
  async function openJournal(indexedDB) {
    const db=await new Promise((resolve,reject)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);q.onblocked=()=>reject(error('STORAGE_BLOCKED','Close other game tabs and reload.'));});
    function transaction(uid,expected,next,write) {return new Promise((resolve,reject)=>{let result,problem;const tx=db.transaction('accounts',write?'readwrite':'readonly'),s=tx.objectStore('accounts'),q=s.get(uid);q.onsuccess=()=>{if(Array.isArray(uid) && q.result!==undefined && (!q.result || typeof q.result!=='object')){problem=error('CORRUPT_AUTHORITY','Protected recovery backup is damaged.');tx.abort();return;}result=q.result || null;if(write){if(!same(result,expected)){problem=error('REVISION_CONFLICT','Another tab changed this account’s progress. Reload.');tx.abort();}else{s.put(next,uid);result=next;}}};tx.oncomplete=()=>resolve(result);tx.onabort=()=>reject(problem || tx.error);tx.onerror=()=>{};});}
    function recover(uid,expected,next,guard) {
      return new Promise((resolve,reject)=>{
        let problem;
        const tx=db.transaction('accounts','readwrite'),store=tx.objectStore('accounts');
        const abort=e=>{problem=e;tx.abort();};
        const check=action=>{try {guard();action();} catch(e) {abort(e);} };
        const active=store.get(uid);
        active.onsuccess=()=>check(()=>{
          const current=active.result || null,backup=store.get(recoveryBackupKey(uid));
          backup.onsuccess=()=>check(()=>{
            const preserved=backup.result,hasBackup=preserved!==undefined;
            if(hasBackup && !same(preserved,expected)) throw error('RECOVERY_ARCHIVE_FULL','A different protected pending backup already exists. Export both copies for review; neither will be replaced.');
            // Idempotent retry after a completed transaction/uncertain response.
            if(same(current,next) && same(preserved,expected)) return;
            if(!same(current,expected)) throw error('REVISION_CONFLICT','Another tab changed this account’s progress. Reload before recovery.');
            if(!hasBackup) {const save=store.put(expected,recoveryBackupKey(uid));save.onsuccess=()=>check(()=>{});}
            const replace=store.put(next,uid);replace.onsuccess=()=>check(()=>{});
          });
        });
        tx.oncomplete=()=>resolve(next);tx.onabort=()=>reject(problem || tx.error || error('STORAGE_ERROR','Recovery could not be stored. Pending progress is unchanged.'));tx.onerror=()=>{};
      });
    }
    function choose(uid,expected,next,bundle,guard) {
      return new Promise((resolve,reject)=>{
        let problem;const tx=db.transaction('accounts','readwrite'),store=tx.objectStore('accounts');
        const check=action=>{try {guard();action();}catch(e){problem=e;tx.abort();}};
        const active=store.get(uid);
        active.onsuccess=()=>check(()=>{
          const backup=store.get(choiceBackupKey(uid));
          backup.onsuccess=()=>check(()=>{
            const archived=backup.result,current=active.result || null;
            if(archived!==undefined && !same(archived,bundle))throw error('RECOVERY_ARCHIVE_FULL','Previous protected saves will not be replaced.');
            if(same(current,next) && same(archived,bundle))return;
            if(!same(current,expected))throw error('REVISION_CONFLICT','Another tab changed this device’s progress.');
            if(archived===undefined)store.put(bundle,choiceBackupKey(uid)).onsuccess=()=>check(()=>{});
            store.put(next,uid).onsuccess=()=>check(()=>{});
          });
        });
        tx.oncomplete=()=>resolve(next);tx.onabort=()=>reject(problem || tx.error || error('STORAGE_ERROR','Save choice could not be protected. Neither save was replaced.'));tx.onerror=()=>{};
      });
    }
    return {read:uid=>transaction(uid,null,null,false),replace:(uid,old,next)=>transaction(uid,old,next,true),readRecoveryBackup:uid=>transaction(recoveryBackupKey(uid),null,null,false),recover,readChoiceBackup:uid=>transaction(choiceBackupKey(uid),null,null,false),choose};
  }
  root.LittleLeafFirebase=Object.freeze({createClient,createRemote,openJournal,capacity,MAX_BYTES,genericDevice});
})(globalThis);
