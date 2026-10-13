'use strict';
// Exercise the real exported Godot JavaScript without starting Wasm or Godot.
const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const {installEngineLaunchHook} = require('./engine_launch_hook');
const file = process.argv[2];
if (!file) throw Error('Pass the exact exported index.js');
const bytes = fs.readFileSync(file), source = bytes.toString('utf8');
const checks = [];
function check(ok, label) {assert(ok, label); checks.push(label);}
function context(secure) {
  const sandbox = {console, URL, TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
    WebAssembly, Promise, fetch: () => {throw Error('No test network');},
    isSecureContext: secure, navigator: {},
    document: {currentScript: {src: 'http://127.0.0.1/index.js'}, createElement: () => ({getContext: () => ({getExtension: () => null})})}};
  sandbox.window = sandbox;
  return vm.createContext(sandbox);
}
(async () => {
  for (const secure of [true, false]) {
    const ctx = context(secure);
    vm.runInContext('(' + installEngineLaunchHook.toString() + ')({args:["--time-scale","0"],reportKey:"observation"})', ctx);
    vm.runInContext(source, ctx, {filename: file});
    vm.runInContext('const discarded = new Engine({}); const engine = new Engine({executable:"index",mainPack:"index.pck"});', ctx);
    check(vm.runInContext('Object.getPrototypeOf(discarded)!==Object.getPrototypeOf(engine)', ctx), 'real SafeEngine has per-instance prototypes, secure=' + secure);
    check(vm.runInContext('!Object.hasOwn(engine,"startGame")', ctx), 'real startup initially lives on this instance prototype');
    const expected = vm.runInContext('JSON.stringify(Features.getMissingFeatures({threads:false}))', ctx);
    const actual = vm.runInContext('JSON.stringify(Engine.getMissingFeatures({threads:false}))', ctx);
    check(actual === expected, 'feature results pass through unchanged, secure=' + secure);
    check(vm.runInContext('Engine.getMissingFeatures===Features.getMissingFeatures', ctx), 'original feature method restored');
    check(vm.runInContext('Object.hasOwn(engine,"startGame")&&!Object.hasOwn(discarded,"startGame")', ctx), 'only actual shell instance is instrumented');
    vm.runInContext('engine.init=()=>Promise.resolve();engine.preloadFile=()=>Promise.resolve();engine.start=function(){window.received={receiver:this===engine,args:this.config.args.slice(),option:this.config.locale};return Promise.resolve();};', ctx);
    await vm.runInContext('engine.startGame({args:["--verbose"],locale:"en"})', ctx);
    check(JSON.stringify(ctx.received.args) === JSON.stringify(['--main-pack','index.pck','--verbose','--time-scale','0']), 'actual startGame forwards existing and official test arguments');
    check(ctx.received.receiver && ctx.received.option === 'en', 'startup receiver and other options preserved');
    check(ctx.observation.launchCalls === 1 && JSON.stringify(ctx.observation.launchArgs) === '["--time-scale","0"]', 'one real shell launch recorded');
  }
  console.log(JSON.stringify({passed:true,checks,export_js_sha256:crypto.createHash('sha256').update(bytes).digest('hex'),scope:'Real exported SafeEngine with init/preload/start stubbed; no Wasm, Godot, browser or storage execution'},null,2));
})().catch(error => {console.error(error);process.exitCode=1;});
