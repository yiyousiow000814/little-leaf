'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {METHODS,DETAILS,validatePacket,within}=require('../../qa/startup_phase/validate');
const {installCollector}=require('../../qa/startup_phase/collector');
const manifest={source_commit:'a'.repeat(40),source_tree:'b'.repeat(40),overlay_id:'c'.repeat(64)};
function packet() {
  let tick=1000;
  const expected=[['_ready','begin'],...METHODS.slice(1).flatMap(m=>[[m,'begin'],[m,'end']]),['_ready','end']];
  const marks=expected.map(([method,boundary])=>({method,boundary,ticks_us:tick+=10}));
  const detail_marks=DETAILS.flatMap(method=>{const parent=method.startsWith("ui_")?"_build_ui":"_setup_music",tick=marks.find(row=>row.method===parent&&row.boundary==="begin").ticks_us;return ["begin","end"].map(boundary=>({method,boundary,ticks_us:tick}));});
  return {schema_version:2,kind:'little-leaf-startup-phases',diagnostic_only:true,release_qualified:false,mode:'instrumented',...manifest,
    clock:'Godot.Time.get_ticks_usec',clock_origin:'engine_monotonic_timer_origin_not_browser_navigation',
    marks,detail_marks,detail_buffer_overflow:false,buffer_overflow:false,
    first_post_draw_ticks_us:1200,emit_started_ticks_us:1250,web_runtime:true,renderer_measured:true,display:'web',
    engine_version:'4.6.3.stable.official',fresh_start:true,save_recovery_blocked:false,web_save_ready:true,scope:'Test fixture only'};
}
let checks=0;
function test(name,callback){callback();checks++;console.log('PASS '+name);}
test('valid packet computes inclusive durations and independent clock scope',()=>{
  const result=validatePacket(packet(),manifest);assert.equal(result.ready_total_us,150);assert.equal(result.method_spans.length,8);assert.equal(result.detail_spans.length,15);assert.match(result.detail_scope,/Nested/);
  assert.equal(result.unwrapped_ready_residual_including_probe_overhead_us,80);
  assert.equal(result.observable_engine_timer_origin_to_ready_us,1010);assert.equal(result.ready_end_to_first_post_draw_us,40);
  assert.match(result.clock_alignment,/independent/);assert.equal(result.release_qualified,false);
});
for(const [name,mutate] of [
  ['unknown detail field',p=>p.detail_marks[0].unexpected=true],['detail overflow',p=>p.detail_buffer_overflow=true],['detail outside parent',p=>p.detail_marks[0].ticks_us=0],['detail wrong order',p=>p.detail_marks.reverse()],['detail missing',p=>p.detail_marks.pop()],
  ['unknown mark field',p=>p.marks[0].unexpected=true],['non-array marks',p=>p.marks={}],
  ['unknown field',p=>p.unexpected=true],['missing field',p=>delete p.scope],['nonboolean web',p=>p.web_runtime='yes'],
  ['source mismatch',p=>p.source_commit='f'.repeat(40)],['overlay mismatch',p=>p.overlay_id='f'.repeat(64)],
  ['overflow',p=>p.buffer_overflow=true],['returning save',p=>p.fresh_start=false],['blocked startup',p=>p.save_recovery_blocked=true],
  ['not Web',p=>p.web_runtime=false],['Web save bypass',p=>p.web_save_ready=false],['headless',p=>p.renderer_measured=false],
  ['reordered boundary',p=>p.marks.reverse()],['duplicate boundary',p=>p.marks.push(p.marks[0])],
  ['nonmonotonic',p=>p.marks[3].ticks_us=0],['draw before ready',p=>p.first_post_draw_ticks_us=1000],
  ['emit before draw',p=>p.emit_started_ticks_us=1199],['unsafe tick',p=>p.emit_started_ticks_us=Number.MAX_SAFE_INTEGER+1],
  ['release qualification',p=>p.release_qualified=true]])test('reject '+name,()=>{const p=packet();mutate(p);assert.throws(()=>validatePacket(p,manifest));});
test('explicit native packet cannot silently qualify browser',()=>{const p=packet();p.web_runtime=false;p.web_save_ready=false;p.renderer_measured=false;validatePacket(p,manifest,{requireWeb:false});assert.throws(()=>validatePacket(p,manifest));});
test('packet contains exactly documented schema fields',()=>{
  const schema=JSON.parse(fs.readFileSync(path.join(__dirname,'../../qa/startup_phase/packet.schema.json')));
  assert.deepEqual(Object.keys(packet()).sort(),schema.required.slice().sort());
});
test('collector captures once, retains duplicate count, performs no bridge',()=>{
  let now=0,status={},frame,observerCallback;
  const context={window:{},performance:{now:()=>++now},document:{getElementById:()=>status},
    requestAnimationFrame:cb=>frame=cb,MutationObserver:class{constructor(cb){observerCallback=cb;}observe(){}disconnect(){}}};
  vm.runInNewContext('('+installCollector.toString()+')()',context);
  frame(10);status=null;observerCallback();frame(20);
  const p=packet();context.window.__littleLeafStartupPhasePacket=p;context.window.__littleLeafStartupPhasePacket={bad:true};
  const state=context.window.__littleLeafPhaseObservation;assert.equal(state.packet,p);assert.equal(state.packetCount,2);
  assert.equal(state.firstLoaderAbsentRafTimestampMs,20);assert.equal(typeof state.loaderRemovedMs,'number');assert(state.firstObservedCallbackMs>=state.loaderRemovedMs);assert.notEqual(state.firstObservedCallbackMs,state.firstLoaderAbsentRafTimestampMs);assert.equal(typeof state.packetReceivedMs,'number');
});
test('manifest paths cannot escape',()=>{for(const name of ['../secret','/etc/passwd','a/../../secret'])assert.throws(()=>within('/tmp/project',name));});
console.log(JSON.stringify({status:'passed',checks,scope:'offline unit tests; no browser/engine measurements'}));
