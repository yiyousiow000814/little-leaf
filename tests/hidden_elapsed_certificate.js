'use strict';
// Synthetic transaction ordering and deferred acknowledgments. Security rules
// are exercised separately with the actual Firestore emulator and SDK.
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),{webcrypto}=require('crypto');
const clone=x=>x==null?null:structuredClone(x);
function environment(){
 let time=100000,uid='certificate-account',delay=null;const docs=new Map(),storage=new Map(),watchers=[],listeners=new Map();
 const root={navigator:{onLine:true},addEventListener:(type,fn)=>{assert(!listeners.has(type));listeners.set(type,fn);},removeEventListener:(type,fn)=>{assert.equal(listeners.get(type),fn);listeners.delete(type);},crypto:webcrypto,TextEncoder,setTimeout,clearTimeout,localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)}};root.globalThis=root;
 for(const name of ['little_leaf_vault','little_leaf_firebase','little_leaf_firebase_session'])vm.runInNewContext(fs.readFileSync(`platform/web/${name}.js`,'utf8'),root);
 const sdk={doc:(db,...parts)=>parts.join('/'),serverTimestamp:()=>time,getDocFromServer:async ref=>({exists:()=>docs.has(ref),data:()=>clone(docs.get(ref))}),onSnapshot:(ref,options,fn)=>{watchers.push({ref,fn});return()=>{};},async runTransaction(db,fn){
   const writes=[];const result=await fn({get:async ref=>({exists:()=>docs.has(ref),data:()=>clone(docs.get(ref))}),set:(ref,value)=>writes.push([ref,clone(value)])});
   for(const [ref,value] of writes)docs.set(ref,value);
   for(const w of watchers)if(writes.some(([ref])=>ref===w.ref))w.fn({exists:()=>docs.has(w.ref),data:()=>clone(docs.get(w.ref)),metadata:{fromCache:false,hasPendingWrites:false}});
   if(delay&&writes.some(([ref,value])=>delay.matches(ref,value))){const d=delay;delay=null;d.committed();await d.gate;}
   return result;
 }};
 function device(){
   const ownership=root.LittleLeafFirebaseSession.createSession({uid:'certificate-account',currentUid:()=>uid,now:()=>time,deviceLabel:'Mac',remote:root.LittleLeafFirebaseSession.createRemote({},sdk,'certificate-account')});
   let local=null;const journal={async read(){return clone(local);},async replace(id,expected,next){assert.equal(JSON.stringify(local),JSON.stringify(expected));local=clone(next);},async readRecoveryBackup(){return null;}};
   const client=root.LittleLeafFirebase.createClient({uid:'certificate-account',currentUid:()=>uid,now:()=>time,codec:root.LittleLeafAuthorityCodec,ownership,journal,status(){},remote:root.LittleLeafFirebase.createRemote({},sdk,ownership)});
   return {ownership,client,local:()=>clone(local)};
 }
 const certificate=()=>clone(docs.get('players/certificate-account/background/interval'));
 return {device,certificate,docs,listeners,offline(){root.navigator.onLine=false;listeners.get('offline')();},online(){root.navigator.onLine=true;},advance:n=>time+=n,setUid:v=>uid=v,async ready(){const a=device();await a.ownership.start();const b=await a.client.boot();const payload=fs.readFileSync('tests/fixtures/startup-retry-v15.json','utf8');assert((await a.client.commit(payload,0,b.profileId)).ok);await a.client.sync();return a;},hold(state){let release,committed;const gate=new Promise(r=>release=r),written=new Promise(r=>committed=r);delay={gate,committed,matches:(ref,v)=>ref.endsWith('/interval')&&v.state===state};return {release,written};}};
}
(async()=>{
 let e=environment(),a=await e.ready(),arm=await a.client.beginBackground(a.local().record.revision,a.local().record.profileId);assert(arm.ok,JSON.stringify(arm));
 assert.equal((await a.client.saveForUpdate(a.local().record.payload,1,a.local().record.profileId)).code,'ELAPSED_UNCERTAIN');
 e.advance(1200000);let proof=await a.client.finishBackground(arm.token);assert(proof.ok,JSON.stringify(proof));assert.equal(proof.seconds,1200);assert.equal(proof.discardedSeconds,0);
 const payload=JSON.stringify({...JSON.parse(a.local().record.payload),coins:7300});let result=await a.client.commitBackground(payload,arm.token);assert(result.ok,JSON.stringify(result));
 assert.equal(e.certificate().state,'consumed');assert.equal(a.local().record.payload,payload);assert.equal(a.local().elapsedPending,null);
 assert.equal((await a.client.commitBackground(payload,arm.token)).code,'ELAPSED_CONSUMED');
 // A start that was dispatched before cancellation cannot reopen after its
 // acknowledgment arrives. Its exact server slot is terminally cancelled.
 e=environment();a=await e.ready();let h=e.hold('open');let pending=a.client.beginBackground(1,a.local().record.profileId);await h.written;const terminal=a.client.cancelBackground();assert.equal((await terminal).backgroundCleared,true);await new Promise(r=>setTimeout(r,0));h.release();result=await pending;assert(!result.ok);assert.equal(e.certificate().state,'cancelled');assert.equal(a.ownership.hasElapsedIntent,false);
 e=environment();a=await e.ready();arm=await a.client.beginBackground(1,a.local().record.profileId);e.advance(120000);h=e.hold('sealed');pending=a.client.finishBackground(arm.token);await h.written;a.client.cancelBackground();await new Promise(r=>setTimeout(r,0));h.release();result=await pending;assert(!result.ok);assert.equal(e.certificate().state,'cancelled');assert.equal(a.local().record.revision,1);
 // Already-authoritative consume survives late cancel; its canonical record
 // is journaled once and the old model stays blocked until reload.
 e=environment();a=await e.ready();arm=await a.client.beginBackground(1,a.local().record.profileId);e.advance(120000);proof=await a.client.finishBackground(arm.token);assert.equal(proof.seconds,120);h=e.hold('consumed');pending=a.client.commitBackground(payload,arm.token);await h.written;assert.equal((await a.client.cancelBackground()).code,'ELAPSED_UNCERTAIN');h.release();result=await pending;assert(result.ok&&result.reloadRequired);assert.equal(a.local().record.payload,payload);assert.equal(e.certificate().resultDigest,a.local().record.digest);
 // An offline event invalidates this interval even after reconnection; close removes its listener.
 e=environment();a=await e.ready();arm=await a.client.beginBackground(1,a.local().record.profileId);e.offline();await a.client.cancelBackground();e.online();assert(!(await a.client.finishBackground(arm.token)).ok);assert.equal(e.certificate().state,'cancelled');a.ownership.close();assert.equal(e.listeners.size,0);
 // Observed unknown ownership and account change invalidate before sealing.
 e=environment();a=await e.ready();arm=await a.client.beginBackground(1,a.local().record.profileId);const ref='players/certificate-account/session/owner';e.docs.set(ref,{...e.docs.get(ref),owner:webcrypto.randomUUID(),epoch:2});e.advance(120000);assert(!(await a.client.finishBackground(arm.token)).ok);assert.equal(a.local().record.revision,1);
 e=environment();a=await e.ready();arm=await a.client.beginBackground(1,a.local().record.profileId);e.setUid('different-account');assert.equal((await a.client.finishBackground(arm.token)).code,'NOT_READY');assert.equal(a.local().record.revision,1);
 console.log('Passed: 20-minute full server-certificate duration, atomic once-only canonical save, updater exclusion, deferred start/seal cancellation, late consumed receipt, takeover and account-switch fences.');
})().catch(e=>{console.error(e);process.exitCode=1;});
