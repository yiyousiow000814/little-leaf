'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {hash, verifyExport} = require('./wall_compatibility_helpers');
const PLAYWRIGHT_VERSION = '1.63.0';
const SERVICE_MP3 = 'assets/audio/小叶食堂_门口的阳光_日常营业.mp3';
const PREFERENCE_KEY = 'little-leaf.preferences.v1';
const MODES = ['enabled', 'disabled', 'zero'];
const GESTURES = ['click', 'touch', 'Enter'];
const SIGNAL_FLOOR = 1e-4, QUIET_CEILING = 1e-5, RATIO = 10;
function preferences(mode) {
  assert(MODES.includes(mode));
  return {format: 1, text: '[audio]\nbgm_enabled=' + (mode !== 'disabled') +
    '\nsfx_enabled=false\nbgm_volume=' + (mode === 'zero' ? 0 : 70) + '\nsfx_volume=0\n'};
}
function verifySource(web, source) {
  const git = (...args) => cp.execFileSync('git', args, {cwd: source, encoding: 'utf8'}).trim();
  assert.equal(git('status', '--porcelain', '--untracked-files=no'), '', 'Clean tracked candidate source required');
  const commit = git('rev-parse', 'HEAD');
  const names = git('ls-files', '-z').split('\0').filter(name =>
    ['project.godot', 'main.tscn', 'export_presets.cfg'].includes(name) ||
    ['assets', 'data', 'scripts', 'shaders', 'web'].includes(name.split('/')[0]));
  const production = Object.fromEntries(names.map(name => [name, hash(fs.readFileSync(path.join(source, name)))]));
  const manifest = verifyExport(web, commit, production);
  assert.deepEqual(manifest.production_sha256, production, 'Complete export source map must match candidate');
  // This QA gate targets the first-gesture descent contract, never old tap-to-skip.
  const intro = fs.readFileSync(path.join(source, 'scripts/cafe_intro.gd'), 'utf8');
  for (const text of ['const DURATION = 6.5', 'const DESCENT_START = 1.0',
    'var entry_requested = false', 'elapsed = maxf(elapsed, DESCENT_START)', 'if entry_requested:finish()']) {
    assert(intro.includes(text), 'Candidate lacks the reviewed first-gesture contract: ' + text);
  }
  assert(production[SERVICE_MP3], 'Service MP3 must be bound by complete source manifest');
  return {manifest, source_commit: commit, manifest_sha256: hash(fs.readFileSync(path.join(web, 'release-manifest.json'))),
    service_mp3: {path: SERVICE_MP3, sha256: production[SERVICE_MP3], stream_identity: 'unproven: no decoded reference matching'}};
}
function launchOptions() {
  // Bundled Chromium revision is pinned by Playwright; no system Chrome fallback.
  return {headless: false, chromiumSandbox: true, ignoreDefaultArgs: ['--mute-audio']};
}
function verifyBrowserArguments(args) {
  assert(Array.isArray(args) && args.length > 0, 'Actual Chromium command line required');
  assert(!args.some(arg => /--(?:no-sandbox|disable-setuid-sandbox|mute-audio)(?:=|$)/.test(arg)), 'Unmuted sandboxed browser required');
  assert(!args.some(arg => /autoplay|media-engagement/i.test(arg)), 'No autoplay policy or engagement override permitted');
}
function primaryGestureTime(raw, gesture) {
  const type = gesture === 'Enter' ? 'keydown' : gesture === 'touch' ? 'touchstart' : 'mousedown';
  const candidates = raw.events.filter(event => event.type === type && (gesture !== 'Enter' || event.key === 'Enter'));
  assert.equal(candidates.length, 1, 'Exactly one ordinary primary gesture required');
  const event = candidates[0];
  assert(event.trusted && !event.repeat, 'Trusted first gesture required');
  // Touch activates on release in Chromium; touchstart need not be active.
  const activation = gesture === 'touch' ? raw.events.find(item => item.type === 'touchend' && item.at >= event.at) : event;
  assert(activation?.trusted && activation.active === true && activation.at - event.at < 500,
    'Trusted active gesture completion required');
  assert.equal(raw.events.filter(item => ['keydown', 'mousedown', 'touchstart'].includes(item.type) && item.at < event.at).length, 0,
    'No earlier primary input may unlock audio');
  return event.at;
}
function gestureTime(raw, gesture) {
  const at = primaryGestureTime(raw, gesture);
  assert(Number.isFinite(raw.firstVisible) && at >= raw.firstVisible && at - raw.firstVisible < 1000,
    'First gesture must occur while the initial welcome is visible');
  return at;
}
function visualGestureTime(raw, gesture) {
  const at = primaryGestureTime(raw, gesture);
  assert(Number.isFinite(raw.firstVisible) && at >= raw.firstVisible, 'Visual-only input must follow actual first visibility');
  return at;
}
function classifyActivation(raw, at) {
  const unresolved = reason => ({path: 'unresolved', reason});
  if (raw.contexts.length !== 1 || raw.taps.length !== 1 || raw.contexts[0].id !== raw.taps[0].context)
    return unresolved('Mixed or missing context identity');
  const states = raw.contexts[0].states;
  if (!states.length || !states.every((row, i) => Number.isFinite(row.at) &&
      ['suspended', 'running', 'closed'].includes(row.state) && (i === 0 || row.at >= states[i - 1].at)))
    return unresolved('Context history must have ordered finite timestamps and known states');
  const before = raw.samples.filter(row => row.at >= raw.firstVisible && row.at < at);
  if (!before.length) return unresolved('Missing pre-gesture baseline');
  if (states.some(row => row.state === 'closed' && row.at <= at + 2200))
    return unresolved('Closed context cannot establish an activation path');
  const priorRunning = states.some(row => row.state === 'running' && row.at < at);
  const runningSamples = before.some(row => row.state === 'running');
  if (priorRunning || runningSamples) {
    if (!priorRunning || !runningSamples || before.some(row => row.state !== 'running' ||
        states.filter(state => state.at <= row.at).at(-1)?.state !== 'running') ||
        states.filter(row => row.at >= before[0].at && row.at < at).some(row => row.state !== 'running'))
      return unresolved('Mixed or contradictory pre-gesture context observations');
    return {path: 'default-autoplay-allowed', reason: 'Context state and output samples were running before the sole trusted input; no unlock claim'};
  }
  if (states[0].state !== 'suspended' || before.some(row => row.state !== 'suspended'))
    return unresolved('No consistent suspended pre-gesture context');
  if (!states.some(row => row.state === 'running' && row.at >= at && row.at <= at + 2200))
    return unresolved('Context did not run after first gesture within the measurement window');
  return {path: 'gesture-unlocked', reason: 'Initially suspended, no earlier running context, running transition after trusted input; quiet baseline and signal still required'};
}

function sustainedSignal(samples, start, end, floor = SIGNAL_FLOOR) {
  const byTap = new Map();
  for (const sample of samples) {
    if (sample.at < start || sample.at > end) continue;
    if (!byTap.has(sample.tap)) byTap.set(sample.tap, []);
    byTap.get(sample.tap).push(sample);
  }
  for (const rows of byTap.values()) {
    let first = null, previous = null;
    for (const sample of rows) {
      if (sample.state !== 'running' || sample.acRms < floor || !Number.isFinite(sample.acRms)) { first = previous = null; continue; }
      if (!previous || sample.at - previous.at > 100 || sample.audioTime <= previous.audioTime) first = sample;
      previous = sample;
      if (sample.at - first.at >= 200) return {onset: first.at, confirmed: sample.at, tap: sample.tap};
    }
  }
  return null;
}
function requireRunningControl(raw, samples, start, end) {
  // Quiet data is a valid control only while its actual output clock runs.
  // Bound the entire measurement window, not just an earlier state transition.
  assert(samples.every(row => row.state === 'running'), 'Silent control samples must all be running');
  assert(samples[0].at - start <= 100 && end - samples.at(-1).at <= 100,
    'Silent control samples must cover both measurement-window edges within 100 ms');
  for (let i = 1; i < samples.length; i++) {
    const previous = samples[i - 1], current = samples[i];
    assert(current.at > previous.at && current.at - previous.at <= 100,
      'Silent control observation gaps must be positive and at most 100 ms');
    assert(current.audioTime > previous.audioTime, 'Silent control audio clock must advance at every observation');
  }
  const states = raw.contexts.find(context => context.id === raw.taps[0].context).states;
  assert(states.every((row, i) => Number.isFinite(row.at) && (i === 0 || row.at >= states[i - 1].at)),
    'Silent control context history must have ordered finite timestamps');
  assert(states.filter(row => row.at <= start).at(-1)?.state === 'running',
    'Silent control context must be running at the measurement-window start');
  assert(states.filter(row => row.at > start && row.at <= end).every(row => row.state === 'running'),
    'Silent control context must remain running throughout the measurement window');
}
function analyzeTrial(trial) {
  assert.equal(trial.profile_kind, 'audio-measurement', 'Only measurement profiles can establish audio acceptance');
  const raw = trial.raw, at = gestureTime(raw, trial.gesture);
  assert.deepEqual(raw.errors, [], 'Observer must not have errors');
  assert.deepEqual(raw.disconnects, [], 'Tapped destination route must remain stable');
  assert(raw.contexts.length > 0 && raw.taps.length > 0, 'Actual WebAudio contexts and destination-bound output required');
  assert.equal(raw.taps.length, 1, 'One summed destination context required; cross-context output is inconclusive');
  const before = raw.samples.filter(row => row.at < at && row.at >= raw.firstVisible);
  assert(before.length > 0, 'Need sampled pre-gesture baseline');
  assert(before.every(row => [row.at, row.acRms, row.audioTime].every(Number.isFinite)), 'Finite pre-gesture observations required');
  const activation = classifyActivation(raw, at);
  assert.notEqual(activation.path, 'unresolved', 'Activation unresolved: ' + activation.reason);
  if (activation.path === 'gesture-unlocked') assert(before.every(row => row.acRms <= QUIET_CEILING), 'No pre-gesture signal on gesture-unlocked path');
  else if (trial.mode !== 'enabled') assert(before.every(row => row.acRms <= QUIET_CEILING), 'Autoplay-allowed silent control must remain quiet before input');
  const after = raw.samples.filter(row => row.at >= at + 50 && row.at <= at + 2200);
  assert(after.length >= 20, 'Enough observed output samples required');
  assert(after.every(row => [row.at, row.acRms, row.rms, row.peak, row.audioTime].every(Number.isFinite)), 'Finite output observations required');
  const activeFrames = raw.frames.filter(t => t >= raw.firstVisible && t <= at + 2500);
  assert(activeFrames.length > 20, 'Need real rendered frame observations');
  assert(activeFrames.slice(1).every((t, i) => t - activeFrames[i] < 250), 'Stall makes intro timing ambiguous');
  const early = trial.early_audio_observation;
  assert(early?.kind === 'nonvisual-audio-observation' && Number.isFinite(early.at) && early.at >= at && early.at <= at + 2500,
    'Early nonvisual observation must precede normal 5.5-second descent completion');
  const signal = sustainedSignal(after, at, early.at);
  if (trial.mode === 'enabled') assert(signal, 'Sustained BGM-correlated output required before the early nonvisual observation');
  else {
    requireRunningControl(raw, after, at + 50, at + 2200);
    assert(after.every(row => row.acRms <= QUIET_CEILING), 'Muted control must remain silent with the same running audio graph');
  }
  return {gesture_at: at, gesture_after_visible_ms: at - raw.firstVisible,
    activation, signal, peak_ac_rms: Math.max(...after.map(row => row.acRms)), sample_count: after.length};
}
function compareTrials(trials) {
  const results = [];
  for (const gesture of GESTURES) {
    const group = {};
    for (const mode of MODES) {
      const matching = trials.filter(trial => trial.gesture === gesture && trial.mode === mode);
      assert.equal(matching.length, 1, 'One independent control per gesture/mode required');
      group[mode] = analyzeTrial(matching[0]);
    }
    const control = Math.max(group.disabled.peak_ac_rms, group.zero.peak_ac_rms, QUIET_CEILING);
    assert(group.enabled.peak_ac_rms >= control * RATIO, 'Enabled output must exceed both isolated controls by at least 20 dB');
    results.push({gesture, modes: group, contrast_ratio: group.enabled.peak_ac_rms / control});
  }
  const paths = new Set(results.flatMap(row => Object.values(row.modes).map(mode => mode.activation.path)));
  assert.equal(paths.size, 1, 'Mixed activation paths are inconclusive; retain the per-case evidence without a combined pass');
  return results;
}
function activationCoverage(comparisons) {
  const paths = new Set(comparisons.flatMap(row => Object.values(row.modes).map(mode => mode.activation.path)));
  assert.equal(comparisons.length, GESTURES.length, 'Complete gesture comparisons required');
  assert.equal(paths.size, 1, 'Mixed activation paths cannot earn a combined pass');
  const path = [...paths][0];
  assert(['gesture-unlocked', 'default-autoplay-allowed'].includes(path), 'Unresolved activation cannot pass');
  return {observed_path: path,
    gesture_unlocked_path: path === 'gesture-unlocked' ? 'verified' : 'unverified-not-exercised',
    default_autoplay_path: path === 'default-autoplay-allowed' ? 'verified' : 'unverified-not-exercised'};
}
module.exports = {PLAYWRIGHT_VERSION, SERVICE_MP3, PREFERENCE_KEY, MODES, GESTURES,
  SIGNAL_FLOOR, QUIET_CEILING, preferences, verifySource, launchOptions, verifyBrowserArguments,
  gestureTime, visualGestureTime, classifyActivation, activationCoverage, sustainedSignal, analyzeTrial, compareTrials};
