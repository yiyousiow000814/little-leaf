'use strict';
const assert=require('node:assert/strict');
const normalize=s=>s.normalize('NFKD').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
function phraseBox(tsv,phrase){
  const words=tsv.split('\n').slice(1).map(line=>line.split('\t')).filter(x=>x.length>=12&&x[0]==='5'&&x[11].trim()).map(x=>({line:x.slice(1,5).join('/'),text:normalize(x.slice(11).join('\t')),x:+x[6],y:+x[7],w:+x[8],h:+x[9]}));
  const wanted=normalize(phrase).split(' '),exactStatus=['saved','saving','not saved'].includes(normalize(phrase));
  for(let i=0;i<words.length;i++){const part=words.slice(i,i+wanted.length);if(part.length===wanted.length&&part.every((w,j)=>w.line===part[0].line&&w.text===wanted[j])&&(!exactStatus||words.filter(w=>w.line===part[0].line).length===wanted.length)){const x=Math.min(...part.map(w=>w.x)),y=Math.min(...part.map(w=>w.y)),right=Math.max(...part.map(w=>w.x+w.w)),bottom=Math.max(...part.map(w=>w.y+w.h));return{x,y,width:right-x,height:bottom-y};}}
  return null;
}
function allowedRequest(url,origin){try{return new URL(url).origin===origin;}catch{return false;}}
function bind(provenance,manifest,expected){assert.equal(provenance.release_qualified,false);assert.equal(provenance.purpose,'browser-harness-diagnostic-only');assert.equal(provenance.export_source_commit,manifest.source_commit);assert.equal(provenance.export_source_tree,manifest.source_tree);assert.equal(String(provenance.export_run_id),String(manifest.workflow_run));assert.equal(provenance.export_manifest_sha256,expected);}
function panelClip(settingsPoint){assert.equal(settingsPoint.length,2);assert(settingsPoint.every(Number.isFinite));
  // Fixed 1360x880 diagnostic viewport; offsets verified against the retained
  // exact-export Settings frame and anchored to its native Settings button.
  const clip={x:Math.floor(settingsPoint[0]-255),y:Math.floor(settingsPoint[1]+72),width:310,height:660};
  assert(clip.x>=0&&clip.y>=0&&clip.x+clip.width<=1360&&clip.y+clip.height<=880);return clip;
}
module.exports={normalize,phraseBox,allowedRequest,bind,panelClip};
if(process.argv.includes('--test')){(async()=>{
  const t='level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n5\t1\t1\t1\t1\t1\t10\t20\t30\t15\t99\tSaved';
  assert(phraseBox(t,'Saved'));assert.equal(phraseBox(t,'Save'),null);assert.equal(phraseBox(t,'Not saved'),null);const notSaved=t.replace('Saved','Not')+'\n5\t1\t1\t1\t1\t2\t45\t20\t35\t15\t99\tsaved';assert.equal(phraseBox(notSaved,'Saved'),null);assert(phraseBox(notSaved,'Not saved'));
  assert(allowedRequest('http://127.0.0.1:123/a','http://127.0.0.1:123'));for(const url of ['https://firebase.googleapis.com','http://127.0.0.1:124','https://evil.invalid/?x=1','file:///tmp/a'])assert.equal(allowedRequest(url,'http://127.0.0.1:123'),false);
  const p={release_qualified:false,purpose:'browser-harness-diagnostic-only',export_source_commit:'a',export_source_tree:'b',export_run_id:'17',export_manifest_sha256:'c'},m={source_commit:'a',source_tree:'b',workflow_run:'17'};bind(p,m,'c');for(const [k,v] of [['source_commit','wrong'],['source_tree','wrong'],['workflow_run','18']])assert.throws(()=>bind(p,{...m,[k]:v},'c'));assert.throws(()=>bind(p,m,'wrong'));
  assert.deepEqual(panelClip([946.075,52.554]),{x:691,y:124,width:310,height:660});assert.throws(()=>panelClip([0,0]));
  const fs=require('node:fs'),vm=require('node:vm');
  const fixtureSource=fs.readFileSync('tests/cloud_settings_browser.js','utf8'),sdkSource=fixtureSource.match(/const sdk=(\{[^\n]+\});/)[1];
  const f={mode:'online',cloud:null,writes:0,signOutCalls:0},auth={currentUser:{uid:'synthetic'}};
  const snapshot=()=>({exists:()=>!!f.cloud,data:()=>structuredClone(f.cloud)});
  const sdk=vm.runInNewContext('('+sdkSource+')',{f,auth,snapshot,structuredClone,Error});
  const root={};root.window=root;vm.runInNewContext(fs.readFileSync('web/little_leaf_firebase.js','utf8'),root);
  const remote=root.LittleLeafFirebase.createRemote({},sdk);assert.equal(await remote.read('synthetic'),null);await remote.compareAndSet('synthetic',null,{digest:'first'},()=>{});assert.equal(f.cloud.digest,'first');assert.equal(f.writes,1);const loaded=await remote.read('synthetic');assert.equal(loaded.digest,'first');loaded.digest='changed-copy';assert.equal(f.cloud.digest,'first');await assert.rejects(remote.compareAndSet('synthetic','wrong-base',{digest:'bad'},()=>{}),e=>e.code==='REVISION_CONFLICT');assert.equal(f.cloud.digest,'first');
  f.mode='hold';const pending=remote.compareAndSet('synthetic','first',{digest:'second'},()=>{});await new Promise(resolve=>setImmediate(resolve));assert.equal(f.cloud.digest,'first');assert.equal(typeof f.pending,'function');f.pending();await pending;assert.equal(f.cloud.digest,'second');
  f.mode='offline';await assert.rejects(remote.read('synthetic'),e=>e.code==='unavailable');await assert.rejects(remote.compareAndSet('synthetic','second',{digest:'third'},()=>{}),e=>e.code==='unavailable');assert.equal(f.cloud.digest,'second');
  assert.equal(await sdk.getRedirectResult(auth),null);await sdk.setPersistence(auth,sdk.browserLocalPersistence);assert.equal(sdk.getAuth(),auth);assert.equal(typeof sdk.onAuthStateChanged(auth,()=>{}),'function');await assert.rejects(sdk.signOut(auth),/Synthetic sign-out failure/);assert.equal(f.signOutCalls,1);assert.equal(auth.currentUser.uid,'synthetic');await assert.rejects(sdk.signInWithRedirect(auth,{}),/never signs in/);
  require('node:child_process').execFileSync(process.execPath,['tests/firebase_boot_presentation.js'],{stdio:'pipe'});
  console.log('Cloud Settings diagnostic source/hash, exact-label, SDK signature/ack and external-network negative guards passed');
})().catch(error=>{console.error(error);process.exitCode=1;});}
