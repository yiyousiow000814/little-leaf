// Pinned Firebase WebChannel's connectivity image is deliberately failed locally.
// This does not permit a request to Google or fake successful connectivity.
export function isConnectivityProbe(value,resourceType){
  const url=new URL(value);
  return ['http:','https:'].includes(url.protocol) && url.hostname==='www.google.com'
    && url.pathname==='/images/cleardot.gif' && resourceType==='image';
}
