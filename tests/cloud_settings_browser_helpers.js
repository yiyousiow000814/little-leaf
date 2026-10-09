'use strict';
const assert=require('node:assert/strict');
const normalize=s=>s.normalize('NFKD').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
function phraseBox(tsv,phrase){
  const words=tsv.split('\n').slice(1).map(line=>line.split('\t')).filter(x=>x.length>=12&&x[0]==='5'&&x[11].trim()).map(x=>({line:x.slice(1,5).join('/'),text:normalize(x.slice(11).join('\t')),x:+x[6],y:+x[7],w:+x[8],h:+x[9]}));
  const wanted=normalize(phrase).split(' ');
  for(let i=0;i<words.length;i++){const part=words.slice(i,i+wanted.length);if(part.length===wanted.length&&part.every((w,j)=>w.line===part[0].line&&w.text===wanted[j])){const x=Math.min(...part.map(w=>w.x)),y=Math.min(...part.map(w=>w.y)),right=Math.max(...part.map(w=>w.x+w.w)),bottom=Math.max(...part.map(w=>w.y+w.h));return{x,y,width:right-x,height:bottom-y};}}
  return null;
}
function allowedRequest(url,origin){try{return new URL(url).origin===origin;}catch{return false;}}
function bind(provenance,manifest,expected){assert.equal(provenance.release_qualified,false);assert.equal(provenance.purpose,'browser-harness-diagnostic-only');assert.equal(provenance.export_source_commit,manifest.source_commit);assert.equal(provenance.export_source_tree,manifest.source_tree);assert.equal(String(provenance.export_run_id),String(manifest.workflow_run));assert.equal(provenance.export_manifest_sha256,expected);}
module.exports={normalize,phraseBox,allowedRequest,bind};
if(process.argv.includes('--test')){
  const t='level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n5\t1\t1\t1\t1\t1\t10\t20\t30\t15\t99\tSaved';
  assert(phraseBox(t,'Saved'));assert.equal(phraseBox(t,'Save'),null);assert.equal(phraseBox(t,'Not saved'),null);
  assert(allowedRequest('http://127.0.0.1:123/a','http://127.0.0.1:123'));for(const url of ['https://firebase.googleapis.com','http://127.0.0.1:124','https://evil.invalid/?x=1','file:///tmp/a'])assert.equal(allowedRequest(url,'http://127.0.0.1:123'),false);
  const p={release_qualified:false,purpose:'browser-harness-diagnostic-only',export_source_commit:'a',export_source_tree:'b',export_run_id:'17',export_manifest_sha256:'c'},m={source_commit:'a',source_tree:'b',workflow_run:'17'};bind(p,m,'c');for(const [k,v] of [['source_commit','wrong'],['source_tree','wrong'],['workflow_run','18']])assert.throws(()=>bind(p,{...m,[k]:v},'c'));assert.throws(()=>bind(p,m,'wrong'));
  console.log('Cloud Settings diagnostic source/hash, exact-label and external-network negative guards passed');
}
