/* Binding presentation has no SDK/storage authority; hooks own verified transitions. */
(function(root){
  'use strict';
  function create({document,origin,capture,signIn,connect,continueCloud,resumeLocal}){
    let panel=null,controller=null,preview=null,busy=false,closed=false;
    const element=(tag,text)=>{const node=document.createElement(tag);if(text)node.textContent=text;return node;};
    function message(text){panel.querySelector('[data-binding-message]').textContent=text;}
    function buttons(items){const actions=panel.querySelector('[data-binding-actions]');actions.replaceChildren();for(const [text,action] of items){const b=element('button',text);b.type='button';b.style.cssText='min-height:48px;padding:10px 14px;margin:4px;border-radius:10px;font:inherit;';b.onclick=async()=>{if(busy)return;busy=true;b.disabled=true;try{await action();}catch(_){message('Could not finish safely. Your local restaurant is still here. Retry or return to local play.');}finally{busy=false;b.disabled=false;}};actions.append(b);}}
    function leave(){if(busy)return;closed=true;controller?.cancel();panel?.remove();panel=null;resumeLocal();}
    async function complete(result){
      if(!result.ok || !result.cloudConfirmed){message('Cloud save is not confirmed. Both protected copies remain. Retry checks the same saved operation; it does not add coins or repeat a transfer.');buttons([['Retry verification',async()=>complete(await controller.retry())],['Return to local play',()=>{busy=false;leave();}]]);return;}
      panel.querySelector('[data-binding-cards]').replaceChildren();
      message('Cloud progress verified. Your original local restaurant remains on this address.');
      buttons([['Continue with Google',()=>continueCloud(result)],['Return to local play',()=>{busy=false;leave();}]]);
    }
    async function inspect(){
      preview=await controller.inspect();if(closed)return;
      if(!preview.ok){message('Binding is unavailable while another save, account ownership or background settlement needs attention. Local progress is unchanged.');buttons([['Retry',inspect],['Return to local play',()=>{busy=false;leave();}]]);return;}
      if(preview.resumable){message('A protected earlier binding is available. Verify its cloud result before continuing.');buttons([['Verify existing binding',async()=>complete(await controller.retry())],['Return to local play',()=>{busy=false;leave();}]]);return;}
      const cards=panel.querySelector('[data-binding-cards]');cards.replaceChildren();
      for(const state of preview.choices){const card=element('article');card.style.cssText='background:#fff7e7;padding:12px;border:1px solid #b9a486;border-radius:10px;margin:8px 0;';card.append(element('h3',state.id==='local'?'This device':'Google cloud'));card.append(element('p','Coins: '+state.coins+' · Save revision: '+state.revision));card.append(element('p','Last saved: '+new Date(state.lastSavedAt).toLocaleString()));cards.append(card);}
      message(preview.choices.length===2?'Choose one complete restaurant. Progress and balances will not be combined. The other state stays protected on this device.':'No cloud restaurant exists. Choose this device to copy its complete restaurant to Google.');
      buttons([...preview.choices.map(state=>[state.id==='local'?'Keep this device restaurant':'Keep Google cloud restaurant',async()=>complete(await controller.choose(state.id,preview.localDigest,preview.cloudDigest))]),['Cancel — return to local play',()=>{busy=false;leave();}]]);
    }
    return {async open(){
      if(panel)return;closed=false;
      panel=element('section');panel.id='google-binding';panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-label','Bind restaurant to Google');panel.style.cssText='position:fixed;inset:8%;max-width:560px;margin:auto;overflow:auto;z-index:90;background:#fffcf4;color:#493d2e;border:2px solid #78694f;border-radius:16px;padding:22px;font:16px Arial;box-shadow:0 8px 40px #0006;';
      panel.append(element('h2','Keep your restaurant safe'));
      panel.append(element('p','Local progress is available only in this browser on '+origin+'. Saves on another address or site cannot be discovered automatically.'));
      const status=element('p','Saving this device before sign-in…');status.setAttribute('data-binding-message','');status.setAttribute('aria-live','polite');panel.append(status);
      const cards=element('div');cards.setAttribute('data-binding-cards','');panel.append(cards);
      const actions=element('div');actions.setAttribute('data-binding-actions','');panel.append(actions);document.body.append(panel);
      try{const result=await capture();if(!result?.ok)throw Error('local save');
        message('This device is saved. Sign-in alone will not choose or overwrite a restaurant.');
        buttons([['Sign in with Google',async()=>{const account=await signIn();controller=await connect(account);await inspect();}],['Cancel — return to local play',()=>{busy=false;leave();}]]);
      }catch(_){message('Could not save this device safely. Binding has stopped; your local progress is unchanged.');buttons([['Return to local play',()=>{busy=false;leave();}]]);}
    },close(){leave();}};
  }
  root.LittleLeafGoogleBindingUI=Object.freeze({create});
})(globalThis);
