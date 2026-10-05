/* Deterministic IDB transaction fixture, not a real-browser substitute. */
class FixtureStore {
 constructor(tx,name){this.transaction=tx;this.name=name;this.indexNames={contains:()=>false}}
 createIndex(){return {}}
 _request(fn){const q={result:undefined,error:null,_listeners:[],addEventListener(type,cb){if(type==='success')this._listeners.push(cb)}};this.transaction._pending++;this.transaction._enqueue(()=>{if(this.transaction._aborted)return;try{q.result=fn();q.onsuccess?.({target:q});for(const cb of q._listeners)cb({target:q})}catch(error){q.error=error;this.transaction.error=error;this.transaction.abort();q.onerror?.({target:q,preventDefault(){}})}finally{this.transaction._pending--;this.transaction._finish()}});return q}
 get(key){return this._request(()=>structuredClone(this.transaction._data.get(this.name).get(key)))}
 put(value,key){return this._request(()=>{if(this.transaction.mode==='readonly')throw new Error('Readonly write');this.transaction._data.get(this.name).set(key,structuredClone(value));return key})}
 add(value,key){return this._request(()=>{if(this.transaction._data.get(this.name).has(key))throw new Error('Duplicate key');this.transaction._data.get(this.name).set(key,structuredClone(value));return key})}
 delete(key){return this._request(()=>this.transaction._data.get(this.name).delete(key))}
 openCursor(){let list,index=0;const q={};const advance=()=>{this.transaction._pending++;this.transaction._enqueue(()=>{list ||= Array.from(this.transaction._data.get(this.name).entries()).sort(([a],[b])=>String(a).localeCompare(String(b)));const item=list[index++];q.result=item?{key:item[0],value:structuredClone(item[1]),continue:advance}:null;q.onsuccess?.({target:q});this.transaction._pending--;this.transaction._finish()})};advance();return q}
}
class FixtureTx {
 constructor(db,names,mode,upgrade=false){this.db=db;this.mode=mode;this.error=null;this._upgrade=upgrade;this._names=Array.isArray(names)?names:[names];this._pending=0;this._tasks=[];this._active=false;this._aborted=false;this._done=false;db._state.queue.push(this);queueMicrotask(()=>db._drain())}
 objectStore(name){return new FixtureStore(this,name)}
 _enqueue(fn){this._tasks.push(fn);this._pump()}
 _pump(){if(!this._active)return;while(this._tasks.length){const task=this._tasks.shift();queueMicrotask(task)}}
 _start(){this._active=true;this._data=new Map(Array.from(this.db._state.stores,([k,v])=>[k,new Map(Array.from(v,([a,b])=>[a,structuredClone(b)]))]));this._pump();this._finish()}
 _finish(){if(this._done||!this._active||(!this._aborted&&this._pending))return;queueMicrotask(()=>{if(this._done||(!this._aborted&&this._pending))return;this._done=true;if(!this._aborted&&this.mode!=='readonly')this.db._state.stores=this._data;if(this._aborted)this.onabort?.({target:this});else this.oncomplete?.({target:this});this.db._state.queue.shift();this.db._drain()})}
 abort(){if(this._done)throw new Error('Transaction complete');this._aborted=true;this._pending=0;this._finish()}
}
class FixtureDB {
 constructor(state){this._state=state;this._closed=false;this.objectStoreNames={contains:n=>state.stores.has(n)}}
 createObjectStore(name){this._state.stores.set(name,new Map());this._upgrade._data?.set(name,new Map());return this._upgrade.objectStore(name)}
 transaction(names,mode){if(this._closed)throw Object.assign(new Error('Closed'),{name:'InvalidStateError'});return new FixtureTx(this,names,mode)}
 close(){this._closed=true}
 _drain(){const next=this._state.queue[0];if(next&&!next._active)next._start()}
}
class FixtureIDB {
 constructor(){this.databases=new Map()}
 open(name,version){const request={};queueMicrotask(()=>{let state=this.databases.get(name);if(state&&version&&version<state.version){request.error=Object.assign(Error('Older version'),{name:'VersionError'});request.onerror?.({target:request,preventDefault(){}});return}if(!state){state={stores:new Map(),version:version||1,queue:[]};this.databases.set(name,state);const db=new FixtureDB(state);request.result=db;request.transaction=new FixtureTx(db,[],'readwrite',true);db._upgrade=request.transaction;request.transaction.oncomplete=()=>request.onsuccess?.({target:request});request.transaction.onabort=()=>{this.databases.delete(name);request.error=Object.assign(Error('Upgrade aborted'),{name:'AbortError'});request.onerror?.({target:request,preventDefault(){}})};request.onupgradeneeded?.({target:request});request.transaction._finish()}else{request.result=new FixtureDB(state);request.onsuccess?.({target:request})}});return request}
}
if(typeof module!=='undefined')module.exports={FixtureIDB,FixtureStore};
