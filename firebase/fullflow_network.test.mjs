import assert from 'node:assert/strict';
import {isConnectivityProbe} from './fullflow_network.mjs';
assert(isConnectivityProbe('https://www.google.com/images/cleardot.gif?zx=synthetic','image'));
assert(isConnectivityProbe('http://www.google.com/images/cleardot.gif','image'));
for(const [url,type] of [['https://www.google.com/images/cleardot.gif','script'],['https://www.google.com/accounts','image'],['https://www.google.com.evil.test/images/cleardot.gif','image'],['https://accounts.google.com/images/cleardot.gif','image']])assert(!isConnectivityProbe(url,type));
console.log('Offline network fixture: only exact SDK connectivity image is locally aborted; no external request allowed.');
