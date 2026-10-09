'use strict';
const assert = require('node:assert/strict');
const {gestureTime, visualGestureTime, sustainedSignal} = require('./welcome_audio_helpers');
// Runs within the existing browser readiness callback, adding no driver round
// trip before input. bootJson later changes on normal autosave, so retain the
// actual pre-input snapshot rather than relabeling a later authority read.
function captureReadyBaseline() {
  const raw = window.__welcomeAudioQA;
  if (!raw || raw.firstVisible === null || !raw.samples.some(row => row.at >= raw.firstVisible)) return false;
  if (!raw.initial_boot_snapshot) raw.initial_boot_snapshot = {
    at: performance.now(), value: JSON.parse(window.__littleLeafVault.bootJson),
  };
  return true;
}
// Dependencies are ordinary input/read/wait/screenshot operations. Offline tests
// inject clocks and slow screenshots to prove the ordering without a browser.
async function capturePhases(trial, io) {
  const visual = trial.profile_kind === 'visual-only';
  assert(visual || trial.profile_kind === 'audio-measurement', 'Explicit independent profile kind required');
  trial.phase_timestamps = {};
  const waitUntil = async time => {const now = await io.now(); if (time > now) await io.wait(time - now);};
  if (visual) await io.shot('before-gesture');
  await io.press(trial.gesture);
  const inputRaw = await io.read();
  const at = visual ? visualGestureTime(inputRaw, trial.gesture) : gestureTime(inputRaw, trial.gesture);
  trial.phase_timestamps.first_visible = inputRaw.firstVisible;
  trial.phase_timestamps.gesture = at;
  if (visual) {
    await io.shot('early-welcome');
    const early = trial.screenshots.find(row => row.name === 'early-welcome');
    const before = trial.screenshots.find(row => row.name === 'before-gesture');
    assert(before?.after <= at, 'A pre-gesture image must actually finish before input');
    assert(early?.before >= at && early.after <= at + 2500, 'Visual-only early image must finish within the unchanged 2.5-second post-input deadline');
    trial.raw = await io.stopAndRead();
    trial.phase_timestamps.observation_stopped = trial.raw.stoppedAt;
    return;
  }
  if (trial.mode === 'enabled') {
    let raw;
    do {
      await io.wait(25); raw = await io.read();
      if (sustainedSignal(raw.samples, at + 50, at + 2200)) break;
    } while (await io.now() < at + 2200);
  } else await io.wait(700);
  trial.early_audio_observation = {kind: 'nonvisual-audio-observation', at: await io.now()};
  await waitUntil(at + 2500);
  trial.raw = await io.stopAndRead();
  trial.phase_timestamps.observation_stopped = trial.raw.stoppedAt;
  assert(trial.raw.stoppedAt >= at + 2500, 'Measurement must cover its complete guarded interval');
  await waitUntil(at + 3000); await io.shot('during-descent');
  await waitUntil(at + 6500); await io.shot('after-normal-descent');
}
module.exports = {capturePhases, captureReadyBaseline};
