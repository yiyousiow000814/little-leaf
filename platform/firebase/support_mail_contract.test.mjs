import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {hash,fingerprint,verifyRecord,normalizeIssue,grant} from './support_mail_contract.mjs';

vm.runInThisContext(readFileSync(new URL('../web/little_leaf_vault.js',import.meta.url),'utf8'));
const browser=globalThis.LittleLeafAuthorityCodec;
const at=Date.now(),profileId='22222222-2222-4222-8222-222222222222';
const payload=coins=>JSON.stringify({schema:'little_leaf_reconstructed_cafe',version:15,new_reconstruction:true,
  checkout_format:'little_leaf.checkout.v1',layout_motion_format:'little_leaf.layout_motion.v1',coins,items:[]});
for(const format of [1,2]){
  const record={format,profileId,revision:1,createdAt:at,updatedAt:at,
    origin:{source:'fresh',legacyDigest:null,importedAt:at},payload:payload(40),previous:null};
  if(format===2)record.campaigns={'little-leaf-0.1.5-existing-profile-compensation':
    {status:'granted',coins:1000,revision:1,grantedAt:at}};
  record.digest=hash(fingerprint(record));
  verifyRecord(record);await browser.verifyRecord(record);
  assert.equal(fingerprint(record),browser.fingerprint(record));
  const mail={profileId,status:'unclaimed',coins:60,items:[{catalogId:'plant',quantity:2,catalogRevision:1}]};
  const result=grant(record,mail,null,at+1);
  assert.equal(result.record.revision,2);
  assert.equal(JSON.parse(result.record.payload).coins,100);
  assert.equal(result.stock.counts.plant,2);
  assert.equal(result.record.mailState.claimSequence,1);
  assert.deepEqual(result.record.campaigns,record.campaigns||{});
  assert.equal(fingerprint(result.record),browser.fingerprint(result.record));
  await browser.verifyRecord(result.record);
  assert.throws(()=>grant(record,{...mail,coins:1000000000},null,at+1),{code:'WALLET_FULL'});
  assert.throws(()=>grant(record,mail,{revision:1,counts:{plant:100}},at+1),{code:'STOCK_FULL'});
  const tampered={...result.record,mailState:{...result.record.mailState,claimSequence:0}};
  tampered.digest=hash(fingerprint(tampered));
  assert.throws(()=>verifyRecord(tampered),{code:'CORRUPT_AUTHORITY'});
  await assert.rejects(browser.verifyRecord(tampered),{code:'CORRUPT_AUTHORITY'});
}
const issue={issueId:'11111111-1111-4111-8111-111111111111',recipientUid:'syntheticRecipient20',profileId,
  caseId:'synthetic-case-20',subject:' Hello ',body:' Take care ',coins:0,items:[{catalogId:'stove',quantity:1}]};
assert.equal(normalizeIssue(issue).subject,'Hello');
for(const invalid of [{...issue,items:[{catalogId:'register',quantity:1}]},{...issue,coins:-1},
  {...issue,items:[{catalogId:'stove',quantity:1},{catalogId:'stove',quantity:1}]},
  {...issue,items:[],coins:0},{...issue,body:'\u0001'}])assert.throws(()=>normalizeIssue(invalid),{code:'INVALID_ISSUE'});
console.log('Support mail contract: browser/server format parity, old receipt preservation, gift stock, wallet and stock caps passed.');
