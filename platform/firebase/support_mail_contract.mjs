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
const SCHEMA = 'little_leaf_reconstructed_cafe', CHECKOUT = 'little_leaf.checkout.v1', MOTION = 'little_leaf.layout_motion.v1';
const HOLD = 'little_leaf.layout_hold.v1', STORAGE = 'little_leaf.storage.v1', fail = error;
export function parsePayload(text, version = 15) {
    if (typeof text !== 'string' || Buffer.byteLength(text) > 1048576) throw fail('INVALID_SAVE', 'Save is unreadable or too large');
    let data;
    try { data = JSON.parse(text); } catch (_) { throw fail('INVALID_SAVE', 'Invalid save JSON'); }
    if (!data || typeof data !== 'object' || Array.isArray(data) || data.schema !== SCHEMA || (data.version !== version && !(version === 15 && [16, 17].includes(data.version))) || data.new_reconstruction !== true || data.checkout_format !== CHECKOUT) throw fail('INVALID_SAVE', 'Unsupported save format');
    if (version === 15 && data.layout_motion_format !== MOTION) throw fail('INVALID_SAVE', 'Missing layout movement format');
    if (version === 13 && Object.hasOwn(data, 'layout_motion_format')) throw fail('INVALID_SAVE', 'Legacy save has a foreign movement format');
    // v16 remains in this profile/authority. Older clients reject its version;
    // neither import nor an award may downgrade or strip its suspended work.
    const runtime = data.runtime, service = runtime && runtime.service;
    const hasHold = Object.hasOwn(data, 'layout_hold_format') || (runtime && Object.hasOwn(runtime, 'layout_hold_format')) || (service && Object.hasOwn(service, 'layout_hold'));
    if (data.version === 16 || (data.version === 17 && hasHold)) {
      const hold = service && service.layout_hold;
      if (data.layout_hold_format !== HOLD || !runtime || runtime.layout_hold_format !== HOLD || !hold || hold.format !== HOLD || Object.keys(hold).sort().join(',') !== 'dishes,floor,format,guests,hosts,staff') throw fail('INVALID_SAVE', 'Missing layout hold format');
      for (const [key, limit] of [['hosts', 512], ['guests', 60], ['staff', 64], ['dishes', 512], ['floor', 512]])
        if (!Array.isArray(hold[key]) || hold[key].length > limit) throw fail('INVALID_SAVE', 'Invalid layout hold bounds');
    } else if (Object.hasOwn(data, 'layout_hold_format') || (runtime && Object.hasOwn(runtime, 'layout_hold_format')) || (service && Object.hasOwn(service, 'layout_hold')))
      throw fail('INVALID_SAVE', 'Legacy save has foreign layout hold state');
    if (!integer(data.coins, 0, MAX_COINS)) throw fail('INVALID_SAVE', 'Invalid wallet');
    validateStorage(data);
    return data;
  }
  // Storage is part of the one save payload, never a second stock balance.
  // Validate one canonical union of placed and stored furniture.
  const OWNED_KINDS = ['table','chair','bench','stove','beverage','sink','counter','bin','register','plant','lamp','bookshelf','rug','divider'];
  const DINING_COSTS = {oak_single:[140,280],cottage_single:[420],retro_single:[1200],refined_single:[3600],legacy_bench:[175]};
  const integer = (value, min, max) => Number.isSafeInteger(value) && value >= min && value <= max;
  function validateStorage(data) {
    if (data.version !== 17) {
      if (Object.hasOwn(data, 'storage') || Object.hasOwn(data, 'storage_format')
        || (Array.isArray(data.items) && data.items.some(item => item && Object.hasOwn(item, 'paid_cost'))))
        throw fail('INVALID_SAVE', 'Legacy save has foreign Storage state');
      return;
    }
    const storage = data.storage;
    if (data.storage_format !== STORAGE || !storage || Object.keys(storage).sort().join(',') !== 'dining_sets,items'
      || !Array.isArray(data.items) || !Array.isArray(data.dining_sets) || !Array.isArray(storage.items) || !Array.isArray(storage.dining_sets))
      throw fail('INVALID_SAVE', 'Missing Storage contract');
    const owned = new Map(); let registers = 0, highest = 0;
    for (const [items, stored] of [[data.items, false], [storage.items, true]]) {
      for (const item of items) {
        if (!item || typeof item !== 'object' || Array.isArray(item) || !integer(item.id, 1, 1000000000)
          || !OWNED_KINDS.includes(item.kind) || !integer(item.x, 0, 17) || !integer(item.z, 0, 17) || !integer(item.rot, 0, 3)
          || owned.has(item.id) || (Object.hasOwn(item, 'paid_cost') && !integer(item.paid_cost, 0, 1000000000))
          || (stored && Object.keys(item).sort().join(',') !== (Object.hasOwn(item, 'paid_cost') ? 'id,kind,paid_cost,rot,x,z' : 'id,kind,rot,x,z')))
          throw fail('INVALID_SAVE', 'Invalid or duplicated owned furniture');
        owned.set(item.id, item); highest = Math.max(highest, item.id);
        if (item.kind === 'register') registers++;
      }
    }
    if (registers > 1) throw fail('INVALID_SAVE', 'Duplicate owned register');
    const hosts = data.runtime?.service?.layout_hold?.hosts || [], held = new Set();
    for (const host of hosts) {
      if (!host || !integer(host.id, 1, 1000000000) || held.has(host.id) || !OWNED_KINDS.includes(host.kind)
        || (owned.has(host.id) && owned.get(host.id).kind !== host.kind)) throw fail('INVALID_SAVE', 'Invalid held furniture identity');
      held.add(host.id); highest = Math.max(highest, host.id);
    }
    if (!integer(data.next_item_id, highest + 1, 1000000001)) throw fail('INVALID_SAVE', 'Invalid owned furniture sequence');
    for (const [items, groups] of [[data.items, data.dining_sets], [storage.items, storage.dining_sets]]) {
      const byId = new Map(items.map(item => [item.id, item])), grouped = new Set(), directions = [[0,1],[-1,0],[0,-1],[1,0]];
      for (const group of groups) {
        const table = byId.get(group?.table_id), seat = byId.get(group?.seat_id), costs = DINING_COSTS[group?.variant];
        if (!group || Object.keys(group).sort().join(',') !== 'id,paid_cost,rot,seat_id,table_id,variant'
          || group.id !== group.table_id || group.table_id === group.seat_id || !integer(group.rot, 0, 3)
          || !table || !seat || table.kind !== 'table' || seat.kind !== (group.variant === 'legacy_bench' ? 'bench' : 'chair')
          || grouped.has(table.id) || grouped.has(seat.id) || !costs || !costs.includes(group.paid_cost)
          || seat.x - table.x !== directions[group.rot][0] || seat.z - table.z !== directions[group.rot][1])
          throw fail('INVALID_SAVE', 'Invalid stored dining set');
        grouped.add(table.id); grouped.add(seat.id);
      }
    }
  }
  function storageFingerprint(data) {
    const storage = data.storage || {items:[], dining_sets:[]};
    const items = storage.items.map(item => {
      const value = {id:item.id, kind:item.kind, x:item.x, z:item.z, rot:item.rot};
      if (Object.hasOwn(item, 'paid_cost')) value.paid_cost = item.paid_cost;
      return value;
    }).sort((a,b) => a.id-b.id);
    const dining_sets = storage.dining_sets.map(group => ({id:group.id, table_id:group.table_id, seat_id:group.seat_id,
      variant:group.variant, rot:group.rot, paid_cost:group.paid_cost})).sort((a,b) => a.id-b.id);
    return JSON.stringify({items,dining_sets});
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
export function normalizeLetter(input) {
  if(!input||typeof input.caseId!=='string'||!/^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$/.test(input.caseId)
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
  return {caseId:input.caseId,subject:input.subject.trim(),body:input.body.trim(),coins:input.coins,items};
}
export function normalizeIssue(input) {
  if(!input||!uuid(input.issueId)||!publicUid(input.recipientPublicUid)||!uuid(input.profileId))
    throw error('INVALID_ISSUE','Mail fields are invalid.');
  return {issueId:input.issueId,recipientPublicUid:input.recipientPublicUid,profileId:input.profileId,...normalizeLetter(input)};
}
// Audience is normalized on the server. UI counts and profile hints grant no
// authority and never determine the final recipient cohort.
export function normalizeAudienceIssue(input) {
  if (!input || !uuid(input.issueId) || !input.audience || !['selected','all'].includes(input.audience.mode))
    throw error('INVALID_ISSUE','Choose a mail audience.');
  let audience={mode:'all'};
  if (input.audience.mode==='selected') {
    const values=input.audience.publicUids;
    if (!Array.isArray(values) || values.length<1 || values.length>100 || values.some(value=>!publicUid(value)))
      throw error('INVALID_ISSUE','Choose one to one hundred exact player UIDs.');
    audience={mode:'selected',publicUids:[...new Set(values)].sort()};
  } else if (Object.keys(input.audience).some(key=>key!=='mode')) {
    throw error('INVALID_ISSUE','All-player audience cannot contain a recipient override.');
  }
  return {issueId:input.issueId,audience,...normalizeLetter(input)};
}
export function grant(record,mail,legacyStock,now) {
  verifyRecord(record);
  if(record.profileId!==mail.profileId||mail.status!=='unclaimed')throw error('PROFILE_CHANGED','Recipient café changed.');
  const data=parsePayload(record.payload);
  if(data.coins>MAX_COINS-mail.coins)throw error('WALLET_FULL','Spend coins before claiming this letter.');
  if (legacyStock != null || (record.format === 3 && data.version !== 17))
    throw error('STORAGE_REVIEW_REQUIRED','Earlier gift stock is preserved and needs review.');
  if (!integer(mail.coins, 0, 100000) || !Array.isArray(mail.items) || mail.items.length > 10)
    throw error('UNSUPPORTED_GIFT','Unsupported letter contents.');
  const kinds=new Set(); let quantity=0;
  for (const item of mail.items) {
    if (!MAIL_CATALOG.includes(item?.catalogId) || item.catalogRevision!==1 || !integer(item.quantity,1,10) || kinds.has(item.catalogId))
      throw error('UNSUPPORTED_GIFT','Unsupported letter item.');
    kinds.add(item.catalogId); quantity+=item.quantity;
  }
  // A new representation, not a repair: preserve legacy furniture and all held
  // service records verbatim. Native validation still owns gameplay geometry.
  data.version=17;data.storage_format=STORAGE;
  data.storage ||= {items:[],dining_sets:[]};
  validateStorage(data);
  if (quantity > 1000000001-data.next_item_id) throw error('STOCK_FULL','Furniture identity limit reached.');
  for (const item of mail.items) for (let i=0;i<item.quantity;i++)
    data.storage.items.push({id:data.next_item_id++,kind:item.catalogId,x:0,z:0,rot:0,paid_cost:0});
  data.coins+=mail.coins;
  const claimSequence=(record.mailState?.claimSequence||0)+1;
  const stockRevision=(record.mailState?.stockRevision||0)+(mail.items.length?1:0);
  const next={...record,format:3,revision:record.revision+1,updatedAt:now,payload:JSON.stringify(data),
    previous:null,campaigns:record.campaigns||{},mailState:{schema:1,claimSequence,stockRevision}};
  next.digest=hash(fingerprint(next));verifyRecord(next);
  return {record:next};
}

// The existing protected-save path is not a server economy simulation. It does
// preserve known acquisition basis while native controls purchases/sales/layout.
export function validateOwnedTransition(current, candidate) {
  const before=parsePayload(current.payload),after=parsePayload(candidate.payload);
  if (before.version!==17 || after.version!==17) throw error('PROTOCOL_CHANGED','Storage saves cannot be downgraded.');
  const oldItems=new Map([...before.items,...before.storage.items].map(item=>[item.id,item]));
  const nextItems=new Map([...after.items,...after.storage.items].map(item=>[item.id,item]));
  for (const item of nextItems.values()) {
    const old=oldItems.get(item.id);
    if (!old && item.id<before.next_item_id) throw error('PROTOCOL_CHANGED','Owned furniture identity was reused.');
    if (old && (old.kind!==item.kind || Object.hasOwn(old,'paid_cost')!==Object.hasOwn(item,'paid_cost') || old.paid_cost!==item.paid_cost))
      throw error('PROTOCOL_CHANGED','Owned furniture purchase history changed.');
  }
  const oldSets=new Map([...before.dining_sets,...before.storage.dining_sets].map(group=>[group.id,group]));
  const nextSets=new Map([...after.dining_sets,...after.storage.dining_sets].map(group=>[group.id,group]));
  for (const old of oldSets.values()) if (nextItems.has(old.table_id) || nextItems.has(old.seat_id)) {
    if (!nextItems.has(old.table_id) || !nextItems.has(old.seat_id) || !nextSets.has(old.id))
      throw error('PROTOCOL_CHANGED','Owned dining-set identity was split or lost.');
  }
  for (const group of nextSets.values()) {
    const old=oldSets.get(group.id);
    if (old && (old.table_id!==group.table_id || old.seat_id!==group.seat_id || old.variant!==group.variant || old.paid_cost!==group.paid_cost))
      throw error('PROTOCOL_CHANGED','Owned dining-set purchase history changed.');
  }
  if (after.next_item_id<before.next_item_id) throw error('PROTOCOL_CHANGED','Owned furniture sequence moved backwards.');
  const delta=candidate.mailState.stockRevision-current.mailState.stockRevision;
  if (delta<0 || delta>candidate.revision-current.revision || (storageFingerprint(before)!==storageFingerprint(after) && delta===0))
    throw error('PROTOCOL_CHANGED','Storage revision changed inconsistently.');
}
export {storageFingerprint};
