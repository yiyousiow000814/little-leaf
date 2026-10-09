'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'startup_timing_browser.js'),'utf8');
const body=source.slice(source.indexOf('async function ownedProcessMemory'),source.indexOf('(async()=>{'));
(async()=>{
 let reads=[];
 const sandbox={Number,RegExp,String,fs:{readFileSync(name){reads.push(name);return 'Name:\tchrome\nVmRSS:\t1234 kB\nVmHWM:\t5678 kB\n';}}};
 vm.createContext(sandbox);vm.runInContext(body,sandbox);
 const report=await sandbox.ownedProcessMemory({send:async()=>({processInfo:[{id:123,type:'renderer'},{id:-1,type:'invalid'}]})});
 assert.equal(reads.length,1);assert.equal(reads[0],'/proc/123/status');
 assert.equal(report.processes[0].rss_bytes,1234*1024);assert.equal(report.processes[0].peak_rss_bytes,5678*1024);
 const unavailable=await sandbox.ownedProcessMemory({send:async()=>{throw Error('Unavailable');}});
 assert.match(unavailable.unavailable,/Unavailable/);
 console.log('STARTUP_MEMORY_REPORT_RESULT '+JSON.stringify({checks:5,failures:[]}));
})().catch(error=>{console.error(error);process.exitCode=1;});
