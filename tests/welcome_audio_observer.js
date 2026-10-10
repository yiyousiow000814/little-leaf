'use strict';
// Test-only parallel tap: existing connections/return values remain untouched.
// Analyser outputs stay unconnected. No resume(), playback or gain mutation.
function installWelcomeAudioObserver() {
  const state = {version: 1, started: performance.now(), firstVisible: null,
    frames: [], contexts: [], taps: [], samples: [], events: [], errors: [], disconnects: [], stopped: false};
  const contexts = new Map(), taps = [], links = [];
  const originalConnect = AudioNode.prototype.connect;
  const originalDisconnect = AudioNode.prototype.disconnect;
  function contextRecord(context) {
    if (contexts.has(context)) return contexts.get(context);
    const record = {id: contexts.size, sampleRate: context.sampleRate, created: performance.now(), states: []};
    const changed = () => record.states.push({at: performance.now(), state: context.state, audioTime: context.currentTime});
    contexts.set(context, record); state.contexts.push(record);
    context.addEventListener('statechange', changed); changed();
    return record;
  }
  // Observing constructors catches contexts that never connect or never run.
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    if (typeof globalThis[name] !== 'function') continue;
    const Original = globalThis[name];
    globalThis[name] = new Proxy(Original, {construct(target, args, newTarget) {
      const context = Reflect.construct(target, args, newTarget);
      contextRecord(context); return context;
    }});
  }
  AudioNode.prototype.connect = function(...args) {
    const result = Reflect.apply(originalConnect, this, args);
    try {
      const destination = args[0], context = this.context, output = args[1] ?? 0;
      if (destination === context.destination && !links.some(link => link.source === this && link.output === output)) {
        const record = contextRecord(context);
        let tap = taps.find(item => item.context === context);
        if (!tap) {
          const analyser = context.createAnalyser();
          analyser.fftSize = 2048; analyser.smoothingTimeConstant = 0;
          analyser.channelCount = context.destination.channelCount;
          analyser.channelCountMode = 'explicit';
          analyser.channelInterpretation = context.destination.channelInterpretation;
          tap = {analyser, data: new Float32Array(analyser.fftSize), context};
          taps.push(tap);
          state.taps.push({id: taps.length - 1, context: record.id, at: performance.now(), routes: []});
        }
        // All destination-bound outputs sum in the SAME context analyser.
        // This avoids treating mutually cancelling source branches as output.
        // Its unconnected output adds no sound and changes no existing route.
        Reflect.apply(originalConnect, this, [tap.analyser, output, 0]);
        links.push({source: this, output});
        state.taps[taps.indexOf(tap)].routes.push({nodeType: this.constructor.name, output, at: performance.now()});
      }
    } catch (error) { state.errors.push(String(error)); }
    return result;
  };
  AudioNode.prototype.disconnect = function(...args) {
    const result = Reflect.apply(originalDisconnect, this, args);
    // Any disconnect on a tapped source makes later graph identity ambiguous.
    // Record and fail closed; do not reconnect, suppress or reinterpret it.
    if (links.some(link => link.source === this)) state.disconnects.push({at: performance.now()});
    return result;
  };
  for (const type of ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchend', 'keydown', 'keyup']) {
    addEventListener(type, event => state.events.push({type, at: performance.now(), trusted: event.isTrusted,
      key: event.key || null, repeat: !!event.repeat, pointerType: event.pointerType || null,
      target: event.target?.tagName || null, active: navigator.userActivation?.isActive ?? null}), {capture: true, passive: true});
  }
  let hadStatus = false;
  function frame(now) {
    if (document.getElementById('status')) hadStatus = true;
    if (state.firstVisible === null && hadStatus && !document.getElementById('status')) state.firstVisible = now;
    state.frames.push(now);
    if (!state.stopped) requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  const timer = setInterval(() => {
    if (state.stopped) { clearInterval(timer); return; }
    for (const [id, tap] of taps.entries()) {
      try {
        tap.analyser.getFloatTimeDomainData(tap.data);
        let sum = 0, square = 0, peak = 0;
        for (const x of tap.data) { sum += x; square += x * x; peak = Math.max(peak, Math.abs(x)); }
        const mean = sum / tap.data.length;
        state.samples.push({tap: id, at: performance.now(), audioTime: tap.context.currentTime,
          state: tap.context.state, rms: Math.sqrt(square / tap.data.length),
          acRms: Math.sqrt(Math.max(0, square / tap.data.length - mean * mean)), peak});
      } catch (error) { state.errors.push(String(error)); }
    }
  }, 20);
  globalThis.__welcomeAudioQA = state;
}
module.exports = {installWelcomeAudioObserver};
