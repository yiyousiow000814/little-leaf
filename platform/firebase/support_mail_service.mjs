import {randomInt} from 'node:crypto';
import {hash,uid,publicUid,uuid,normalizeIssue,verifyRecord,grant,error,parsePayload,validateOwnedTransition} from './support_mail_contract.mjs';

// Trusted Firestore service. All paths, roles and player identities are derived
// here; callable arguments never grant authority. The default flag is closed.
export function createSupportMailService({db,enabled=false,publicUidEnabled=false,now=Date.now,
  randomPublicUid=()=>String(randomInt(100000000000,1000000000000))}) {
  const path=(...segments)=>db.doc(segments.join('/'));
  const role=actor=>path('supportAdmins',actor);
  const identity=player=>path('players',player,'identity','public');
  const publicIndex=id=>path('playerUidIndex',id);
  const save=player=>path('players',player,'saves','cafe');
  const control=player=>path('players',player,'saveControl','protocol');
  const session=player=>path('players',player,'session','owner');
  const mail=(player,id)=>path('players',player,'mail',id);
  const claim=(player,id)=>path('players',player,'mailClaims',id);
  // Read-only legacy evidence. Unified Storage lives only inside saves/cafe.
  const legacyStock=player=>path('players',player,'giftStock','current');
  const audit=id=>path('supportAudit',id);
  const issue=id=>path('supportIssues',id);
  const preview=id=>path('supportPreviews',id);
  const backup=player=>path('players',player,'saveBackups','supportMailV1');
  const caseRef=(player,caseId)=>path('supportCases',hash(player+'\n'+caseId));
  const rate=player=>path('supportRate',player);
  function checkedRate(snapshot,kind,time,limit) {
    const previous=snapshot.data()||{},minute=Math.floor(time/60000);
    const count=previous[kind]?.minute===minute?previous[kind].count:0;
    if(!Number.isSafeInteger(count)||count<0||count>=limit)throw error('RATE_LIMITED','Wait before another support action.');
    return {...previous,schema:1,[kind]:{minute,count:count+1}};
  }
  function active() {if(!enabled)throw error('FEATURE_DISABLED','Support mail is unavailable.');}
  function actor(context) {
    const auth=context?.auth;
    if(!uid(auth?.uid)||auth.token?.firebase?.sign_in_provider!=='google.com')throw error('UNAUTHENTICATED','Sign in with Google.');
    return auth.uid;
  }
  async function authorized(context,capability) {
    active();
    const id=actor(context),r=(await role(id).get()).data();
    if(r?.enabled!==true||!Array.isArray(r.capabilities)||!r.capabilities.includes(capability))throw error('PERMISSION_DENIED','Support access is unavailable.');
    return id;
  }
  function head(doc) {
    if(doc?.schema!==1||typeof doc.record!=='string'||Buffer.byteLength(doc.record)>900000)throw error('CORRUPT_AUTHORITY','Cloud save is invalid.');
    let record;
    try {record=JSON.parse(doc.record);verifyRecord(record);}catch {throw error('CORRUPT_AUTHORITY','Cloud save is invalid.');}
    if(doc.digest!==record.digest||doc.revision!==record.revision||doc.profileId!==record.profileId)throw error('CORRUPT_AUTHORITY','Cloud save identity changed.');
    return record;
  }
  function fence(value,request,time,requireIdle=false) {
    if(!uuid(request.writerId)||!Number.isSafeInteger(request.writerEpoch)||request.writerEpoch<1
      ||value?.schema!==1||value.owner!==request.writerId||value.epoch!==request.writerEpoch
      ||value.ack!==null||(requireIdle&&value.request!==null)||!value.updatedAt?.toMillis
      ||time>=value.updatedAt.toMillis()+60000)throw error('OWNERSHIP_LOST','This device no longer owns the café.');
  }
  function expected(record,request) {
    if(record.profileId!==request.profileId||record.revision!==request.revision||record.digest!==request.digest)
      throw error('REVISION_CONFLICT','Cloud progress changed. Reload before continuing.');
  }
  function docFor(record,old,request) {
    return {schema:1,profileId:record.profileId,revision:record.revision,digest:record.digest,record:JSON.stringify(record),
      writerId:request.writerId,writerEpoch:request.writerEpoch,device:old.device||'Unknown device'};
  }
  // Only the trusted service can allocate/resolve this player-facing identifier.
  // The private auth UID remains the owner of save, mail and session documents.
  async function myPublicUid(context) {
    const player=actor(context);
    for(let attempt=0;attempt<8;attempt++){
      const result=await db.runTransaction(async tx=>{
        const existing=await tx.get(identity(player));
        if(existing.exists){
          const value=existing.data();
          if(value?.schema!==1||!publicUid(value.publicUid))throw error('CORRUPT_IDENTITY','Player UID is unavailable.');
          const paired=await tx.get(publicIndex(value.publicUid));
          if(!paired.exists||paired.data()?.schema!==1||paired.data()?.authUid!==player)
            throw error('CORRUPT_IDENTITY','Player UID is unavailable.');
          return {publicUid:value.publicUid};
        }
        if(!publicUidEnabled)throw error('FEATURE_DISABLED','Player UID allocation is unavailable.');
        const candidate=randomPublicUid();
        if(!publicUid(candidate))throw error('INVALID_UID','Public UID allocator returned an invalid value.');
        const taken=await tx.get(publicIndex(candidate));
        if(taken.exists)return {collision:true};
        tx.create(identity(player),{schema:1,publicUid:candidate});
        tx.create(publicIndex(candidate),{schema:1,authUid:player});
        return {publicUid:candidate};
      });
      if(!result.collision)return result;
    }
    throw error('UID_UNAVAILABLE','Player UID is temporarily unavailable.');
  }
  async function resolvePublic(tx,id) {
    if(!publicUid(id))throw error('INVALID_UID','Enter the exact 12-digit player UID.');
    const indexed=await tx.get(publicIndex(id));
    if(!indexed.exists)throw error('PLAYER_NOT_FOUND','No cloud café exists for that UID.');
    const player=indexed.data()?.authUid;
    if(indexed.data()?.schema!==1||!uid(player))throw error('CORRUPT_IDENTITY','Player UID is unavailable.');
    const paired=await tx.get(identity(player));
    if(!paired.exists||paired.data()?.schema!==1||paired.data()?.publicUid!==id)
      throw error('CORRUPT_IDENTITY','Player UID is unavailable.');
    return player;
  }
  async function lookup(context,recipientPublicUid) {
    const actorId=await authorized(context,'lookup'),time=now();
    if(!publicUid(recipientPublicUid))throw error('INVALID_UID','Enter the exact 12-digit player UID.');
    const found=await db.runTransaction(async tx=>{
      const limit=rate(actorId);
      const [r,quota]=await Promise.all([tx.get(role(actorId)),tx.get(limit)]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('lookup'))throw error('PERMISSION_DENIED','Support access changed.');
      const recipientUid=await resolvePublic(tx,recipientPublicUid);
      const [saved,ctrl,recent]=await Promise.all([tx.get(save(recipientUid)),tx.get(control(recipientUid)),
        tx.get(db.collection(`players/${recipientUid}/mail`).orderBy('issuedAt','desc').limit(10))]);
      const next=checkedRate(quota,'lookup',time,20);
      tx.set(limit,next);
      if(!saved.exists)return {missing:true};
      const record=head(saved.data());
      return {publicUid:recipientPublicUid,profileId:record.profileId,revision:record.revision,
        savedAt:record.updatedAt,timeSource:'client record time',device:saved.data().device||'Unknown device',
        protected:ctrl.exists,evidence:'Current verified save only; historic purchases unavailable.',
        recentMail:recent.docs.map(doc=>({mailId:doc.id,caseId:doc.data().caseId||'',
          status:doc.data().status,issuedAt:doc.data().issuedAt,claimedAt:doc.data().claimedAt})),historyLimit:10};
    });
    if(found.missing)throw error('PLAYER_NOT_FOUND','No cloud café exists for that UID.');
    return found;
  }
  async function capabilities(context) {
    const id=actor(context),r=(await role(id).get()).data();
    return {canLookup:enabled&&r?.enabled===true&&r.capabilities?.includes('lookup')===true,
      canIssue:enabled&&r?.enabled===true&&r.capabilities?.includes('issue')===true};
  }
  async function previewMail(context,input) {
    const actorId=await authorized(context,'issue'),value=normalizeIssue(input),time=now();
    const normalizedHash=hash(JSON.stringify(value));
    return db.runTransaction(async tx=>{
      const limit=rate(actorId);
      const [r,quota,p,existing]=await Promise.all([tx.get(role(actorId)),tx.get(limit),tx.get(preview(value.issueId)),
        tx.get(issue(value.issueId))]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('issue'))throw error('PERMISSION_DENIED','Support access changed.');
      if(existing.exists)throw error('ISSUE_EXISTS','This issue was already sent. Check its status.');
      if(p.exists&&p.data().requestHash!==normalizedHash)throw error('ISSUE_CONFLICT','Issue ID was already used for different content.');
      const recipientUid=await resolvePublic(tx,value.recipientPublicUid);
      const s=await tx.get(save(recipientUid));
      if(!s.exists)throw error('PLAYER_NOT_FOUND','No cloud café exists for that UID.');
      const record=head(s.data());
      if(record.profileId!==value.profileId)throw error('PROFILE_CHANGED','Recipient café changed.');
      tx.set(limit,checkedRate(quota,'preview',time,10));
      tx.set(preview(value.issueId),{schema:1,actorUid:actorId,requestHash:normalizedHash,
        recipientUid,recipientPublicUid:value.recipientPublicUid,profileId:value.profileId,createdAt:time,expiresAt:time+10*60*1000});
      return {issueId:value.issueId,previewHash:normalizedHash,expiresAt:time+10*60*1000,
        recipientPublicUid:value.recipientPublicUid,profileId:value.profileId,subject:value.subject,body:value.body,
        coins:value.coins,items:value.items,caseId:value.caseId};
    });
  }
  async function issueMail(context,input) {
    const actorId=await authorized(context,'issue'),value=normalizeIssue(input),time=now();
    const normalizedHash=hash(JSON.stringify(value));
    return db.runTransaction(async tx=>{
      const limit=rate(actorId);
      const [r,quota,p,existing]=await Promise.all([tx.get(role(actorId)),tx.get(limit),tx.get(preview(value.issueId)),
        tx.get(issue(value.issueId))]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('issue'))throw error('PERMISSION_DENIED','Support access changed.');
      if(existing.exists){
        if(existing.data().requestHash!==normalizedHash||existing.data().actorUid!==actorId)throw error('ISSUE_CONFLICT','Issue ID was already used.');
        return {mailId:value.issueId,status:'sent',alreadyIssued:true};
      }
      const recipientUid=await resolvePublic(tx,value.recipientPublicUid);
      const [usedCase,s]=await Promise.all([tx.get(caseRef(recipientUid,value.caseId)),tx.get(save(recipientUid))]);
      if(usedCase.exists)throw error('CASE_ALREADY_ISSUED','This recipient and case already have a letter.');
      if(!p.exists||p.data().actorUid!==actorId||p.data().requestHash!==normalizedHash
        ||p.data().recipientUid!==recipientUid||p.data().expiresAt<time)
        throw error('PREVIEW_EXPIRED','Review the exact letter again before sending.');
      if(!s.exists||head(s.data()).profileId!==value.profileId)throw error('PROFILE_CHANGED','Recipient café changed.');
      tx.set(limit,checkedRate(quota,'issue',time,5));
      const payload={schema:1,mailId:value.issueId,issueId:value.issueId,caseId:value.caseId,profileId:value.profileId,
        title:value.subject,body:value.body,coins:value.coins,items:value.items,
        issuedAt:time,status:'unclaimed',claimedAt:null};
      tx.create(issue(value.issueId),{...value,recipientUid,requestHash:normalizedHash,actorUid:actorId,issuedAt:time});
      tx.create(caseRef(recipientUid,value.caseId),{issueId:value.issueId,recipientUid,recipientPublicUid:value.recipientPublicUid,caseId:value.caseId});
      tx.create(mail(recipientUid,value.issueId),payload);
      tx.create(audit(value.issueId+'-issued'),{type:'issued',issueId:value.issueId,actorUid:actorId,
        recipientUid,recipientPublicUid:value.recipientPublicUid,profileId:value.profileId,requestHash:normalizedHash,at:time});
      return {mailId:value.issueId,status:'sent',alreadyIssued:false};
    });
  }
  async function listMyMail(context,cursor=null) {
    const player=actor(context);
    const saved=await save(player).get();
    if(!saved.exists)throw error('MAIL_UNAVAILABLE','Open a cloud café before reading mail.');
    const profileId=head(saved.data()).profileId;
    let query=db.collection(`players/${player}/mail`).orderBy('issuedAt','desc').limit(21);
    if(cursor!==null){if(!uuid(cursor))throw error('INVALID_CURSOR','Invalid mail page.');
      const previous=await mail(player,cursor).get();if(!previous.exists)throw error('INVALID_CURSOR','Mail page changed.');
      query=query.startAfter(previous);
    }
    const page=await query.get(),window=page.docs.slice(0,20),rows=window.map(s=>s.data()).filter(m=>m.profileId===profileId);
    return {profileId,mail:rows,nextCursor:page.docs.length>20?window.at(-1).id:null};
  }
  function unifiedProtocol(record, ctrl, legacy) {
    if (legacy.exists || (record.format===3 && parsePayload(record.payload).version!==17))
      throw error('STORAGE_REVIEW_REQUIRED','Earlier gift stock is preserved and needs review.');
    if (ctrl.exists) {
      const value=ctrl.data();
      if (record.format!==3 || value?.schema!==1 || value.version!==1
        || value.claimSequence!==record.mailState.claimSequence || value.stockRevision!==record.mailState.stockRevision)
        throw error('PROTOCOL_CHANGED','Save protocol changed.');
    } else if (record.format===3) throw error('PROTOCOL_CHANGED','Save protocol changed.');
  }
  async function claimMail(context,request) {
    active();
    const player=actor(context);
    if(!uuid(request?.mailId)||!uuid(request?.operationId))throw error('INVALID_CLAIM','Invalid claim request.');
    return db.runTransaction(async tx=>{
      const [m,c,s,ctrl,own,g,b]=await Promise.all([tx.get(mail(player,request.mailId)),tx.get(claim(player,request.mailId)),
        tx.get(save(player)),tx.get(control(player)),tx.get(session(player)),tx.get(legacyStock(player)),tx.get(backup(player))]);
      const time=now();
      if(!m.exists||!s.exists)throw error('MAIL_UNAVAILABLE','This letter is unavailable.');
      const current=head(s.data());
      fence(own.data(),request,time,true);
      unifiedProtocol(current,ctrl,g);
      if(c.exists){if(m.data().status!=='claimed')throw error('CORRUPT_MAIL','Claim state is inconsistent.');
        return {status:'claimed',receipt:c.data(),record:current};}
      if(m.data().status!=='unclaimed')throw error('CORRUPT_MAIL','Claim state is inconsistent.');
      expected(current,request);
      const awarded=grant(current,m.data(),null,time),receipt={schema:1,mailId:request.mailId,
        issueId:m.data().issueId,operationId:request.operationId,coins:m.data().coins,items:m.data().items,
        claimedAt:time,claimSequence:awarded.record.mailState.claimSequence,fromDigest:current.digest,
        toDigest:awarded.record.digest,fromRevision:current.revision,toRevision:awarded.record.revision,
        profileId:current.profileId};
      if(!ctrl.exists){
        if(b.exists)throw error('PROTOCOL_CHANGED','Migration backup already exists without control.');
        tx.create(backup(player),{schema:1,record:s.data().record,digest:current.digest,at:time});
      }
      tx.set(control(player),{schema:1,version:1,claimSequence:awarded.record.mailState.claimSequence,
        stockRevision:awarded.record.mailState.stockRevision});
      tx.set(save(player),docFor(awarded.record,s.data(),request));
      tx.create(claim(player,request.mailId),receipt);
      tx.update(mail(player,request.mailId),{status:'claimed',claimedAt:time});
      tx.create(audit(request.mailId+'-claimed'),{type:'claimed',actorUid:player,recipientUid:player,
        mailId:request.mailId,operationId:request.operationId,fromDigest:current.digest,toDigest:awarded.record.digest,at:time});
      return {status:'claimed',receipt,record:awarded.record};
    });
  }
  async function commitProtectedSave(context,request) {
    const player=actor(context),candidate=request?.candidate;
    verifyRecord(candidate);
    if(candidate.format!==3)throw error('PROTOCOL_CHANGED','Update the game to save this café.');
    return db.runTransaction(async tx=>{
      const [s,ctrl,own,g]=await Promise.all([tx.get(save(player)),tx.get(control(player)),tx.get(session(player)),tx.get(legacyStock(player))]);
      const time=now();
      if(!s.exists||!ctrl.exists)throw error('PROTOCOL_CHANGED','Protected save is unavailable.');
      fence(own.data(),request,time);
      const current=head(s.data()),protocol=ctrl.data();
      unifiedProtocol(current,ctrl,g);
      if(current.digest===candidate.digest)return {status:'saved',record:current};
      expected(current,request);
      if(current.format!==3||protocol.version!==1||protocol.claimSequence!==current.mailState.claimSequence
        ||protocol.stockRevision!==current.mailState.stockRevision
        ||candidate.revision<=current.revision||candidate.profileId!==current.profileId
        ||candidate.createdAt!==current.createdAt||JSON.stringify(candidate.origin)!==JSON.stringify(current.origin)
        ||JSON.stringify(candidate.campaigns)!==JSON.stringify(current.campaigns)
        ||candidate.mailState.claimSequence!==current.mailState.claimSequence
        ||candidate.previous!==null)
        throw error('PROTOCOL_CHANGED','Save was based on an old claim or café. Reload.');
      validateOwnedTransition(current,candidate);
      tx.set(save(player),docFor(candidate,s.data(),request));
      tx.set(control(player),{...protocol,stockRevision:candidate.mailState.stockRevision});
      return {status:'saved',record:candidate};
    });
  }
  return {myPublicUid,capabilities,lookup,previewMail,issueMail,listMyMail,claimMail,commitProtectedSave};
}
