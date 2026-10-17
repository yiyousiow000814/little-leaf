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
const stored = structuredClone(baseline);
stored.version = 17; stored.storage_format = 'little_leaf.storage.v1';
stored.storage = {items: [{id: stored.next_item_id++, kind: 'plant', x: 0, z: 0, rot: 2, paid_cost: 45}], dining_sets: []};
ok(modern.parsePayload(JSON.stringify(stored), 15).storage.items[0].paid_cost === 45, 'owned v17 keeps purchase basis and stored identity');
ok(modern.buildingPayload(JSON.stringify(stored), 15).generation === modern.buildingPayload(JSON.stringify(baseline), 15).generation, 'Storage uses the same building profile');
rejects(old, stored, 15, 'old reader cannot discard Storage');
rejects(modern, stored, 13, 'legacy import cannot consume Storage');
const storedHeld = structuredClone(stored);
storedHeld.layout_hold_format = held.layout_hold_format;
storedHeld.runtime.layout_hold_format = held.layout_hold_format;
storedHeld.runtime.service.layout_hold = structuredClone(held.runtime.service.layout_hold);
storedHeld.runtime.service.version = 6;
ok(modern.parsePayload(JSON.stringify(storedHeld), 15).runtime.service.version === 6, 'Storage preserves current service-v6 and matching held-work markers');
for (const mutate of [d => delete d.storage, d => d.storage_format = 'future', d => d.version = 15,
  d => d.storage.items.push(structuredClone(d.items[0])), d => d.next_item_id--,
  d => d.storage.items[0].kind = 'future_item', d => d.storage.items[0].paid_cost = -1,
  d => d.storage.items[0].paid_cost = 1.5, d => d.storage.items[0].extra = true,
  d => d.storage.items[0].rot = 4, d => d.storage.items[0].x = 18,
  d => d.storage.dining_sets.push({}), d => d.storage.extra = []]) {
  const broken = structuredClone(stored); mutate(broken); rejects(modern, broken, 15, 'malformed owned records fail closed');
}
for (const mutate of [d => delete d.layout_hold_format, d => delete d.runtime.layout_hold_format,
  d => delete d.runtime.service.layout_hold, d => d.runtime.service.layout_hold = []]) {
  const broken = structuredClone(storedHeld); mutate(broken); rejects(modern, broken, 15, 'v17 cannot hide mismatched held work');
}
for (const shell of ['little_leaf_shell.html', 'little_leaf_crazygames_shell.html'])
  ok(fs.readFileSync('platform/web/' + shell, 'utf8').includes(current), shell + ' embeds the exact authority codec');
console.log('LAYOUT_HOLD_BROWSER_CODEC_RESULT', JSON.stringify({checks, failures: [], original_player_save_used: false, browser_verified: false}));
