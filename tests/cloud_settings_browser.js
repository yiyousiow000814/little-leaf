'use strict';
// Diagnostic only: unchanged exported Godot + real adapter/boot module, mocked SDK transport.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto'),cp=require('node:child_process'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const {phraseBox,allowedRequest,bind,panelClip}=require('./cloud_settings_browser_helpers');
const arg=n=>{const i=process.argv.indexOf(n);return i<0?null:path.resolve(process.argv[i+1]);};
const web=arg('--web-build'),out=arg('--output'),layoutPath=arg('--layout-report'),provenancePath=arg('--diagnostic-provenance');
for(const p of [web,out,layoutPath,provenancePath])assert(p,'required diagnostic paths');fs.mkdirSync(out,{recursive:true});
const raw=fs.readFileSync(path.join(web,'release-manifest.json')),manifest=JSON.parse(raw),provenance=JSON.parse(fs.readFileSync(provenancePath));bind(provenance,manifest,crypto.createHash('sha256').update(raw).digest('hex'));
const layout=JSON.parse(fs.readFileSync(layoutPath));assert(!layout.failures.length);const settingsPoint=layout.web_input_points.settings;assert(settingsPoint?.length===2);
const report={purpose:'synthetic-cloud-settings-diagnostic-only',release_qualified:false,hosted_account_acceptance:false,player_data_used:false,export_source_commit:manifest.source_commit,export_source_tree:manifest.source_tree,export_manifest_sha256:provenance.export_manifest_sha256,clock_scope:'Official engine --time-scale 0.1 only for this bounded UI diagnostic; no natural-service qualification',checks:[],errors:[],external_requests:[]};
const check=(ok,message)=>{assert(ok,message);report.checks.push(message);};
function installSynthetic({adapter,boot,payload}){
  Object.defineProperty(window,'Engine',{configurable:true,set(Engine){
    const features=Engine.getMissingFeatures;
    Engine.getMissingFeatures=function(...args){
      const missing=features.apply(this,args);Engine.getMissingFeatures=features;
      const instance=engine,original=instance.startGame;
      instance.startGame=async function(options){
        const f=window.__cloudFixture={mode:'hold',writes:0,signOutCalls:0,pending:null,cloud:null};
        const auth={currentUser:{uid:'synthetic-cloud-settings',isAnonymous:false},authStateReady:async()=>{}};
        const snapshot=()=>({exists:()=>!!f.cloud,data:()=>structuredClone(f.cloud)});
        const sdk={initializeApp:()=>({}),getAuth:()=>auth,getFirestore:()=>({}),GoogleAuthProvider:class{},setPersistence:async()=>{},browserLocalPersistence:{},getRedirectResult:async()=>null,signInWithRedirect:async()=>{throw Error('Synthetic test never signs in');},signOut:async()=>{f.signOutCalls++;throw Error('Synthetic sign-out failure');},onAuthStateChanged:()=>()=>{},doc:()=>({}),getDocFromServer:async()=>{if(f.mode==='offline')throw Object.assign(Error('Synthetic offline'),{code:'unavailable'});return snapshot();},runTransaction:async(_db,fn)=>{if(f.mode==='offline')throw Object.assign(Error('Synthetic offline'),{code:'unavailable'});let next;await fn({get:async()=>snapshot(),set:(_,value)=>{next=structuredClone(value);}});if(f.mode==='hold')await new Promise(resolve=>{f.pending=resolve;});f.cloud=next;f.writes++;}};
        new Function(adapter)();
        const codec=window.LittleLeafAuthorityCodec,now=Date.now();
        const record={format:2,profileId:crypto.randomUUID(),revision:1,createdAt:now,updatedAt:now,payload,digest:null,origin:{source:'fresh',legacyDigest:null,importedAt:now},previous:null,campaigns:{}};record.digest=await codec.hash(codec.fingerprint(record));
        f.cloud={schema:1,profileId:record.profileId,revision:1,digest:record.digest,record:JSON.stringify(record)};
        const start=new Function(...Object.keys(sdk),boot.replace(/^import .*;\n/gm,'').replace('export async function start','async function start')+';return start;')(...Object.values(sdk));
        await start({authDomain:location.hostname});await window.__littleLeafVault.boot();
        const save=window.__littleLeafVault.save;f.localAcks=0;
        window.__littleLeafVault.save=function(p,r,id,callback){return save.call(this,p,r,id,result=>{if(JSON.parse(result).ok)f.localAcks++;return callback(result);});};
        f.sync=()=>window.__littleLeafVault.sync();f.ack=()=>{assertPending();const resolve=f.pending;f.pending=null;resolve();};function assertPending(){if(!f.pending)throw Error('No pending synthetic transport');}
        return original.call(this,{...options,args:[...(options?.args||[]),'--time-scale','0.1','--','--skip-intro']});
      };return missing;
    };Object.defineProperty(window,'Engine',{configurable:true,writable:true,value:Engine});
  }});
}
(async()=>{let browser,server,context,page;try{
  server=http.createServer((req,res)=>{const pathname=new URL(req.url,'http://localhost').pathname;const file=path.resolve(web,'.'+pathname);if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.png':'image/png'})[path.extname(file)]||'application/octet-stream');res.end(fs.readFileSync(file));});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const origin='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({headless:false,chromiumSandbox:true,channel:process.env.PLAYWRIGHT_CHROMIUM_CHANNEL||undefined});context=await browser.newContext({viewport:{width:1360,height:880},serviceWorkers:'block'});
  await context.route('**/*',route=>{if(!allowedRequest(route.request().url(),origin)){report.external_requests.push(route.request().url());return route.abort('blockedbyclient');}return route.continue();});
  page=await context.newPage();page.on('pageerror',e=>report.errors.push(String(e)));page.on('console',m=>{if(/SCRIPT ERROR|ERROR:/.test(m.text()))report.errors.push(m.text());});let acceptSignout=false;page.on('dialog',dialog=>acceptSignout?dialog.accept():dialog.dismiss());
  await page.addInitScript(installSynthetic,{adapter:fs.readFileSync('web/little_leaf_firebase.js','utf8'),boot:fs.readFileSync('web/little_leaf_firebase_boot.mjs','utf8'),payload:fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8')});
  await page.goto(origin+'/index.html');await page.waitForFunction(()=>!document.getElementById('status'),null,{timeout:60000});check(await page.evaluate(()=>document.getElementById('cloud-account').hidden),'No signed-in account strip covers actual gameplay');
  const clip=panelClip(settingsPoint);report.ocr={clip,pixel_scale:2,method:'nearest-neighbor detached canvas',full_originals_retained:true};
  async function visible(name,phrase){const deadline=Date.now()+15000;let text='';do{
    assert(!report.errors.length,report.errors.join('\n'));const file=path.join(out,name+'.png');await page.screenshot({path:file});
    const png=await page.screenshot({clip});const scaled=await page.evaluate(async base64=>{const raw=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));const bitmap=await createImageBitmap(new Blob([raw],{type:'image/png'}));const canvas=new OffscreenCanvas(bitmap.width*2,bitmap.height*2),ctx=canvas.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);return Array.from(new Uint8Array(await(await canvas.convertToBlob({type:'image/png'})).arrayBuffer()));},png.toString('base64'));
    const input=path.join(out,name+'-ocr.png');fs.writeFileSync(input,Buffer.from(scaled));text=cp.execFileSync('tesseract',[input,'stdout','--psm','6','tsv'],{encoding:'utf8',timeout:10000,env:{...process.env,OMP_THREAD_LIMIT:'1'}});fs.writeFileSync(path.join(out,name+'.tsv'),text);const box=phraseBox(text,phrase);
    if(box){check(true,'Actual rendered '+name+' contains '+phrase);return{x:clip.x+box.x/2,y:clip.y+box.y/2,width:box.width/2,height:box.height/2};}await page.waitForTimeout(150);
  }while(Date.now()<deadline);throw Error('Rendered '+phrase+' not found: '+name);}
  const clickLabel=async(name,phrase)=>{const b=await visible(name,phrase);await page.mouse.click(b.x+b.width/2,b.y+b.height/2);};
  await page.mouse.click(...settingsPoint);await visible('settings-saved','Saved');
  await page.keyboard.press('Escape');await page.mouse.click(...settingsPoint);await visible('settings-reopened','Saved');
  const prior=await page.evaluate(()=>__cloudFixture.localAcks);await clickLabel('save-button','Save');await page.waitForFunction(n=>__cloudFixture.localAcks>n,prior);await visible('settings-saving','Saving');
  await page.evaluate(()=>{__cloudFixture.sync();});await page.waitForFunction(()=>!!__cloudFixture.pending);await visible('settings-awaiting-ack','Saving');
  await page.evaluate(()=>__cloudFixture.ack());await visible('settings-cloud-acknowledged','Saved');check(await page.evaluate(()=>__cloudFixture.writes===1),'Saved follows a genuine adapter acknowledgment, not the local commit');
  await clickLabel('cancel-signout-button','Sign out');check(await page.evaluate(()=>__cloudFixture.signOutCalls===0),'Canceled native Sign out leaves SDK/client untouched');
  acceptSignout=true;await clickLabel('failed-signout-button','Sign out');await visible('settings-signout-failed','still signed in');check(await page.evaluate(()=>__cloudFixture.signOutCalls===1),'Native Sign out reaches real module failure handling once');
  await page.evaluate(()=>{__cloudFixture.mode='offline';});await clickLabel('save-after-signout-failure','Save');await visible('settings-pending-again','Saving');await page.waitForTimeout(31000);await page.evaluate(()=>__cloudFixture.sync());await visible('settings-offline','Not saved');
  check(await page.evaluate(()=>JSON.parse(__littleLeafVault.bootJson).ok),'Failed sign-out does not stop the account save client');
  await page.keyboard.press('Escape');await page.mouse.click(...settingsPoint);await visible('settings-offline-reopened','Not saved');
  check(report.errors.length===0,'No script or engine error');check(report.external_requests.length===0,'Synthetic run attempted no external network request');const probe=await page.evaluate(()=>fetch('https://synthetic-network-probe.invalid/').then(()=>false,()=>true));check(probe&&report.external_requests.length===1&&report.external_requests[0]==='https://synthetic-network-probe.invalid/','Deliberate negative external request was blocked before transport');report.status='passed';
}catch(error){report.status='failed';report.error=String(error.stack||error);if(page)await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});process.exitCode=1;}finally{fs.writeFileSync(path.join(out,'cloud-settings-browser.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));if(context)await context.close();if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));}})();
