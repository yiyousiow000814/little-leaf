'use strict';
// Synthetic SDK contract fixtures; no real account/cloud persistence claim.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const {webcrypto} = require('node:crypto');
const {sourcePath} = require('./source_paths.js');
let webDir = path.dirname(sourcePath(path.resolve(__dirname, '..'), 'web/little_leaf_crazygames_shell.html')), preview = false, embedded = false;
for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  if (arg === '--developer-preview') preview = true;
  else if (arg === '--embedded') embedded = true;
  else if (arg === '--web-dir' && process.argv[i + 1]) webDir = process.argv[++i];
  else throw Error('Unknown or incomplete SDK test argument: ' + arg);
}
const source = name => fs.readFileSync(path.join(webDir,name+'.js'),'utf8');
const shell = fs.readFileSync(path.join(webDir,'little_leaf_crazygames_shell.html'),'utf8');
const adapter = source('little_leaf_crazygames');
const scripts = [...shell.matchAll(/<script>\s*([\s\S]*?)<\/script>/g)].map(match=>match[1]);
const embeddedAdapters = scripts.filter(text=>text.includes('/* CrazyGames-only variant.'));
const embeddedStorage = scripts.filter(text=>text.includes('/* Little Leaf authoritative Web storage.'));
assert.equal(embeddedAdapters.length,1,'one embedded SDK adapter');
assert.equal(embeddedStorage.length,1,'one embedded codec/Inbox/diagnostic block');
assert.equal(embeddedAdapters[0].trim(),adapter.trim(),'embedded SDK adapter exactly matches standalone');
const payload = fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');
const productionKeys=['little-leaf.cg.profile.v1','little-leaf.cg.preferences.v1'];
const previewKeys=['little-leaf.cg.developer-preview.profile.v1','little-leaf.cg.developer-preview.preferences.v1'];
const [KEY,PREFS]=preview?previewKeys:productionKeys, protectedKeys=preview?productionKeys:previewKeys;
const protectedValues=['protected profile bytes: never parse or reset','protected preference bytes: never parse or reset'];
const sessions=[];
let checks=0;const check=(condition,label)=>{assert(condition,label);checks++;};
function harness(map=new Map()) {
  for(let i=0;i<protectedKeys.length;i++)map.set(protectedKeys[i],protectedValues[i]);
  const control={user:null,writes:0,operations:[],events:[],getError:false,setError:false,initError:false,scopeHook:null,accountCalls:0,listenerCalls:0};
  const access=(method,key)=>{control.operations.push({method,key});assert([KEY,PREFS].includes(key),'SDK must never access another save namespace');};
  const sdk={environment:'local',init:async()=>{if(control.initError)throw Error('Synthetic init failure');},
    user:{isUserAccountAvailable:true,getUser:async()=>{control.accountCalls++;if(!sdk.user.isUserAccountAvailable)throw Error("Account API unavailable");control.scopeHook?.();return control.user;},addAuthListener:f=>{control.listenerCalls++;if(!sdk.user.isUserAccountAvailable)throw Error("Auth listener unavailable");control.auth=f;}},
    game:{settings:{muteAudio:false},loadingStart:()=>control.events.push('loadingStart'),loadingStop:()=>control.events.push('loadingStop'),gameplayStart:()=>control.events.push('gameplayStart'),gameplayStop:()=>control.events.push('gameplayStop')},
    data:{getItem:key=>{access('get',key);if(control.getError)throw Error('Synthetic read failure');return map.get(key)??null;},setItem:(key,value)=>{access('set',key);if(control.setError)throw Error('Synthetic set failure');map.set(key,value);control.writes++;},
      removeItem:key=>{access('remove',key);throw Error('Save reset is forbidden');},clear:()=>{access('clear','*');throw Error('Shared SDK store reset is forbidden');}}
  };
  // Opposite-mode URL hints/globals cannot switch an export's fixed SDK keys.
  const c=vm.createContext({CrazyGames:{SDK:sdk},crypto:webcrypto,Date,TextEncoder,TextDecoder,Uint8Array,Int8Array,URL,TypeError,DOMException,setTimeout,clearTimeout,
    LittleLeafDeveloperPreview:!preview,LittleLeafSaveNamespace:preview?'production':'developer-preview',
    location:{search:preview?'?developer-preview=false&save_namespace=production':'?developer-preview=true&save_namespace=developer-preview',reload(){control.events.push('reload');}}});
  for(const key of ['indexedDB','localStorage','sessionStorage'])Object.defineProperty(c,key,{get(){throw Error('Application must not access a local fallback');}});
  if(embedded)vm.runInContext(embeddedStorage[0],c);
  else for(const name of ['little_leaf_save_log','little_leaf_vault'])vm.runInContext(source(name),c);
  vm.runInContext(embedded?embeddedAdapters[0]:adapter,c);
  const session={c,control,map,client:c.__littleLeafVault,prefs:c.__littleLeafPreferences};sessions.push(session);return session;
}
(async()=>{
  let h=harness(),b=await h.client.boot();check(b.ok&&b.source==='fresh'&&b.revision===0,'fresh means SDK key truly absent');
  check(b.inbox?.ok&&b.inbox.profileId===b.profileId&&b.inbox.revision===0&&b.inbox.paid.length===0&&b.inbox.deferred.length===0,'fresh verified platform save projects a true empty Inbox');
  check((await h.prefs.boot()).ok,'preferences boot exclusively through SDK');
  const result=await h.client.commit(payload,0,b.profileId);
  check(result.ok&&result.platformAccepted&&result.durable===false&&result.cloudConfirmed===false,'SDK acceptance never claims cloud or durability');
  check(result.revision===1,'submission advances guarded revision');
  check(result.inbox?.ok&&result.inbox.profileId===b.profileId&&result.inbox.revision===1&&result.inbox.paid.length===0,'platform save acknowledgement retains empty Inbox at accepted revision');
  check(JSON.parse(h.client.bootJson).inbox.revision===1,'serialized platform boot includes matching Inbox after save');
  check(!h.c.LittleLeafSaveLog.snapshot().some(e=>e.event==='save_confirmed'),'no false IndexedDB transaction confirmation');
  const original=h.map.get(KEY),restored=harness(h.map),r=await restored.client.boot();
  check(r.ok&&r.profileId===b.profileId&&r.revision===1&&r.payload===payload,'new fixture session restores exact SDK identity/revision/payload');
  check(r.inbox?.ok&&r.inbox.revision===1&&r.inbox.paid.length===0,'reloaded empty platform Inbox remains available');
  const receiptRecord=JSON.parse(original);
  receiptRecord.campaigns={older:{coins:200,grantedAt:100,revision:1,status:'granted'},newer:{coins:300,grantedAt:200,revision:1,status:'granted'}};
  receiptRecord.digest=await h.c.LittleLeafAuthorityCodec.hash(h.c.LittleLeafAuthorityCodec.fingerprint(receiptRecord));
  const receiptMap=new Map([[KEY,JSON.stringify(receiptRecord)]]),letters=harness(receiptMap),letterBoot=await letters.client.boot();
  check(letterBoot.ok&&letterBoot.inbox?.paid.map(x=>x.id).join(',')==='newer,older','only verified stored receipts become sorted platform letters');
  check(letters.control.writes===0&&letterBoot.payload===payload,'reading platform letters never saves or credits money');
  letterBoot.inbox.paid[0].coins=999;
  const letterSave=await letters.client.commit(payload,1,letterBoot.profileId);
  check(letterSave.inbox.paid[0].coins===300&&letterSave.creditedCoins===0&&letterSave.inbox.deferred.length===0,'display snapshot is detached and never grants compensation');
  check(h.prefs.writeText('[audio]\nvolume=42'),'preferences written through SDK');
  check(JSON.parse(h.map.get(PREFS)).text.includes('42'),'preferences in platform key');
  const preferenceReload=harness(h.map);await preferenceReload.client.boot();
  check((await preferenceReload.prefs.boot()).text==='[audio]\nvolume=42','reload restores preferences from the same selected namespace');
  check((await h.client.commit(payload,0,b.profileId)).code==='REVISION_CONFLICT','stale revision cannot write');
  for(const mode of ['init','read','corrupt','nonstring']){
    const x=harness();if(mode==='init')x.control.initError=true;if(mode==='read')x.control.getError=true;if(mode==='corrupt')x.map.set(KEY,'{broken');if(mode==='nonstring')x.map.set(KEY,{});
    const boot=await x.client.boot();check(!boot.ok&&!x.c.LittleLeafPlatform.ready,'load failure blocks fresh gameplay: '+mode);check(!boot.inbox,'failed platform read cannot pretend Inbox is empty: '+mode);check(x.control.writes===0,'load failure never writes empty replacement: '+mode);
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
  h=harness();h.c.CrazyGames.SDK.user.isUserAccountAvailable=false;b=await h.client.boot();
  check(b.ok&&h.control.accountCalls===0&&h.control.listenerCalls===0,'unavailable account system uses Data without unsupported user APIs');
  check((await h.prefs.boot()).ok&&(await h.client.commit(payload,0,b.profileId)).ok,'guest Data progress/preferences remain usable without account APIs');
  h.c.CrazyGames.SDK.user.isUserAccountAvailable=true;
  check((await h.client.commit(payload,1,b.profileId)).code==='PLATFORM_ACCOUNT_CHANGED','unavailable to available blocks stale profile until reload');
  h=harness();b=await h.client.boot();h.c.CrazyGames.SDK.user.isUserAccountAvailable=false;
  check(!h.prefs.writeText('stale'),'availability transition blocks synchronous preference writes');
  h=harness();b=await h.client.boot();before=h.control.operations.length;
  check(Object.keys(h.c.LittleLeafVault).join(',')==='retry','ordinary Web createClient/import APIs are not exposed by platform singleton');
  h.c.LittleLeafVault.retry();await Promise.resolve();
  check(h.control.events.includes('reload')&&h.control.operations.length===before,'recovery reloads without invoking ordinary Web fallback');
  const productionPendingProfile='99999999-9999-4999-8999-999999999999';
  check((await h.client.commit(payload,0,productionPendingProfile)).code==='REVISION_CONFLICT'&&h.control.writes===1,'old-profile pending submission is rejected without replay or reset');
  h=harness();b=await h.client.boot();const interrupted=h.client.commit(payload,0,b.profileId);h.control.auth();
  check(!(await interrupted).ok&&h.control.writes===1,'account invalidation during an in-flight save blocks its eventual write');
  if(embedded){
    const unrelated=new Map([['little-leaf.preferences.v1','protected preferences'],['production-pending-write','protected pending payload'],['little-leaf.inbox.display.v1/clock/'+productionPendingProfile,'123']]);
    const original=new Map(unrelated),metadataAccess=[];
    const store={get length(){return unrelated.size;},key:i=>[...unrelated.keys()][i],
      getItem:key=>{metadataAccess.push(key);return unrelated.get(key)??null;},setItem:(key,value)=>{metadataAccess.push(key);unrelated.set(key,value);},removeItem:key=>{metadataAccess.push(key);unrelated.delete(key);}};
    const inbox=h.c.LittleLeafInbox.createClient({storage:store,now:()=>1000});
    const projected=JSON.parse(inbox.visibleSnapshotJson(JSON.stringify(b.inbox),true));
    check(projected.ok&&projected.paid.length===0,'Inbox projection cannot infer player progress from local metadata');
    check(metadataAccess.every(key=>key==='little-leaf.inbox.display.v1/clock/'+b.profileId),'empty test Inbox reads/writes only its own profile-scoped display clock');
    check([...original].every(([key,value])=>unrelated.get(key)===value),'Inbox leaves unrelated progress, preferences, pending data and other-profile metadata unchanged');
  }
  check(!JSON.stringify(h.c.LittleLeafSaveLog.snapshot()).includes('syntheticPadding'),'no payload logging');
  check(shell.includes(adapter.trim()),'platform shell exact adapter');
  check(!shell.includes('async function readLegacy(factory){')&&!shell.includes('const KEY=\'little-leaf.preferences.v1\''),'legacy preferences probe absent');
  for(const session of sessions){
    check(session.control.operations.every(op=>['get','set'].includes(op.method)&&[KEY,PREFS].includes(op.key)),'all successful and failed operations use only the selected SDK keys; no resets');
    check(protectedKeys.every((key,i)=>session.map.get(key)===protectedValues[i]),'other namespace retains exact profile and preference bytes');
  }
  check(protectedKeys.every(key=>!adapter.includes(key)),'adapter contains no opposite-namespace fallback');
  check(shell.includes('id="developer-preview-notice"')===preview,'developer loading notice appears only in preview');
  if(preview)check(shell.includes('Separate test progress')&&shell.includes('pointer-events:none')&&shell.includes(' · Developer preview</title>'),'preview notice and page title identify separate test progress');
  console.log(JSON.stringify({passed:true,total_checks:checks,save_variant:preview?'developer-preview':'production',adapter:embedded?'embedded':'standalone',synthetic_sdk:true,real_account:false,remote_cloud_ack:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
