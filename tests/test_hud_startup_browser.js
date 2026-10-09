'use strict';
const assert=require('node:assert/strict');
const {postLoaderWindows,ownedProcessMemory}=require('./hud_startup_browser');
const fs=require('node:fs');
assert.throws(()=>postLoaderWindows({}),/DOM removal/);
const rows={loaderRemovedMs:100,callbacks:[
 {executedMs:90,rafMs:0,loaderPresent:true},
 {executedMs:105,rafMs:1,loaderPresent:false},
 {executedMs:121,rafMs:2,loaderPresent:false},
 {executedMs:140,rafMs:3,loaderPresent:false},
 {executedMs:1150,rafMs:4,loaderPresent:false},
 {executedMs:1201,rafMs:5,loaderPresent:false},
 {executedMs:6700,rafMs:6,loaderPresent:false},
 {executedMs:6860,rafMs:7,loaderPresent:false}]};
const r=postLoaderWindows(rows);
assert.equal(r['0_1000ms'].samples,2);assert.equal(r['0_1000ms'].max_ms,19);
assert.equal(r['1000_6500ms'].samples,2);assert.equal(r['1000_6500ms'].max_ms,1010);
assert.equal(r['6500_11000ms'].samples,2);assert.equal(r['6500_11000ms'].over100,2);
assert.equal(postLoaderWindows({loaderRemovedMs:0,callbacks:[]})['0_1000ms'].p50_ms,null);
const crossing=postLoaderWindows({loaderRemovedMs:0,callbacks:[{executedMs:990,loaderPresent:false},{executedMs:1200,loaderPresent:false}]});
assert.equal(crossing['0_1000ms'].samples,0);assert.equal(crossing['1000_6500ms'].samples,1);assert.equal(crossing['1000_6500ms'].max_ms,210);
const beforeLoader=postLoaderWindows({loaderRemovedMs:100,callbacks:[{executedMs:90,loaderPresent:false},{executedMs:105,loaderPresent:false}]});
assert.equal(beforeLoader['0_1000ms'].samples,0,'Never import pre-loader time into a visible gap');
const boundary=postLoaderWindows({loaderRemovedMs:0,callbacks:[{executedMs:990,loaderPresent:false},{executedMs:1000,loaderPresent:false},{executedMs:1010,loaderPresent:false}]});
assert.equal(boundary['0_1000ms'].samples,1);assert.equal(boundary['1000_6500ms'].samples,1);
async function memoryFixture(){
 const original=fs.readFileSync;
 try{
  fs.readFileSync=(file,...args)=>file==='/proc/424242/status'?'Name:\tchrome\nVmHWM:\t   67890 kB\nVmRSS:\t   12345 kB\n':original(file,...args);
  const memory=await ownedProcessMemory({send:async()=>({processInfo:[{id:424242,type:'renderer'}]})});
  assert.equal(memory.processes.length,1);assert.equal(memory.processes[0].rss_bytes,12345*1024);assert.equal(memory.processes[0].peak_rss_bytes,67890*1024);
 }finally{fs.readFileSync=original;}
 console.log('HUD startup collector: 17 assertions passed; no browser acceptance');
}
memoryFixture().catch(error=>{console.error(error);process.exitCode=1;});
