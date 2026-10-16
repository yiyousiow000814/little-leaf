import {createHash} from 'node:crypto';

export const MAIL_CATALOG = Object.freeze(['stove','beverage','sink','counter','bin','plant','lamp','bookshelf','rug','divider']);
export const MAX_COINS = 1000000000;
const uidPattern = /^[A-Za-z0-9_-]{6,128}$/;
const publicUidPattern = /^[1-9][0-9]{11}$/;
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const digestPattern = /^[a-f0-9]{64}$/;
const error = (code, message) => Object.assign(new Error(message), {code});
export {error};
export const hash = value => createHash('sha256').update(value, 'utf8').digest('hex');
export const uid = value => typeof value === 'string' && uidPattern.test(value);
export const publicUid = value => typeof value === 'string' && publicUidPattern.test(value);
export const uuid = value => typeof value === 'string' && uuidPattern.test(value);

// Keep the browser authority's ordered fingerprint, including historic formats.
export function fingerprint(record) {
  const value = {format:record.format,profileId:record.profileId,revision:record.revision,
    createdAt:record.createdAt,updatedAt:record.updatedAt,origin:record.origin,payload:record.payload};
  if (record.format >= 2) value.campaigns=record.campaigns;
  if (record.format === 3) value.mailState=record.mailState;
  return JSON.stringify(value);
}
export function parsePayload(text) {
  if(typeof text !== 'string' || Buffer.byteLength(text)>1048576)throw error('INVALID_SAVE','Save is unreadable or too large.');
  let data;
  try {data=JSON.parse(text);}catch {throw error('INVALID_SAVE','Invalid save JSON.');}
  if(!data || Array.isArray(data) || data.schema!=='little_leaf_reconstructed_cafe' || data.version!==15
    || data.new_reconstruction!==true || data.checkout_format!=='little_leaf.checkout.v1'
    || data.layout_motion_format!=='little_leaf.layout_motion.v1')throw error('INVALID_SAVE','Unsupported save format.');
  if(!Number.isSafeInteger(data.coins)||data.coins<0||data.coins>MAX_COINS)throw error('INVALID_SAVE','Invalid wallet.');
  return data;
}
export function verifyRecord(record) {
  if(!record || ![1,2,3].includes(record.format) || !uuid(record.profileId)
    || !Number.isSafeInteger(record.revision) || record.revision<1
    || !Number.isFinite(record.createdAt)||!Number.isFinite(record.updatedAt)
    || typeof record.payload!=='string'||!digestPattern.test(record.digest||'')
    || !record.origin || !['fresh','legacy-v13','import-v15'].includes(record.origin.source)
    || !Number.isFinite(record.origin.importedAt)
    || (record.origin.source==='legacy-v13' ? !digestPattern.test(record.origin.legacyDigest||'') : record.origin.legacyDigest!==null)
    || Object.keys(record.origin).sort().join(',')!=='importedAt,legacyDigest,source')throw error('CORRUPT_AUTHORITY','Invalid save envelope.');
  if(record.format===1){if(Object.hasOwn(record,'campaigns')||Object.hasOwn(record,'mailState'))throw error('CORRUPT_AUTHORITY','Unexpected save metadata.');}
  else {
    if(!record.campaigns||typeof record.campaigns!=='object'||Array.isArray(record.campaigns)||Object.keys(record.campaigns).length>128)throw error('CORRUPT_AUTHORITY','Invalid campaign receipts.');
    for(const [id,r] of Object.entries(record.campaigns))if(!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(id)
      || r?.status!=='granted'||!Number.isSafeInteger(r.coins)||r.coins<1||r.coins>MAX_COINS
      || !Number.isSafeInteger(r.revision)||r.revision<1||r.revision>record.revision
      || !Number.isFinite(r.grantedAt)||r.grantedAt<0||Object.keys(r).sort().join(',')!=='coins,grantedAt,revision,status')
      throw error('CORRUPT_AUTHORITY','Invalid campaign receipt.');
  }
  if(record.format===3){
    const s=record.mailState;
    if(!s||s.schema!==1||!Number.isSafeInteger(s.claimSequence)||s.claimSequence<1
      || !Number.isSafeInteger(s.stockRevision)||s.stockRevision<0
      || Object.keys(s).sort().join(',')!=='claimSequence,schema,stockRevision')throw error('CORRUPT_AUTHORITY','Invalid mail watermark.');
  }else if(Object.hasOwn(record,'mailState'))throw error('CORRUPT_AUTHORITY','Unexpected mail watermark.');
  parsePayload(record.payload);
  if(hash(fingerprint(record))!==record.digest)throw error('CORRUPT_AUTHORITY','Save checksum failed.');
  if(Buffer.byteLength(JSON.stringify(record))>900000)throw error('SAVE_TOO_LARGE','Cloud save limit reached.');
  return record;
}
export function normalizeIssue(input) {
  if(!input||!uuid(input.issueId)||!publicUid(input.recipientPublicUid)||!uuid(input.profileId)
    || typeof input.caseId!=='string'||!/^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$/.test(input.caseId)
    || typeof input.subject!=='string'||input.subject.trim().length<1||input.subject.length>100
    || typeof input.body!=='string'||input.body.trim().length<1||input.body.length>2000
    || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(input.subject+input.body)
    || !Number.isSafeInteger(input.coins)||input.coins<0||input.coins>100000
    || !Array.isArray(input.items)||input.items.length>10)throw error('INVALID_ISSUE','Mail fields are invalid.');
  const kinds=new Set(),items=[];
  for(const item of input.items){
    if(!item||!MAIL_CATALOG.includes(item.catalogId)||!Number.isSafeInteger(item.quantity)||item.quantity<1||item.quantity>10||kinds.has(item.catalogId))throw error('INVALID_ISSUE','Unsupported gift item.');
    kinds.add(item.catalogId);items.push({catalogId:item.catalogId,quantity:item.quantity,catalogRevision:1});
  }
  items.sort((a,b)=>a.catalogId.localeCompare(b.catalogId));
  if(input.coins===0&&items.length===0)throw error('INVALID_ISSUE','A gift is required.');
  return {issueId:input.issueId,recipientPublicUid:input.recipientPublicUid,profileId:input.profileId,caseId:input.caseId,
    subject:input.subject.trim(),body:input.body.trim(),coins:input.coins,items};
}
export function grant(record,mail,stock,now) {
  verifyRecord(record);
  if(record.profileId!==mail.profileId||mail.status!=='unclaimed')throw error('PROFILE_CHANGED','Recipient café changed.');
  const data=parsePayload(record.payload);
  if(data.coins>MAX_COINS-mail.coins)throw error('WALLET_FULL','Spend coins before claiming this letter.');
  const counts={...(stock?.counts||{})};
  for(const item of mail.items){
    if(!MAIL_CATALOG.includes(item.catalogId)||item.catalogRevision!==1||!Number.isSafeInteger(item.quantity)||item.quantity<1||item.quantity>10)throw error('UNSUPPORTED_GIFT','Unsupported gift item.');
    const before=counts[item.catalogId]||0;
    if(!Number.isSafeInteger(before)||before<0||before>100-item.quantity)throw error('STOCK_FULL','Gift storage is full.');
    counts[item.catalogId]=before+item.quantity;
  }
  data.coins+=mail.coins;
  const claimSequence=(record.mailState?.claimSequence||0)+1;
  const stockRevision=(stock?.revision||0)+(mail.items.length?1:0);
  const next={...record,format:3,revision:record.revision+1,updatedAt:now,payload:JSON.stringify(data),
    previous:null,campaigns:record.campaigns||{},mailState:{schema:1,claimSequence,stockRevision}};
  next.digest=hash(fingerprint(next));verifyRecord(next);
  return {record:next,stock:{schema:1,revision:stockRevision,counts}};
}
