import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc} from 'firebase/firestore';

assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/,
  'This generated-identity test only permits the local emulator');
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules:readFileSync('firestore.rules','utf8')}});
try {
  const google={firebase:{sign_in_provider:'google.com'}};
  const player=env.authenticatedContext('syntheticRecipient20',google).firestore();
  const other=env.authenticatedContext('syntheticOther20',google).firestore();
  const save=doc(player,'players','syntheticRecipient20','saves','cafe');
  const control=doc(player,'players','syntheticRecipient20','saveControl','protocol');
  const grant=doc(player,'players','syntheticRecipient20','giftStock','current');
  const role=doc(player,'supportAdmins','syntheticRecipient20');
  const mail=doc(player,'players','syntheticRecipient20','mail','letter');
  const writerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
  await env.withSecurityRulesDisabled(async context=>{
    const db=context.firestore();
    await setDoc(doc(db,'players','syntheticRecipient20','session','owner'),{schema:1,owner:writerId,epoch:1,device:'Mac',
      updatedAt:new Date(),request:null,ack:null});
    await setDoc(doc(db,'players','syntheticRecipient20','saves','cafe'),{schema:1,profileId:'22222222-2222-4222-8222-222222222222',
      revision:2,digest:'a'.repeat(64),record:'synthetic',writerId,writerEpoch:1});
    await setDoc(doc(db,'players','syntheticRecipient20','saveControl','protocol'),{schema:1,version:1,claimSequence:1,stockRevision:1});
  });
  await assertFails(getDoc(control)); // The adapter never reads private protocol metadata.
  await assertFails(getDoc(doc(other,'players','syntheticRecipient20','saveControl','protocol')));
  await assertFails(setDoc(control,{schema:1,version:0}));
  await assertFails(setDoc(role,{enabled:true,capabilities:['issue']}));
  await assertFails(setDoc(doc(player,'players','syntheticRecipient20','identity','public'),{schema:1,publicUid:'123456789012'}));
  await assertFails(getDoc(doc(player,'players','syntheticRecipient20','identity','public')));
  await assertFails(setDoc(doc(player,'playerUidIndex','123456789012'),{schema:1,authUid:'syntheticRecipient20'}));
  await assertFails(getDoc(doc(other,'playerUidIndex','123456789012')));
  await assertFails(setDoc(grant,{schema:1,revision:999,counts:{stove:99}}));
  await assertFails(setDoc(mail,{status:'claimed'}));
  await assertFails(setDoc(doc(player,'players','syntheticRecipient20','mailClaims','letter'),{coins:99}));
  await assertFails(setDoc(save,{schema:1,profileId:'22222222-2222-4222-8222-222222222222',
    revision:3,digest:'b'.repeat(64),record:'synthetic old writer',writerId,writerEpoch:1}));
  assert.equal((await getDoc(save)).data().revision,2);
  console.log('Support mail rules emulator: protected old writer and forged roles, mail, stock and claims denied.');
}finally{await env.cleanup();}
