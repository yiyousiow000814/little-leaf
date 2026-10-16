import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {onCall,HttpsError} from 'firebase-functions/v2/https';
import {createSupportMailService} from './support_mail_service.mjs';

initializeApp();
const service=createSupportMailService({db:getFirestore(),enabled:process.env.LITTLE_LEAF_SUPPORT_MAIL_ENABLED==='true'});
const codes={UNAUTHENTICATED:'unauthenticated',PERMISSION_DENIED:'permission-denied',FEATURE_DISABLED:'failed-precondition',
  PLAYER_NOT_FOUND:'not-found',MAIL_UNAVAILABLE:'not-found',REVISION_CONFLICT:'aborted',OWNERSHIP_LOST:'failed-precondition',
  WALLET_FULL:'failed-precondition',STOCK_FULL:'failed-precondition',PROTOCOL_CHANGED:'failed-precondition',
  INVALID_ISSUE:'invalid-argument',INVALID_UID:'invalid-argument',INVALID_CLAIM:'invalid-argument',INVALID_CURSOR:'invalid-argument'};
const call=method=>onCall({maxInstances:4},async request=>{
  try{return await service[method]({auth:request.auth},...(Array.isArray(request.data)?request.data:[request.data]));}
  catch(e){throw new HttpsError(codes[e.code]||'internal',e.message||'Support mail failed.',{code:e.code||'INTERNAL'});}
});
export const supportCapabilities=call('capabilities');
export const lookupPlayerForSupport=call('lookup');
export const previewSupportMail=call('previewMail');
export const issueSupportMail=call('issueMail');
export const listMyMail=call('listMyMail');
export const claimSupportMail=call('claimMail');
// Keep ordinary protected saves available while new grants are disabled.
export const commitProtectedSave=call('commitProtectedSave');
