import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {releasedFixture,finalBinding,RELEASED_SOURCE,legacyHtml} from './legacy_pending_fixture.mjs';
const root=path.resolve(import.meta.dirname,'..');
const old=releasedFixture(root),binding=finalBinding(root);
for(const [name,source] of Object.entries(old.sources))assert.equal(source,execFileSync('git',['show',RELEASED_SOURCE+':web/'+name],{cwd:root,encoding:'utf8'}),'fixture matches exact released Git blob');
for(const name of Object.keys(binding.source_sha256))assert.equal(fs.readFileSync(path.join(root,name),'utf8'),execFileSync('git',['show',binding.candidate_tree+':'+name],{cwd:root,encoding:'utf8'}),'runtime matches final candidate Git blob');
assert(legacyHtml.includes("import {initializeApp} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js'"),'share canonical app registry with real Firestore module');
assert(!legacyHtml.includes("from '/sdk/firebase-app.js'"),'no second app registry');
assert(legacyHtml.includes('await compare(...args)'));assert(legacyHtml.includes("sdk.connectFirestoreEmulator(db,'127.0.0.1',8080"));assert(!legacyHtml.includes('withSecurityRulesDisabled'));
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'legacy-pending-guards-'));
try{
 const dir=path.join(tmp,'tests/fixtures/released-0.1.10');fs.mkdirSync(dir,{recursive:true});
 fs.cpSync(path.join(root,'tests/fixtures/released-0.1.10'),dir,{recursive:true});releasedFixture(tmp);
 fs.appendFileSync(path.join(dir,'little_leaf_firebase.js'),'\n// altered');assert.throws(()=>releasedFixture(tmp),/unchanged released source/);
 fs.writeFileSync(path.join(dir,'little_leaf_firebase.js'),old.sources['little_leaf_firebase.js']);
 const manifest={...old.manifest,source_commit:'0'.repeat(40)};fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify(manifest));assert.throws(()=>releasedFixture(tmp));
 for(const name of Object.keys(binding.source_sha256)){fs.mkdirSync(path.dirname(path.join(tmp,name)),{recursive:true});fs.copyFileSync(path.join(root,name),path.join(tmp,name));}
 finalBinding(tmp);fs.appendFileSync(path.join(tmp,'firebase/firestore.rules'),'\n// altered');assert.throws(()=>finalBinding(tmp),/exact final runtime firebase\/firestore.rules/);
}finally{fs.rmSync(tmp,{recursive:true,force:true});}
console.log('PASS: exact released Git blobs, final runtime bindings, local-emulator-only route, tampered legacy source/commit/rules rejected.');

const sdkIndex=process.argv.indexOf('--firestore-sdk');
if(sdkIndex>=0){
 const sdk=fs.readFileSync(process.argv[sdkIndex+1],'utf8');
 const sdkApp=sdk.match(/from["'](https:\/\/www\.gstatic\.com\/firebasejs\/[^"']+\/firebase-app\.js)["']/)?.[1];
 assert(sdkApp,'real pinned Firestore SDK imports a canonical App module');
 const shared=html=>assert.equal(html.match(/import \{initializeApp\} from ['"]([^'"]+)['"]/)[1],sdkApp,'legacy loader and actual Firestore SDK must share App registry URL');
 shared(legacyHtml);
 assert.throws(()=>shared(legacyHtml.replace(sdkApp,'/sdk/firebase-app.js')),/share App registry URL/);
 console.log('PASS: actual pinned Firestore SDK and legacy loader share canonical App URL; second-registry negative control rejected.');
}
