'use strict';
// Passed to context.addInitScript before a fresh navigation. No bridge per phase.
function installCollector() {
  const state=window.__littleLeafPhaseObservation={packet:null,packetCount:0,packetReceivedMs:null,
    startedMs:performance.now(),loaderRemovedMs:null,firstLoaderAbsentRafTimestampMs:null,firstObservedCallbackMs:null,callbacks:[],stopped:false};
  Object.defineProperty(window,'__littleLeafStartupPhasePacket',{configurable:false,
    set(packet){state.packetCount++;if(state.packetCount===1){state.packetReceivedMs=performance.now();state.packet=packet;}},
    get(){return state.packet;}});
  let hadStatus=false;
  const observer=new MutationObserver(()=>{if(document.getElementById('status'))hadStatus=true;
    if(hadStatus&&!document.getElementById('status')&&state.loaderRemovedMs===null)state.loaderRemovedMs=performance.now();});
  observer.observe(document,{subtree:true,childList:true});
  function frame(timestamp){const executed=performance.now(),status=document.getElementById('status');if(status)hadStatus=true;
    if(hadStatus&&!status&&state.firstLoaderAbsentRafTimestampMs===null)state.firstLoaderAbsentRafTimestampMs=timestamp;
    if(!status&&state.loaderRemovedMs!==null&&executed>=state.loaderRemovedMs&&state.firstObservedCallbackMs===null)state.firstObservedCallbackMs=executed;
    // The supplied rAF timestamp can predate loader removal. Only callback execution
    // time after observed removal may delimit the loader-absent scheduling phase.
    state.callbacks.push({rafMs:timestamp,executedMs:executed,loaderPresent:!!status});
    if(!state.stopped)requestAnimationFrame(frame);else observer.disconnect();}
  requestAnimationFrame(frame);
}
module.exports={installCollector};
