'use strict';
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {capturePhases, captureReadyBaseline} = require('./welcome_audio_capture');
const {gestureTime} = require('./welcome_audio_helpers');
let checks = 0;
async function test(name, fn) {await fn(); checks++; console.log('ok ' + name);}
function harness(profile_kind = 'audio-measurement', options = {}) {
  let clock = options.start ?? 1200;
  const trial = {profile_kind, mode: options.mode || 'disabled', gesture: options.gesture || 'click', screenshots: []};
  const calls = [], raw = {firstVisible: 1000, events: [], samples: []};
  const io = {
    now: async () => clock,
    wait: async ms => {
      const until = clock + ms;
      while (clock < until) {
        clock = Math.min(clock + 20, until);
        raw.samples.push({tap: 0, at: clock, audioTime: clock / 1000, state: 'running', acRms: trial.mode === 'enabled' ? 0.01 : 0});
      }
    },
    read: async () => structuredClone(raw),
    press: async gesture => {
      calls.push({kind: 'input', at: clock});
      raw.events.push({type: gesture === 'Enter' ? 'keydown' : gesture === 'touch' ? 'touchstart' : 'mousedown',
        key: gesture === 'Enter' ? 'Enter' : null, at: clock, trusted: true, active: gesture !== 'touch', repeat: false});
      if (gesture === 'touch') raw.events.push({type: 'touchend', at: clock, trusted: true, active: true});
    },
    shot: async name => {
      const before = clock; clock += options.shotCost ?? 871;
      calls.push({kind: 'shot', name, at: before});
      trial.screenshots.push({profile_kind, name, before, after: clock});
      if (options.mislabel && name === 'early-welcome') trial.screenshots[0].after = clock;
    },
    stopAndRead: async () => {calls.push({kind: 'stop', at: clock}); return {...structuredClone(raw), stoppedAt: options.badStop ? clock - 1 : clock};},
  };
  return {trial, calls, io};
}
async function main() {
  await test('initial boot snapshot remains genuinely pre-input after later autosave', () => {
    const raw = {firstVisible: 1000, samples: [{at: 1100}]};
    const sandbox = {window: {__welcomeAudioQA: raw, __littleLeafVault: {bootJson: JSON.stringify({source: 'fresh', payload: null})}}, performance: {now: () => 1150}};
    const call = () => vm.runInNewContext('(' + captureReadyBaseline.toString() + ')()', sandbox);
    assert.equal(call(), true); assert.equal(raw.initial_boot_snapshot.at, 1150);
    sandbox.window.__littleLeafVault.bootJson = JSON.stringify({source: 'authority', payload: 'autosave'});
    assert.equal(call(), true); assert.equal(raw.initial_boot_snapshot.value.source, 'fresh');
    assert.equal(raw.initial_boot_snapshot.value.payload, null);
  });
  await test('readiness needs a visible sampled baseline before taking initial boot evidence', () => {
    const raw = {firstVisible: null, samples: []};
    const sandbox = {window: {__welcomeAudioQA: raw}, performance: {now: () => 1150}};
    const call = () => vm.runInNewContext('(' + captureReadyBaseline.toString() + ')()', sandbox);
    assert.equal(call(), false); raw.firstVisible = 1000; assert.equal(call(), false);
    assert.equal(raw.initial_boot_snapshot, undefined);
  });
  for (const gesture of ['click', 'touch', 'Enter']) {
    await test(gesture + ' slow screenshots cannot delay measured first gesture or interrupt guarded window', async () => {
      const {trial, calls, io} = harness('audio-measurement', {gesture}); await capturePhases(trial, io);
      assert.equal(gestureTime(trial.raw, gesture), 1200);
      assert.deepEqual(calls.map(row => row.kind), ['input', 'stop', 'shot', 'shot']);
      assert.equal(calls[1].at, 3700);
      assert.deepEqual(trial.screenshots.map(row => row.name), ['during-descent', 'after-normal-descent']);
      assert(trial.screenshots.every(row => row.before > trial.raw.stoppedAt));
      assert.equal(trial.screenshots[0].before, 4200); assert.equal(trial.screenshots[1].before, 7700);
      assert.deepEqual(trial.early_audio_observation, {kind: 'nonvisual-audio-observation', at: 1900});
    });
  }
  await test('enabled signal polling remains screenshot-free through full measurement', async () => {
    const {trial, calls, io} = harness('audio-measurement', {mode: 'enabled'}); await capturePhases(trial, io);
    assert(trial.early_audio_observation.at < 3400);
    assert.equal(calls[1].kind, 'stop'); assert.equal(calls[1].at, 3700);
  });
  await test('separate visual profile keeps true pre-input and early-image phases', async () => {
    const {trial, calls, io} = harness('visual-only'); await capturePhases(trial, io);
    assert.deepEqual(calls.map(row => row.kind), ['shot', 'input', 'shot', 'stop']);
    assert.equal(trial.phase_timestamps.gesture, 2071);
    assert.equal(trial.screenshots[0].after, 2071);
    assert.equal(trial.screenshots[1].before, 2071); assert.equal(trial.screenshots[1].after, 2942);
    assert(trial.screenshots.every(row => row.profile_kind === 'visual-only'));
    assert.equal(trial.early_audio_observation, undefined);
    assert.throws(() => gestureTime(trial.raw, 'click'), /initial welcome/);
  });
  await test('unknown profile kind is rejected before input', async () => {
    const {trial, calls, io} = harness('unknown'); await assert.rejects(capturePhases(trial, io), /profile kind/); assert.equal(calls.length, 0);
  });
  await test('measured late input still fails the original one-second deadline', async () => {
    const {trial, io} = harness('audio-measurement', {start: 2000}); await assert.rejects(capturePhases(trial, io), /initial welcome/);
  });
  await test('post-input image cannot be relabeled pre-input', async () => {
    const {trial, io} = harness('visual-only', {mislabel: true}); await assert.rejects(capturePhases(trial, io), /actually finish before input/);
  });
  await test('visual-only early screenshot still fails after 2.5 seconds', async () => {
    const {trial, io} = harness('visual-only', {shotCost: 2501}); await assert.rejects(capturePhases(trial, io), /unchanged 2.5-second/);
  });
  await test('premature measurement stop cannot pass', async () => {
    const {trial, io} = harness('audio-measurement', {badStop: true}); await assert.rejects(capturePhases(trial, io), /complete guarded interval/);
  });
  console.log('Welcome audio capture offline checks: ' + checks);
}
main().catch(error => {console.error(error); process.exitCode = 1;});
