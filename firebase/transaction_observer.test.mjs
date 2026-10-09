import assert from 'node:assert/strict';
import {observeTransactions,summary,boundedFailure} from './transaction_observer.mjs';
const events=[],db={app:{options:{projectId:'demo-little-leaf'}}},secret='PRIVATE_PAYLOAD';
const value={owner:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',epoch:2,updatedAt:{toMillis:()=>123},payload:secret,record:secret,token:secret};
let writes=0,callbacks=0;const ref={id:'owner'};
const tx={async get(){return {exists:()=>true,data:()=>value};},set(r,v){assert.equal(r,ref);assert.equal(v,value);writes++;return this;}};
const real=async(database,callback)=>{assert.equal(database,db);return callback(tx);};
const observer=observeTransactions(real,events);const result=await observer(db,async t=>{callbacks++;assert.equal((await t.get(ref)).data(),value);assert.equal(t.set(ref,value),t);return value;});
assert.equal(result,value);assert.equal(writes,1);assert.equal(callbacks,1);assert(!JSON.stringify(events).includes(secret));assert.equal(events[0].reads[0].value.updatedAt,123);
const denied=Object.assign(Error(secret),{code:'permission-denied'});await assert.rejects(observeTransactions(async()=>{throw denied;},events)(db,()=>{}),e=>e===denied);assert.equal(events.at(-1).code,'permission-denied');
await assert.rejects(observer({app:{options:{projectId:'production'}}},()=>{}),/Synthetic/);assert.equal(callbacks,1);
for(let i=0;i<300;i++)await observer(db,()=>null);assert.equal(events.length,240);assert.equal(summary({payload:secret}).digest,null);
console.log('Transaction observer: actual callback/result/error identity, one write, synthetic-only guard, no payload, bounded240 events passed.');

let assertion;try{assert.deepEqual({payload:secret},{payload:'different'});}catch(e){assertion=e;}assert(assertion);assert(!JSON.stringify(boundedFailure(assertion)).includes(secret));assert(!JSON.stringify(boundedFailure(Object.assign(Error(secret),{code:secret,operator:secret}))).includes(secret));console.log('Bounded failure metadata rejects raw deep-equality actual/expected, stack, message and arbitrary codes.');
