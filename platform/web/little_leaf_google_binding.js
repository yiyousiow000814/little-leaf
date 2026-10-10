/* Explicit same-origin local -> Google transition. Never deletes the source vault. */
(function(root){
  'use strict';
  const copy=value=>value==null?null:JSON.parse(JSON.stringify(value));
  const fault=code=>Object.assign(Error(code),{code});
  function create({uid,currentUid,codec,source,remote,journal,ownership,now=Date.now}){
    const key=['google-binding-v1',uid],historyKey=['google-binding-history-v1',uid];let preview=null,busy=false;
    function guard(){
      if(currentUid()!==uid)throw fault('ACCOUNT_CHANGED');
      ownership.assertActive();
      const state=ownership.snapshot();
      if(ownership.hasElapsedIntent || state.elapsedPending || state.activeClaim)throw fault('ELAPSED_UNCERTAIN');
    }
    async function local(){const value=await source();await codec.verifyRecord(value);if(!value.revision)throw fault('LOCAL_SAVE_REQUIRED');return value;}
    async function cloud(){guard();const doc=await remote.read(uid);guard();if(!doc)return null;
      if(doc.schema!==1 || typeof doc.record!=='string')throw fault('CORRUPT_AUTHORITY');
      const record=JSON.parse(doc.record);await codec.verifyRecord(record);
      if(record.digest!==doc.digest || record.profileId!==doc.profileId || record.revision!==doc.revision || !record.revision)throw fault('CORRUPT_AUTHORITY');
      return {document:doc,record};
    }
    const summary=(id,record)=>({id,profileId:record.profileId,revision:record.revision,coins:codec.parsePayload(record.payload,15).coins,lastSavedAt:record.updatedAt});
    async function validateOperation(operation){
      if(operation?.format!=='little-leaf.google-binding.v1' || operation.uid!==uid || typeof operation.complete!=='boolean' || !['local','cloud'].includes(operation.choice))throw fault('CORRUPT_AUTHORITY');
      await codec.verifyRecord(operation.source);await codec.verifyRecord(operation.selected);
      const d=operation.document,r=operation.selected;
      if(d?.schema!==1 || d.profileId!==r.profileId || d.revision!==r.revision || d.digest!==r.digest || d.record!==JSON.stringify(r))throw fault('CORRUPT_AUTHORITY');
      if(operation.previousCloud){const previous=operation.previousCloud;await codec.verifyRecord(previous.record);if(previous.document.digest!==previous.record.digest || previous.document.record!==JSON.stringify(previous.record))throw fault('CORRUPT_AUTHORITY');}
      if(operation.base!==(operation.previousCloud?.record.digest || null))throw fault('CORRUPT_AUTHORITY');
      const chosen=operation.choice==='cloud'?operation.previousCloud?.record:operation.source;
      if(!chosen || r.payload!==chosen.payload || JSON.stringify(r.campaigns)!==JSON.stringify(chosen.campaigns))throw fault('CORRUPT_AUTHORITY');
    }
    async function safe(action){if(busy)return {ok:false,code:'BINDING_BUSY'};busy=true;try{return await action();}catch(e){return {ok:false,code:e.code || 'BINDING_FAILED'};}finally{busy=false;}}
    async function resume(operation){
      await validateOperation(operation);
      guard();const current=await local();if(current.digest!==operation.source.digest)throw fault('LOCAL_CHANGED');
      const account=await journal.read(uid);if(account?.pending || account?.uploading || account?.elapsedPending)throw fault('ACCOUNT_PENDING');
      const observed=await cloud();
      if(operation.complete){
        if(observed?.record.digest!==operation.selected.digest)throw fault('CLOUD_CHANGED');
        return {ok:true,cloudConfirmed:true,profileId:operation.selected.profileId,revision:operation.selected.revision,digest:operation.selected.digest};
      }
      if(observed?.record.digest!==operation.selected.digest){
        if((observed?.record.digest || null)!==operation.base)throw fault('CLOUD_CHANGED');
        // The complete source and prior cloud state are durable before a request.
        guard();await remote.compareAndSet(uid,operation.base,operation.document,guard);
      }
      const verified=await cloud();guard();
      if(verified?.record.digest!==operation.selected.digest || verified.record.profileId!==operation.selected.profileId || verified.record.revision!==operation.selected.revision)throw fault('CLOUD_UNCONFIRMED');
      if((await local()).digest!==operation.source.digest)throw fault('LOCAL_CHANGED');
      const complete={...operation,complete:true};await journal.replace(key,operation,complete);guard();
      return {ok:true,cloudConfirmed:true,profileId:complete.selected.profileId,revision:complete.selected.revision,digest:complete.selected.digest};
    }
    return {
      inspect(){return safe(async()=>{
        guard();const account=await journal.read(uid);if(account?.pending || account?.uploading || account?.elapsedPending)throw fault('ACCOUNT_PENDING');
        const sourceRecord=await local(),target=await cloud();let saved=await journal.read(key);guard();
        if(saved){
          await validateOperation(saved);
          if(saved.source.digest===sourceRecord.digest && (!saved.complete || target?.record.digest===saved.selected.digest))return {ok:true,resumable:true,complete:saved.complete,choices:[],source:summary('local',sourceRecord)};
          // A changed local restaurant cannot replay an unresolved older write.
          if(!saved.complete){
            if(target?.record.digest!==saved.selected.digest)throw fault('PREVIOUS_BINDING_UNCERTAIN');
            const complete={...saved,complete:true};await journal.replace(key,saved,complete);saved=complete;guard();
          }
        }
        preview={source:copy(sourceRecord),cloud:copy(target),prior:copy(saved)};
        return {ok:true,resumable:false,choices:[summary('local',sourceRecord),...(target?[summary('cloud',target.record)]:[])],source:summary('local',sourceRecord),localDigest:sourceRecord.digest,cloudDigest:target?.record.digest || null};
      });},
      choose(choice,localDigest,cloudDigest){return safe(async()=>{
        if(!preview || !['local','cloud'].includes(choice) || preview.source.digest!==localDigest || (preview.cloud?.record.digest || null)!==cloudDigest || choice==='cloud'&&!preview.cloud)throw fault('CHOICE_REQUIRED');
        guard();const current=await local(),latest=await cloud();
        if(current.digest!==localDigest || (latest?.record.digest || null)!==cloudDigest)throw fault('CHOICE_CHANGED');
        const account=await journal.read(uid);if(account?.pending || account?.uploading || account?.elapsedPending)throw fault('ACCOUNT_PENDING');
        let selected=copy(choice==='cloud'?latest.record:current);
        if(latest){
          // Keep the full chosen payload/campaign history, never combine wallets.
          selected={...selected,profileId:latest.record.profileId,createdAt:latest.record.createdAt,revision:Math.max(selected.revision,latest.record.revision)+1,updatedAt:now(),previous:null};
          if(!Number.isSafeInteger(selected.revision))throw fault('REVISION_LIMIT');
          selected.digest=await codec.hash(codec.fingerprint(selected));
        }
        const document={schema:1,profileId:selected.profileId,revision:selected.revision,digest:selected.digest,record:JSON.stringify(selected),device:'Unknown device'};
        root.LittleLeafFirebase.capacity(selected);
        const operation={format:'little-leaf.google-binding.v1',uid,choice,source:copy(current),previousCloud:copy(latest),selected,document,base:cloudDigest,complete:false};
        if(preview.prior){
          const history=await journal.read(historyKey),records=history || [];
          if(!Array.isArray(records) || records.length>8)throw fault('CORRUPT_AUTHORITY');
          for(const prior of records)await validateOperation(prior);
          if(!records.some(prior=>prior.source.digest===preview.prior.source.digest && prior.selected.digest===preview.prior.selected.digest)){
            if(records.length===8)throw fault('BINDING_ARCHIVE_FULL');
            guard();await journal.replace(historyKey,history,[...records,preview.prior]);
          }
        }
        guard();await journal.replace(key,preview.prior,operation);preview=null;return resume(operation);
      });},
      retry(){return safe(async()=>{guard();const operation=await journal.read(key);if(!operation)throw fault('NO_BINDING');return resume(operation);});},
      cancel(){preview=null;return {ok:true,localPreserved:true};},
      snapshot(){return {busy,origin:root.location?.origin || '',crossOriginAccess:false};}
    };
  }
  root.LittleLeafGoogleBinding=Object.freeze({create});
})(globalThis);
