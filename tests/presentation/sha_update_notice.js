'use strict';
const assert=require('node:assert/strict');
const {create}=require('../../platform/web/little_leaf_update');
function marker(hash,sequence,version='0.1.11-pre.'+hash.slice(0,8)){
 return {schema_version:1,version,source_commit:hash,release_order:{target:'siowyiyou/little-leaf:html5',channel_version:sequence}};
}
async function check(current,target){
 let remote=target, reloads=0;
 const manager=create({currentRelease:current,fetch:async()=>({ok:true,json:async()=>remote}),storage:{getItem:()=>null},
 setInterval:()=>0,clearInterval(){},reload(){reloads++;},canReloadUpdate:()=>true,
 checkUpdateReady:async()=>({ok:true,cloudConfirmed:true,profileId:'p',revision:1,updateToken:'t'})});
 manager.start(current.version);await manager.poll();
 return {manager,state:()=>JSON.parse(manager.snapshot()),target(v){remote=v;},reloads:()=>reloads};
}
(async()=>{
 const old=marker('f'.repeat(40),10),fresh=marker('01234567'+'a'.repeat(32),11);
 let s=await check(old,fresh);assert(s.state().available,'descending SHA is newer by publication order');
 assert((await s.manager.reloadForUpdate(fresh.version,'p',1,'t')).ok);assert.equal(s.reloads(),1);
 s=await check(fresh,old);assert(!s.state().available,'ascending SHA with older receipt is not newer');
 for(const target of [marker(old.source_commit,20),{...fresh,release_order:undefined},marker(fresh.source_commit,10),
 {...fresh,source_commit:'b'.repeat(40)},{...fresh,release_order:{target:'wrong',channel_version:30}},
 marker(fresh.source_commit,Number.MAX_SAFE_INTEGER+1)]){
  s=await check(old,target);assert(!s.state().available,'missing, duplicate, foreign or unsafe chronology');
 }
 s=await check(old,marker('a'.repeat(40),null,'0.1.11'));assert(s.state().available,'final beats same-family prerelease');
 s=await check(marker('a'.repeat(40),null,'0.1.11'),fresh);assert(!s.state().available,'prerelease cannot replace final');
 s=await check(marker('a'.repeat(40),null,'0.1.10d'),fresh);assert(s.state().available,'newly loaded compatible adapter accepts legacy baseline');
 s=await check(old,fresh);s.target({...fresh,release_order:{...fresh.release_order,channel_version:12}});
 assert(!(await s.manager.reloadForUpdate(fresh.version,'p',1,'t')).ok);assert.equal(s.reloads(),0,'receipt changes invalidate reload ticket');
 s=await check(old,fresh);s.target(old);await s.manager.poll();assert(!s.state().available,'rollback clears notice');
 console.log('SHA updates: opaque decimal/leading-zero identity, receipt order independent of SHA, final precedence, duplicate/rollback/receipt fences passed.');
})().catch(e=>{console.error(e);process.exitCode=1;});
