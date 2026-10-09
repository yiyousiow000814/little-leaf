'use strict';
// Offline shared validator. No browser/network dependencies or side effects.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const canonical = value => Array.isArray(value) ? '['+value.map(canonical).join(',')+']' :
  value && typeof value === 'object' ? '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}' : JSON.stringify(value);
const production = name => ['project.godot','main.tscn','export_presets.cfg'].includes(name)||['assets','data','scripts','shaders','web'].includes(name.split('/')[0]);
function within(root, relative) {
  assert(!path.isAbsolute(relative) && !relative.split(/[\\/]/).includes('..'),'Unsafe manifest path');
  const full=path.resolve(root,relative);assert(full.startsWith(path.resolve(root)+path.sep),'Path escaped root');return full;
}
function verifyManifest(web, root) {
  assert(!fs.existsSync(path.join(web,'release-manifest.json')),'A diagnostic must never have a release manifest');
  const manifest=JSON.parse(fs.readFileSync(path.join(web,'diagnostic-manifest.json')));
  assert.equal(manifest.kind,'startup-phase-diagnostic-export');assert.equal(manifest.schema_version,1);
  assert.equal(manifest.diagnostic_only,true);assert.equal(manifest.release_qualified,false);
  assert.equal(manifest.release_qualification_prohibited,true);assert.equal(manifest.export_status,'passed');
  assert(['control','instrumented'].includes(manifest.mode));
  const git=(...args)=>cp.execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
  assert.equal(git('rev-parse','HEAD'),manifest.source_commit);assert.equal(git('rev-parse','HEAD^{tree}'),manifest.source_tree);
  const productionPaths=['project.godot','main.tscn','export_presets.cfg','assets','data','scripts','shaders','web'];
  assert.equal(git('diff','--name-only','HEAD','--',...productionPaths),'','No staged or unstaged production changes');
  assert(!git('ls-files','--others','--exclude-standard','-z').split('\0').some(production),'No untracked production inputs');
  const entries=git('ls-tree','-rz','HEAD','--',...productionPaths).split('\0').filter(Boolean);
  const source=Object.fromEntries(entries.map(entry=>{
    const tab=entry.indexOf('\t'),[mode,type,oid]=entry.slice(0,tab).split(' '),name=entry.slice(tab+1),file=within(root,name);
    assert(type==='blob'&&mode!=='120000'&&!fs.lstatSync(file).isSymbolicLink(),'Regular committed production input');
    const bytes=fs.readFileSync(file);
    const blob=crypto.createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
    assert.equal(blob,oid,'Worktree bytes equal committed blob '+name);
    return [name,hash(bytes)];
  }));
  assert.deepEqual(source,manifest.base_production_sha256,'Exact unchanged production checkout');
  for(const [name,digest] of Object.entries(manifest.overlay_templates_sha256))
    assert.equal(hash(fs.readFileSync(within(path.join(root,'qa/startup_descent'),name))),digest,'Exact overlay helper '+name);
  const basis={schema_version:1,source_commit:manifest.source_commit,source_tree:manifest.source_tree,
    base_production_sha256:source,overlay_templates_sha256:manifest.overlay_templates_sha256};
  assert.equal(hash(canonical(basis)),manifest.pair_id,'Pair binding');
  assert.equal(hash(canonical({pair_id:manifest.pair_id,mode:manifest.mode})),manifest.overlay_id,'Overlay binding');
  const entry=fs.readFileSync(path.join(root,'main.tscn'),'utf8').replace('path="res://scripts/main.gd"','path="res://qa/startup_descent/main.gd"');
  let script=fs.readFileSync(path.join(root,'qa/startup_descent',manifest.mode+'.gd'),'utf8');
  for(const [token,value] of [['SOURCE_COMMIT',manifest.source_commit],['SOURCE_TREE',manifest.source_tree],['OVERLAY_ID',manifest.overlay_id]])script=script.replaceAll('@'+token+'@',value);
  assert.deepEqual(manifest.diagnostic_project_sha256,{...source,'main.tscn':hash(entry),'qa/startup_descent/main.gd':hash(script)},'Only declared overlay changed');
  const actual=fs.readdirSync(web).filter(name=>name!=='diagnostic-manifest.json').sort();
  assert.deepEqual(actual,Object.keys(manifest.files).sort(),'No unbound export files');
  assert(actual.includes('index.pck')&&actual.includes('index.wasm')&&actual.includes('index.html'),'Complete Web export');
  for(const [name,row] of Object.entries(manifest.files)){
    const bytes=fs.readFileSync(within(web,name));assert.equal(bytes.length,row.bytes);assert.equal(hash(bytes),row.sha256,'Exact exported '+name);
  }
  return manifest;
}
function validatePacket(packet, manifest, {requireWeb=true}={}) {
  assert.equal(packet.schema_version,1);assert.equal(packet.kind,'little-leaf-descent-frames');
  assert.equal(packet.diagnostic_only,true);assert.equal(packet.release_qualified,false);
  for(const key of ['source_commit','source_tree','overlay_id'])assert.equal(packet[key],manifest[key]);
  assert.equal(packet.overflow,false);assert.equal(packet.fresh_start,true);
  if(requireWeb){assert.equal(packet.web_runtime,true);assert.equal(packet.renderer_measured,true);}
  assert(Number.isSafeInteger(packet.ready_begin_us)&&packet.ready_begin_us>=0);
  assert(Number.isSafeInteger(packet.ready_end_us)&&packet.ready_end_us>=packet.ready_begin_us);
  assert.deepEqual(packet.process_columns,['engine_frame','begin_us','end_us']);
  assert.deepEqual(packet.draw_columns,['engine_frame','post_draw_us','intro_active','intro_elapsed_s','hud_alpha','preparing','reported_draw_calls','reported_primitives','reported_objects','reported_process_s']);
  for(const [name,width] of [['processes',3],['draws',10]]) {
    assert(Array.isArray(packet[name])&&packet[name].length>2&&packet[name].length<=8192);
    for(const [i,row] of packet[name].entries()) {
      assert(Array.isArray(row)&&row.length===width&&row.every(Number.isFinite));
      assert(Number.isSafeInteger(row[0])&&row[0]>=0);
      assert(Number.isSafeInteger(row[1])&&row[1]>=packet.ready_begin_us);
      if(i){assert(row[0]>=packet[name][i-1][0]);assert(row[1]>=packet[name][i-1][1]);}
      if(name==='processes')assert(Number.isSafeInteger(row[2])&&row[2]>=row[1]);
      else {assert([0,1].includes(row[2])&&[0,1].includes(row[5]));assert(row[3]>=0&&row[4]>=0&&row[4]<=1);assert(row.slice(6).every(n=>n>=0));}
    }
  }
  assert(packet.draws.some(r=>r[2]===1),'Welcome must be observed');
  assert(packet.draws.some(r=>r[2]===0),'Completed entrance must be observed');
  const phase=r=>r[5]?'preparing':!r[2]?'settled':r[3]<1?'welcome_hold':r[4]>0?'hud_fade':'descent_before_hud';
  const gaps=packet.draws.slice(1).map((r,i)=>({end_engine_frame:r[0],end_us:r[1],gap_us:r[1]-packet.draws[i][1],phase_at_end:phase(r),phase_at_start:phase(packet.draws[i]),intro_elapsed_s:r[3],hud_alpha:r[4],reported_draw_calls:r[6],reported_primitives:r[7]}));
  const summarize=values=>{values.sort((a,b)=>a-b);return {samples:values.length,p50:values[Math.floor((values.length-1)*.5)]??null,p95:values[Math.floor((values.length-1)*.95)]??null,max:values.at(-1)??null};};
  return {ready_wall_us:packet.ready_end_us-packet.ready_begin_us,
    main_process_wall_us:summarize(packet.processes.map(r=>r[2]-r[1])),
    post_draw_gap_us_by_ending_phase:Object.fromEntries(['preparing','welcome_hold','descent_before_hud','hud_fade','settled'].map(p=>[p,summarize(gaps.filter(r=>r.phase_at_end===p).map(r=>r.gap_us))])),
    largest_gaps:gaps.sort((a,b)=>b.gap_us-a.gap_us).slice(0,12),
    scope:'Boundary-crossing gaps retained once under ending phase with both phases explicit. Main wrapper excludes child work. Engine-reported draw counters are not GPU duration. Independent browser/Godot clocks are not aligned.'};
}
module.exports={hash,canonical,within,verifyManifest,validatePacket};
