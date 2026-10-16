import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {hash,fingerprint,verifyRecord,normalizeIssue,publicUid,grant,parsePayload,storageFingerprint,validateOwnedTransition} from './support_mail_contract.mjs';

vm.runInThisContext(readFileSync(new URL('../web/little_leaf_vault.js',import.meta.url),'utf8'));
const browser=globalThis.LittleLeafAuthorityCodec;
const source=name=>readFileSync(new URL(name,import.meta.url),'utf8');
const storageBlock=text=>text.slice(text.indexOf('  // Storage is part'),text.indexOf('  function fingerprint(record)')<0?text.indexOf('export function verifyRecord'):text.indexOf('  function fingerprint(record)')).trim();
assert.equal(storageBlock(source('./support_mail_contract.mjs')),storageBlock(source('../web/little_leaf_vault.js')),'browser/server structural Storage validators cannot drift');
const at=1000,profileId='22222222-2222-4222-8222-222222222222';
const baseline=JSON.parse(readFileSync(new URL('../../tests/fixtures/unified_building_candidate.json',import.meta.url),'utf8'));
const payload=coins=>JSON.stringify({...baseline,coins});
const sign=record=>({...record,digest:hash(fingerprint(record))});
const mail={profileId,status:'unclaimed',coins:60,items:[{catalogId:'plant',quantity:2,catalogRevision:1}]};

function rejects(data){
  for(const api of [{parsePayload},browser]){assert.throws(()=>api.parsePayload(JSON.stringify(data),15),{code:'INVALID_SAVE'});}
}
for(const format of [1,2]){
  const original={format,profileId,revision:1,createdAt:at,updatedAt:at,
    origin:{source:'fresh',legacyDigest:null,importedAt:at},payload:payload(40),previous:null};
  if(format===2)original.campaigns={'little-leaf-0.1.5-existing-profile-compensation':
    {status:'granted',coins:1000,revision:1,grantedAt:at}};
  const record=sign(original);
  verifyRecord(record);await browser.verifyRecord(record);
  assert.equal(fingerprint(record),browser.fingerprint(record));
  const result=grant(record,mail,null,at+1),data=JSON.parse(result.record.payload);
  assert.equal(result.record.revision,2);assert.equal(data.version,17);assert.equal(data.coins,100);
  assert.deepEqual(data.items,baseline.items,'claim never places or rewrites purchased furniture');
  assert.equal(data.storage.items.length,2);assert.equal(data.next_item_id,baseline.next_item_id+2);
  assert.deepEqual(data.storage.items.map(item=>item.id),[baseline.next_item_id,baseline.next_item_id+1]);
  assert(data.storage.items.every(item=>item.paid_cost===0));assert.equal(Object.hasOwn(result,'stock'),false);
  assert.equal(result.record.mailState.claimSequence,1);assert.equal(result.record.mailState.stockRevision,1);
  assert.deepEqual(result.record.campaigns,record.campaigns||{});
  assert.equal(fingerprint(result.record),browser.fingerprint(result.record));await browser.verifyRecord(result.record);
  assert.equal(storageFingerprint(data),browser.storageFingerprint(data));
  assert.throws(()=>grant(sign({...record,payload:payload(1000000000)}),{...mail,coins:1},null,at+1),{code:'WALLET_FULL'});
  for(const legacy of [{schema:1,revision:0,counts:{}},{schema:1,revision:1,counts:{plant:1}}])
    assert.throws(()=>grant(record,mail,legacy,at+1),{code:'STORAGE_REVIEW_REQUIRED'});
  const tampered=sign({...result.record,mailState:{...result.record.mailState,claimSequence:0}});
  assert.throws(()=>verifyRecord(tampered),{code:'CORRUPT_AUTHORITY'});
  await assert.rejects(browser.verifyRecord(tampered),{code:'CORRUPT_AUTHORITY'});
  for(const mutate of [d=>delete d.storage_format,d=>delete d.storage,d=>d.storage.items.push(d.items[0]),
    d=>d.storage.items[0].id=0,d=>d.storage.items[0].paid_cost=-1,d=>d.storage.items[0].untracked=true,
    d=>d.storage.items[0].kind='unknown',d=>d.next_item_id=d.storage.items[0].id,
    d=>d.storage.items[0].x=18,d=>d.storage.items[0].rot=4,d=>d.storage.extra=[],
    d=>d.storage.items[0].kind='register',d=>d.storage.dining_sets.push(d.dining_sets[0])]){
    const broken=structuredClone(data);mutate(broken);rejects(broken);
  }
  // Identity capacity, not a per-kind or per-Finish limit.
  const many=structuredClone(data);
  for(let i=0;i<150;i++)many.storage.items.push({id:many.next_item_id++,kind:'plant',x:0,z:0,rot:0,paid_cost:100});
  parsePayload(JSON.stringify(many));browser.parsePayload(JSON.stringify(many),15);
  const full=structuredClone(data);full.next_item_id=1000000001;
  assert.throws(()=>grant(sign({...result.record,payload:JSON.stringify(full)}),mail,null,at+2),{code:'STOCK_FULL'});
  const dining=structuredClone(data),group=dining.dining_sets.shift(),members=new Set([group.table_id,group.seat_id]);
  dining.storage.items.push(...dining.items.filter(item=>members.has(item.id)));dining.items=dining.items.filter(item=>!members.has(item.id));dining.storage.dining_sets.push(group);
  const diningNext=sign({...result.record,revision:3,payload:JSON.stringify(dining),mailState:{...result.record.mailState,stockRevision:2}});
  validateOwnedTransition(result.record,diningNext);await browser.verifyRecord(diningNext);
  const lostGroup=structuredClone(dining);lostGroup.storage.dining_sets=[];
  assert.throws(()=>validateOwnedTransition(result.record,sign({...diningNext,payload:JSON.stringify(lostGroup)})),{code:'PROTOCOL_CHANGED'});
  const reused=structuredClone(data);reused.storage.items.push({id:baseline.next_item_id-1,kind:'plant',x:0,z:0,rot:0});
  reused.items=reused.items.filter(item=>item.id!==baseline.next_item_id-1);
  const removed=structuredClone(data);removed.items=removed.items.filter(item=>item.id!==baseline.next_item_id-1);
  // Use an unused identity from a genuinely removed asset, not a duplicate.
  const removeBase=sign({...result.record,payload:JSON.stringify(removed)});
  assert.throws(()=>validateOwnedTransition(removeBase,sign({...diningNext,payload:JSON.stringify(reused)})),{code:'PROTOCOL_CHANGED'});
  const unpack=structuredClone(data),item=unpack.storage.items.shift();unpack.items.push({...item,x:8,z:8});
  const next=sign({...result.record,revision:3,payload:JSON.stringify(unpack),mailState:{...result.record.mailState,stockRevision:2}});
  validateOwnedTransition(result.record,next);
  const badBasis=structuredClone(unpack);badBasis.items.at(-1).paid_cost=100;
  assert.throws(()=>validateOwnedTransition(result.record,sign({...next,payload:JSON.stringify(badBasis)})),{code:'PROTOCOL_CHANGED'});
  const invented=structuredClone(unpack);invented.items[0].paid_cost=0;
  assert.throws(()=>validateOwnedTransition(result.record,sign({...next,payload:JSON.stringify(invented)})),{code:'PROTOCOL_CHANGED'});
  // Ordinary save coalescing may include multiple changes or a round trip.
  validateOwnedTransition(result.record,sign({...next,revision:5,mailState:{...next.mailState,stockRevision:4}}));
  validateOwnedTransition(result.record,sign({...result.record,revision:4,mailState:{...next.mailState,stockRevision:3}}));
  assert.throws(()=>validateOwnedTransition(result.record,sign({...next,mailState:result.record.mailState})),{code:'PROTOCOL_CHANGED'});
  assert.throws(()=>validateOwnedTransition(result.record,sign({...next,mailState:{...next.mailState,stockRevision:3}})),{code:'PROTOCOL_CHANGED'});
}
for(const version of [15,16]){
  const data=structuredClone(baseline);data.version=version;
  if(version===16){data.layout_hold_format='little_leaf.layout_hold.v1';data.runtime.layout_hold_format=data.layout_hold_format;
    data.runtime.service.layout_hold={format:data.layout_hold_format,hosts:[{id:data.next_item_id++,kind:'stove',x:1,z:1,rot:0}],guests:[],staff:[],dishes:[],floor:[]};}
  assert.deepEqual(parsePayload(JSON.stringify(data)),data);assert.equal(browser.parsePayload(JSON.stringify(data),15).version,version);
  const record=sign({format:2,profileId,revision:1,createdAt:at,updatedAt:at,origin:{source:'fresh',legacyDigest:null,importedAt:at},payload:JSON.stringify(data),previous:null,campaigns:{}});
  const awarded=grant(record,mail,null,at+1),claimed=JSON.parse(awarded.record.payload);
  assert.deepEqual(claimed.runtime,data.runtime,'held service is retained exactly');await browser.verifyRecord(awarded.record);
  for(const change of [d=>d.storage={},d=>d.storage_format='little_leaf.storage.v1']){const bad=structuredClone(data);change(bad);rejects(bad);}
  if(version===16){
    // A held host is a non-owning historical descriptor. Packing that same
    // physical ID is valid, but it cannot silently change furniture kind.
    const packedHost=structuredClone(claimed);
    packedHost.storage.items.push({...packedHost.runtime.service.layout_hold.hosts[0]});
    assert.equal(parsePayload(JSON.stringify(packedHost)).storage.items.at(-1).kind,'stove');
    assert.equal(browser.parsePayload(JSON.stringify(packedHost),15).storage.items.at(-1).kind,'stove');
    const mismatchedHost=structuredClone(packedHost);mismatchedHost.storage.items.at(-1).kind='plant';rejects(mismatchedHost);
    for(const change of [d=>delete d.layout_hold_format,d=>delete d.runtime.layout_hold_format,d=>delete d.runtime.service.layout_hold,d=>d.runtime.service.layout_hold.hosts[0].id=d.next_item_id]){
      const bad=structuredClone(claimed);change(bad);rejects(bad);
    }
  }
}
assert.equal(publicUid('123456789012'),true);
for(const invalid of ['012345678901','12345678901','1234567890123','１２３４５６７８９０１２',123456789012,'syntheticRecipient20'])assert.equal(publicUid(invalid),false);
const issue={issueId:'11111111-1111-4111-8111-111111111111',recipientPublicUid:'123456789012',profileId,
  caseId:'synthetic-case-20',subject:' Hello ',body:' Take care ',coins:0,items:[{catalogId:'stove',quantity:1}]};
assert.equal(normalizeIssue(issue).subject,'Hello');
for(const invalid of [{...issue,recipientPublicUid:'syntheticRecipient20'},{...issue,items:[{catalogId:'register',quantity:1}]},{...issue,coins:-1},
  {...issue,items:[{catalogId:'stove',quantity:1},{catalogId:'stove',quantity:1}]},{...issue,items:[],coins:0},{...issue,body:'\u0001'}])assert.throws(()=>normalizeIssue(invalid),{code:'INVALID_ISSUE'});
console.log('Support mail contract: Storage identity/cost/limits, browser/server parity, old receipt and15/16 hold preservation, issue/UID checks passed. Real browser/emulator not exercised.');
