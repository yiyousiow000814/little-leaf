'use strict';
// Execute only the wrapper controller with synthetic DOM boundaries: no SDK or storage.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(process.argv[2],'utf8');
const controller=html.match(/\/\* Little Leaf trusted-preview wrapper\.[\s\S]*?<\/script>/)[0].replace('</script>','');
function fixture(){
  const elements=new Map(),frames=[],controls=[];let reloads=0;
  const node=()=>({hidden:false,disabled:false,handlers:{},style:{},setAttribute(){},focus(){},addEventListener(type,fn){this.handlers[type]=fn;}});
  for(const name of ['itch-entry','itch-local','itch-account','canvas','status'])elements.set(name,node());
  const window={location:{reload(){reloads++;}}};
  const document={getElementById:id=>elements.get(id),createElement:tag=>{assert(['iframe','button'].includes(tag));return {...node(),tag};},body:{append(...items){for(const item of items)(item.tag==='iframe'?frames:controls).push(item);}}};
  vm.runInNewContext(controller,{window,document});
  return {window,elements,frames,controls,reloads:()=>reloads};
}
(async()=>{
  const local=fixture();let localStarted=false;local.window.LittleLeafItchEntryReady.then(()=>{localStarted=true;});
  assert.equal(local.frames.length,0);assert.equal(localStarted,false);
  local.elements.get('itch-local').handlers.click();await Promise.resolve();assert.equal(localStarted,true);
  local.elements.get('itch-account').handlers.click();assert.equal(local.frames.length,0);
  const account=fixture();let originalVaultMayBoot=false;account.window.LittleLeafItchEntryReady.then(()=>{originalVaultMayBoot=true;});
  account.elements.get('itch-account').handlers.click();account.elements.get('itch-account').handlers.click();
  account.elements.get('itch-local').handlers.click();await Promise.resolve();
  assert.equal(account.frames.length,1);assert.equal(originalVaultMayBoot,false);
  assert.match(account.frames[0].src,/^https:\/\/little-leaf-41e5d--itch-embed-test-[a-z0-9]+\.web\.app\/$/);
  assert.equal(account.controls.length,1);account.controls[0].handlers.click();assert.equal(account.reloads(),1);
  assert(!/postMessage|addEventListener\(['"]message|indexedDB|localStorage|firebase-auth/.test(controller));
  console.log('Trusted itch wrapper: explicit local/cloud choice and original-vault isolation passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
