import assert from 'node:assert/strict';
import vm from 'node:vm';
import {isConnectivityProbe,failureCategory,requestFamily,syntheticRPCOrigin,emulatorProxyTarget,emulatorPreflightHeaders,installPackagedWorklets} from './fullflow_network.mjs';
assert(isConnectivityProbe('https://www.google.com/images/cleardot.gif?zx=synthetic','image'));
assert(isConnectivityProbe('http://www.google.com/images/cleardot.gif','image'));
for(const [url,type] of [['https://www.google.com/images/cleardot.gif','script'],['https://www.google.com/accounts','image'],['https://www.google.com.evil.test/images/cleardot.gif','image'],['https://accounts.google.com/images/cleardot.gif','image']])assert(!isConnectivityProbe(url,type));
console.log('Offline network fixture: only exact SDK connectivity image is locally aborted; no external request allowed.');
for(const [message,category] of [['blocked by Local Network Access: PRIVATE_TOKEN','local-network'],['Mixed Content PRIVATE_TOKEN','mixed-content'],['CORS PRIVATE_TOKEN','cross-origin'],['Failed to fetch PRIVATE_TOKEN','network'],['permission-denied PRIVATE_TOKEN','permission-denied'],['IndexedDB PRIVATE_TOKEN','storage'],['SyntaxError PRIVATE_TOKEN','script'],['PRIVATE_TOKEN','other']])assert.equal(failureCategory(message),category);
assert.equal(requestFamily('http://127.0.0.1:43123/sdk/firebase-firestore.js?token=PRIVATE_TOKEN','http://127.0.0.1:43123'),'loopback-sdk');
assert.equal(requestFamily('http://127.0.0.1:8080/PRIVATE_TOKEN','http://127.0.0.1:43123'),'loopback-emulator');
assert.equal(requestFamily('https://evil.test/PRIVATE_TOKEN','http://127.0.0.1:43123'),'other');
assert.equal(requestFamily('not a URL PRIVATE_TOKEN','http://127.0.0.1:43123'),'other');
assert.equal(requestFamily(syntheticRPCOrigin+'/PRIVATE_TOKEN','http://127.0.0.1:43123'),'synthetic-emulator');
assert.equal(requestFamily('https://little-leaf-41e5d.firebaseapp.com/itch/sdk/firebase-firestore.js','http://127.0.0.1:43123'),'frame-sdk');
console.log('Failure observations expose only finite categories, including secret-bearing unknown inputs.');
const channel='/google.firestore.v1.Firestore/Listen/channel?database=projects%2Fdemo-little-leaf%2Fdatabases%2F(default)&RID=rpc';
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+channel,'GET'),'http://127.0.0.1:8080'+channel);
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+'/v1/projects/demo-little-leaf/databases/(default)/documents:commit','POST'),'http://127.0.0.1:8080/v1/projects/demo-little-leaf/databases/(default)/documents:commit');
for(const [url,method] of [[syntheticRPCOrigin+channel,'DELETE'],['https://firestore.googleapis.com'+channel,'GET'],[syntheticRPCOrigin+'/v1/projects/little-leaf-41e5d/databases/(default)/documents:commit','POST'],[syntheticRPCOrigin+'/google.firestore.v1.Firestore/Listen/channel?database=projects%2Flittle-leaf-41e5d%2Fdatabases%2F(default)','GET'],[syntheticRPCOrigin+'/unknown','GET'],['https://user:PRIVATE_TOKEN@firestore.fullflow.test'+channel,'GET'],[syntheticRPCOrigin+channel+'#PRIVATE_TOKEN','GET']])assert.throws(()=>emulatorProxyTarget(url,method));
assert.throws(()=>emulatorProxyTarget(syntheticRPCOrigin+channel+'&database=projects%2Fproduction%2Fdatabases%2F(default)','GET'));
assert.equal(emulatorProxyTarget(syntheticRPCOrigin+channel.replace('/Listen/','/Write/'),'POST'),'http://127.0.0.1:8080'+channel.replace('/Listen/','/Write/'));
console.log('HTTPS emulator proxy permits only fixed loopback, demo project and known SDK RPCs.');
const preflight={origin:'https://little-leaf-41e5d.firebaseapp.com','access-control-request-method':'POST','access-control-request-headers':'Authorization, content-type, x-goog-api-client, x-firebase-gmpid, google-cloud-resource-prefix, x-goog-request-params'};
assert.deepEqual(emulatorPreflightHeaders(syntheticRPCOrigin+channel,preflight),{'access-control-allow-origin':preflight.origin,'access-control-allow-credentials':'true','access-control-allow-methods':'GET, POST','access-control-allow-headers':'authorization, content-type, x-goog-api-client, x-firebase-gmpid, google-cloud-resource-prefix, x-goog-request-params'});
for(const extra of [{origin:'https://evil.test'},{'access-control-request-method':'DELETE'},{'access-control-request-headers':'PRIVATE_TOKEN'},{'access-control-request-private-network':'true'}])assert.throws(()=>emulatorPreflightHeaders(syntheticRPCOrigin+channel,{...preflight,...extra}));
assert.throws(()=>emulatorPreflightHeaders(syntheticRPCOrigin+'/PRIVATE_TOKEN',preflight));
console.log('Preflight stays local and refuses unknown methods, origins, headers and private-network grants.');

const workletOrigin='https://little-leaf-41e5d.firebaseapp.com';
const moduleBytes={'index.audio.worklet.js':Buffer.from([0,10,13,127,128,255]),
  'index.audio.position.worklet.js':Buffer.from('registerProcessor("test", class {});\n')};
const modules=Object.fromEntries(Object.entries(moduleBytes).map(([name,bytes])=>[name,bytes.toString('base64')]));
function workletHarness(location={origin:workletOrigin,pathname:'/itch/',href:workletOrigin+'/itch/'}){
  const active=new Map(),calls=[],revoked=[];
  class FixtureURL extends URL{
    static createObjectURL(blob){const url='blob:'+location.origin+'/'+active.size;active.set(url,blob);return url;}
    static revokeObjectURL(url){assert(active.delete(url));revoked.push(url);}
  }
  class AudioWorklet{
    async addModule(url,...options){calls.push({bytes:Buffer.from(await active.get(url).arrayBuffer()),options});if(this.reject)throw Error('Original module rejected');return 'executed';}
  }
  const original=AudioWorklet.prototype.addModule;
  const install=vm.runInNewContext('('+installPackagedWorklets.toString()+')',{location,URL:FixtureURL,Blob,Uint8Array,atob,AudioWorklet});
  return {install,AudioWorklet,original,active,calls,revoked};
}
const h=workletHarness();h.install({origin:workletOrigin,pathname:'/itch/',modules});
for(const name of Object.keys(modules)){
  assert.equal(await new h.AudioWorklet().addModule(name,{credentials:'same-origin'}),'executed');
  assert.deepEqual(h.calls.at(-1).bytes,moduleBytes[name]);
  assert.equal(h.calls.at(-1).options[0].credentials,'same-origin');
  assert.equal(h.active.size,0);
}
const rejected=new h.AudioWorklet();rejected.reject=true;
await assert.rejects(rejected.addModule(workletOrigin+'/itch/index.audio.worklet.js'),/Original module rejected/);
assert.equal(h.active.size,0);assert.equal(h.revoked.length,3);
for(const url of [workletOrigin+'/itch/index.audio.worklet.js?changed=1',workletOrigin+'/itch/unknown.js','https://evil.test/itch/index.audio.worklet.js']){
  await assert.rejects(new h.AudioWorklet().addModule(url),/Unknown compiled worklet URL/);
}
assert.equal(h.calls.length,3,'unknown URLs never execute or fetch');
for(const location of [{origin:workletOrigin,pathname:'/',href:workletOrigin+'/'},{origin:'https://html-classic.itch.zone',pathname:'/itch/',href:'https://html-classic.itch.zone/itch/'}]){
  const other=workletHarness(location);other.install({origin:workletOrigin,pathname:'/itch/',modules});
  assert.equal(other.AudioWorklet.prototype.addModule,other.original,'only exact nested game frame changes');
}
assert.throws(()=>workletHarness().install({origin:workletOrigin,pathname:'/itch/',modules:{...modules,unknown:'AA=='}}),/Exact packaged worklets required/);
console.log('Packaged worklet fixture: exact binary bytes/options execute, failures propagate, Blob URLs revoke, unknown URLs refuse, other frames unchanged.');
