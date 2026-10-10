'use strict';
// Actual session protocol counterexamples; synthetic remote, no Firebase I/O.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const path = require('node:path');
const read = name => fs.readFileSync(path.join(__dirname, '..', name), 'utf8');
const context = { crypto: webcrypto };
vm.runInNewContext(read('web/little_leaf_firebase_session.js'), context);
async function run() {
  let time = 1000, state = null;
  const watchers = new Set();
  const remote = {
    async change(transition, guard) { guard(); state = transition(state, null, () => time); return state; },
    async read() { return state; },
    watch(receive) { watchers.add(receive); return () => watchers.delete(receive); }
  };
  const owner = context.LittleLeafFirebaseSession.createSession({ remote, uid: 'synthetic', currentUid: () => 'synthetic', now: () => time });
  await owner.start();
  const epoch = state.epoch, leaseAt = state.updatedAt;
  time += 120000;
  assert.equal(owner.snapshot().status, 'active', 'cached active can outlive authority');
  await owner.renew();
  assert.equal(state.epoch, epoch, 'successful renewal does not expose the expired gap');
  assert(state.updatedAt > leaseAt + context.LittleLeafFirebaseSession.LEASE_MS);
  const other = context.LittleLeafFirebaseSession.createSession({ remote, uid: 'synthetic', currentUid: () => 'synthetic', now: () => time });
  await other.start(); await other.requestTakeover();
  const renewedAt = state.updatedAt;
  time += 10001;
  await other.takeOver(true);
  assert(time < renewedAt + context.LittleLeafFirebaseSession.LEASE_MS, 'takeover is allowed inside the lease');
  for (const receive of watchers) receive(state);
  assert.equal(owner.snapshot().status, 'other-device');
  const policy = read('scripts/cafe_hidden_time_policy.gd');
  assert.match(policy, /static func catch_up_seconds\(\)->float:[\s\S]*return 0\.0/);
  assert.match(policy, /delta>MAX_CALLBACK_SECONDS/);
  const lifecycle = read('scripts/cafe_web_lifecycle.gd');
  assert.match(lifecycle, /reason=="hidden":game\.set_browser_hidden\(true\)/);
  assert.match(lifecycle, /reason=="pagehide":game\.set_browser_suspended\(true\)/);
  assert.match(read('scripts/main.gd'), /if world_delta>0\.0 and not editing and not paused and not save_recovery_blocked:/);
  console.log('Hidden authority: protocol expiry/renewal and early-force-takeover counterexamples plus source guards passed (synthetic; no engine economy claim).');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
