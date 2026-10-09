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
 for(const name of ['startup_timing_browser.js','startup_trace_browser.js']) {
  const code=fs.readFileSync(require('node:path').join(__dirname,name),'utf8');
  assert(!code.includes("send('Browser.getBrowserCommandLine')"),'Diagnostics must not require an automation-only CDP method');
  const line=code.split('\n').find(row=>row.trim().startsWith('report.graphics_flags='));
  const report={gpu:{commandLine:'/opt/chrome --enable-unsafe-swiftshader --use-angle=vulkan --no-sandbox --user-data-dir=/tmp/test'}};
  vm.runInNewContext(line,{report});
  assert.equal(JSON.stringify(report.graphics_flags),JSON.stringify(['--enable-unsafe-swiftshader','--use-angle=vulkan','--no-sandbox']));
  const missing={gpu:{}};vm.runInNewContext(line,{report:missing});assert.equal(missing.graphics_flags.length,0);
 }
 console.log('STARTUP_MEMORY_REPORT_RESULT '+JSON.stringify({checks:11,failures:[]}));
})().catch(error=>{console.error(error);process.exitCode=1;});
