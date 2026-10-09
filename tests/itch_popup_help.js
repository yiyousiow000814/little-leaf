'use strict';
// Exact source and a synthetic Godot-substituted shell; no engine/browser/account/storage runtime.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),path=require('node:path');
const shell=fs.readFileSync('web/little_leaf_shell.html','utf8');
const url='https://little-leaf-41e5d.firebaseapp.com/';
const base=process.env.ITCH_BASE_EXPORT ? fs.readFileSync(process.env.ITCH_BASE_EXPORT,'utf8') : null;
const config=base?.match(/const GODOT_CONFIG = ([^\n]+);/)?.[1] || '{}';
const exported=shell.replaceAll('$GODOT_PROJECT_NAME','Little Leaf').replaceAll('$GODOT_SPLASH','index.png')
  .replaceAll('$GODOT_URL','index.js').replaceAll('$GODOT_CONFIG',config).replaceAll('$GODOT_THREADS_ENABLED','false').replaceAll('$GODOT_HEAD_INCLUDE','');
let checks=0;const check=(ok,why)=>{assert(ok,why);checks++;};
const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();};
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
function fixture(html,clipboard){
  const scripts=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x=>x[1]);
  const entry=scripts.find(s=>s.includes('/* Little Leaf itch entry only.'));
  const startup=scripts.find(s=>s.includes('const GODOT_CONFIG = ')).replace('$GODOT_CONFIG','{}').replace('$GODOT_THREADS_ENABLED','false');
  const calls=[],nodes=Object.fromEntries(['itch-entry','itch-local','itch-copy','itch-copy-status','itch-account-address','canvas','status'].map(id=>[id,{
    hidden:id==='itch-entry',disabled:false,textContent:'',value:id==='itch-account-address'?url:'',listeners:{},selected:0,focusCount:0,
    addEventListener(type,fn,opts){this.listeners[type]={fn,once:!!opts?.once};},
    dispatch(type){const h=this.listeners[type];if(h){if(h.once)delete this.listeners[type];return h.fn();}},
    focus(){this.focusCount++;this.dispatch('focus');},select(){this.selected++;}
  }]));
  const context={Promise,console,location:{hostname:'html-classic.itch.zone'},navigator:clipboard===undefined?{}:{clipboard},
    document:{getElementById:id=>nodes[id]},__littleLeafVault:{boot(){calls.push('vault');return Promise.resolve();}},
    __littleLeafPreferences:{boot(){calls.push('preferences');return Promise.resolve();}},LittleLeafBoot:{engineReady(){calls.push('ready');},fail(e){throw e;}}};
  context.Engine=function(){return {startGame(){calls.push('engine');return Promise.resolve();}};};context.Engine.getMissingFeatures=()=>[];
  for(const key of ['indexedDB','localStorage','sessionStorage','fetch','open'])Object.defineProperty(context,key,{get(){throw Error('Unexpected boundary: '+key);}});
  context.window=context;vm.createContext(context);vm.runInContext(entry,context);vm.runInContext(startup,context);
  return {nodes,calls,context,entry};
}
(async()=>{
  for(const [kind,html] of [['source-template',shell],['synthetic-exported-shell',exported]]){
    check(html.includes(`id="itch-account-address" type="text" readonly value="${url}"`),'Visible readonly canonical address');
    check(html.includes(`href="${url}" target="_blank" rel="noopener noreferrer"`),'Original new-tab account link');
    check(html.includes('If the account tab does not open, copy this address and open it in a new browser tab.'),'Conditional help avoids asserting popup failure');
    check(html.includes('Account progress is separate: your existing itch progress does not transfer automatically.'),'Separate progress wording retained');
    check(html.includes('Continue local play on itch'),'Local access retained');
    check(html.indexOf('id="itch-account"')<html.indexOf('id="itch-account-address"') && html.indexOf('id="itch-account-address"')<html.indexOf('id="itch-copy"') && html.indexOf('id="itch-copy"')<html.indexOf('id="itch-local"'),'Natural keyboard DOM order');
    check(!/tabindex="-1"/.test(html),'No controls removed from keyboard order');
    {
      let writes=0,written;const pending=deferred(),f=fixture(html,{writeText(value){writes++;written=value;return pending.promise;}});await flush();
      f.nodes['itch-copy'].focus();const copying=f.nodes['itch-copy'].dispatch('click');f.nodes['itch-copy'].dispatch('click');
      check(writes===1 && written===url && f.nodes['itch-copy'].disabled,'Repeated clicks coalesce while clipboard pending');
      check(f.calls.length===0 && !f.nodes['itch-entry'].hidden,'Copy cannot open account or local game');
      pending.resolve();await copying;await flush();
      check(f.nodes['itch-copy-status'].textContent==='Link copied. Paste it into a new browser tab.','Success describes copy only');
      check(!f.nodes['itch-copy'].disabled && f.nodes['itch-copy'].focusCount===1 && f.nodes['itch-account-address'].focusCount===0,'Success restores control without stealing focus');
      await f.nodes['itch-copy'].dispatch('click');check(writes===2,'A completed copy can be repeated');
      check(!/getElementById\(['"]itch-account['"]\)/.test(f.entry),'Account anchor remains native navigation');
      check(!f.entry.includes('permissions') && !f.entry.includes('execCommand'),'No permission request or legacy copy workaround');
    }
    for(const failure of ['unavailable','cancelled','rejected','throws']){
      const clipboard=failure==='unavailable'?undefined:{writeText(){if(failure==='throws')throw Error('Synthetic synchronous failure');return Promise.reject(Error(failure));}};
      const f=fixture(html,clipboard);await f.nodes['itch-copy'].dispatch('click');await flush();
      check(!f.nodes['itch-copy'].disabled && f.nodes['itch-account-address'].focusCount===1 && f.nodes['itch-account-address'].selected>0,'Copy failure restores button and focuses/selects manual address');
      check(f.nodes['itch-copy-status'].textContent.includes('Copy did not finish.') && f.nodes['itch-copy-status'].textContent.includes('copy it manually'),'Failure/cancellation has manual fallback');
      check(!f.nodes['itch-copy-status'].textContent.includes('blocked') && f.calls.length===0 && !f.nodes['itch-entry'].hidden,'Failure cannot invent blocked-popup state or launch game');
      f.nodes['itch-local'].dispatch('click');f.nodes['itch-local'].dispatch('click');await flush();
      check(JSON.stringify(f.calls)==='["vault","preferences","engine","ready"]','Local play boots once after copy failure');
    }
    for(const outcome of ['success','failure']){
      const pending=deferred(),f=fixture(html,{writeText(){return pending.promise;}});
      const copying=f.nodes['itch-copy'].dispatch('click');f.nodes['itch-local'].dispatch('click');await flush();
      outcome==='success'?pending.resolve():pending.reject(Error('Cancelled after local choice'));
      await copying;await flush();
      check(f.nodes['itch-entry'].hidden && JSON.stringify(f.calls)==='["vault","preferences","engine","ready"]','Late clipboard result cannot interrupt local play');
      check(f.nodes['itch-account-address'].focusCount===0 && !f.nodes['itch-copy-status'].textContent,'Late clipboard result cannot focus hidden controls or announce stale status');
    }
    const manual=fixture(html);manual.nodes['itch-account-address'].focus();check(manual.nodes['itch-account-address'].selected===1,'Keyboard/manual focus selects the address');
  }
  const receipt={passed:true,checks,scope:'Exact source and synthetic exported-shell entry/startup scripts in synthetic DOM; keyboard focus calls, repeat copy, cancellation and fallback contracts only',base:'e8532a45495724e30d7c9b66c6fd47ba79224f7f',shell_sha256:crypto.createHash('sha256').update(shell).digest('hex'),synthetic_export_sha256:crypto.createHash('sha256').update(exported).digest('hex'),prior_ci_config_reused:!!base,real_browser:false,real_clipboard:false,real_google_sign_in:false,player_save_used:false};
  if(process.env.ITCH_HELP_EVIDENCE){fs.mkdirSync(process.env.ITCH_HELP_EVIDENCE,{recursive:true});fs.writeFileSync(path.join(process.env.ITCH_HELP_EVIDENCE,'synthetic-exported-shell.html'),exported);fs.writeFileSync(path.join(process.env.ITCH_HELP_EVIDENCE,'popup-help-contract.json'),JSON.stringify(receipt,null,2)+'\n');}
  console.log(JSON.stringify(receipt,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
