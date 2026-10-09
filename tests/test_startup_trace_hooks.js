'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/startup_trace_browser.js','utf8');
const begin=source.indexOf('await context.addInitScript(()=>{')+'await context.addInitScript(()=>'.length;
const end=source.indexOf('\n  });\n  const page',begin)+4;
const hook='(()=>'+source.slice(begin,end)+')';
let clock=10,status={},observer,raf,bootCalls=0;
class GL {texImage2D(value){if(value==='throw')throw Error('native failure');return value;}}
const context={document:{getElementById:()=>status},MutationObserver:class {constructor(f){observer=f;}observe(){}},PerformanceObserver:class {observe(){}},performance:{now:()=>clock,mark(){}},requestAnimationFrame:f=>raf=f,WebAssembly:{instantiate:async value=>value},WebGLRenderingContext:GL,WebGL2RenderingContext:null};context.window=context;
vm.runInNewContext(hook+'()',context);
(async()=>{
 const native={bootJson:'fresh',async boot(){bootCalls++;this.bootJson='done';return {source:'fresh'};}};
 context.__littleLeafVault=native;assert.equal(context.__littleLeafVault,native);assert.equal((await native.boot()).source,'fresh');assert.equal(native.bootJson,'done');assert.equal(bootCalls,1);
 const realBoot=Object.freeze({engineReady(){assert.equal(this,realBoot);return 7;},firstFrameReady(){return 9;}});
 context.LittleLeafBoot=realBoot;assert.equal(context.LittleLeafBoot.engineReady(),7);assert.equal(context.LittleLeafBoot.firstFrameReady(),9);assert(Object.isFrozen(context.LittleLeafBoot));
 const sentinel={};assert.equal(await context.WebAssembly.instantiate(sentinel),sentinel);
 const gl=new GL();assert.equal(gl.texImage2D('pixel'), 'pixel');assert.throws(()=>gl.texImage2D('throw'),/native failure/);assert.equal(context.startupTiming.webgl_calls.texImage2D.count,2);
 raf(1);status=null;clock=500;observer();raf(100);assert.equal(context.startupTiming.loader_removed_at,500);assert.equal(context.startupTiming.firstVisible,100);assert.equal(context.startupTiming.callbacks.at(-1).executed,500);
 assert(context.startupTiming.marks.some(x=>x.name==='__littleLeafVault:boot:end'&&x.detail.source==='fresh'));
 console.log('STARTUP_TRACE_HOOK_RESULT '+JSON.stringify({checks:16,failures:[]}));
})().catch(error=>{console.error(error);process.exitCode=1;});
