'use strict';
const assert=require('node:assert/strict');
const {create}=require('../web/little_leaf_update');
function setup(initial='0.1.10a'){
 let target={schema_version:1,version:initial,source_commit:'a'.repeat(40)},count=0,checks=0,reloads=0,offline=false,canReload=true,gate={ok:true,cloudConfirmed:true,profileId:'cafe',revision:2,updateToken:'token'};
 const seen=new Map();
 const manager=create({canReloadUpdate:()=>canReload,fetch:async(path,options)=>{assert.equal(path,'./hosting-release.json');assert.equal(options.cache,'no-store');count++;if(offline)throw Error('offline');return {ok:true,json:async()=>({...target})};},storage:{getItem:k=>seen.get(k),setItem:(k,v)=>seen.set(k,v)},setInterval:()=>1,clearInterval:()=>{},reload:()=>reloads++,checkUpdateReady:async()=>{checks++;return gate;}});
 return {manager,state:()=>JSON.parse(manager.snapshot()),target:x=>target={...target,...x},offline:x=>offline=x,gate:x=>gate=x,canReload:x=>canReload=x,counts:()=>({checks,reloads,count})};
}
(async()=>{
 let s=setup();s.manager.start('0.1.10');await s.manager.poll();assert(s.state().available);assert.equal(s.state().version,'0.1.10a');assert.equal(s.counts().reloads,0);
 s.manager.dismiss('0.1.10a');assert(!s.state().available);await s.manager.poll();assert(!s.state().available);s.target({version:'0.1.10b'});await s.manager.poll();assert(s.state().available);
 let callback;s.manager.dismiss('other');assert(s.state().available);
 let result=await s.manager.reloadForUpdate('0.1.10b','cafe',2,'token',raw=>callback=JSON.parse(raw));assert(result.ok&&callback.ok);assert.equal(s.counts().reloads,1);
 assert(!(await s.manager.reloadForUpdate('0.1.10b','cafe',2,'token')).ok);assert.equal(s.counts().reloads,1);
 for(const v of ['0.1.9','0.1.10','0.1.10aa','bogus']){s=setup(v);s.manager.start('0.1.10');await s.manager.poll();assert(!s.state().available,v);}
 s=setup('0.1.11');s.manager.start('0.1.10z');await s.manager.poll();assert(s.state().available);
 s=setup();s.manager.start('0.1.10');await s.manager.poll();s.offline(true);assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);assert.equal(s.counts().checks,0);assert.equal(s.counts().reloads,0);
 s.offline(false);s.target({source_commit:'b'.repeat(40)});assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);assert.equal(s.counts().checks,0);
 for(const gate of [{ok:false},{ok:true,cloudConfirmed:false},{ok:true,cloudConfirmed:true,profileId:'other',revision:2,updateToken:'token'},{ok:true,cloudConfirmed:true,profileId:'cafe',revision:3,updateToken:'token'},{ok:true,cloudConfirmed:true,profileId:'cafe',revision:2,updateToken:'other'}]){s=setup();s.manager.start('0.1.10');await s.manager.poll();s.gate(gate);assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);assert.equal(s.counts().reloads,0);}
 s=setup();s.manager.start('0.1.10');await s.manager.poll();s.target({version:'0.1.11'});assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);assert.equal(s.counts().checks,0);
 s=setup();s.manager.start('0.1.10');await s.manager.poll();const first=s.manager.reloadForUpdate('0.1.10a','cafe',2,'token');assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);await first;assert.equal(s.counts().reloads,1);
 s=setup();s.manager.start('0.1.10');await s.manager.poll();assert(s.state().available);s.target({version:'0.1.10'});await s.manager.poll();assert(!s.state().available,'rollback clears stale notice');

 s=setup();s.manager.start('0.1.10');await s.manager.poll();s.manager.close();assert(!s.state().available);assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);await s.manager.poll();assert.equal(s.counts().reloads,0);
 s=setup();s.manager.start('0.1.10');await s.manager.poll();s.canReload(false);assert(!(await s.manager.reloadForUpdate('0.1.10a','cafe',2,'token')).ok);assert.equal(s.counts().reloads,0,'final account/ownership predicate blocks reload');
 // A deployment rollback during the cloud check must fail before navigation.
 let releaseGate,enterGate;const gateEntered=new Promise(resolve=>enterGate=resolve);
 let deployment={schema_version:1,version:'0.1.10a',source_commit:'a'.repeat(40)},reloads=0;
 const manager=create({canReloadUpdate:()=>true,fetch:async()=>({ok:true,json:async()=>({...deployment})}),storage:{getItem:()=>null},setInterval:()=>0,clearInterval(){},reload(){reloads++;},checkUpdateReady:async()=>{enterGate();await new Promise(resolve=>releaseGate=resolve);return {ok:true,cloudConfirmed:true,profileId:'p',revision:2,updateToken:'t'};}});
 manager.start('0.1.10');await manager.poll();const pending=manager.reloadForUpdate('0.1.10a','p',2,'t');await gateEntered;
 deployment={...deployment,version:'0.1.10'};releaseGate();assert(!(await pending).ok);assert.equal(reloads,0);
 // A stalled readiness check times out without a late reload or lost UI callback.
 let expire,lateGate,timedEntered;const timedStart=new Promise(resolve=>timedEntered=resolve);
 const timed=create({canReloadUpdate:()=>true,fetch:async()=>({ok:true,json:async()=>({schema_version:1,version:'0.1.10a',source_commit:'a'.repeat(40)})}),storage:{getItem:()=>null},setInterval:()=>0,clearInterval(){},setTimeout(fn){expire=fn;return 1;},clearTimeout(){},reload(){reloads++;},checkUpdateReady:async()=>{timedEntered();return new Promise(resolve=>lateGate=resolve);}});
 timed.start('0.1.10');await timed.poll();const waiting=timed.reloadForUpdate('0.1.10a','p',2,'t');await timedStart;expire();assert(!(await waiting).ok);lateGate({ok:true,cloudConfirmed:true,profileId:'p',revision:2,updateToken:'t'});await Promise.resolve();assert.equal(reloads,0);assert(!JSON.parse(timed.snapshot()).busy);
 console.log('Update notice: version ordering, quiet polling, dismissals, manifest binding, confirmed save gate, offline and duplicate reload guards passed.');
})().catch(e=>{console.error(e);process.exit(1);});
