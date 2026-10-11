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
    if(u.origin==='https://www.gstatic.com' && u.pathname.startsWith('/firebasejs/12.19.0/'))return 'sdk-module';
    if(u.origin==='https://little-leaf-41e5d.firebaseapp.com' && u.pathname.startsWith('/itch/'))return 'game-frame';
    if(['https://html-classic.itch.zone','https://siowyiyou.itch.io'].includes(u.origin))return 'wrapper';
  }catch(_){}
  return 'other';
}
