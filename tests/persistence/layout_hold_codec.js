'use strict';
// Generated snapshots, production browser codec, retained old-client codec.
// No browser storage, cloud account, SDK or original save is accessed.
const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm');
const current = fs.readFileSync('platform/web/little_leaf_vault.js', 'utf8');
const previous = fs.readFileSync('tests/fixtures/inbox-vault-018.js', 'utf8');
function codec(source) { const c = vm.createContext({TextEncoder}); vm.runInContext(source.includes('root.LittleLeafAuthorityCodec =') ? source : source.replace('root.LittleLeafVault = Object.freeze', 'root.LittleLeafAuthorityCodec = Object.freeze({parsePayload}); root.LittleLeafVault = Object.freeze'), c); return c.LittleLeafAuthorityCodec; }
const modern = codec(current), old = codec(previous);
const baseline = JSON.parse(fs.readFileSync('tests/fixtures/unified_building_candidate.json', 'utf8'));
const held = structuredClone(baseline);
held.version = 16; held.layout_hold_format = 'little_leaf.layout_hold.v1';
held.runtime.layout_hold_format = held.layout_hold_format;
held.runtime.service.layout_hold = {format: held.layout_hold_format, hosts: [], guests: [], staff: [], dishes: [], floor: []};
let checks = 0;
const ok = (value, label) => { assert(value, label); checks++; };
const rejects = (api, data, version, label) => { assert.throws(() => api.parsePayload(JSON.stringify(data), version), {code: 'INVALID_SAVE'}, label); checks++; };
ok(modern.parsePayload(JSON.stringify(baseline), 15).version === 15, 'ordinary v15 remains accepted');
ok(old.parsePayload(JSON.stringify(baseline), 15).version === 15, 'old reader fixture is functional');
ok(modern.parsePayload(JSON.stringify(held), 15).version === 16, 'modern profile preserves explicit v16');
ok(modern.buildingPayload(JSON.stringify(held), 15).generation === modern.buildingPayload(JSON.stringify(baseline), 15).generation, 'building authority accepts v16 without another profile');
rejects(old, held, 15, 'previous client rejects held save instead of dropping state');
rejects(modern, held, 13, 'legacy import cannot ingest held work');
for (const mutate of [d => delete d.layout_hold_format, d => delete d.runtime.layout_hold_format,
  d => delete d.runtime.service.layout_hold, d => d.runtime.service.layout_hold.format = 'future',
  d => d.runtime.service.layout_hold.guests = Array(61).fill({}), d => d.runtime.service.layout_hold.extra = [],
  d => d.runtime.service.layout_hold.staff = {}, d => d.version = 15, d => d.version = 17]) {
  const broken = structuredClone(held); mutate(broken); rejects(modern, broken, 15, 'reject malformed or disguised hold');
}
for (const shell of ['little_leaf_shell.html', 'little_leaf_crazygames_shell.html'])
  ok(fs.readFileSync('platform/web/' + shell, 'utf8').includes(current), shell + ' embeds the exact authority codec');
console.log('LAYOUT_HOLD_BROWSER_CODEC_RESULT', JSON.stringify({checks, failures: [], original_player_save_used: false, browser_verified: false}));
