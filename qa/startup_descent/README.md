# PR105 / PR107 opaque warm-up comparison

Diagnostic-only; no new production optimization. Exact PR105 df115a0/tree b30fb0c versus PR107 456a916/tree b0f0046. Both already have actual correctness/native evidence. PR107 contains atlas readiness and opaque HUD first-use warm-up. Its native cold descent max was about83ms versus403–421ms in that matched run. That does not establish the corresponding Web effect.

Each production tree is exported twice, unchanged except main.tscn's script reference: an empty subclass control and an instrumented subclass. Runtime main bodies are inherited, not copied or replaced. Both still differ from production parsing/export inputs. Buffers and wrappers introduce overhead; symmetric control/instrumented trials measure its bounds without constant subtraction.

16 fresh navigations: control baseline/candidate/candidate/baseline, then instrumented in the same order, each cold/warm HTTP cache. Browser profiles contain only newly generated local progress. No cloud/account fixture. DOM loader removal and actual callback execution timestamps delimit browser scheduling. No screenshot, trace, input, analyser or readback tool runs during timing. SystemInfo and RSS queries run outside each measurement window. Chrome graphics identity and command line are retained. SwiftShader results do not establish hardware-device FPS.

Instrumented main._process records wall-time begin/end and engine frame. This excludes child callbacks, rendering and GPU work. A post-draw callback records engine frame/time, intro elapsed/active/HUD opacity/preparing, reported draw calls/primitives/objects and engine process monitor. These counters are sampled engine reports, not GPU timings or physical presentation. There is no browser/Godot clock alignment. Raw intervals crossing phase boundaries remain once, labeled by both beginning and ending phase.

8192 preallocated rows cap each buffer. Frame callbacks perform numeric writes only, without bridge, logs, array growth or serialization. After eleven seconds of post-loader browser observation, the collector stops first; one explicit browser call then stops engine sampling and serializes the packet. This keeps packet serialization outside measured callback windows. Fail closed on overflow, engine/browser errors, external requests, absent intro/completion, source/hash mismatch, missing packet or undeclared export files. Browser cannot request collection in production: the callback exists only in the disposable diagnostic subclass.

The two production scenes retain original entry structure and ordinary boot path. Readiness is asynchronous in its own CanvasLayer; main._ready itself remains synchronous. The callback measures that ready body without pretending its return means the cover is removed. No change to first-gesture/audio policy. Native headless import/start is only a parse check, never renderer acceptance.

Run offline:
- python3 -m unittest discover -s tests/startup_descent -p 'test_*.py' -v
- node tests/startup_descent/test_validate.js

CI branch qa/readiness-descent-10a alone enables the diagnostic job. Read-only token, exact production pins and official checksum-pinned engine/template. Artifact allowlist excludes profiles and exports. No release manifest or release qualification; existing PR105/107/108/109/110 heads stay fixed.
