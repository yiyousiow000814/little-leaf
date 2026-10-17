// Synthetic transaction fixture, not Firestore/emulator evidence. Serial commit
// gives deterministic concurrency and rollback probes without any live account.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {hash,fingerprint} from './support_mail_contract.mjs';
export const player='syntheticStorageOwner',profileId='22222222-2222-4222-8222-222222222222';
export const writerId='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',mailId='11111111-1111-4111-8111-111111111111';
export const auth={auth:{uid:player,token:{firebase:{sign_in_provider:'google.com'}}}};
export const sign=record=>({...record,digest:hash(fingerprint(record))});
export const document=record=>({schema:1,profileId:record.profileId,revision:record.revision,digest:record.digest,record:JSON.stringify(record),writerId,writerEpoch:1,device:'Mac'});
export const key=part=>`players/${player}/${part}`;
export function fixture(){
  const baseline=JSON.parse(readFileSync(new URL('../../tests/fixtures/unified_building_candidate.json',import.meta.url),'utf8'));
  const original=sign({format:2,profileId,revision:1,createdAt:1,updatedAt:1,origin:{source:'fresh',legacyDigest:null,importedAt:1},payload:JSON.stringify({...baseline,coins:40}),previous:null,campaigns:{}});
  const documents=new Map([[key('saves/cafe'),document(original)],
    [key('session/owner'),{schema:1,owner:writerId,epoch:1,updatedAt:{toMillis:()=>1000},request:null,ack:null}],
    [key(`mail/${mailId}`),{schema:1,mailId,issueId:mailId,profileId,status:'unclaimed',coins:60,items:[{catalogId:'plant',quantity:2,catalogRevision:1}],claimedAt:null}]]);
  let queue=Promise.resolve();
  const copy=value=>value && typeof value==='object'?Array.isArray(value)?value.map(copy):Object.fromEntries(Object.entries(value).map(([k,v])=>[k,typeof v==='function'?v:copy(v)])):value;
  const snapshot=ref=>({id:ref.path.split('/').at(-1),ref,exists:documents.has(ref.path),data:()=>copy(documents.get(ref.path))});
  function query(group,after=null,count=Infinity) {
    return {group,after,count,orderBy(field){assert.equal(field,'__name__');return this;},
      startAfter(ref){return query(group,ref.path,count);},limit(n){return query(group,after,n);}};
  }
  const read=ref=>ref.group?{docs:[...documents.keys()].filter(path=>path.split('/').at(-2)===ref.group
    &&(!ref.after||path>ref.after)).sort().slice(0,ref.count).map(path=>snapshot(db.doc(path)))}:snapshot(ref);
  const db={documents,failNextCommit:false,doc:path=>({path,async get(){return snapshot(this);}}),
    collectionGroup:name=>query(name),commits:0,queryReads:[],
    runTransaction(callback){
      const pending=queue.then(async()=>{
        const writes=[];
        const tx={async get(ref){assert.equal(writes.length,0,'Firestore transaction reads precede all writes');if(ref.group)db.queryReads.push({group:ref.group,limit:ref.count});return read(ref);},
          set(ref,value){writes.push(['set',ref.path,copy(value)]);},create(ref,value){writes.push(['create',ref.path,copy(value)]);},
          update(ref,value){writes.push(['update',ref.path,copy(value)]);}};
        const result=await callback(tx);
        const next=new Map(documents);
        for(const [operation,path,value] of writes){
          if(operation==='create')assert(!next.has(path),`duplicate create ${path}`);
          if(operation==='update')assert(next.has(path),`missing update ${path}`);
          next.set(path,operation==='update'?{...next.get(path),...value}:value);
        }
        if(db.failNextCommit||db.failAtCommit===db.commits+1){db.failNextCommit=false;db.failAtCommit=null;throw Object.assign(Error('Synthetic commit unavailable'),{code:'OFFLINE'});}
        documents.clear();for(const entry of next)documents.set(...entry);
        db.commits++;if(db.afterCommit)db.afterCommit(db.commits);
        return result;
      });queue=pending.catch(()=>{});return pending;
    }};
  const request={mailId,operationId:'33333333-3333-4333-8333-333333333333',profileId,revision:1,digest:original.digest,writerId,writerEpoch:1};
  return {db,documents,original,baseline,request};
}
