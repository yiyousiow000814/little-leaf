// Test-only fixture seed/read boundary. Never used by the application.
import assert from 'node:assert/strict';
import {doc,getDocFromServer,setDoc} from 'firebase/firestore';
export function createFixtureStore(environment){
  assert.equal(environment.projectId,'demo-little-leaf');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  const reference=(db,uid,kind)=>{
    assert.match(uid,/^fullflow-[a-z-]+$/,'synthetic account names only');
    assert(['save','owner'].includes(kind),'bounded fixture document');
    return doc(db,'players',uid,...(kind==='save'?['saves','cafe']:['session','owner']));
  };
  return {
    async read(uid,kind='save'){
      let result=null;
      // RulesTestEnvironment deliberately returns void from this callback API.
      // Capture the observation explicitly rather than assuming it is returned.
      await environment.withSecurityRulesDisabled(async context=>{
        const snapshot=await getDocFromServer(reference(context.firestore(),uid,kind));
        result=snapshot.exists()?snapshot.data():null;
      });
      return result;
    },
    async seed(uid,value){
      await environment.withSecurityRulesDisabled(context=>setDoc(reference(context.firestore(),uid,'save'),value));
    }
  };
}
