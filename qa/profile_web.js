const fs=require('node:fs');
(async()=>{
 const info=await(await fetch('http://127.0.0.1:'+process.argv[2]+'/json/version')).json();
 const ws=new WebSocket(info.webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let serial=0,report=null;const pending=new Map(),errors=[];
 ws.addEventListener('message',e=>{const d=JSON.parse(e.data),p=pending.get(d.id);if(p){pending.delete(d.id);d.error?p.reject(Error(JSON.stringify(d.error))):p.resolve(d.result)}
  if(d.method==='Runtime.consoleAPICalled')for(const a of d.params.args){if(typeof a.value==='string'){fs.appendFileSync(process.argv[4]+'/console.log',a.value+'\n');if(a.value.startsWith('PERFORMANCE_RESULT '))report=JSON.parse(a.value.slice(19));if(/SCRIPT ERROR|Parse Error/.test(a.value))errors.push(a.value)}}
  if(d.method==='Runtime.exceptionThrown')errors.push(d.params.exceptionDetails.text);
 });
 const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}))});
 try{
  const tab=(await send('Target.getTargets')).targetInfos.find(t=>t.type==='page');const sid=(await send('Target.attachToTarget',{targetId:tab.targetId,flatten:true})).sessionId;
  await send('Runtime.enable',{},sid);await send('Page.enable',{},sid);
  await send('Emulation.setDeviceMetricsOverride',{width:1360,height:880,deviceScaleFactor:1,mobile:false},sid);
  await send('Page.navigate',{url:process.argv[3]},sid);
  const deadline=Date.now()+150000;
  while(!report&&Date.now()<deadline&&!errors.length)await new Promise(r=>setTimeout(r,500));
  if(!report)throw Error('Missing profile: '+JSON.stringify(errors));
  report.browser=info.Browser;
  const gpu=await send('SystemInfo.getInfo');report.gpu=gpu.gpu;
  const shot=await send('Page.captureScreenshot',{format:'png'},sid);fs.writeFileSync(process.argv[4]+'/frame.png',Buffer.from(shot.data,'base64'));
  fs.writeFileSync(process.argv[4]+'/profile.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify({platform:report.platform,tick:report.tick_us,edge_batch_us:report.edge_batch_us,browser:report.browser,errors}));
 }finally{await send('Browser.close').catch(()=>{});ws.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
