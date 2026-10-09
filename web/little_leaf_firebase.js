/* Optional Firebase vault. No default Web/CG database is opened or migrated. */
(function(root) {
  'use strict';
  const MAX_BYTES = 900000; // leaves >140 KiB for Firestore document/path overhead
  const error = (code, message) => Object.assign(new Error(message), {code});
  const failure = e => ({ok:false, code:e.code || 'CLOUD_ERROR', error:e.message});
  const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
  const recoveryBackupKey = uid => ['recovery-v1',uid];
  const offline = e => ['unavailable','deadline-exceeded','resource-exhausted','OFFLINE'].includes(e.code);
  function capacity(record) {
    const text = JSON.stringify(record);
    if (new TextEncoder().encode(text).length > MAX_BYTES) throw error('SAVE_TOO_LARGE','This café exceeds the cloud save limit. Previous progress is unchanged.');
    return text;
  }
  function createRemote(db, sdk) {
    const ref=uid=>sdk.doc(db,'players',uid,'saves','cafe');
    return {
      async read(uid) { const snapshot=await sdk.getDocFromServer(ref(uid));return snapshot.exists()?snapshot.data():null; },
      async compareAndSet(uid,base,next,guard) {
        await sdk.runTransaction(db,async tx=>{
          guard();const snapshot=await tx.get(ref(uid)),old=snapshot.exists()?snapshot.data():null;guard();
          if(old?.digest===next.digest)return;
          if((old?.digest || null)!==base)throw error('REVISION_CONFLICT','Another device has newer progress. Pending progress is preserved.');
          tx.set(ref(uid),next);
        });
      }
    };
  }
  function createClient({uid, codec, remote, journal, currentUid, status, now=Date.now}) {
    let entry, opened, busy=false, syncing=false, bootReady=false, stopped=false, closed=false, lastAttempt=-Infinity;
    let recovery=null, recoveryBackup=null, recoveryBusy=false, recoveredDigest=null, recoveredRevision=null, pendingExport=null, backupProblem='';
    let localQueue=Promise.resolve();
    // Network waits never hold this queue. Only local journal transitions serialize.
    function serial(action) { const result=localQueue.then(action);localQueue=result.catch(()=>{});return result; }
    const accountGuard = () => { if(closed || currentUid() !== uid) throw error('NOT_READY','Account changed. Reload to load its progress.'); };
    const guard = () => { accountGuard(); if(stopped) throw error('NOT_READY','Progress is blocked. Reload or review recovery before continuing.'); };
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
      return record;
    }
    async function validateLocal(local) {
      if(!local) return;
      if(typeof local.pending!=='boolean' || !(local.base===null || /^[a-f0-9]{64}$/.test(local.base))) throw error('CORRUPT_AUTHORITY','Local account journal is damaged.');
      await codec.verifyRecord(local.record); capacity(local.record);
      if(local.pending && !local.record.revision) throw error('CORRUPT_AUTHORITY','Pending local progress is damaged.');
      if(!local.pending && local.base!==local.record.digest) throw error('CORRUPT_AUTHORITY','Local cloud acknowledgment is damaged.');
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

    async function upload() {
      guard();
      if(!entry?.pending) return;
      lastAttempt=now();
      let snapshot;
      await serial(async()=>{
        guard();
        // Persist the exact upload before touching the network. If acknowledgment
        // is lost, replay this same snapshot; never mistake it for another device.
        if(!entry.uploading) {
          const next={...entry,uploading:{base:entry.base,record:entry.record}};
          await journal.replace(uid,entry,next);entry=next;
        }
        snapshot=entry.uploading;
      });
      const candidate={schema:1, profileId:snapshot.record.profileId, revision:snapshot.record.revision, digest:snapshot.record.digest, record:capacity(snapshot.record)};
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
          await validateLocal(local); guard();pendingExport=local?.pending ? local : null;
          await refreshBackup();guard();
          try {
            const cloud=await remote.read(uid); guard(); const record=await validate(cloud);
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
              entry={base:token(cloud),pending:false,record:record || {format:2,profileId:root.crypto.randomUUID(),revision:0,createdAt:time,updatedAt:time,payload:null,digest:null,origin:null,previous:null,campaigns:{}}};
              await journal.replace(uid,local,entry);
            }
            if(entry.pending) { try { await upload(); } catch(e) { if(!offline(e)) throw e; state('offline'); } }
            else state(entry.record.revision ? 'saved':'ready');
          } catch(e) {
            if(!offline(e) || !local) throw e;
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
          pendingRevision:allowed ? (pendingExport || recoveryBackup)?.record?.revision ?? null : null,
          reason:allowed ? recovery?.blocked || backupProblem || recovery?.reason || (recoveryBackup ? 'The pending copy is protected on this device and can be exported.' : '') : 'Account changed. Reload to load its progress.',
          expectedCloudDigest:allowed ? recovery?.record?.digest || recoveredDigest || null : null
        };
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
          if(pending && backup && !same(pending,backup)) bundle.protectedBackup=backup;
          if(backupProblem) bundle.note='The protected backup could not be verified and remains untouched on this device.';
          const text=JSON.stringify(bundle,null,2);accountGuard();
          return {ok:true,fileName:`little-leaf-pending-recovery-r${saved.record?.revision || 0}.json`,text};
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
            await journal.recover(uid,pending,next,accountGuard);
            accountGuard();entry=next;recoveryBackup=pending;
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
          const next={...entry,pending:true,record};await journal.replace(uid,entry,next);entry=next;guard();state('pending');
          return {ok:true,durable:true,cloudConfirmed:false,profileId,revision:record.revision,creditedCoins:0};
          });
        } catch(e) { if(['REVISION_CONFLICT','NOT_READY'].includes(e.code)){stopped=true;state('conflict');}else state('blocked');return failure(e); }
        finally {busy=false;}
      },
      async sync() { if(syncing || !bootReady || stopped || !entry?.pending || now()-lastAttempt<30000)return;syncing=true;try {await upload();}catch(e){if(offline(e))state('offline');else {stopped=true;state('conflict');}}finally{syncing=false;} },
      save(payload,revision,profileId,callback){client.commit(payload,revision,profileId).then(r=>callback(JSON.stringify(r)));},
      close(){closed=true;stopped=true;state('signed-out');}
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
    return {read:uid=>transaction(uid,null,null,false),replace:(uid,old,next)=>transaction(uid,old,next,true),readRecoveryBackup:uid=>transaction(recoveryBackupKey(uid),null,null,false),recover};
  }
  root.LittleLeafFirebase=Object.freeze({createClient,createRemote,openJournal,capacity,MAX_BYTES});
})(globalThis);
