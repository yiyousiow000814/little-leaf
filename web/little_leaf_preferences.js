/* Preferences are independent from café progress and never use Godot IDBFS. */
(function(root) {
  'use strict';
  const KEY='little-leaf.preferences.v1';
  const LIMIT=65536;
  const failure=(code,error)=>({ok:false,code,error});
  function valid(text){return typeof text==='string'&&new TextEncoder().encode(text).length<=LIMIT;}
  function createClient(options={}) {
    let storage=null, factory=null, text='', ready=false;
    const api={bootJson:'',lastError:'',
      async boot(){
        try {
          // Acquire browser storage only inside the error boundary: some
          // privacy modes throw even while reading window.localStorage.
          storage=options.localStorage||root.localStorage;
          factory=options.indexedDB||root.indexedDB;
          const raw=storage.getItem(KEY);
          if(raw!==null){
            let item;try{item=JSON.parse(raw)}catch(_){throw Error('Saved preferences are damaged');}
            if(!item||item.format!==1||!valid(item.text))throw Error('Saved preferences have an unsupported format');
            text=item.text;ready=true;
            const result={ok:true,source:'preferences',text};api.bootJson=JSON.stringify(result);return result;
          }
          const legacy=await readLegacy(factory);
          text=legacy||'';ready=true;
          // Migration is read-only until Godot parses the CFG successfully and
          // calls acceptLoaded; malformed settings cannot enter the new store.
          const result={ok:true,source:legacy===null?'default':'legacy-readonly',text};api.bootJson=JSON.stringify(result);return result;
        } catch(error){api.lastError=error.message||String(error);const result=failure(error.name||'PREFERENCES_ERROR',api.lastError);api.bootJson=JSON.stringify(result);return result;}
      },
      writeText(value){
        if(!ready||!storage){api.lastError='Preferences storage is unavailable';return false;}
        if(!valid(value)){api.lastError='Preferences are unreadable or too large';return false;}
        try{storage.setItem(KEY,JSON.stringify({format:1,text:value}));text=value;api.lastError='';api.bootJson=JSON.stringify({ok:true,source:'preferences',text});return true}
        catch(error){api.lastError=error.message||String(error);return false;}
      },
      acceptLoaded(){return api.writeText(text);}
    };
    return api;
  }
  function readLegacy(factory){
    return new Promise((resolve,reject)=>{
      let request,absent=false,settled=false;
      const timer=setTimeout(()=>{settled=true;reject(Error('Legacy preference read timed out'))},10000);
      function done(error,value){clearTimeout(timer);if(settled)return;settled=true;error?reject(error):resolve(value)}
      try{request=factory.open('/userfs')}catch(error){done(error);return;}
      request.onupgradeneeded=()=>{absent=true;request.transaction.abort()};
      request.onerror=event=>{event.preventDefault();done(absent?null:request.error,null)};
      request.onblocked=()=>done(Error('Legacy preferences are blocked by another browser tab'));
      request.onsuccess=()=>{
        const db=request.result;if(settled){db.close();return;}
        if(!db.objectStoreNames.contains('FILE_DATA')){db.close();done(Error('Legacy preferences store is unreadable'));return;}
        let tx;
        try{tx=db.transaction('FILE_DATA','readonly')}catch(error){db.close();done(error);return;}
        const profiles=[],settings=[];
        tx.onabort=()=>{db.close();done(tx.error||Error('Legacy preference read failed'))};
        tx.onerror=()=>{};
        tx.objectStore('FILE_DATA').openCursor().onsuccess=event=>{
          const c=event.target.result;if(!c)return;
          const path=String(c.key);
          if(/^\/userfs\/(?:[^/]+\/)*little_leaf_cafe_v13\.json$/.test(path))profiles.push(path);
          if(/^\/userfs\/(?:[^/]+\/)*little_leaf_settings\.cfg$/.test(path))settings.push({path,entry:c.value});
          c.continue();
        };
        tx.oncomplete=()=>{
          db.close();
          try{
            const candidates=profiles.length===1?settings.filter(x=>x.path===profiles[0].replace(/[^/]+$/,'little_leaf_settings.cfg')):settings;
            if(candidates.length>1)throw Error('Several legacy preference profiles were found; no profile was guessed');
            if(!candidates.length){done(null,null);return;}
            const bytes=candidates[0].entry&&candidates[0].entry.contents;
            // IDBFS may retain the signed HEAP8 view used by native writes.
            if(!(bytes instanceof Uint8Array || bytes instanceof Int8Array)||bytes.byteLength>LIMIT)throw Error('Legacy preferences are unreadable or too large');
            done(null,new TextDecoder('utf-8',{fatal:true}).decode(bytes));
          }catch(error){done(error);}
        };
      };
    });
  }
  root.LittleLeafPreferences=Object.freeze({KEY,createClient});
  root.__littleLeafPreferences=createClient();
})(globalThis);
