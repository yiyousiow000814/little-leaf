// Pinned Firebase WebChannel's connectivity image is deliberately failed locally.
// This does not permit a request to Google or fake successful connectivity.
export function isConnectivityProbe(value,resourceType){
  const url=new URL(value);
  return ['http:','https:'].includes(url.protocol) && url.hostname==='www.google.com'
    && url.pathname==='/images/cleardot.gif' && resourceType==='image';
}

// Failure evidence is finite and credential-free; never retain raw SDK messages/URLs.
export function failureCategory(value){
  const text=String(value).toLowerCase();
  if(/local network|local-network|private network|loopback/.test(text))return 'local-network';
  if(/mixed content/.test(text))return 'mixed-content';
  if(/cors|cross.origin|access.control/.test(text))return 'cross-origin';
  if(/failed to fetch|networkerror|network request|dynamically imported/.test(text))return 'network';
  if(/permission.denied|insufficient permissions/.test(text))return 'permission-denied';
  if(/indexeddb|storage/.test(text))return 'storage';
  if(/script error|parse error|syntaxerror/.test(text))return 'script';
  return 'other';
}

export function requestFamily(value,fixtureOrigin){
  try{
    const u=new URL(value);
    if(u.origin===fixtureOrigin && /^\/sdk\/(firebase-app|firebase-firestore)\.js$/.test(u.pathname))return 'loopback-sdk';
    if(u.origin==='http://127.0.0.1:8080')return 'loopback-emulator';
    if(u.origin===syntheticRPCOrigin)return 'synthetic-emulator';
    if(u.origin==='https://www.gstatic.com' && u.pathname.startsWith('/firebasejs/12.19.0/'))return 'sdk-module';
    if(u.origin==='https://little-leaf-41e5d.firebaseapp.com' && u.pathname==='/itch/sdk/firebase-firestore.js')return 'frame-sdk';
    if(workletName(value))return 'audio-worklet';
    if(u.origin==='https://little-leaf-41e5d.firebaseapp.com' && u.pathname.startsWith('/itch/'))return 'game-frame';
    if(['https://html-classic.itch.zone','https://siowyiyou.itch.io'].includes(u.origin))return 'wrapper';
  }catch(_){}
  return 'other';
}

// Observe only the two actual exported worklets, without retaining URLs/queries.
export function workletName(value){
  try{
    const u=new URL(value);
    if(u.origin!=='https://little-leaf-41e5d.firebaseapp.com' || u.search || u.hash)return null;
    const names=['index.audio.worklet.js','index.audio.position.worklet.js'];
    return names.find(name=>u.pathname==='/itch/'+name)||null;
  }catch(_){return null;}
}

export const syntheticRPCOrigin='https://firestore.fullflow.test';
export function emulatorProxyTarget(value,method){
  const u=new URL(value);
  if(u.origin!==syntheticRPCOrigin || u.username || u.password || u.hash || !['GET','POST'].includes(method))throw Error('Nonfixture emulator request');
  const p=decodeURIComponent(u.pathname);
  const channel=/^\/google\.firestore\.v1\.Firestore\/(Listen|Write)\/channel$/.test(p);
  const unary=/^\/v1\/projects\/demo-little-leaf\/databases\/\(default\)\/documents:(batchGet|commit)$/.test(p);
  if(!channel && !unary)throw Error('Unknown emulator RPC');
  if(channel && (u.searchParams.getAll('database').length!==1 || u.searchParams.get('database')!=='projects/demo-little-leaf/databases/(default)'))throw Error('Nonfixture emulator database');
  return 'http://127.0.0.1:8080'+u.pathname+u.search;
}

export function emulatorRequestKind(value,method){
  emulatorProxyTarget(value,method); // Keep the existing exact demo-only boundary.
  const p=new URL(value).pathname;
  if(p.endsWith('/Listen/channel'))return method==='GET'?'listen-poll':'listen-send';
  if(p.endsWith('/Write/channel'))return method==='GET'?'write-poll':'write-send';
  return p.endsWith(':batchGet')?'batch-get':'commit';
}

// Serialized into the synthetic SDK module. Every original transaction/callback
// is still awaited and its exact return/error is forwarded; no extra RPC occurs.
export function observeTransaction(runTransaction,db,update,options,state){
  const elapsed=()=>Math.max(0,Date.now()-state.clockOrigin);
  const row={sequence:++state.sequence,start_ms:elapsed(),attempts:0,events:[],outcome:'pending'};
  state.rows.push(row);if(state.rows.length>128)state.rows.shift();
  const event=kind=>{if(row.events.length<64)row.events.push({kind,at_ms:elapsed()});};
  const kind=ref=>/^players\/fullflow-[a-z-]+\/session\/owner$/.test(ref?.path)?'owner'
    :/^players\/fullflow-[a-z-]+\/saves\/cafe$/.test(ref?.path)?'save':'other';
  const observe=async tx=>{
    row.attempts++;event('attempt');
    const observed=new Proxy(tx,{get(target,key){
      if(key==='get')return ref=>{
        const name=kind(ref);event(name+'-read-start');
        return target.get(ref).then(value=>{event(name+'-read-end');return value;});
      };
      if(key==='set')return(ref,value,...rest)=>{
        const name=kind(ref);event(name==='owner'&&value?.ack?'ack-write':name+'-write');
        return target.set(ref,value,...rest);
      };
      const value=target[key];return typeof value==='function'?value.bind(target):value;
    }});
    return update(observed);
  };
  return runTransaction(db,observe,options).then(value=>{
    row.end_ms=elapsed();row.outcome='resolved';return value;
  },error=>{
    row.end_ms=elapsed();
    row.outcome=['permission-denied','deadline-exceeded','unavailable','failed-precondition'].includes(error?.code)?error.code:'other';
    throw error;
  });
}

export function emulatorPreflightHeaders(value,headers){
  emulatorProxyTarget(value,headers['access-control-request-method']);
  if(headers.origin!=='https://little-leaf-41e5d.firebaseapp.com' || headers['access-control-request-private-network'])throw Error('Nonfixture preflight origin');
  const allowed=['authorization','content-type','x-goog-api-client','x-firebase-gmpid','google-cloud-resource-prefix','x-goog-request-params'];
  const requested=(headers['access-control-request-headers']||'').split(',').map(name=>name.trim().toLowerCase()).filter(Boolean);
  if(requested.some(name=>!allowed.includes(name)))throw Error('Unknown preflight header');
  return {'access-control-allow-origin':headers.origin,'access-control-allow-credentials':'true','access-control-allow-methods':'GET, POST','access-control-allow-headers':allowed.join(', ')};
}
