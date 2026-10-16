import {hash,uid,uuid,normalizeIssue,verifyRecord,grant,error,parsePayload,MAIL_CATALOG} from './support_mail_contract.mjs';

// Trusted Firestore service. All paths, roles and player identities are derived
// here; callable arguments never grant authority. The default flag is closed.
export function createSupportMailService({db,enabled=false,now=Date.now}) {
  const path=(...segments)=>db.doc(segments.join('/'));
  const role=actor=>path('supportAdmins',actor);
  const save=player=>path('players',player,'saves','cafe');
  const control=player=>path('players',player,'saveControl','protocol');
  const session=player=>path('players',player,'session','owner');
  const mail=(player,id)=>path('players',player,'mail',id);
  const claim=(player,id)=>path('players',player,'mailClaims',id);
  const stock=player=>path('players',player,'giftStock','current');
  const audit=id=>path('supportAudit',id);
  const issue=id=>path('supportIssues',id);
  const preview=id=>path('supportPreviews',id);
  const backup=player=>path('players',player,'saveBackups','supportMailV1');
  const placement= (player,id)=>path('players',player,'giftPlacements',id);
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
  async function lookup(context,recipientUid) {
    const actorId=await authorized(context,'lookup'),time=now();
    if(!uid(recipientUid))throw error('INVALID_UID','Enter one exact player UID.');
    const found=await db.runTransaction(async tx=>{
      const limit=rate(actorId);
      const [r,quota,saved,ctrl,recent]=await Promise.all([tx.get(role(actorId)),tx.get(limit),
        tx.get(save(recipientUid)),tx.get(control(recipientUid)),
        tx.get(db.collection(`players/${recipientUid}/mail`).orderBy('issuedAt','desc').limit(10))]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('lookup'))throw error('PERMISSION_DENIED','Support access changed.');
      const next=checkedRate(quota,'lookup',time,20);
      tx.set(limit,next);
      if(!saved.exists)return {missing:true};
      const record=head(saved.data());
      return {uid:recipientUid,profileId:record.profileId,revision:record.revision,
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
      const [r,quota,p,s,existing]=await Promise.all([tx.get(role(actorId)),tx.get(limit),tx.get(preview(value.issueId)),
        tx.get(save(value.recipientUid)),tx.get(issue(value.issueId))]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('issue'))throw error('PERMISSION_DENIED','Support access changed.');
      if(existing.exists)throw error('ISSUE_EXISTS','This issue was already sent. Check its status.');
      if(p.exists&&p.data().requestHash!==normalizedHash)throw error('ISSUE_CONFLICT','Issue ID was already used for different content.');
      if(!s.exists)throw error('PLAYER_NOT_FOUND','No cloud café exists for that UID.');
      const record=head(s.data());
      if(record.profileId!==value.profileId)throw error('PROFILE_CHANGED','Recipient café changed.');
      tx.set(limit,checkedRate(quota,'preview',time,10));
      tx.set(preview(value.issueId),{schema:1,actorUid:actorId,requestHash:normalizedHash,
        recipientUid:value.recipientUid,profileId:value.profileId,createdAt:time,expiresAt:time+10*60*1000});
      return {issueId:value.issueId,previewHash:normalizedHash,expiresAt:time+10*60*1000,
        recipientUid:value.recipientUid,profileId:value.profileId,subject:value.subject,body:value.body,
        coins:value.coins,items:value.items,caseId:value.caseId};
    });
  }
  async function issueMail(context,input) {
    const actorId=await authorized(context,'issue'),value=normalizeIssue(input),time=now();
    const normalizedHash=hash(JSON.stringify(value));
    return db.runTransaction(async tx=>{
      const limit=rate(actorId);
      const [r,quota,p,existing,usedCase,s]=await Promise.all([tx.get(role(actorId)),tx.get(limit),tx.get(preview(value.issueId)),
        tx.get(issue(value.issueId)),tx.get(caseRef(value.recipientUid,value.caseId)),tx.get(save(value.recipientUid))]);
      if(r.data()?.enabled!==true||!r.data()?.capabilities?.includes('issue'))throw error('PERMISSION_DENIED','Support access changed.');
      if(existing.exists){
        if(existing.data().requestHash!==normalizedHash||existing.data().actorUid!==actorId)throw error('ISSUE_CONFLICT','Issue ID was already used.');
        return {mailId:value.issueId,status:'sent',alreadyIssued:true};
      }
      if(usedCase.exists)throw error('CASE_ALREADY_ISSUED','This recipient and case already have a letter.');
      if(!p.exists||p.data().actorUid!==actorId||p.data().requestHash!==normalizedHash||p.data().expiresAt<time)
        throw error('PREVIEW_EXPIRED','Review the exact letter again before sending.');
      if(!s.exists||head(s.data()).profileId!==value.profileId)throw error('PROFILE_CHANGED','Recipient café changed.');
      tx.set(limit,checkedRate(quota,'issue',time,5));
      const payload={schema:1,mailId:value.issueId,issueId:value.issueId,caseId:value.caseId,profileId:value.profileId,
        title:value.subject,body:value.body,coins:value.coins,items:value.items,
        issuedAt:time,status:'unclaimed',claimedAt:null};
      tx.create(issue(value.issueId),{...value,requestHash:normalizedHash,actorUid:actorId,issuedAt:time});
      tx.create(caseRef(value.recipientUid,value.caseId),{issueId:value.issueId,recipientUid:value.recipientUid,caseId:value.caseId});
      tx.create(mail(value.recipientUid,value.issueId),payload);
      tx.create(audit(value.issueId+'-issued'),{type:'issued',issueId:value.issueId,actorUid:actorId,
        recipientUid:value.recipientUid,profileId:value.profileId,requestHash:normalizedHash,at:time});
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
  async function myGiftStock(context) {
    const player=actor(context);
    return db.runTransaction(async tx=>{
      const [saved,g,ctrl]=await Promise.all([tx.get(save(player)),tx.get(stock(player)),tx.get(control(player))]);
      if(!saved.exists)throw error('MAIL_UNAVAILABLE','Open a cloud café before reading gifts.');
      const record=head(saved.data()),value=g.data()||{schema:1,revision:0,counts:{}};
      if((record.format===3&&(value.revision!==record.mailState.stockRevision||!ctrl.exists
        ||ctrl.data().stockRevision!==value.revision))||(record.format!==3&&(g.exists||ctrl.exists)))
        throw error('PROTOCOL_CHANGED','Gift stock and cloud save differ. Reload.');
      return {profileId:record.profileId,revision:record.revision,digest:record.digest,stock:value};
    });
  }
  async function claimMail(context,request) {
    active();
    const player=actor(context);
    if(!uuid(request?.mailId)||!uuid(request?.operationId))throw error('INVALID_CLAIM','Invalid claim request.');
    return db.runTransaction(async tx=>{
      const [m,c,s,ctrl,own,g,b]=await Promise.all([tx.get(mail(player,request.mailId)),tx.get(claim(player,request.mailId)),
        tx.get(save(player)),tx.get(control(player)),tx.get(session(player)),tx.get(stock(player)),tx.get(backup(player))]);
      const time=now();
      if(!m.exists||!s.exists)throw error('MAIL_UNAVAILABLE','This letter is unavailable.');
      const current=head(s.data());
      fence(own.data(),request,time,true);
      if(c.exists){if(m.data().status!=='claimed')throw error('CORRUPT_MAIL','Claim state is inconsistent.');
        return {status:'claimed',receipt:c.data(),record:current,stock:g.data()||{schema:1,revision:0,counts:{}}};}
      if(m.data().status!=='unclaimed')throw error('CORRUPT_MAIL','Claim state is inconsistent.');
      expected(current,request);
      if(ctrl.exists && (current.format!==3||ctrl.data().claimSequence!==current.mailState.claimSequence
        ||ctrl.data().stockRevision!==current.mailState.stockRevision
        ||(g.data()?.revision||0)!==current.mailState.stockRevision))throw error('PROTOCOL_CHANGED','Save protocol changed.');
      if(!ctrl.exists && current.format===3)throw error('PROTOCOL_CHANGED','Save protocol changed.');
      const awarded=grant(current,m.data(),g.data(),time),receipt={schema:1,mailId:request.mailId,
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
      tx.set(stock(player),awarded.stock);
      tx.create(claim(player,request.mailId),receipt);
      tx.update(mail(player,request.mailId),{status:'claimed',claimedAt:time});
      tx.create(audit(request.mailId+'-claimed'),{type:'claimed',actorUid:player,recipientUid:player,
        mailId:request.mailId,operationId:request.operationId,fromDigest:current.digest,toDigest:awarded.record.digest,at:time});
      return {status:'claimed',receipt,record:awarded.record,stock:awarded.stock};
    });
  }
  async function commitProtectedSave(context,request) {
    const player=actor(context),candidate=request?.candidate;
    verifyRecord(candidate);
    if(candidate.format!==3)throw error('PROTOCOL_CHANGED','Update the game to save this café.');
    return db.runTransaction(async tx=>{
      const [s,ctrl,own]=await Promise.all([tx.get(save(player)),tx.get(control(player)),tx.get(session(player))]);
      const time=now();
      if(!s.exists||!ctrl.exists)throw error('PROTOCOL_CHANGED','Protected save is unavailable.');
      fence(own.data(),request,time);
      const current=head(s.data()),protocol=ctrl.data();
      if(current.digest===candidate.digest)return {status:'saved',record:current};
      expected(current,request);
      if(current.format!==3||protocol.version!==1||protocol.claimSequence!==current.mailState.claimSequence
        ||protocol.stockRevision!==current.mailState.stockRevision
        ||candidate.revision!==current.revision+1||candidate.profileId!==current.profileId
        ||candidate.createdAt!==current.createdAt||JSON.stringify(candidate.origin)!==JSON.stringify(current.origin)
        ||JSON.stringify(candidate.campaigns)!==JSON.stringify(current.campaigns)
        ||JSON.stringify(candidate.mailState)!==JSON.stringify(current.mailState)
        ||candidate.previous!==null)
        throw error('PROTOCOL_CHANGED','Save was based on an old claim or café. Reload.');
      tx.set(save(player),docFor(candidate,s.data(),request));
      return {status:'saved',record:candidate};
    });
  }
  async function commitGiftPlacement(context,request) {
    const player=actor(context),candidate=request?.candidate,consumed=request?.consumed;
    if(!uuid(request?.operationId)||!Array.isArray(consumed)||consumed.length<1||consumed.length>10)
      throw error('INVALID_PLACEMENT','Invalid gift placement.');
    verifyRecord(candidate);
    const operations=new Map();
    for(const entry of consumed){
      if(!entry||!MAIL_CATALOG.includes(entry.catalogId)||!Number.isSafeInteger(entry.itemId)
        ||entry.itemId<1||entry.itemId>1000000000||operations.has(entry.itemId))throw error('INVALID_PLACEMENT','Invalid gift furnishing.');
      operations.set(entry.itemId,entry.catalogId);
    }
    const operationHash=hash(JSON.stringify({digest:candidate.digest,consumed:[...operations].sort((a,b)=>a[0]-b[0]),
      profileId:request.profileId,revision:request.revision,base:request.digest}));
    return db.runTransaction(async tx=>{
      const [done,s,ctrl,own,g]=await Promise.all([tx.get(placement(player,request.operationId)),tx.get(save(player)),
        tx.get(control(player)),tx.get(session(player)),tx.get(stock(player))]);
      const time=now();
      if(!s.exists||!ctrl.exists||!g.exists)throw error('PROTOCOL_CHANGED','Gift stock is unavailable.');
      const current=head(s.data()),protocol=ctrl.data(),stockValue=g.data();
      fence(own.data(),request,time,true);
      if(done.exists){
        if(done.data().operationHash!==operationHash)throw error('ISSUE_CONFLICT','Placement ID was already used.');
        return {status:'placed',receipt:done.data(),record:current,stock:stockValue};
      }
      expected(current,request);
      if(current.format!==3||candidate.format!==3||candidate.profileId!==current.profileId
        ||candidate.revision!==current.revision+1||candidate.createdAt!==current.createdAt
        ||candidate.previous!==null
        ||JSON.stringify(candidate.origin)!==JSON.stringify(current.origin)
        ||JSON.stringify(candidate.campaigns)!==JSON.stringify(current.campaigns)
        ||protocol.claimSequence!==current.mailState.claimSequence
        ||protocol.stockRevision!==current.mailState.stockRevision||stockValue.revision!==protocol.stockRevision
        ||candidate.mailState.claimSequence!==current.mailState.claimSequence
        ||candidate.mailState.stockRevision!==current.mailState.stockRevision+1)
        throw error('PROTOCOL_CHANGED','Gift placement was based on old progress.');
      const oldItems=parsePayload(current.payload).items,nextItems=parsePayload(candidate.payload).items;
      if(!Array.isArray(oldItems)||!Array.isArray(nextItems))throw error('INVALID_PLACEMENT','Invalid furniture list.');
      const oldIds=new Set(),newIds=new Set(),added=new Map();
      for(const item of oldItems){
        if(!Number.isSafeInteger(item?.id)||oldIds.has(item.id))throw error('INVALID_PLACEMENT','Invalid saved furnishing identity.');
        oldIds.add(item.id);
      }
      for(const item of nextItems){
        if(!Number.isSafeInteger(item?.id)||newIds.has(item.id))throw error('INVALID_PLACEMENT','Duplicate furnishing.');
        newIds.add(item.id);
        if(!oldIds.has(item.id))added.set(item.id,item.kind);
      }
      const counts={...stockValue.counts};
      for(const [itemId,kind] of operations){
        if(added.get(itemId)!==kind||!Number.isSafeInteger(counts[kind])||counts[kind]<1)
          throw error('STOCK_CHANGED','Gift stock or placed furnishing changed.');
        counts[kind]--;
      }
      const updatedStock={schema:1,revision:stockValue.revision+1,counts};
      const receipt={schema:1,operationId:request.operationId,operationHash,profileId:current.profileId,
        consumed:[...operations].map(([itemId,catalogId])=>({itemId,catalogId})),
        fromDigest:current.digest,toDigest:candidate.digest,at:time};
      tx.set(save(player),docFor(candidate,s.data(),request));
      tx.set(stock(player),updatedStock);
      tx.set(control(player),{...protocol,stockRevision:updatedStock.revision});
      tx.create(placement(player,request.operationId),receipt);
      tx.create(audit(request.operationId+'-gift-placement'),{type:'gift-placement',actorUid:player,
        recipientUid:player,operationHash,fromDigest:current.digest,toDigest:candidate.digest,at:time});
      return {status:'placed',receipt,record:candidate,stock:updatedStock};
    });
  }
  return {capabilities,lookup,previewMail,issueMail,listMyMail,myGiftStock,claimMail,commitProtectedSave,commitGiftPlacement};
}
