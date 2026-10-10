/* Optional Firebase vault. No default Web/CG database is opened or migrated. */
(function(root) {
  'use strict';
  const MAX_BYTES = 900000; // leaves >140 KiB for Firestore document/path overhead
  const error = (code, message) => Object.assign(new Error(message), {code});
  const failure = e => ({ok:false, code:e.code || 'CLOUD_ERROR', error:e.message});
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
    let entry, opened, busy=false, syncing=false, bootReady=false, stopped=false, lastAttempt=-Infinity;
    let localQueue=Promise.resolve();
    // Network waits never hold this queue. Only local journal transitions serialize.
    function serial(action) { const result=localQueue.then(action);localQueue=result.catch(()=>{});return result; }
    const guard = () => { if(stopped || currentUid() !== uid) throw error('NOT_READY','Account changed. Reload to load its progress.'); };
    const token = doc => doc ? doc.digest : null;
    function state(value) { status(value); }
    async function validate(doc) {
      if (!doc) return null;
      if(doc.schema !== 1 || typeof doc.record !== 'string') throw error('CORRUPT_AUTHORITY','Cloud save is damaged.');
      const record=JSON.parse(doc.record); await codec.verifyRecord(record); capacity(record);
      if(doc.digest!==record.digest || doc.revision!==record.revision || doc.profileId!==record.profileId) throw error('CORRUPT_AUTHORITY','Cloud save identity is damaged.');
      return record;
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
          if(local) { if(typeof local.pending!=='boolean' || !(local.base===null || /^[a-f0-9]{64}$/.test(local.base))) throw error('CORRUPT_AUTHORITY','Local account journal is damaged.'); await codec.verifyRecord(local.record); capacity(local.record); if(!local.pending && local.base!==local.record.digest) throw error('CORRUPT_AUTHORITY','Local cloud acknowledgment is damaged.');
            if(local.uploading) {
              await codec.verifyRecord(local.uploading.record);capacity(local.uploading.record);
              if(!local.pending || local.uploading.base!==local.base || local.uploading.record.profileId!==local.record.profileId || local.uploading.record.revision<1 || local.uploading.record.revision>local.record.revision)
                throw error('CORRUPT_AUTHORITY','Pending cloud upload is damaged.');
            }
          }
          try {
            const cloud=await remote.read(uid); guard(); const record=await validate(cloud);
            if(local && !local.pending && local.base && !cloud) throw error('CORRUPT_AUTHORITY','Previously saved cloud progress is missing. Local progress is preserved.');
            if(local?.pending) {
              if(token(cloud)===local.record.digest) { const next={...local,base:token(cloud),pending:false,uploading:null}; await journal.replace(uid,local,next); local=next; }
              else if(local.uploading && token(cloud)===local.uploading.record.digest) { const next={...local,base:token(cloud),uploading:null};await journal.replace(uid,local,next);local=next; }
              else if(token(cloud)!==local.base) throw error('REVISION_CONFLICT','Another device has newer progress. Pending progress is preserved on this device; do not overwrite it.');
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
          guard(); const r=entry.record;
          const result={ok:true,source:r.revision?'authority':'fresh',profileId:r.profileId,revision:r.revision,payload:r.payload};
          bootReady=true;client.bootJson=JSON.stringify(result);return result;
        } catch(e) { stopped=true;state(e.code==='REVISION_CONFLICT'?'conflict':'blocked');const result=failure(e);client.bootJson=JSON.stringify(result);return result; }})();return opened;
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
      close(){stopped=true;state('signed-out');}
    };return client;
  }
  // Each read/compare/write is a single IDB transaction; concurrent tabs fail closed.
  async function openJournal(indexedDB) {
    const db=await new Promise((resolve,reject)=>{const q=indexedDB.open('little-leaf.firebase-journal.v1',1);q.onupgradeneeded=()=>q.result.createObjectStore('accounts');q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);q.onblocked=()=>reject(error('STORAGE_BLOCKED','Close other game tabs and reload.'));});
    function transaction(uid,expected,next,write) {return new Promise((resolve,reject)=>{let result,problem;const tx=db.transaction('accounts',write?'readwrite':'readonly'),s=tx.objectStore('accounts'),q=s.get(uid);q.onsuccess=()=>{result=q.result || null;if(write){if(JSON.stringify(result)!==JSON.stringify(expected)){problem=error('REVISION_CONFLICT','Another tab changed this account’s progress. Reload.');tx.abort();}else{s.put(next,uid);result=next;}}};tx.oncomplete=()=>resolve(result);tx.onabort=()=>reject(problem || tx.error);tx.onerror=()=>{};});}
    return {read:uid=>transaction(uid,null,null,false),replace:(uid,old,next)=>transaction(uid,old,next,true)};
  }
  root.LittleLeafFirebase=Object.freeze({createClient,createRemote,openJournal,capacity,MAX_BYTES});
})(globalThis);
