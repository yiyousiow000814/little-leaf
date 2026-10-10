'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const context={};context.globalThis=context;vm.runInNewContext(fs.readFileSync('platform/web/little_leaf_firebase.js','utf8'),context);
const ownerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',proof={writerId:ownerId,writerEpoch:1,commitServerStamp:'100000'};
let owner={owner:ownerId,epoch:1,updatedAt:100000,request:null,ack:null},writes=0;
const sdk={doc:(db,...p)=>p.join('/'),runTransaction:async(db,action)=>action({get:async ref=>({exists:()=>true,data:()=>ref==='session'?owner:{digest:'base'}}),set:()=>writes++})};
const remote=context.LittleLeafFirebase.createRemote({},sdk,{sessionRef:'session',assertActive:()=>({writerId:ownerId,writerEpoch:1})});
(async()=>{
 for(const changed of [{request:{id:'pending'}},{updatedAt:100001},{epoch:2},{ack:{requestId:'ack'}}]){
  owner={owner:ownerId,epoch:1,updatedAt:100000,request:null,ack:null,...changed};
  await assert.rejects(remote.compareAndSet('uid','base',{digest:'next'},()=>{},proof),x=>['ELAPSED_CHANGED','OWNERSHIP_LOST'].includes(x.code));assert.equal(writes,0);
 }
 owner={owner:ownerId,epoch:1,updatedAt:100000,request:null,ack:null};
 await remote.compareAndSet('uid','base',{digest:'next'},()=>{},proof);assert.equal(writes,1);
 console.log('Passed: actual production snapshot CAS rejects changed request, server timestamp, epoch and acknowledgment before any elapsed snapshot write.');
})().catch(e=>{console.error(e);process.exitCode=1;});
