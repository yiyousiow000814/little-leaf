'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const cp = require('node:child_process');
const {hash} = require('./wall_compatibility_helpers');
const {installWelcomeAudioObserver} = require('./welcome_audio_observer');
const {preferences, MODES, GESTURES, PREFERENCE_KEY, sustainedSignal, analyzeTrial, compareTrials,
  launchOptions, verifyBrowserArguments, verifySource, SERVICE_MP3} = require('./welcome_audio_helpers');
let checks = 0;
function test(name, fn) {fn(); checks++; console.log('ok ' + name);}
function fails(fn, message) {assert.throws(fn, message);}
function fixture(mode = 'enabled', gesture = 'click') {
  const at = 1200, type = gesture === 'Enter' ? 'keydown' : gesture === 'touch' ? 'touchstart' : 'mousedown';
  const samples = [];
  for (let time = 1000; time <= 8000; time += 20) samples.push({tap: 0, at: time,
    audioTime: Math.max(0, (time - at) / 1000), state: time < at ? 'suspended' : 'running',
    acRms: mode === 'enabled' && time > at ? 0.01 : 0, rms: 0.01, peak: 0.02});
  return {mode, gesture, screenshots: [{name: 'early-welcome', before: 1900, after: 2000}], raw: {
    firstVisible: 1000, errors: [], disconnects: [], taps: [{id: 0, context: 0}],
    contexts: [{id: 0, states: [{at: 900, state: 'suspended'}, {at, state: 'running'}]}],
    frames: Array.from({length: 450}, (_, i) => 1000 + i * 16.7), samples,
    events: [{type, key: gesture === 'Enter' ? 'Enter' : null, at, trusted: true, repeat: false, active: gesture !== 'touch'},
      ...(gesture === 'touch' ? [{type: 'touchend', at: at + 20, trusted: true, active: true}] : [])]}};
}
const suite = () => GESTURES.flatMap(gesture => MODES.map(mode => fixture(mode, gesture)));
async function preferenceTests() {
  for (const mode of MODES) {
    const store = new Map([[PREFERENCE_KEY, JSON.stringify(preferences(mode))]]);
    const sandbox = {localStorage: {getItem: key => store.get(key) ?? null, setItem: (key, value) => store.set(key, value)}, TextEncoder};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../web/little_leaf_preferences.js'), 'utf8'), sandbox);
    const result = await sandbox.__littleLeafPreferences.boot();
    assert(result.ok && result.source === 'preferences'); assert.equal(result.text, preferences(mode).text);
    assert.equal(sandbox.__littleLeafPreferences.acceptLoaded(), true);
    assert.equal(JSON.parse(store.get(PREFERENCE_KEY)).format, 1);
    assert(result.text.includes('sfx_enabled=false\n') && result.text.includes('sfx_volume=0\n'));
  }
}
test('unknown mode rejected', () => fails(() => preferences('bogus')));
test('launch keeps sandbox and default autoplay without mute', () => {
  assert.deepEqual(launchOptions(), {headless: false, chromiumSandbox: true, ignoreDefaultArgs: ['--mute-audio']});
  verifyBrowserArguments(['/pinned/chromium', '--enable-automation']);
  for (const flag of ['--no-sandbox', '--disable-setuid-sandbox', '--mute-audio', '--autoplay-policy=no-user-gesture-required', '--disable-features=AutoplayIgnoreWebAudio', '--media-engagement=high'])
    fails(() => verifyBrowserArguments(['/pinned/chromium', flag]));
});
test('isolated controls allow causal signal classification only', () => assert.equal(compareTrials(suite()).length, 3));
test('untrusted input rejected', () => {const row = fixture(); row.raw.events[0].trusted = false; fails(() => analyzeTrial(row), /Trusted/);});
test('unactivated input rejected', () => {const row = fixture(); row.raw.events[0].active = false; fails(() => analyzeTrial(row), /Trusted/);});
test('prior click before Enter rejected', () => {const row = fixture('enabled', 'Enter'); row.raw.events.unshift({type: 'mousedown', at: 1100}); fails(() => analyzeTrial(row), /earlier/);});
test('repeated first gesture rejected', () => {const row = fixture(); row.raw.events.push({...row.raw.events[0], at: 1300}); fails(() => analyzeTrial(row), /Exactly one/);});
test('late gesture rejected', () => {const row = fixture(); row.raw.events[0].at = 2100; fails(() => analyzeTrial(row), /initial welcome/);});
test('already running context rejected', () => {const row = fixture(); row.raw.contexts[0].states[0].state = 'running'; fails(() => analyzeTrial(row), /begin suspended/);});
test('early auto-resumption rejected', () => {const row = fixture(); row.raw.contexts[0].states[1].at = 1100; fails(() => analyzeTrial(row), /before/);});
test('missing context or output rejected', () => {const row = fixture(); row.raw.taps = []; fails(() => analyzeTrial(row), /destination-bound/);});
test('multiple independent output contexts are inconclusive', () => {const row = fixture(); row.raw.taps.push({id: 1, context: 1}); fails(() => analyzeTrial(row), /One summed/);});
test('running silent graph alone never passes', () => {const row = fixture(); row.raw.samples.forEach(x => x.acRms = 0); fails(() => analyzeTrial(row), /Sustained/);});
test('DC is not music evidence', () => {const row = fixture(); row.raw.samples.forEach(x => {x.rms = 0.1; x.acRms = 0;}); fails(() => analyzeTrial(row), /Sustained/);});
test('suspended data cannot masquerade as output', () => {const row = fixture(); row.raw.samples.forEach(x => x.state = 'suspended'); fails(() => analyzeTrial(row), /Sustained/);});
test('frozen audio clock rejected', () => {const row = fixture(); row.raw.samples.forEach(x => x.audioTime = 0); fails(() => analyzeTrial(row), /Sustained/);});
test('isolated spike rejected', () => {const row = fixture(); row.raw.samples.forEach(x => x.acRms = x.at === 1400 ? 0.2 : 0); fails(() => analyzeTrial(row), /Sustained/);});
test('multiple taps cannot stitch a sustained signal', () => {
  const rows = Array.from({length: 12}, (_, i) => ({tap: i % 2, at: i * 60, audioTime: i * 0.06, state: 'running', acRms: 0.1}));
  assert.equal(sustainedSignal(rows, 0, 1000), null);
});
test('nonfinite observation rejected', () => {const row = fixture(); row.raw.samples[20].acRms = NaN; fails(() => analyzeTrial(row), /Finite/);});
test('no pregesture baseline rejected', () => {const row = fixture(); row.raw.samples = row.raw.samples.filter(x => x.at >= 1200); fails(() => analyzeTrial(row), /baseline/);});
test('pregesture signal rejected', () => {const row = fixture(); row.raw.samples[0].acRms = 0.1; fails(() => analyzeTrial(row), /pre-gesture signal/);});
test('noise in disabled control rejected', () => {const rows = suite(); rows[1].raw.samples.filter(x => x.at > 1250).forEach(x => x.acRms = 0.002); fails(() => compareTrials(rows), /control.*silent/);});
test('noise in zero-volume control rejected', () => {const rows = suite(); rows[2].raw.samples.filter(x => x.at > 1250).forEach(x => x.acRms = 0.002); fails(() => compareTrials(rows), /control.*silent/);});
for (const mode of ['disabled', 'zero']) {
  const measured = row => row.raw.samples.filter(sample => sample.at >= 1250 && sample.at <= 3400);
  const keepMeasured = (row, predicate) => {
    row.raw.samples = row.raw.samples.filter(sample => sample.at < 1250 || sample.at > 3400 || predicate(sample));
  };
  test(mode + ' control rejects entirely suspended samples despite prior running transition', () => {
    const row = fixture(mode); measured(row).forEach(sample => sample.state = 'suspended');
    fails(() => analyzeTrial(row), /control samples must all be running/);
  });
  test(mode + ' control rejects one suspended measured sample', () => {
    const row = fixture(mode); measured(row)[30].state = 'suspended';
    fails(() => analyzeTrial(row), /control samples must all be running/);
  });
  test(mode + ' control rejects frozen audio clock', () => {
    const row = fixture(mode); measured(row).forEach(sample => sample.audioTime = 0.5);
    fails(() => analyzeTrial(row), /control audio clock must advance/);
  });
  test(mode + ' control rejects one frozen or backwards clock step', () => {
    for (const change of [0, -0.01]) {
      const row = fixture(mode), samples = measured(row); samples[30].audioTime = samples[29].audioTime + change;
      fails(() => analyzeTrial(row), /control audio clock must advance/);
    }
  });
  test(mode + ' control rejects fewer than twenty observations', () => {
    const row = fixture(mode); keepMeasured(row, sample => sample.at % 200 === 0);
    fails(() => analyzeTrial(row), /Enough observed output samples/);
  });
  test(mode + ' control rejects a large gap despite sufficient total samples', () => {
    const row = fixture(mode); keepMeasured(row, sample => sample.at < 1700 || sample.at > 2300);
    assert(measured(row).length >= 20); fails(() => analyzeTrial(row), /control observation gaps/);
  });
  test(mode + ' control rejects insufficient leading interval coverage', () => {
    const row = fixture(mode); keepMeasured(row, sample => sample.at >= 1500);
    assert(measured(row).length >= 20); fails(() => analyzeTrial(row), /cover both measurement-window edges/);
  });
  test(mode + ' control rejects insufficient trailing interval coverage', () => {
    const row = fixture(mode); keepMeasured(row, sample => sample.at <= 3200);
    assert(measured(row).length >= 20); fails(() => analyzeTrial(row), /cover both measurement-window edges/);
  });
  test(mode + ' control rejects duplicate or reversed wall-clock observations', () => {
    for (const change of [0, -1]) {
      const row = fixture(mode), samples = measured(row); samples[30].at = samples[29].at + change;
      fails(() => analyzeTrial(row), /control observation gaps/);
    }
  });
  test(mode + ' control rejects a suspension between apparently running samples', () => {
    const row = fixture(mode); row.raw.contexts[0].states.push({at: 1801, state: 'suspended'}, {at: 1819, state: 'running'});
    fails(() => analyzeTrial(row), /remain running throughout/);
  });
  test(mode + ' control rejects late resume despite running samples', () => {
    const row = fixture(mode); row.raw.contexts[0].states[1].at = 1300;
    fails(() => analyzeTrial(row), /running at the measurement-window start/);
  });
  test(mode + ' control rejects malformed or unordered context history', () => {
    for (const at of [NaN, 1900]) {
      const row = fixture(mode); row.raw.contexts[0].states.push({at: 2000, state: 'running'}, {at, state: 'running'});
      fails(() => analyzeTrial(row), /ordered finite timestamps/);
    }
  });
  test(mode + ' control accepts advancing observations at the existing 100-ms gap boundary', () => {
    const row = fixture(mode); keepMeasured(row, sample => sample.at % 100 === 0);
    assert(measured(row).length >= 20); analyzeTrial(row);
  });
}
test('missing control cannot imply causality', () => fails(() => compareTrials(suite().slice(1)), /independent control/));
test('destination disconnect invalidates samples', () => {const row = fixture(); row.raw.disconnects.push({at: 1500}); fails(() => analyzeTrial(row), /stable/);});
test('observer errors fail closed', () => {const row = fixture(); row.raw.errors.push('tap failed'); fails(() => analyzeTrial(row), /errors/);});
test('frame stall makes intro timing inconclusive', () => {const row = fixture(); row.raw.frames = row.raw.frames.filter(t => t < 1300 || t > 2500); fails(() => analyzeTrial(row), /Stall/);});
test('late evidence cannot prove welcome audio', () => {const row = fixture(); row.screenshots[0].after = 4000; fails(() => analyzeTrial(row), /Early screenshot/);});
test('signal after screenshot cannot prove welcome audio', () => {const row = fixture(); row.raw.samples.filter(x => x.at < 2000).forEach(x => x.acRms = 0); fails(() => analyzeTrial(row), /Sustained/);});
function mockBrowser() {
  let now = 0, timer, frame, resumeCalls = 0;
  const events = new Map(), connections = [];
  class AudioNode {
    constructor(context) {this.context = context;}
    connect(...args) {if (args[0] === 'throw') throw Error('original connect failure'); connections.push({source: this, args}); return args[0];}
    disconnect(...args) {if (args[0] === 'throw') throw Error('original disconnect failure');}
  }
  class AudioContext {
    constructor() {this.state = 'suspended'; this.currentTime = 0; this.sampleRate = 48000; this.destination = new AudioNode(this); this.destination.channelCount = 2; this.destination.channelInterpretation = 'speakers'; this.handlers = [];}
    addEventListener(type, fn) {this.handlers.push(fn);}
    resume() {resumeCalls++; this.state = 'running';}
    createAnalyser() {const analyser = new AudioNode(this); analyser.getFloatTimeDomainData = data => data.forEach((_, i) => data[i] = i % 2 ? 0.1 : -0.1); return analyser;}
  }
  const sandbox = {AudioNode, AudioContext, performance: {now: () => now}, navigator: {userActivation: {isActive: true}},
    document: {getElementById: () => now < 100 ? {} : null}, addEventListener: (type, fn) => events.set(type, fn),
    requestAnimationFrame: fn => {frame = fn;}, setInterval: fn => {timer = fn; return 1;}, clearInterval() {}, Float32Array};
  vm.runInNewContext('(' + installWelcomeAudioObserver.toString() + ')()', sandbox);
  return {sandbox, connections, events, setNow(value) {now = value;}, frame() {frame(now);}, tick() {timer();}, resumes: () => resumeCalls};
}
test('observer retains original graph destination and return value', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext(), node = new m.sandbox.AudioNode(context);
  assert.equal(node.connect(context.destination, 0, 0), context.destination);
  assert.equal(m.connections.length, 2); assert.equal(m.connections[0].args[0], context.destination);
  const analyser = m.connections[1].args[0]; assert.notEqual(analyser, context.destination);
  assert(!m.connections.some(row => row.source === analyser)); // no tap output connected
  assert.equal(m.resumes(), 0); assert.equal(context.state, 'suspended');
  node.connect(context.destination, 0); assert.equal(m.sandbox.__welcomeAudioQA.taps.length, 1);
});
test('destination routes share one summed analyser and do not add an output', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext();
  new m.sandbox.AudioNode(context).connect(context.destination);
  new m.sandbox.AudioNode(context).connect(context.destination);
  assert.equal(m.sandbox.__welcomeAudioQA.taps.length, 1);
  assert.equal(m.sandbox.__welcomeAudioQA.taps[0].routes.length, 2);
  assert.equal(m.connections[1].args[0], m.connections[3].args[0]);
  assert.equal(m.connections[1].args[0].channelCount, context.destination.channelCount);
  assert(!m.connections.some(row => row.source === m.connections[1].args[0]));
});
test('touchstart need not be activated but its trusted release must be', () => {
  const row = fixture('enabled', 'touch'); analyzeTrial(row);
  row.raw.events[1].active = false; fails(() => analyzeTrial(row), /completion/);
});
test('observer ignores non-destination connections', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext(), node = new m.sandbox.AudioNode(context);
  node.connect(new m.sandbox.AudioNode(context)); assert.equal(m.sandbox.__welcomeAudioQA.taps.length, 0);
});
test('observer propagates original connection failures', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext(), node = new m.sandbox.AudioNode(context);
  fails(() => node.connect('throw'), /original connect/); fails(() => node.disconnect('throw'), /original disconnect/);
});
test('observer records context states, raw output and trusted input without resuming', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext(), node = new m.sandbox.AudioNode(context);
  node.connect(context.destination); m.frame(); m.setNow(100); m.frame();
  m.events.get('mousedown')({isTrusted: true, target: {tagName: 'CANVAS'}});
  context.state = 'running'; context.currentTime = 0.5; context.handlers[0](); m.tick();
  const raw = m.sandbox.__welcomeAudioQA;
  assert.equal(raw.firstVisible, 100); assert.equal(raw.contexts[0].states.length, 2);
  assert.equal(raw.samples[0].state, 'running'); assert(Math.abs(raw.samples[0].acRms - 0.1) < 1e-6);
  assert.equal(raw.events[0].trusted, true); assert.equal(m.resumes(), 0);
  node.disconnect(context.destination); assert.equal(raw.disconnects.length, 1);
});
test('observer instrumentation failure does not alter original successful connect', () => {
  const m = mockBrowser(), context = new m.sandbox.AudioContext(), node = new m.sandbox.AudioNode(context);
  context.createAnalyser = () => {throw Error('analyser blocked');};
  assert.equal(node.connect(context.destination), context.destination); assert.equal(m.connections.length, 1);
  assert.equal(m.sandbox.__welcomeAudioQA.errors.length, 1);
});
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'welcome-audio-binding-'));
try {
  const source = path.join(temporary, 'source'), web = path.join(temporary, 'web');
  fs.mkdirSync(source); fs.mkdirSync(web);
  const git = (...args) => cp.execFileSync('git', ['-c', 'user.name=Offline QA', '-c', 'user.email=qa@example.invalid', ...args], {cwd: source, encoding: 'utf8'}).trim();
  git('init', '-q');
  const files = {
    'project.godot': 'synthetic project fixture', 'scripts/cafe_intro.gd': [
      'const DURATION = 6.5', 'const DESCENT_START = 1.0', 'var entry_requested = false',
      'elapsed = maxf(elapsed, DESCENT_START)', 'if entry_requested:finish()'].join('\n'),
    [SERVICE_MP3]: 'synthetic hash fixture, never real audio', 'web/shell.html': 'fixture shell'
  };
  for (const [name, text] of Object.entries(files)) {fs.mkdirSync(path.dirname(path.join(source, name)), {recursive: true}); fs.writeFileSync(path.join(source, name), text);}
  git('add', '.'); git('commit', '-qm', 'Synthetic source-binding unit fixture');
  const bytes = Buffer.from('synthetic export fixture');
  fs.writeFileSync(path.join(web, 'index.pck'), bytes);
  const manifest = {source_commit: git('rev-parse', 'HEAD'), toolchain_verification: 'checksum-pinned-official-archives',
    packed_smoke: 'passed', production_sha256: Object.fromEntries(Object.entries(files).map(([name, text]) => [name, hash(text)])),
    files: {'index.pck': {bytes: bytes.length, sha256: hash(bytes)}}};
  const save = value => fs.writeFileSync(path.join(web, 'release-manifest.json'), JSON.stringify(value));
  save(manifest);
  test('complete clean source and exact checked export bind', () => assert.equal(verifySource(web, source).service_mp3.sha256, hash(files[SERVICE_MP3])));
  test('wrong export source commit fails before browser', () => {save({...manifest, source_commit: '0'.repeat(40)}); fails(() => verifySource(web, source), /exact source commit/); save(manifest);});
  test('manifest cannot omit a source file', () => {const copy = structuredClone(manifest); delete copy.production_sha256[SERVICE_MP3]; save(copy); fails(() => verifySource(web, source), /Source differs/); save(manifest);});
  test('manifest cannot add unverified production files', () => {const copy = structuredClone(manifest); copy.production_sha256['web/extra.js'] = '0'.repeat(64); save(copy); fails(() => verifySource(web, source), /Complete export source/); save(manifest);});
  test('dirty candidate source is rejected', () => {fs.appendFileSync(path.join(source, 'project.godot'), '!'); fails(() => verifySource(web, source), /Clean tracked/); fs.writeFileSync(path.join(source, 'project.godot'), files['project.godot']);});
  test('replaced export bytes are rejected', () => {fs.appendFileSync(path.join(web, 'index.pck'), '!'); fails(() => verifySource(web, source), /size/); fs.writeFileSync(path.join(web, 'index.pck'), bytes);});
  test('old immediate-skip source cannot satisfy welcome gate', () => {
    fs.writeFileSync(path.join(source, 'scripts/cafe_intro.gd'), 'finish()'); git('add', '.'); git('commit', '-qm', 'Synthetic old contract');
    const copy = structuredClone(manifest); copy.source_commit = git('rev-parse', 'HEAD'); copy.production_sha256['scripts/cafe_intro.gd'] = hash('finish()'); save(copy);
    fails(() => verifySource(web, source), /first-gesture contract/);
  });
} finally {fs.rmSync(temporary, {recursive: true, force: true});}
(async () => {await preferenceTests(); checks++; console.log('ok real preference envelopes load through production client'); console.log(JSON.stringify({checks, failures: [], scope: 'Node mocked-observer/helper unit tests only; actual browser and audibility not run'}));})().catch(error => {console.error(error); process.exitCode = 1;});
