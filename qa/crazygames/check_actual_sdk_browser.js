'use strict';
const fs=require('node:fs');
(async()=>{
 const m=await(await fetch('http://127.0.0.1:'+process.argv[2]+'/json/version')).json(),ws=new WebSocket(m.webSocketDebuggerUrl);
 await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let serial=0,lastAccepted=null;const pending=new Map(),requests=new Map(),errors=[],consoleProblems=[];
 ws.addEventListener('message',e=>{const d=JSON.parse(e.data),p=pending.get(d.id);if(p){pending.delete(d.id);d.error?p.reject(Error(d.error.message)):p.resolve(d.result)}
 if(d.method==='Network.requestWillBeSent'){let u;try{u=new URL(d.params.request.url)}catch{return}requests.set(d.params.requestId,{url:u.origin+u.pathname,startWall:d.params.wallTime*1000,offset:d.params.wallTime*1000-d.params.timestamp*1000})}
 if(d.method==='Network.responseReceived'){const r=requests.get(d.params.requestId);if(r){r.status=d.params.response.status;r.contentEncoding=d.params.response.headers['Content-Encoding']||d.params.response.headers['content-encoding']||null}}
 if(d.method==='Network.loadingFinished'){const r=requests.get(d.params.requestId);if(r){r.bytes=d.params.encodedDataLength;r.endWall=d.params.timestamp*1000+r.offset}}
 if(d.method==='Runtime.bindingCalled'&&d.params.name==='__cgAccepted')lastAccepted=JSON.parse(d.params.payload);
 if(d.method==='Runtime.exceptionThrown')errors.push({type:d.params.exceptionDetails.text});
 if(d.method==='Runtime.consoleAPICalled'&&['error','warning'].includes(d.params.type))consoleProblems.push({type:d.params.type,text:d.params.args.filter(a=>a.type==='string').map(a=>a.value).join(' ').slice(0,400)});
 });
 const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
 const tab=(await send('Target.getTargets')).targetInfos.find(t=>t.type==='page'),sid=(await send('Target.attachToTarget',{targetId:tab.targetId,flatten:true})).sessionId;
 for(const method of ['Network.enable','Runtime.enable','Page.enable'])await send(method,{},sid);
 const inspect=async()=>{const v=await send('Runtime.evaluate',{expression:`(async()=>{const b=JSON.parse(globalThis.__littleLeafVault?.bootJson||'{}');const raw=globalThis.CrazyGames?.SDK?.data.getItem('little-leaf.cg.profile.v1');const r=raw?JSON.parse(raw):null;const hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(v=>v.toString(16).padStart(2,'0')).join('');return JSON.stringify({sdkPresent:!!globalThis.CrazyGames?.SDK,environment:globalThis.CrazyGames?.SDK?.environment,platform:{ready:globalThis.LittleLeafPlatform?.ready,firstGameplayAt:globalThis.LittleLeafPlatform?.firstGameplayAt,musicReady:globalThis.LittleLeafPlatform?.musicReady},boot:{ok:b.ok,code:b.code,revision:b.revision,source:b.source},record:r?{revision:r.revision,identityHash:await hash(r.profileId),payloadHash:r.payload?await hash(r.payload):null,bytes:new TextEncoder().encode(raw).length}:null,log:globalThis.LittleLeafSaveLog?.text()})})()`,awaitPromise:true,returnByValue:true},sid);return JSON.parse(v.result.value)};
 await send('Runtime.addBinding',{name:'__cgAccepted'},sid);
 await send('Page.navigate',{url:process.argv[3]},sid);await new Promise(r=>setTimeout(r,28000));

 const image=await send('Page.captureScreenshot',{format:'png'},sid);
 // Quiesce the disposable adapter after genuine autosave, so refresh comparison excludes racing autosaves.
 await send('Runtime.evaluate',{expression:'globalThis.__littleLeafVault.close()'},sid);const before=await inspect();
 fs.writeFileSync('crazygames-variant/qa/crazygames/actual-sdk-browser.png',Buffer.from(image.data,'base64'));
 const networkBefore=[...requests.values()],first=before.platform.firstGameplayAt,initial=networkBefore.filter(r=>r.startWall<=first&&r.bytes&&/^https?:/.test(r.url));
 await send('Page.reload',{ignoreCache:false},sid);await new Promise(r=>setTimeout(r,7000));const after=await inspect();
 const expected=lastAccepted||before.record;const same=before.record&&after.record&&before.record.identityHash===after.record.identityHash&&expected.revision===after.record.revision&&expected.payloadHash===after.record.payloadHash&&expected.bytes===after.record.bytes,music=networkBefore.find(r=>r.url.endsWith('/music.pck'));
 const checks={officialSdkLoaded:networkBefore.some(r=>r.url==='https://sdk.crazygames.com/crazygames-sdk-v3.js'&&r.status===200),freshRuntimeSaved:before.boot.ok&&before.record.revision>0&&!!before.record.payloadHash,submittedWithoutCloudClaim:before.log.includes('platform_save_accepted')&&before.log.includes('platform_controller_accepted')&&!before.log.includes('save_confirmed'),refreshRestoredSameRecord:!!same,backgroundMusicLoaded:before.platform.musicReady===true,musicStartedAfterGameplay:music?.startWall>=first,initialCompressedBytesUnder20MB:initial.reduce((s,r)=>s+r.bytes,0)<20000000,noRuntimeExceptions:errors.length===0};
 const d={mode:'Real exported game, official CDN SDK, fresh synthetic Chrome profile; local SDK simulation only',synthetic_sdk:false,real_account:false,exact_refresh_fixture:'Adapter close quiesces new writes after real autosave; no stored data is changed. Separate NORMAL-REFRESH-OBSERVATION.json records ordinary refresh with continuing autosaves.',checks,passed:Object.values(checks).every(Boolean),initialTransfer:{bytes:initial.reduce((s,r)=>s+r.bytes,0),basis:'CDP Network.loadingFinished encodedDataLength including response headers; requests started before first real gameplayStart; loopback gzip hosting, not CrazyGames CDN proof'},before,after,lastAcceptedBeforeReload:lastAccepted,responses:networkBefore,errors,consoleProblems};
 fs.writeFileSync('crazygames-variant/qa/crazygames/actual-sdk-browser.json',JSON.stringify(d,null,2)+'\n');console.log(JSON.stringify({checks,passed:d.passed,initialTransfer:d.initialTransfer,before:before.record,after:after.record,consoleProblems}));
 await send('Browser.close');ws.close();if(!d.passed)process.exitCode=1;
})().catch(e=>{console.error('Actual SDK browser failed: '+e.name);process.exitCode=1});
