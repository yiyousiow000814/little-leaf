import {randomInt} from 'node:crypto';
import {hash,uid,publicUid,uuid,normalizeIssue,normalizeAudienceIssue,verifyRecord,grant,error,parsePayload,validateOwnedTransition} from './support_mail_contract.mjs';

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
      canIssue:enabled&&r?.enabled===true&&r.capabilities?.includes('issue')===true,
      canIssueMany:enabled&&r?.enabled===true&&r.capabilities?.includes('issue')===true&&r.capabilities?.includes('issue_many')===true,
      canIssueAll:enabled&&r?.enabled===true&&r.capabilities?.includes('issue')===true&&r.capabilities?.includes('issue_all')===true};
  }
  async function previewMail(context,input) {
    if(input?.audience)return prepareAudience(context,input);
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
    if(input?.audience)return issueAudience(context,input);
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
  const PREPARE_PAGE=50, DELIVERY_PAGE=10;
  const member=(id,index)=>path('supportPreviews',id,'recipients',String(index).padStart(12,'0'));
  const delivered=(id,index)=>path('supportPreviews',id,'deliveries',String(index).padStart(12,'0'));
  function audienceCapability(value) {
    return value.audience.mode==='all'?'issue_all':value.audience.publicUids.length>1?'issue_many':'issue';
  }
  function requireAudienceRole(snapshot,value) {
    const r=snapshot.data();
    if(r?.enabled!==true||!Array.isArray(r.capabilities)||!r.capabilities.includes('issue')
      ||!r.capabilities.includes(audienceCapability(value)))throw error('PERMISSION_DENIED','Support audience access changed.');
  }
  function recipientMailId(issueId,player) {
    const h=hash('little-leaf-support-mail-v1\n'+issueId+'\n'+player);
    return `${h.slice(0,8)}-${h.slice(8,12)}-5${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
  }
  function audienceReview(value,p) {
    return {...value,status:p.status==='preparing'?'preparing':'ready',previewHash:p.previewHash||null,
      preparedCount:p.count,recipientCount:p.status==='preparing'?null:p.count,expiresAt:p.expiresAt,
      captureStartedAt:p.createdAt,captureCompletedAt:p.completedAt||null,
      totals:p.status==='preparing'?null:{coins:value.coins*p.count,
        items:value.items.map(item=>({catalogId:item.catalogId,quantity:item.quantity*p.count}))},
      scope:value.audience.mode==='all'?'Cloud cafés found during this review':'Selected player UIDs'};
  }
  async function prepareAudience(context,input) {
    const value=normalizeAudienceIssue(input),actorId=await authorized(context,audienceCapability(value));
    const requestHash=hash(JSON.stringify(value)),time=now();
    return db.runTransaction(async tx=>{
      const [r,quota,prior,oldIssue]=await Promise.all([tx.get(role(actorId)),tx.get(rate(actorId)),
        tx.get(preview(value.issueId)),tx.get(issue(value.issueId))]);
      requireAudienceRole(r,value);
      if(oldIssue.exists)throw error('ISSUE_EXISTS','This issue ID already belongs to a letter.');
      let p=prior.data();
      if(p && (p.schema!==2||p.actorUid!==actorId||p.requestHash!==requestHash))
        throw error('ISSUE_CONFLICT','Issue ID was already used for a different review.');
      if(p && p.status!=='preparing') {
        if(p.sentCount===0&&p.failedCount===0&&time>p.expiresAt)throw error('PREVIEW_EXPIRED','Start a new letter review.');
        return audienceReview(value,p);
      }
      if(p && time>p.expiresAt)throw error('PREVIEW_EXPIRED','Start a new letter review.');
      p ||= {schema:2,actorUid:actorId,requestHash,value,status:'preparing',count:0,cursor:null,
        createdAt:time,expiresAt:time+10*60*1000,sentCount:0,failedCount:0,nextIndex:0,failures:[],
        cohortHash:hash('little-leaf-audience-v1\n'+actorId+'\n'+requestHash)};
      const members=[];
      let finished=true,cursor=p.cursor;
      if(value.audience.mode==='selected') {
        for(const id of value.audience.publicUids) {
          const player=await resolvePublic(tx,id),saved=await tx.get(save(player));
          if(!saved.exists)throw error('PLAYER_NOT_FOUND','A selected player has no cloud café.');
          members.push({recipientUid:player,recipientPublicUid:id,profileId:head(saved.data()).profileId});
        }
      } else {
        // Parent player documents need not exist. Enumerate the authoritative
        // save collection group, not the optional public-UID allocation index.
        let query=db.collectionGroup('saves').orderBy('__name__').limit(PREPARE_PAGE);
        if(cursor)query=query.startAfter(db.doc(cursor));
        const page=await tx.get(query);
        finished=page.docs.length<PREPARE_PAGE;
        if(page.docs.length)cursor=page.docs.at(-1).ref.path;
        for(const saved of page.docs) {
          const match=/^players\/([^/]+)\/saves\/cafe$/.exec(saved.ref.path);
          if(!match)continue;
          const player=match[1];
          if(!uid(player))throw error('CORRUPT_IDENTITY','A cloud café has an invalid owner.');
          const record=head(saved.data()),ident=await tx.get(identity(player));
          let id=null;
          if(ident.exists) {
            id=ident.data()?.publicUid;
            if(ident.data()?.schema!==1||!publicUid(id))throw error('CORRUPT_IDENTITY','A player UID is invalid.');
            const paired=await tx.get(publicIndex(id));
            if(paired.data()?.schema!==1||paired.data()?.authUid!==player)throw error('CORRUPT_IDENTITY','A player UID changed.');
          }
          members.push({recipientUid:player,recipientPublicUid:id,profileId:record.profileId});
        }
      }
      // No write occurs until the whole bounded page has passed validation.
      const next={...p,cursor,count:p.count+members.length,status:finished?'ready':'preparing',
        expiresAt:time+10*60*1000};
      if(!Number.isSafeInteger(next.count)||!Number.isSafeInteger(value.coins*next.count)
        ||value.items.some(item=>!Number.isSafeInteger(item.quantity*next.count)))
        throw error('AUDIENCE_TOO_LARGE','Audience totals exceed exact numeric bounds.');
      for(const target of members)next.cohortHash=hash(next.cohortHash+'\n'+JSON.stringify(target));
      if(finished) {
        next.completedAt=time;
        next.previewHash=hash(JSON.stringify({actorUid:actorId,requestHash,cohortHash:next.cohortHash,
          count:next.count,expiresAt:next.expiresAt}));
      }
      tx.set(rate(actorId),checkedRate(quota,'preview',time,10));
      members.forEach((m,index)=>tx.create(member(value.issueId,p.count+index),
        {...m,schema:1,mailId:recipientMailId(value.issueId,m.recipientUid)}));
      tx.set(preview(value.issueId),next);
      return audienceReview(value,next);
    });
  }
  function deliverySummary(p) {
    const pendingCount=p.count-p.sentCount-p.failedCount;
    return {issueId:p.value.issueId,status:pendingCount?'sending':p.failedCount?'completed_with_failures':'sent',
      total:p.count,sentCount:p.sentCount,failedCount:p.failedCount,pendingCount,failures:p.failures};
  }
  async function issueAudience(context,input) {
    const value=normalizeAudienceIssue(input),actorId=await authorized(context,audienceCapability(value));
    const requestHash=hash(JSON.stringify(value));
    let result;
    for(let step=0;step<DELIVERY_PAGE;step++) {
      result=await db.runTransaction(async tx=>{
        const [r,prior,quota]=await Promise.all([tx.get(role(actorId)),tx.get(preview(value.issueId)),tx.get(rate(actorId))]);
        requireAudienceRole(r,value);
        const p=prior.data(),time=now();
        if(!p||p.schema!==2||p.actorUid!==actorId||p.status==='preparing')
          throw error('PREVIEW_REQUIRED','Finish reviewing this exact audience before sending.');
        if(p.requestHash!==requestHash||input.previewHash!==p.previewHash)
          throw error('PREVIEW_CHANGED','Review confirmation does not match the frozen audience and letter.');
        if(!p.sentCount&&!p.failedCount&&time>p.expiresAt)throw error('PREVIEW_EXPIRED','Review expired before sending.');
        if(p.nextIndex===p.count)return deliverySummary(p);
        const [m,receipt]=await Promise.all([tx.get(member(value.issueId,p.nextIndex)),tx.get(delivered(value.issueId,p.nextIndex))]);
        const target=m.data();
        if(!target||receipt.exists)throw error('CORRUPT_AUDIENCE','Delivery progress is inconsistent.');
        const [saved,usedCase,ident,existing,audited,inbox]=await Promise.all([
          tx.get(save(target.recipientUid)),tx.get(caseRef(target.recipientUid,value.caseId)),
          tx.get(identity(target.recipientUid)),tx.get(issue(target.mailId)),tx.get(audit(target.mailId+'-issued')),
          tx.get(mail(target.recipientUid,target.mailId))]);
        let failure=null;
        if(target.recipientPublicUid!==null) {
          const paired=await tx.get(publicIndex(target.recipientPublicUid));
          if(ident.data()?.schema!==1||ident.data()?.publicUid!==target.recipientPublicUid
            ||paired.data()?.schema!==1||paired.data()?.authUid!==target.recipientUid)failure='IDENTITY_CHANGED';
        }
        if(!failure) {
          try {if(!saved.exists||head(saved.data()).profileId!==target.profileId)failure='PROFILE_CHANGED';}
          catch(e) {if(e.code!=='CORRUPT_AUTHORITY')throw e;failure=e.code;}
        }
        if(!failure&&usedCase.exists)failure='CASE_ALREADY_ISSUED';
        if(existing.exists||audited.exists||inbox.exists)throw error('CORRUPT_AUDIENCE','Delivery identity already exists without a receipt.');
        const next={...p,nextIndex:p.nextIndex+1,sentCount:p.sentCount+(failure?0:1),failedCount:p.failedCount+(failure?1:0)};
        if(failure&&p.failures.length<5)next.failures=[...p.failures,{publicUid:target.recipientPublicUid,code:failure}];
        if(!failure) {
          const payload={schema:1,mailId:target.mailId,issueId:target.mailId,campaignId:value.issueId,
            caseId:value.caseId,profileId:target.profileId,title:value.subject,body:value.body,
            coins:value.coins,items:value.items,issuedAt:time,status:'unclaimed',claimedAt:null};
          tx.create(mail(target.recipientUid,target.mailId),payload);
          tx.create(issue(target.mailId),{...value,...target,campaignId:value.issueId,issueId:target.mailId,
            requestHash,actorUid:actorId,issuedAt:time});
          tx.create(caseRef(target.recipientUid,value.caseId),{issueId:target.mailId,campaignId:value.issueId,
            recipientUid:target.recipientUid,recipientPublicUid:target.recipientPublicUid,caseId:value.caseId});
          tx.create(audit(target.mailId+'-issued'),{type:'issued',issueId:target.mailId,campaignId:value.issueId,
            actorUid:actorId,recipientUid:target.recipientUid,profileId:target.profileId,requestHash,at:time});
        }
        if(p.nextIndex===0)tx.set(rate(actorId),checkedRate(quota,'issue',time,5));
        tx.create(delivered(value.issueId,p.nextIndex),{schema:1,mailId:target.mailId,
          recipientUid:target.recipientUid,status:failure?'failed':'sent',code:failure,at:time});
        tx.set(preview(value.issueId),next);
        return deliverySummary(next);
      });
      if(result.pendingCount===0)break;
    }
    return result;
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
