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

// A context owns its intercepted requests. Closing it cancels outstanding frame
// evaluations/fetches; drain those callbacks before starting the next case.
// Only cancellation from an explicitly requested, confirmed close is expected.
export function createRouteLifetime(context,errors){
  let retiring=false,closed=false,closing,callbackFailure;
  const pending=new Set(),cancelled=[];
  context.on('close',()=>{closed=true;});
  const targetClosed=error=>/^(frame\.evaluate|route\.(fetch|fulfill|abort|continue|fallback)): Target page, context or browser has been closed(?:\n|$)/.test(String(error?.message));
  const failed=error=>{callbackFailure??=error;errors.push('Fixture route callback failed: '+(targetClosed(error)?'target-closed':failureCategory(error?.message||error)));};
  return {
    handle(callback){return route=>{
      const operation=(async()=>{
        try{
          if(retiring){if(!closed)await route.abort('blockedbyclient');return;}
          await callback(route);
        }catch(error){
          if(retiring && targetClosed(error))cancelled.push(error);
          else failed(error);
        }
      })();
      pending.add(operation);
      operation.finally(()=>pending.delete(operation));
      return operation;
    };},
    close(){
      if(!closing){
        retiring=true;
        closing=(async()=>{
          let failure;
          try{await context.close();if(!closed)throw Error('Fixture context close not confirmed');}
          catch(error){failure=error;}
          if(closed)while(pending.size)await Promise.all([...pending]);
          if(!closed)for(const error of cancelled)failed(error);
          cancelled.length=0;
          if(failure)errors.push('Fixture context cleanup failed');
          if(failure || callbackFailure)throw failure || callbackFailure;
        })();
      }
      return closing;
    },
  };
}

// AudioWorklet fetches can escape Playwright's document routing. Keep the exact
// packaged code executing in its own frame instead of requesting a live host.
// The caller verifies these bytes against the immutable variant inventory.
export function installPackagedWorklets({origin,pathname,modules}){
  if(location.origin!==origin || location.pathname!==pathname)return;
  const names=['index.audio.worklet.js','index.audio.position.worklet.js'];
  if(Object.keys(modules).sort().join(',')!==names.sort().join(',')
      || names.some(name=>typeof modules[name]!=='string'||!modules[name]))throw Error('Exact packaged worklets required');
  const original=AudioWorklet.prototype.addModule;
  AudioWorklet.prototype.addModule=async function(value,...options){
    const url=new URL(value,location.href);
    const name=names.find(name=>url.href===origin+pathname+name);
    if(!name)throw Error('Unknown compiled worklet URL');
    const bytes=Uint8Array.from(atob(modules[name]),character=>character.charCodeAt(0));
    const blob=URL.createObjectURL(new Blob([bytes],{type:'text/javascript'}));
    try{return await Reflect.apply(original,this,[blob,...options]);}
    finally{URL.revokeObjectURL(blob);}
  };
}

// Only immutable compiled PCK bytes cross this fixture bridge. A full PCK
// base64 CDP fulfill exceeds Chrome's100MiB pipe limit; each message stays256KiB.
export function packagedPckChunk(bytes,offset){
  if(!Buffer.isBuffer(bytes) || !Number.isSafeInteger(offset) || offset<0 || offset>=bytes.length)
    throw Error('Exact packaged PCK offset required');
  return bytes.subarray(offset,Math.min(offset+256*1024,bytes.length)).toString('base64');
}

export function installPackagedPckStream({origin,pathname,bytes}){
  if(location.origin!==origin || location.pathname!==pathname)return;
  if(!Number.isSafeInteger(bytes) || bytes<=0 || bytes>192*1024*1024)
    throw Error('Finite packaged PCK inventory required');
  const original=globalThis.fetch;
  globalThis.fetch=async function(input,init){
    const url=new URL(typeof input==='string'||input instanceof URL?input:input.url,location.href);
    if(url.href!==origin+pathname+'index.pck')return Reflect.apply(original,this,[input,init]);
    const method=init?.method || input?.method || 'GET';
    if(method!=='GET' || new Headers(init?.headers || input?.headers).has('range'))
      throw Error('Only the complete packaged PCK GET is supported');
    const signal=init?.signal || input?.signal;
    const aborted=()=>signal?.reason || new DOMException('Aborted','AbortError');
    if(signal?.aborted)throw aborted();
    let offset=0,cancelled=false;
    const body=new ReadableStream({
      async pull(controller){
        try{
          if(signal?.aborted)throw aborted();
          const encoded=await globalThis.__littleLeafPackagedPckChunk(offset);
          if(cancelled)return;
          if(signal?.aborted)throw aborted();
          const chunk=Uint8Array.from(atob(encoded),character=>character.charCodeAt(0));
          if(chunk.length!==Math.min(256*1024,bytes-offset))throw Error('Packaged PCK chunk differs');
          offset+=chunk.length;controller.enqueue(chunk);
          if(offset===bytes)controller.close();
        }catch(error){controller.error(error);}
      },
      cancel(){cancelled=true;},
    });
    const response=new Response(body,{status:200,headers:{'Content-Type':'application/octet-stream','Content-Length':String(bytes)}});
    Object.defineProperty(response,'url',{value:url.href});
    return response;
  };
}
