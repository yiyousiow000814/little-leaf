'use strict';
const assert=require('node:assert/strict');
const {validatePacket}=require('../../qa/startup_descent/validate');
const {postLoaderWindows,ownedProcessMemory}=require('../../qa/startup_descent/run_browser');
const manifest={source_commit:'a'.repeat(40),source_tree:'b'.repeat(40),overlay_id:'c'.repeat(64)};
const packet={schema_version:1,kind:'little-leaf-descent-frames',diagnostic_only:true,release_qualified:false,...manifest,ready_begin_us:10,ready_end_us:20,
 process_columns:['engine_frame','begin_us','end_us'],processes:[[1,21,23],[2,24,29],[3,30,35]],
 draw_columns:['engine_frame','post_draw_us','intro_active','intro_elapsed_s','hud_alpha','preparing','reported_draw_calls','reported_primitives','reported_objects','reported_process_s'],
 draws:[[1,100,1,0,1,1,30,200,20,.02],[2,200,1,.1,0,0,30,200,20,.02],[3,500,1,5,.5,0,40,300,25,.03],[4,600,0,6.5,1,0,40,300,25,.03]],
 overflow:false,fresh_start:true,web_runtime:true,renderer_measured:true};
let checks=0;const check=(fn)=>{fn();checks++;};
check(()=>{const p=validatePacket(packet,manifest);assert.equal(p.largest_gaps[0].gap_us,300);assert.equal(p.largest_gaps[0].phase_at_start,'welcome_hold');assert.equal(p.largest_gaps[0].phase_at_end,'hud_fade');assert.equal(p.post_draw_gap_us_by_ending_phase.hud_fade.samples,1);});
for(const mutate of [p=>p.overflow=true,p=>p.source_commit='wrong',p=>p.draws[1][1]=0,p=>p.draws[1][4]=1.1,p=>p.processes[0][2]=0,p=>p.draws[0].pop(),p=>p.fresh_start=false,p=>p.draws.forEach(r=>r[2]=1),p=>p.draws[0][6]=-1,p=>p.renderer_measured=false])check(()=>{const p=structuredClone(packet);mutate(p);assert.throws(()=>validatePacket(p,manifest));});
const cb=(t,loader=false)=>({executedMs:t,loaderPresent:loader});
check(()=>{const w=postLoaderWindows({loaderRemovedMs:0,callbacks:[cb(990),cb(1200),cb(6500),cb(6600)]});assert.equal(w['1000_6500ms'].samples,2);assert.equal(w['6500_11000ms'].samples,1);assert.equal(w['1000_6500ms'].p50_ms,210);});
check(()=>{const w=postLoaderWindows({loaderRemovedMs:100,callbacks:[cb(0,true),cb(110),cb(1100),cb(1200)]});assert.equal(w['0_1000ms'].samples,1);assert.equal(w['1000_6500ms'].samples,1);});
const fs=require('node:fs'),original=fs.readFileSync;
(async()=>{try{fs.readFileSync=()=> 'Name:\tchrome\nVmRSS:\t12345 kB\nVmHWM:\t67890 kB\n';const p=await ownedProcessMemory({send:async()=>({processInfo:[{id:123,type:'renderer'}]})});check(()=>assert.equal(p.processes[0].rss_bytes,12345*1024));check(()=>assert.equal(p.processes[0].peak_rss_bytes,67890*1024));}finally{fs.readFileSync=original;}console.log(checks+' descent diagnostic assertions passed');})().catch(e=>{console.error(e);process.exitCode=1;});
