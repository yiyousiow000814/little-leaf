'use strict';
const {sourcePath,resourceName}=require('./source_paths.js');
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
function verifySource(web, source, expectedBuiltCommit) {
  const git = (...args) => cp.execFileSync('git', args, {cwd: source, encoding: 'utf8'}).trim();
  assert.equal(git('status', '--porcelain', '--untracked-files=no'), '', 'Clean tracked candidate source required');
  const commit = git('rev-parse', 'HEAD');
  const names = git('ls-files', '-z').split('\0').map(resourceName).filter(name =>
    ['project.godot', 'main.tscn', 'export_presets.cfg'].includes(name) ||
    ['assets', 'data', 'scripts', 'shaders', 'web'].includes(name.split('/')[0]));
  const production = Object.fromEntries(names.map(name => [name, hash(fs.readFileSync(sourcePath(source,name)))]));
  const builtCommit = expectedBuiltCommit || JSON.parse(fs.readFileSync(path.join(web, 'release-manifest.json'))).source_commit;
  assert(/^[0-9a-f]{40}$/.test(builtCommit), 'Export must identify its exact source commit');
  let builtTree;
  try { builtTree = git('rev-parse', builtCommit + '^{tree}'); }
  catch { assert.fail('Export must match a known exact source commit'); }
  const checkoutTree = git('rev-parse', 'HEAD^{tree}');
  assert.equal(builtTree, checkoutTree, 'Built and requested source trees must be identical');
  const manifest = verifyExport(web, builtCommit, production);
  assert.deepEqual(manifest.production_sha256, production, 'Complete export source map must match candidate');
  assert(production[SERVICE_MP3], 'Service MP3 must be bound by complete source manifest');
  return {manifest, source_commit: commit, built_source_commit: builtCommit, source_tree: checkoutTree, manifest_sha256: hash(fs.readFileSync(path.join(web, 'release-manifest.json'))),
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
function gestureTime(raw, gesture) {
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
  assert(Number.isFinite(raw.firstVisible) && event.at >= raw.firstVisible && event.at - raw.firstVisible < 1000,
    'First gesture must occur while the initial welcome is visible');
  return event.at;
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
  const raw = trial.raw, at = gestureTime(raw, trial.gesture);
  assert.deepEqual(raw.errors, [], 'Observer must not have errors');
  assert.deepEqual(raw.disconnects, [], 'Tapped destination route must remain stable');
  assert(raw.contexts.length > 0 && raw.taps.length > 0, 'Actual WebAudio contexts and destination-bound output required');
  assert.equal(raw.taps.length, 1, 'One summed destination context required; cross-context output is inconclusive');
  const contextIds = new Set(raw.taps.map(tap => tap.context));
  for (const id of contextIds) {
    const states = raw.contexts.find(context => context.id === id)?.states || [];
    assert(states.length > 0 && states[0].state === 'suspended', 'Fresh-origin context must begin suspended');
    assert(!states.some(row => row.state === 'running' && row.at < at), 'Audio must not unlock before the ordinary gesture');
    assert(states.some(row => row.state === 'running' && row.at >= at && row.at <= at + 2200), 'AudioContext must run after first gesture');
  }
  const before = raw.samples.filter(row => row.at < at && row.at >= raw.firstVisible);
  assert(before.length > 0, 'Need sampled pre-gesture baseline');
  assert(before.every(row => row.acRms <= QUIET_CEILING), 'No pre-gesture signal');
  const after = raw.samples.filter(row => row.at >= at + 50 && row.at <= at + 2200);
  assert(after.length >= 20, 'Enough observed output samples required');
  assert(after.every(row => [row.at, row.acRms, row.rms, row.peak, row.audioTime].every(Number.isFinite)), 'Finite output observations required');
  const activeFrames = raw.frames.filter(t => t >= raw.firstVisible && t <= at + 2500);
  assert(activeFrames.length > 20, 'Need real rendered frame observations');
  assert(activeFrames.slice(1).every((t, i) => t - activeFrames[i] < 250), 'Stall makes intro timing ambiguous');
  const early = trial.screenshots.find(row => row.name === 'early-welcome');
  assert(early && early.before >= at && early.after <= at + 2500, 'Early screenshot must precede normal 5.5-second descent completion');
  const signal = sustainedSignal(after, at, early.before);
  if (trial.mode === 'enabled') assert(signal, 'Sustained BGM-correlated output required before the early welcome screenshot');
  else {
    requireRunningControl(raw, after, at + 50, at + 2200);
    assert(after.every(row => row.acRms <= QUIET_CEILING), 'Muted control must remain silent with the same running audio graph');
  }
  return {gesture_at: at, gesture_after_visible_ms: at - raw.firstVisible,
    signal, peak_ac_rms: Math.max(...after.map(row => row.acRms)), sample_count: after.length};
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
  return results;
}
module.exports = {PLAYWRIGHT_VERSION, SERVICE_MP3, PREFERENCE_KEY, MODES, GESTURES,
  SIGNAL_FLOOR, QUIET_CEILING, preferences, verifySource, launchOptions, verifyBrowserArguments,
  gestureTime, sustainedSignal, analyzeTrial, compareTrials};
