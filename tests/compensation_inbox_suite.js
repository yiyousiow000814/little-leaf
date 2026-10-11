/* Shared real-browser / deterministic transaction tests. Synthetic data only. */
async function runInboxSuite(env) {
  const { vault, oldVault, factory, storePrototype, markers, storage } = env;
  const checks = [], check = (ok, name) => { if (!ok) throw Error(name); checks.push(name); };
  let serial = 0;
  const campaign = vault.CAMPAIGNS[0], profile2 = '22222222-2222-4222-8222-222222222222';
  const legacy = JSON.stringify({ schema:'little_leaf_reconstructed_cafe', version:13, new_reconstruction:true, checkout_format:'little_leaf.checkout.v1', coins:2000, synthetic:'é中文' });
  const payload = JSON.stringify({ ...JSON.parse(legacy), version:15, layout_motion_format:'little_leaf.layout_motion.v1' });
  const scoped = () => { const prefix = 'inbox-synthetic-' + env.runId + '-' + (++serial) + '-'; return { open(name, version) { return version === undefined ? factory.open(prefix + name) : factory.open(prefix + name, version); } }; };
  const open = (idb, name, version) => new Promise((resolve,reject) => { const q = version === undefined ? idb.open(name) : idb.open(name,version); q.onupgradeneeded=()=>q.result.createObjectStore('FILE_DATA');q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error); });
  const record = async (idb, legacyOnly=false) => { const db=await open(idb,legacyOnly?'/userfs':vault.DB_NAME);try{return await new Promise((resolve,reject)=>{const tx=db.transaction(legacyOnly?'FILE_DATA':'profiles','readonly'),q=tx.objectStore(legacyOnly?'FILE_DATA':'profiles').get(legacyOnly?'/userfs/synthetic/little_leaf_cafe_v13.json':'active');tx.oncomplete=()=>resolve(q.result);tx.onabort=()=>reject(tx.error);});}finally{db.close();} };
  const seed = async idb => { const db=await open(idb,'/userfs',21);try{await new Promise((resolve,reject)=>{const tx=db.transaction('FILE_DATA','readwrite');tx.objectStore('FILE_DATA').put({contents:new Int8Array(new TextEncoder().encode(legacy).buffer),mode:33188,timestamp:new Date(1000)},'/userfs/synthetic/little_leaf_cafe_v13.json');tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});}finally{db.close();} };
  const setup = async (api=vault,config) => { const idb=scoped();await seed(idb);const client=api.createClient({indexedDB:idb,...(config?{campaigns:config}:{})});const boot=await client.boot();check(boot.ok,'synthetic boot '+serial);return {idb,client,boot}; };
  const save = s => s.client.commit(payload,JSON.parse(s.client.bootJson).revision,s.boot.profileId);
  const snapshot = client => JSON.parse(client.snapshotJson());
  // 0.1.8 writer seeds the already-paid envelope; the new reader must expose
  // historical and retired receipts without needing another save.
  let s=await setup(oldVault);await save(s);
  const original=JSON.stringify(await record(s.idb)), originalLegacy=JSON.stringify(await record(s.idb,true));
  let client=vault.createClient({indexedDB:s.idb,campaigns:[{...campaign,coins:999,state:'retired'}]});let boot=await client.boot();
  check(boot.ok && snapshot(client).paid[0].coins===1000,'historical 0.1.8 receipt amount survives changed retired config');
  check(boot.inbox.paid[0].revision===1 && boot.inbox.paid[0].status==='granted','boot projects original durable receipt');
  const projection=snapshot(client);projection.paid[0].coins=900;projection.paid.push({id:'fake'});
  check(snapshot(client).paid.length===1 && snapshot(client).paid[0].coins===1000,'serialized projection cannot mutate receipt authority');
  let read=markers.createClient({storage});const receipt=snapshot(client).paid[0];
  check(!read.isRead(boot.profileId,receipt.id,receipt.revision),'missing sidecar is unread');
  read.markRead(boot.profileId,receipt.id,receipt.revision,true);
  check(markers.createClient({storage}).isRead(boot.profileId,receipt.id,receipt.revision),'detail acknowledgement persists across adapter reload');
  check(!read.isRead(profile2,receipt.id,receipt.revision),'same grant in another profile stays unread');
  check(!read.isRead(boot.profileId,receipt.id,receipt.revision+1),'future grant revision stays unread');
  check(JSON.stringify(await record(s.idb))===original && JSON.stringify(await record(s.idb,true))===originalLegacy,'snapshot/read/reopen leave current, previous, digest, payload and legacy bytes unchanged');
  const stale=markers.createClient({storage}), other=markers.createClient({storage});
  stale.markRead(boot.profileId,'archived-second',2,true);other.markRead(boot.profileId,'archived-third',3,true);
  check(markers.createClient({storage}).isRead(boot.profileId,'archived-second',2)&&stale.isRead(boot.profileId,'archived-third',3),'stale clients cannot overwrite different acknowledgements');
  storage.setItem(markers.PREFIX+profile2+'/'+campaign.id+'/1','malformed');
  check(!markers.createClient({storage}).isRead(profile2,campaign.id,1),'corrupt sidecar marker is unread');
  storage.clear();
  check(!markers.createClient({storage}).isRead(boot.profileId,receipt.id,receipt.revision),'cleared markers restore unread only');
  const afterClear=await client.commit(boot.payload,boot.revision,boot.profileId);
  check(afterClear.ok && afterClear.creditedCoins===0,'clearing read markers cannot regrant retired compensation');
  const denied={getItem(){throw Error('denied');},setItem(){throw Error('denied');},get length(){throw Error('denied');}};
  read=markers.createClient({storage:denied});check(!read.isRead(boot.profileId,receipt.id,receipt.revision),'denied marker read stays unread');read.markRead(boot.profileId,receipt.id,receipt.revision,true);
  check(read.isRead(boot.profileId,receipt.id,receipt.revision)&&read.notice.includes('after reload'),'denied writes retain session read with honest notice');
  const silentLoss={getItem(){return null;},setItem(){},length:0};read=markers.createClient({storage:silentLoss});read.markRead(boot.profileId,receipt.id,receipt.revision,true);check(read.notice.includes('after reload'),'unretained marker write is detected');
  read=markers.createClient({storage});read.markRead(boot.profileId,receipt.id,receipt.revision,false);check(read.isRead(boot.profileId,receipt.id,receipt.revision)&&storage.length===0,'suppressed/review acknowledgement is session only');
  check(!read.markRead('invalid',receipt.id,1,true)&&!read.markRead(boot.profileId,'../bad',1,true)&&!read.markRead(boot.profileId,receipt.id,0,true),'invalid marker identities cannot create keys');
  for(let i=0;i<markers.MAX_MARKERS;i++) storage.setItem(markers.PREFIX+'synthetic-bound-'+i,'1');
  read=markers.createClient({storage});read.markRead(boot.profileId,receipt.id,receipt.revision,true);check(storage.length===markers.MAX_MARKERS&&read.notice.includes('after reload'),'sidecar storage limit falls back to session without deleting other markers');storage.clear();
  // Retention changes only the presentation sidecar. The input below is a
  // projection of the historical, verified 0.1.8 receipt, not a new award.
  const retentionSource = client.snapshotJson(), retentionSnapshot = JSON.parse(retentionSource);
  const retainedProfile = retentionSnapshot.profileId, retainedReceipt = retentionSnapshot.paid[0];
  const grantTime = retainedReceipt.grantedAt, duration = markers.RETENTION_MS;
  const readKey = markers.PREFIX + retainedProfile + '/' + retainedReceipt.id + '/' + retainedReceipt.revision;
  const expiryKey = markers.EXPIRED_PREFIX + retainedProfile + '/' + retainedReceipt.id + '/' + retainedReceipt.revision;
  const futureKey = markers.FUTURE_PREFIX + retainedProfile + '/' + retainedReceipt.id + '/' + retainedReceipt.revision;
  const firstAnchorKey = futureKey + '/' + grantTime;
  const clockKey = markers.CLOCK_PREFIX + retainedProfile;
  const storedBytes = () => JSON.stringify(Array.from({length:storage.length},(_,i)=>storage.key(i)).sort().map(key=>[key,storage.getItem(key)]));
  const view = (reader, source = retentionSource, persist = true) => JSON.parse(reader.visibleSnapshotJson(typeof source === 'string' ? source : JSON.stringify(source), persist));
  const authorityBeforeRetention = JSON.stringify(await record(s.idb));
  const legacyBeforeRetention = JSON.stringify(await record(s.idb,true));
  let realNow = grantTime + duration - 1;
  read = markers.createClient({storage,now:()=>realNow});
  let visible = view(read);
  check(duration===14*86400000 && visible.paid.length===1 && visible.retentionDays===14,'letter remains visible until one millisecond before 14 real days');
  check(visible.paid[0].grantedAt===grantTime && visible.paid[0].deliveredAt===grantTime && visible.displayNow===realNow,'ordinary display keeps the immutable delivery timestamp');
  check(view(read).paid.length===1 && client.snapshotJson()===retentionSource,'repeated views neither duplicate letters nor modify the source snapshot');
  const unrelatedKeys = [markers.PREFIX+profile2+'/'+retainedReceipt.id+'/'+retainedReceipt.revision,markers.PREFIX+retainedProfile+'/'+retainedReceipt.id+'/'+(retainedReceipt.revision+1),markers.PREFIX+retainedProfile+'/unrelated-campaign/1','unrelated-local-preference'];
  for(const key of unrelatedKeys) storage.setItem(key,'keep');
  read.markRead(retainedProfile,retainedReceipt.id,retainedReceipt.revision,true);
  realNow++;
  check(view(read).paid.length===0 && storage.getItem(readKey)===null,'exact 14-day boundary removes the letter and its exact disposable read marker');
  check(unrelatedKeys.every(key=>storage.getItem(key)==='keep') && storage.getItem(expiryKey)==='1','expiration retains unrelated profiles, revisions, campaigns and preferences');
  check(view(read).paid.filter(r=>!read.isRead(retainedProfile,r.id,r.revision)).length===0,'expired letters contribute no unread count');
  realNow=grantTime;
  const staleReader=markers.createClient({storage,now:()=>realNow});
  check(view(staleReader).paid.length===0 && view(staleReader).displayNow===grantTime+duration,'reload and stale tabs read the retained high-water time after clock rollback');
  // Simulate an interleaved stale tab writing the clock after a newer tab.
  storage.setItem(clockKey,String(grantTime));
  check(view(markers.createClient({storage,now:()=>realNow})).paid.length===0,'independent expired metadata prevents resurrection even after a stale clock overwrite');
  check(!staleReader.markRead(retainedProfile,retainedReceipt.id,retainedReceipt.revision,true) && storage.getItem(readKey)===null,'a stale detail cannot recreate an expired read marker');
  const anotherProfile={...retentionSnapshot,profileId:profile2};
  check(view(staleReader,anotherProfile).paid.length===1,'another profile has independent clock and expiration metadata');
  realNow=grantTime+duration;
  const nextRevision={...retentionSnapshot,revision:retentionSnapshot.revision+1,paid:[{...retainedReceipt,revision:retentionSnapshot.revision+1,grantedAt:realNow}]};
  check(view(staleReader,nextRevision).paid.length===1,'the same campaign at a new grant revision has an independent letter identity');
  storage.clear();realNow=grantTime+duration+30*86400000;
  check(view(markers.createClient({storage,now:()=>realNow})).paid.length===0,'first launch after more than 14 offline days hides the historical letter immediately');
  check(JSON.stringify(await record(s.idb))===authorityBeforeRetention && JSON.stringify(await record(s.idb,true))===legacyBeforeRetention,'expiry, pruning, clock rollback and offline filtering leave wallet, receipts, digest, current, previous and legacy bytes untouched');
  storage.clear();realNow=grantTime;
  const futureSnapshot={...retentionSnapshot,paid:[{...retainedReceipt,grantedAt:grantTime+365*86400000}]};
  const futureSource=JSON.stringify(futureSnapshot);
  read=markers.createClient({storage,now:()=>realNow});visible=view(read,futureSource);
  check(visible.paid.length===1 && visible.paid[0].deliveredAt===grantTime && visible.paid[0].grantedAt===futureSnapshot.paid[0].grantedAt && read.notice.includes('future-dated'),'future grant retains its immutable timestamp and openly uses a fixed first-visit display anchor');
  realNow+=86400000;
  check(view(markers.createClient({storage,now:()=>realNow}),futureSource).paid[0].deliveredAt===grantTime && storage.getItem(firstAnchorKey)==='1' && storage.getItem(futureKey)===null,'append-only future delivery anchor stays fixed across visits and adapter reloads');
  storage.setItem(clockKey,String(grantTime-3600000));realNow=grantTime-3600000;
  check(view(markers.createClient({storage,now:()=>realNow}),futureSource).paid[0].deliveredAt===grantTime,'an intact future anchor never moves when the clock metadata rolls backward');
  realNow=grantTime+duration-1;
  check(view(read,futureSource).paid.length===1,'future-dated letter remains visible until its fixed 14-day boundary');
  realNow++;
  check(view(read,futureSource).paid.length===0 && storage.getItem(firstAnchorKey)==='1','future grant is bounded to 14 days and preserves its anchor after expiry');
  realNow=grantTime;
  check(view(markers.createClient({storage,now:()=>realNow}),futureSource).paid.length===0 && JSON.stringify(futureSnapshot)===futureSource,'expired future mail cannot return after rollback while metadata remains intact');
  storage.clear();realNow=grantTime+86400000;storage.setItem(futureKey,String(grantTime));
  check(view(markers.createClient({storage,now:()=>realNow}),futureSource).paid[0].deliveredAt===grantTime && storage.getItem(futureKey)===String(grantTime) && storage.getItem(firstAnchorKey)===null,'legacy exact future anchors remain readable and are never rewritten');
  storage.clear();
  // Both first visits read no anchor. The earlier write completes just before
  // the delayed later write, reproducing a last-writer-wins exact-key race.
  let pendingAnchor=null, interleaved=false, delayedView;
  const interleavedStorage={
    get length(){return storage.length;},key(i){return storage.key(i);},getItem(key){return storage.getItem(key);},removeItem(key){storage.removeItem(key);},
    setItem(key,value){
      const isAnchor=key===futureKey || key.startsWith(futureKey+'/');
      if(isAnchor && !interleaved){
        interleaved=true;pendingAnchor=[key,value];
        delayedView=view(markers.createClient({storage:interleavedStorage,now:()=>grantTime+86400000}),futureSource);
        return;
      }
      if(isAnchor && pendingAnchor){storage.setItem(...pendingAnchor);pendingAnchor=null;}
      storage.setItem(key,value);
    }
  };
  view(markers.createClient({storage:interleavedStorage,now:()=>grantTime}),futureSource);
  check(interleaved && delayedView.paid[0].deliveredAt===grantTime && storage.getItem(firstAnchorKey)==='1' && storage.getItem(futureKey+'/'+(grantTime+86400000))==='1','interleaved first visits retain both immutable anchors and immediately select the earliest');
  realNow=grantTime+duration;
  check(view(markers.createClient({storage,now:()=>realNow}),futureSource).paid.length===0 && JSON.stringify(futureSnapshot)===futureSource,'reload expires future mail at the earliest first-seen boundary after a delayed writer');
  storage.clear();realNow=grantTime+duration;
  storage.setItem(readKey,'1');storage.setItem('unrelated-local-preference','keep');
  const reviewBefore=storedBytes();read=markers.createClient({storage,now:()=>realNow});
  check(view(read,retentionSource,false).paid.length===0 && storedBytes()===reviewBefore,'review/suppressed expiry writes no clock or expired metadata and deletes no stored markers');
  realNow=grantTime;
  check(view(read,retentionSource,false).paid.length===0 && storedBytes()===reviewBefore,'review uses session high-water without persistent writes after clock rollback');
  read=markers.createClient({storage,now:()=>realNow});visible=view(read,futureSource,false);
  check(visible.paid[0].deliveredAt===grantTime && storedBytes()===reviewBefore,'review future-date fallback is session-only and does not create an anchor');
  read.markRead(retainedProfile,'review-only-letter',1,false);
  check(storedBytes()===reviewBefore,'review acknowledgement and retention remain wholly read-only in storage');
  storage.clear();realNow=grantTime;
  read=markers.createClient({storage:denied,now:()=>realNow});
  check(view(read,futureSource).paid.length===1 && read.notice.includes('after reload'),'denied metadata storage shows an honest session-only timing notice');
  realNow=grantTime+duration;
  check(view(read,futureSource).paid.length===0,'denied storage still expires future mail after 14 days within the session');
  realNow=grantTime;
  check(view(read,futureSource).paid.length===0,'denied storage preserves expiry through backward clock changes in the same session');
  check(view(markers.createClient({storage:denied,now:()=>realNow}),futureSource).paid.length===1,'unavailable metadata cannot promise rollback protection after reload');
  realNow=grantTime+duration;
  check(view(markers.createClient({storage:denied,now:()=>realNow})).paid.length===0,'normal grant expiry works after reload with denied storage and an accurate clock');
  read=markers.createClient({storage:silentLoss,now:()=>realNow});
  check(view(read).paid.length===0 && read.notice.includes('after reload'),'silently discarded retention writes are detected without showing expired mail');
  storage.clear();realNow=grantTime;
  const malformedBefore=storedBytes();read=markers.createClient({storage,now:()=>realNow});
  const invalidSources=['not json',{...retentionSnapshot,ok:false},{...retentionSnapshot,profileId:'invalid'},{...retentionSnapshot,paid:[{...retainedReceipt,grantedAt:null}]},{...retentionSnapshot,paid:[retainedReceipt,retainedReceipt]}];
  check(invalidSources.every(source=>!view(read,source).ok) && storedBytes()===malformedBefore,'invalid, failed and duplicate receipt projections cause no metadata writes or deletes');
  for(let i=0;i<markers.MAX_METADATA;i++)storage.setItem(markers.DISPLAY_PREFIX+'synthetic-bound-'+i,'1');
  read=markers.createClient({storage,now:()=>realNow});visible=view(read,futureSource);
  check(visible.paid.length===1 && storage.length===markers.MAX_METADATA && read.notice.includes('after reload'),'bounded retention metadata falls back to session without deleting unrelated keys');
  realNow=grantTime+duration;
  check(view(read,futureSource).paid.length===0 && storage.length===markers.MAX_METADATA,'metadata capacity exhaustion still expires a session letter');
  const manyFuture={...futureSnapshot,paid:Array.from({length:markers.MAX_MARKERS+1},(_,i)=>({...futureSnapshot.paid[0],id:'synthetic-future-'+i}))};
  realNow=grantTime;read=markers.createClient({storage:denied,now:()=>realNow});
  check(view(read,manyFuture).paid.length===markers.MAX_MARKERS && read.notice.includes('hidden'),'future letters without room for a stable anchor stay hidden instead of getting a sliding lifetime');
  realNow=grantTime+86400000;
  check(view(read,manyFuture).paid.every(r=>r.deliveredAt===grantTime),'bounded future session anchors never rebase on a later visit');
  realNow=grantTime+duration;
  check(view(read,manyFuture).paid.length===0,'large future receipt lists remain bounded by the 14-day session limit');
  storage.clear();
  const afterExpiry=await client.commit(JSON.parse(client.bootJson).payload,retentionSnapshot.revision,retainedProfile);
  check(afterExpiry.ok && afterExpiry.creditedCoins===0 && snapshot(client).paid.length===1 && snapshot(client).paid[0].grantedAt===grantTime,'clearing disposable retention state cannot erase the receipt, change delivery time or grant compensation twice');
  s=await setup();const full=JSON.stringify({...JSON.parse(payload),coins:999999500});let result=await s.client.commit(full,0,s.boot.profileId);
  check(result.ok&&result.creditedCoins===0&&snapshot(s.client).paid.length===0&&snapshot(s.client).deferred[0].reason==='wallet_cap','wallet-cap state is deferred, never a paid receipt');
  client=vault.createClient({indexedDB:s.idb});boot=await client.boot();check(snapshot(client).deferred.length===1&&snapshot(client).paid.length===0,'pending eligibility reconstructed by verified planner after reload');
  read=markers.createClient({storage});check(!read.markRead(boot.profileId,campaign.id,0,true),'pending entry has no paid grant acknowledgement identity');
  result=await client.commit(payload,boot.revision,boot.profileId);check(result.ok&&result.creditedCoins===1000&&snapshot(client).deferred.length===0&&snapshot(client).paid.length===1,'deferred amount becomes paid only after durable save');
  check(!read.isRead(boot.profileId,campaign.id,result.revision),'later paid message is newly unread');
  // Failed writes, request-success abort, race loser and lost acknowledgement.
  for(const failure of ['quota','abort']) {
    s=await setup();const before=s.client.snapshotJson(),put=storePrototype.put;
    storePrototype.put=function(){if(this.name==='profiles'&&failure==='quota')throw new DOMException('Synthetic quota','QuotaExceededError');const q=put.apply(this,arguments);if(this.name==='profiles')q.addEventListener('success',()=>this.transaction.abort());return q;};
    try{result=await save(s);}finally{storePrototype.put=put;}
    check(!result.ok&&s.client.snapshotJson()===before&&Object.keys((await record(s.idb)).campaigns).length===0,failure+' cannot project tentative paid receipt');
    result=await save(s);check(result.ok&&result.creditedCoins===1000&&snapshot(s.client).paid.length===1,failure+' retries once durably');
  }
  s=await setup();client=vault.createClient({indexedDB:s.idb});boot=await client.boot();const pair=await Promise.all([save(s),client.commit(payload,boot.revision,boot.profileId)]);
  check(pair.filter(x=>x.ok).length===1&&pair.filter(x=>!x.ok&&['REVISION_CONFLICT','SAVE_BUSY'].includes(x.code)).length===1,'racing writers have one winner under revision CAS or exclusive lock');
  check([s.client,client].filter(c=>snapshot(c).paid.length===1).length===1,'race loser never displays pending grant as paid');
  client=vault.createClient({indexedDB:s.idb});boot=await client.boot();check(snapshot(client).paid.length===1,'reload after lost response recovers paid history');
  result=await client.commit(boot.payload,boot.revision,boot.profileId);check(result.creditedCoins===0&&snapshot(client).paid.length===1,'lost acknowledgement cannot double-credit or duplicate message');
  check(snapshot(client).paid[0].revision===1&&snapshot(client).revision===2,'ordinary autosave preserves grant revision');
  // Retained unknown IDs and immutable chronology do not depend on today's config.
  s=await setup(vault,[campaign,{...campaign,id:'retired-unknown-compensation',state:'disabled'}]);await save(s);
  client=vault.createClient({indexedDB:s.idb,campaigns:[{...campaign,state:'retired'},{...campaign,id:'retired-unknown-compensation',coins:200,state:'enabled'}]});boot=await client.boot();result=await client.commit(boot.payload,boot.revision,boot.profileId);
  check(snapshot(client).paid.length===2&&snapshot(client).paid[0].id==='retired-unknown-compensation'&&snapshot(client).paid[0].revision===2,'newest grant sorts first and retains independent amount');
  const state=await record(s.idb);state.campaigns[campaign.id].coins=9000;
  const db=await open(s.idb,vault.DB_NAME);await new Promise((resolve,reject)=>{const tx=db.transaction('profiles','readwrite');tx.objectStore('profiles').put(state,'active');tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});db.close();
  const corrupt=vault.createClient({indexedDB:s.idb});const rejected=await corrupt.boot();
  check(!rejected.ok&&rejected.code==='CORRUPT_AUTHORITY'&&!snapshot(corrupt).ok,'checksum-rejected receipts cannot leak into paid snapshot');
  check(JSON.stringify(await record(s.idb))===JSON.stringify(state),'rejected snapshot reads leave corrupted authority unchanged');
  const fresh=vault.createClient({indexedDB:scoped()});const freshBoot=await fresh.boot();
  check(freshBoot.ok&&freshBoot.source==='fresh'&&snapshot(fresh).paid.length===0&&snapshot(fresh).deferred.length===0,'fresh identity has empty Inbox, never balance-based compensation');
  return {passed:true,checks,synthetic_only:true};
}
if(typeof module!=='undefined')module.exports=runInboxSuite;
