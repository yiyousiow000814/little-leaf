// Immutable released client sources, served only by the synthetic fullflow harness.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
export const RELEASED_SOURCE='b8b80eea57ac3cb141cb5c771b375207a284436a';
export const FINAL_TREE='08bd2d87c4969dce910c7907682f4653b0110b65';
const expected={
 'little_leaf_firebase.js':'04774d3495b891c95e00a5525b6d74fab93aa6eb2b84199e065a82369d0fa6bc',
 'little_leaf_vault.js':'c85110f26a0a3e694da418d5a2381856cc98082a366e80ea77d553a4859fa9da'
};
export function releasedFixture(root){
 const directory=path.join(root,'tests/fixtures/released-0.1.10');
 const manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json')));
 assert.equal(manifest.source_commit,RELEASED_SOURCE);assert.equal(manifest.source_version,'0.1.10');
 const sources={};
 assert.deepEqual(Object.keys(manifest.files).sort(),Object.keys(expected).sort());
 for(const [name,digest] of Object.entries(expected)){
  assert.equal(manifest.files[name].source_path,'web/'+name);assert.equal(manifest.files[name].sha256,digest);
  sources[name]=fs.readFileSync(path.join(directory,name),'utf8');
  assert.equal(crypto.createHash('sha256').update(sources[name]).digest('hex'),digest,'unchanged released source '+name);
 }
 return {manifest,sources};
}
export const legacyHtml=`<!doctype html><title>Released 0.1.10 synthetic pending migration</title>
<script src="/legacy/little_leaf_vault.js"></script><script src="/legacy/little_leaf_firebase.js"></script>
<script type="module">
import {initializeApp} from '/sdk/firebase-app.js';
import * as sdk from '/sdk/firebase-firestore.js';
const uid=globalThis.__qaUid;
if(!/^fullflow-legacy-(auto|local|cloud)$/.test(uid))throw Error('Synthetic account required');
const db=sdk.initializeFirestore(initializeApp({apiKey:'emulator-synthetic-key',projectId:'demo-little-leaf',appId:'1:123:web:synthetic'}),{experimentalForceLongPolling:true});
sdk.connectFirestoreEmulator(db,'127.0.0.1',8080,{mockUserToken:{sub:uid,firebase:{sign_in_provider:'google.com'}}});
const remote=LittleLeafFirebase.createRemote(db,sdk),compare=remote.compareAndSet;
globalThis.__legacyAttempts=[];
remote.compareAndSet=async(...args)=>{const observation={base:args[1],candidate:args[2]};__legacyAttempts.push(observation);try{const result=await compare(...args);observation.result='accepted';return result;}catch(error){observation.result=error.code;throw error;}};
globalThis.__legacyStates=[];
globalThis.__legacyClient=LittleLeafFirebase.createClient({uid,codec:LittleLeafAuthorityCodec,remote,journal:await LittleLeafFirebase.openJournal(indexedDB),currentUid:()=>uid,status:value=>__legacyStates.push(value)});
globalThis.__legacyBoot=await __legacyClient.boot();
</script>`;

export function finalBinding(root){
 const binding=JSON.parse(fs.readFileSync(path.join(root,'tests/fixtures/released-0.1.10/final-binding.json')));
 assert.equal(binding.candidate_tree,FINAL_TREE);
 for(const [name,digest] of Object.entries(binding.source_sha256)){
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex'),digest,'exact final runtime '+name);
 }
 return binding;
}
