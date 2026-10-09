// Deterministic actual-SDK ordering: owner renewal commits after requester's read,
// before its request commit. No application writes use disabled security rules.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import * as sdk from 'firebase/firestore';
import {observeTransactions,summary,boundedFailure} from './transaction_observer.mjs';
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
vm.runInThisContext(fs.readFileSync('../web/little_leaf_firebase_session.js','utf8'));
const env=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync('firestore.rules','utf8')}});
const events=[],sessions=[],checks=[];let release,timer;
const report={synthetic_only:true,diagnostic_only:true,release_qualification:false,source_sha256:Object.fromEntries(['request_renew_race.test.mjs','transaction_observer.mjs','firestore.rules','../web/little_leaf_firebase_session.js'].map(n=>[n,crypto.createHash('sha256').update(fs.readFileSync(n)).digest('hex')])),checks,events};
try{
 const uid='race-request-renew',db=env.authenticatedContext(uid,{firebase:{sign_in_provider:'google.com'}}).firestore();
 let armed=false,readReached;const reached=new Promise(r=>readReached=r),gate=new Promise(r=>release=r);
 const real=sdk.runTransaction,observed=observeTransactions(real,events,{afterCallback:async observation=>{
  if(armed&&observation.writes.some(w=>w.value?.request)) {armed=false;readReached();await gate;}
 }});
 const a=LittleLeafFirebaseSession.createSession({uid,currentUid:()=>uid,deviceLabel:'Mac',remote:LittleLeafFirebaseSession.createRemote(db,sdk,uid)});
 const b=LittleLeafFirebaseSession.createSession({uid,currentUid:()=>uid,deviceLabel:'iPhone',remote:LittleLeafFirebaseSession.createRemote(db,{...sdk,runTransaction:observed},uid)});sessions.push(a,b);
 await a.start();await b.start();const before=await sdk.getDocFromServer(a.sessionRef);armed=true;
 const attempt=b.requestTakeover().then(value=>({ok:true,value}),error=>({ok:false,code:boundedFailure(error).code}));
 await Promise.race([reached,new Promise((_,reject)=>timer=setTimeout(()=>reject(Error('Request callback was not reached')),10000))]);
 clearTimeout(timer);await a.renew();const renewed=await sdk.getDocFromServer(a.sessionRef);assert(renewed.data().updatedAt.toMillis()>before.data().updatedAt.toMillis());release();
 report.first=await attempt;const requested=events.find(e=>e.event==='callback'&&e.writes.some(w=>w.value?.request));report.request_callback_attempts=requested?events.filter(e=>e.transaction===requested.transaction&&e.event==='callback').length:0;const after=(await sdk.getDocFromServer(a.sessionRef)).data();report.after=summary(after);assert.equal(after.updatedAt.toMillis(),renewed.data().updatedAt.toMillis(),'request preserves renewed owner timestamp');
 assert.equal(after.owner,before.data().owner);assert.equal(after.epoch,before.data().epoch);checks.push('racing request cannot transfer or regress owner epoch');
 if(!report.first.ok){assert.equal(report.first.code,'permission-denied');assert.equal(after.request,null);checks.push('denied stale request leaves no invented acknowledgement or request');
  // Represents a second explicit player action, not automatic production retry.
  await b.requestTakeover();const retried=(await sdk.getDocFromServer(a.sessionRef)).data();assert(retried.request);assert.equal(retried.owner,after.owner);assert.equal(retried.updatedAt.toMillis(),renewed.data().updatedAt.toMillis(),'explicit retry preserves renewed owner timestamp');report.explicit_retry=summary(retried);checks.push('fresh explicit retry can ask without weakening server rules');
 }else{assert(after.request);checks.push('request committed a valid request after prescribed owner renewal');}
 report.passed=true;
}catch(e){report.passed=false;report.failure='Synthetic race assertion failed';report.failureMetadata=boundedFailure(e);throw Error('Synthetic request-renew race failed; see bounded diagnostic receipt.');}
finally{clearTimeout(timer);release?.();for(const s of sessions)s.close();await env.cleanup();if(process.env.REQUEST_RENEW_REPORT)fs.writeFileSync(process.env.REQUEST_RENEW_REPORT,JSON.stringify(report,null,2));console.log(JSON.stringify(report));}
