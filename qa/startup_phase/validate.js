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
const METHODS = ['_ready','_load_startup','_setup_world','_build_ui','_setup_music','_rebuild_room','_rebuild_furniture','_restore_service_runtime'];
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
    assert.equal(hash(fs.readFileSync(within(path.join(root,'qa/startup_phase'),name))),digest,'Exact overlay helper '+name);
  const basis={schema_version:1,source_commit:manifest.source_commit,source_tree:manifest.source_tree,
    base_production_sha256:source,overlay_templates_sha256:manifest.overlay_templates_sha256};
  assert.equal(hash(canonical(basis)),manifest.pair_id,'Pair binding');
  assert.equal(hash(canonical({pair_id:manifest.pair_id,mode:manifest.mode})),manifest.overlay_id,'Overlay binding');
  const entry=fs.readFileSync(path.join(root,'main.tscn'),'utf8').replace('path="res://scripts/main.gd"','path="res://qa/startup_phase/main.gd"');
  let script=fs.readFileSync(path.join(root,'qa/startup_phase',manifest.mode+'.gd'),'utf8');
  for(const [token,value] of [['SOURCE_COMMIT',manifest.source_commit],['SOURCE_TREE',manifest.source_tree],['OVERLAY_ID',manifest.overlay_id]])script=script.replaceAll('@'+token+'@',value);
  assert.deepEqual(manifest.diagnostic_project_sha256,{...source,'main.tscn':hash(entry),'qa/startup_phase/main.gd':hash(script)},'Only declared overlay changed');
  const actual=fs.readdirSync(web).filter(name=>name!=='diagnostic-manifest.json').sort();
  assert.deepEqual(actual,Object.keys(manifest.files).sort(),'No unbound export files');
  assert(actual.includes('index.pck')&&actual.includes('index.wasm')&&actual.includes('index.html'),'Complete Web export');
  for(const [name,row] of Object.entries(manifest.files)){
    const bytes=fs.readFileSync(within(web,name));assert.equal(bytes.length,row.bytes);assert.equal(hash(bytes),row.sha256,'Exact exported '+name);
  }
  return manifest;
}
function validatePacket(packet, manifest, {requireWeb=true}={}) {
  const schema=JSON.parse(fs.readFileSync(path.join(__dirname,'packet.schema.json')));
  assert.deepEqual(Object.keys(packet).sort(),schema.required.slice().sort(),'Exact packet schema fields');
  for(const key of ['web_runtime','renderer_measured','web_save_ready'])assert.equal(typeof packet[key],'boolean');
  for(const key of ['display','engine_version','scope'])assert.equal(typeof packet[key],'string');
  assert.equal(packet.schema_version,1);assert.equal(packet.kind,'little-leaf-startup-phases');
  assert.equal(packet.diagnostic_only,true);assert.equal(packet.release_qualified,false);assert.equal(packet.mode,'instrumented');
  for(const field of ['source_commit','source_tree','overlay_id'])assert.equal(packet[field],manifest[field],'Packet '+field);
  assert.equal(packet.clock,'Godot.Time.get_ticks_usec');
  assert.equal(packet.clock_origin,'engine_monotonic_timer_origin_not_browser_navigation');
  assert.equal(packet.buffer_overflow,false);assert.equal(packet.fresh_start,true);assert.equal(packet.save_recovery_blocked,false);
  if(requireWeb){assert.equal(packet.web_runtime,true);assert.equal(packet.web_save_ready,true);assert.equal(packet.renderer_measured,true);}
  assert(Array.isArray(packet.marks),'Marks array required');
  for(const row of packet.marks){assert(row&&typeof row==='object'&&!Array.isArray(row));assert.deepEqual(Object.keys(row).sort(),['boundary','method','ticks_us'],'Exact mark schema fields');}
  const expected=[['_ready','begin'],...METHODS.slice(1).flatMap(method=>[[method,'begin'],[method,'end']]),['_ready','end']];
  assert.deepEqual(packet.marks.map(row=>[row.method,row.boundary]),expected,'Exact real startup wrappers once each');
  const ticks=[...packet.marks.map(row=>row.ticks_us),packet.first_post_draw_ticks_us,packet.emit_started_ticks_us];
  assert(ticks.every(tick=>Number.isSafeInteger(tick)&&tick>=0),'Safe monotonic integer microseconds');
  assert(ticks.every((tick,index)=>index===0||tick>=ticks[index-1]),'Ordered monotonic boundaries');
  const spans=METHODS.map(method=>{const rows=packet.marks.filter(row=>row.method===method);return {method,start_ticks_us:rows[0].ticks_us,end_ticks_us:rows[1].ticks_us,duration_us:rows[1].ticks_us-rows[0].ticks_us};});
  const ready=spans[0];
  return {ready_total_us:ready.duration_us,method_spans:spans,
    unwrapped_ready_residual_including_probe_overhead_us:ready.duration_us-spans.slice(1).reduce((n,row)=>n+row.duration_us,0),
    observable_engine_timer_origin_to_ready_us:ready.start_ticks_us,
    ready_end_to_first_post_draw_us:packet.first_post_draw_ticks_us-ready.end_ticks_us,
    ready_start_to_first_post_draw_us:packet.first_post_draw_ticks_us-ready.start_ticks_us,
    first_post_draw_to_emit_started_us:packet.emit_started_ticks_us-packet.first_post_draw_ticks_us,
    pre_ready_attribution:'unknown; opaque elapsed engine timer interval, including overlay parsing/allocation; not a browser navigation duration',
    clock_alignment:'none; Godot ticks and browser performance.now are independent domains',
    release_qualified:false};
}
module.exports={hash,canonical,within,METHODS,verifyManifest,validatePacket};
