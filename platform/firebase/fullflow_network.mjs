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
    if(u.origin==='https://little-leaf-41e5d.firebaseapp.com' && u.pathname.startsWith('/itch/'))return 'game-frame';
    if(['https://html-classic.itch.zone','https://siowyiyou.itch.io'].includes(u.origin))return 'wrapper';
  }catch(_){}
  return 'other';
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

export function emulatorPreflightHeaders(value,headers){
  emulatorProxyTarget(value,headers['access-control-request-method']);
  if(headers.origin!=='https://little-leaf-41e5d.firebaseapp.com' || headers['access-control-request-private-network'])throw Error('Nonfixture preflight origin');
  const allowed=['authorization','content-type','x-goog-api-client','x-firebase-gmpid','google-cloud-resource-prefix','x-goog-request-params'];
  const requested=(headers['access-control-request-headers']||'').split(',').map(name=>name.trim().toLowerCase()).filter(Boolean);
  if(requested.some(name=>!allowed.includes(name)))throw Error('Unknown preflight header');
  return {'access-control-allow-origin':headers.origin,'access-control-allow-credentials':'true','access-control-allow-methods':'GET, POST','access-control-allow-headers':allowed.join(', ')};
}
