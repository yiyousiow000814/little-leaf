'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const assert=require('node:assert/strict');
const {FixtureIDB,FixtureStore}=require('./inbox_transaction_fixture');
const run=require('./compensation_inbox_suite');
const root=path.resolve(__dirname,'..'),factory=new FixtureIDB();
const storage=new class {constructor(){this.data=new Map();}get length(){return this.data.size;}key(i){return [...this.data.keys()][i]||null;}getItem(k){return this.data.get(k)||null;}setItem(k,v){this.data.set(k,String(v));}removeItem(k){this.data.delete(k);}clear(){this.data.clear();}}();
const context=vm.createContext({crypto:crypto.webcrypto,TextEncoder,TextDecoder,Uint8Array,Int8Array,structuredClone,setTimeout,clearTimeout,DOMException,indexedDB:factory,localStorage:storage});
vm.runInContext(fs.readFileSync(path.join(__dirname,'fixtures/inbox-vault-018.js'),'utf8'),context);const oldVault=context.LittleLeafVault;
for(const file of ['little_leaf_vault.js','little_leaf_inbox.js']){const source=fs.readFileSync(path.join(root,'platform/web',file),'utf8');assert(fs.readFileSync(path.join(root,'platform/web/little_leaf_shell.html'),'utf8').replace(/\r\n/g,'\n').includes(source.trim().replace(/\r\n/g,'\n')),file+' shell embedding');vm.runInContext(source,context);}
const timer=setTimeout(()=>{console.error('Inbox suite timed out');process.exit(2);},10000);
run({vault:context.LittleLeafVault,oldVault,factory,storePrototype:FixtureStore.prototype,markers:context.LittleLeafInbox,storage,runId:crypto.randomUUID()}).then(report=>{clearTimeout(timer);report.method='Deterministic async transaction fixture, not real browser proof';console.log(JSON.stringify(report,null,2));}).catch(error=>{clearTimeout(timer);console.error(error);process.exitCode=1;});
