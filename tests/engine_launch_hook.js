'use strict';

// Test-page runtime instrumentation only. Godot 4.6 SafeEngine creates a fresh
// prototype per instance. The standard shell constructs its lexical `engine`
// before asking Engine.getMissingFeatures, so bind that exact instance here.
// Feature results, startup receiver/return value and all storage paths pass through.
function installEngineLaunchHook({args, reportKey}) {
  Object.defineProperty(window, 'Engine', {configurable: true, set(Engine) {
    const features = Engine.getMissingFeatures;
    Engine.getMissingFeatures = function(...featureArgs) {
      const missing = features.apply(this, featureArgs);
      Engine.getMissingFeatures = features;
      const instance = engine, start = instance.startGame;
      instance.startGame = function(options) {
        const observation = window[reportKey] || (window[reportKey] = {});
        observation.launchArgs = args.slice();
        observation.launchCalls = (observation.launchCalls || 0) + 1;
        return start.call(this, {...options, args: [...(options?.args || []), ...args]});
      };
      return missing;
    };
    Object.defineProperty(window, 'Engine', {configurable: true, writable: true, value: Engine});
  }});
}

module.exports = {installEngineLaunchHook};
