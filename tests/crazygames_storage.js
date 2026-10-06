'use strict';
// Synthetic SDK contract fixtures; no real account/cloud persistence claim.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const {webcrypto} = require('node:crypto');
const source = name => fs.readFileSync('web/'+name+'.js','utf8');
const payload = fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const KEY='little-leaf.cg.profile.v1', PREFS='little-leaf.cg.preferences.v1';
let checks=0;const check=(condition,label)=>{assert(condition,label);checks++;};
function harness(map=new Map()) {
  const control={user:null,writes:0,events:[],getError:false,setError:false,initError:false,scopeHook:null};
  const sdk={environment:'local',init:async()=>{if(control.initError)throw Error('Synthetic init failure');},
    user:{isUserAccountAvailable:true,getUser:async()=>{control.scopeHook?.();return control.user;},addAuthListener:f=>{control.auth=f;}},
    game:{settings:{muteAudio:false},loadingStart:()=>control.events.push('loadingStart'),loadingStop:()=>control.events.push('loadingStop'),gameplayStart:()=>control.events.push('gameplayStart'),gameplayStop:()=>control.events.push('gameplayStop')},
    data:{getItem:key=>{if(control.getError)throw Error('Synthetic read failure');return map.get(key)??null;},setItem:(key,value)=>{if(control.setError)throw Error('Synthetic set failure');map.set(key,value);control.writes++;}}
  };
  const c=vm.createContext({CrazyGames:{SDK:sdk},crypto:webcrypto,Date,TextEncoder,TextDecoder,Uint8Array,Int8Array,URL,TypeError,DOMException,setTimeout,clearTimeout,location:{reload(){control.events.push('reload');}}});
  for(const key of ['indexedDB','localStorage','sessionStorage'])Object.defineProperty(c,key,{get(){throw Error('Application must not access a local fallback');}});
  for(const name of ['little_leaf_save_log','little_leaf_vault','little_leaf_crazygames'])vm.runInContext(source(name),c);
  return {c,control,map,client:c.__littleLeafVault,prefs:c.__littleLeafPreferences};
}
(async()=>{
  let h=harness(),b=await h.client.boot();check(b.ok&&b.source==='fresh'&&b.revision===0,'fresh means SDK key truly absent');
  check((await h.prefs.boot()).ok,'preferences boot exclusively through SDK');
  const result=await h.client.commit(payload,0,b.profileId);
  check(result.ok&&result.platformAccepted&&result.durable===false&&result.cloudConfirmed===false,'SDK acceptance never claims cloud or durability');
  check(result.revision===1,'submission advances guarded revision');
  check(!h.c.LittleLeafSaveLog.snapshot().some(e=>e.event==='save_confirmed'),'no false IndexedDB transaction confirmation');
  const original=h.map.get(KEY),restored=harness(h.map),r=await restored.client.boot();
  check(r.ok&&r.profileId===b.profileId&&r.revision===1&&r.payload===payload,'new fixture session restores exact SDK identity/revision/payload');
  check(h.prefs.writeText('[audio]\nvolume=42'),'preferences written through SDK');
  check(JSON.parse(h.map.get(PREFS)).text.includes('42'),'preferences in platform key');
  check((await h.client.commit(payload,0,b.profileId)).code==='REVISION_CONFLICT','stale revision cannot write');
  for(const mode of ['init','read','corrupt','nonstring']){
    const x=harness();if(mode==='init')x.control.initError=true;if(mode==='read')x.control.getError=true;if(mode==='corrupt')x.map.set(KEY,'{broken');if(mode==='nonstring')x.map.set(KEY,{});
    const boot=await x.client.boot();check(!boot.ok&&!x.c.LittleLeafPlatform.ready,'load failure blocks fresh gameplay: '+mode);check(x.control.writes===0,'load failure never writes empty replacement: '+mode);
  }
  h=harness();b=await h.client.boot();let before=h.map.get(KEY);h.control.setError=true;
  check(!(await h.client.commit(payload,0,b.profileId)).ok,'SDK write exception stays failure');check(h.map.get(KEY)===before,'write failure leaves prior value');
  h=harness();b=await h.client.boot();h.control.user={__dangerousUserId:'other',username:'synthetic'};
  check((await h.client.commit(payload,0,b.profileId)).code==='PLATFORM_ACCOUNT_CHANGED','changed account cannot receive stale guest payload');check(h.control.writes===1,'account transition no extra write');
  h=harness();b=await h.client.boot();h.control.auth();check(!h.c.LittleLeafPlatform.ready,'auth event blocks immediately');check(!h.prefs.writeText('stale'),'auth transition blocks preferences');check(!(await h.client.commit(payload,0,b.profileId)).ok,'auth transition blocks progress');
  h=harness();b=await h.client.boot();h.map.set(KEY,'different SDK cache');
  check((await h.client.commit(payload,0,b.profileId)).code==='REVISION_CONFLICT','changed SDK cache stops optimistic write');
  h=harness();b=await h.client.boot();const first=h.client.commit(payload,0,b.profileId);check((await h.client.commit(payload,0,b.profileId)).code==='SAVE_BUSY','reentrant submission blocked');check((await first).ok,'first submission finishes');
  h=harness();b=await h.client.boot();before=h.map.get(KEY);const big=JSON.parse(payload);big.syntheticPadding='x'.repeat(1048000);
  check(!(await h.client.commit(JSON.stringify(big),0,b.profileId)).ok,'over-limit payload blocked before SDK write');check(h.map.get(KEY)===before,'limit failure leaves authority unchanged');
  const near=JSON.parse(payload);near.syntheticPadding='x'.repeat(990000);check(h.prefs.writeText('x'.repeat(65000)),'large valid preference fixture accepted');
  check((await h.client.commit(JSON.stringify(near),0,b.profileId)).code==='PLATFORM_DATA_LIMIT','combined progress/preferences SDK JSON budget enforced');
  h=harness();b=await h.client.boot();h.map.set(PREFS,'broken');check(!(await h.prefs.boot()).ok&&!h.c.LittleLeafPlatform.ready,'preference load error stops engine start');
  h=harness();await h.client.boot();h.c.LittleLeafPlatform.update(true);h.c.LittleLeafPlatform.update(true);h.c.LittleLeafPlatform.update(false);
  check(h.control.events.filter(x=>x==='gameplayStart').length===1&&h.control.events.includes('loadingStop')&&h.control.events.includes('gameplayStop'),'loading/gameplay events sent on state edges');
  h.c.CrazyGames.SDK.game.settings.muteAudio=true;h.c.LittleLeafPlatform.update(false);check(h.c.LittleLeafPlatform.muteAudio,'platform mute propagated');
  h=harness();h.c.LittleLeafPlatform.update(true);check(h.control.events.length===0,'no fake start before SDK or Data loading');
  const opening=h.client.boot();await Promise.resolve();h.c.LittleLeafPlatform.update(true);check(!h.control.events.includes('gameplayStart'),'loading Data is not playable');await opening;
  h.c.LittleLeafPlatform.update(false);check(!h.control.events.includes('loadingStop')&&!h.c.LittleLeafPlatform.firstGameplayAt,'too-small first viewport stays loading without fake start');
  h.c.LittleLeafPlatform.update(true);check(h.c.LittleLeafPlatform.playing&&h.control.events.filter(e=>e==='gameplayStart').length===1,'too-small to valid starts exactly once');
  const firstAt=h.c.LittleLeafPlatform.firstGameplayAt;h.c.LittleLeafPlatform.update(false);check(!h.c.LittleLeafPlatform.playing&&h.control.events.filter(e=>e==='gameplayStop').length===1,'valid to too-small stops gameplay');
  h.c.LittleLeafPlatform.update(false);check(h.control.events.filter(e=>e==='gameplayStop').length===1,'menu/loading blocked state has no repeated stop');
  h.c.LittleLeafPlatform.update(true);check(h.control.events.filter(e=>e==='gameplayStart').length===2&&h.c.LittleLeafPlatform.firstGameplayAt===firstAt,'resize/menu resume preserves first real playable timestamp');
  h.control.auth();h.c.LittleLeafPlatform.update(true);check(!h.c.LittleLeafPlatform.playing&&h.control.events.filter(e=>e==='gameplayStart').length===2,'auth invalidation cannot fake resume');
  check(!JSON.stringify(h.c.LittleLeafSaveLog.snapshot()).includes('syntheticPadding'),'no payload logging');
  const shell=fs.readFileSync('web/little_leaf_crazygames_shell.html','utf8');check(shell.includes(source('little_leaf_crazygames').trim()),'platform shell exact adapter');
  check(!shell.includes('async function readLegacy(factory){')&&!shell.includes('const KEY=\'little-leaf.preferences.v1\''),'legacy preferences probe absent');
  console.log(JSON.stringify({passed:true,total_checks:checks,synthetic_sdk:true,real_account:false,remote_cloud_ack:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
