# Rendering correctness and performance

This is a reusable development and verification contract. Current delivery,
ownership and acceptance status live only in the [roadmap](../roadmap.md#current-state).

## Design before implementation

For a feature affecting gameplay, animation, UI or camera rendering, identify
what actually changes each frame, what Godot can retain, and which events
invalidate each resource. Prefer engine transforms, retained draw commands and
batching before introducing another rendering abstraction. Avoid repeated
geometry construction, allocations and unchanged material assignments. Keep
cache sizes bounded, resource lifetimes explicit and fallback paths complete.

Separate script/simulation work, redraw invalidation, geometry preparation,
render submission, GPU work and browser scheduling when diagnosing cost.
Draw-call counts alone do not identify the dominant time. Nested timings must
not be added twice, and browser rAF is not proof of completed game frames.

## Visual gate

Preserve original geometry, colors, alpha edges, detail, object presence,
animation timing and wall/furniture/character painter order. Compare identical
deterministic poses and consecutive first frames after movement/zoom, including
cars, doors, kitchen actions and both sides of atlas/cache thresholds.
Investigate pixel differences rather than changing the reference to pass.
Withdraw an optimization that cannot satisfy this gate.

Submitted packed arrays must have independent ownership. Scene-tree child order
must agree with native painter order immediately after insertion. Camera motion
must not leave stale geometry, bounds, materials or cached atlas detail. Choose
atlas coverage from raster scale even before an object enters the viewport.

Atlas source-manifest updates require actual native regeneration and the
existing exact-RGBA check. Preserve reference PNGs and import settings. Engine
or template changes require separate provenance and rendering parity; game
source comparisons cannot certify a different engine.

## Web frame-time gate

The player options are 30 and 60 FPS. The target is stable 60 from the first
moving Welcome frame, through natural unskipped startup and at least 10 seconds
after cafe appearance, plus ordinary movement and the complete supported zoom
range. Loading/login may prepare expensive resources before animation starts.
Use a private uncapped probe only to measure headroom, not to add player options.

Use human-paced input, for example a 220-pixel drag over 1.5 seconds and one
wheel notch every 400 ms with settling time. Cover both limits, changes of
direction and Home. Retain the complete completed-frame curve, slow intervals,
p95/max frame times and first-use stalls; a whole-run average is insufficient.

Record exact source/tree, export hashes, official/custom engine provenance,
browser, viewport, DPR, device, visibility/focus and background load. Freeze
measurement buffers before exporting logs/screenshots. Keep builds and other
owned rendering tests outside timed runs. Headless runs are scoped diagnostics,
not foreground or physical-device acceptance. Desktop evidence does not prove
phone FPS, thermals or battery use; the named targets are iPhone 16 Pro Max and
Samsung S24.

Run the smallest applicable regression set and preserve the required complete
CI/release gates. Keep generated traces, screenshots, exports and private
handoffs outside tracked source. Separate verified results, failed experiments
and hypotheses. If performance moves to a later milestone, deliver a clean
functional candidate and preserve evidence; do not call the FPS target passed.

## Developer-only white-floor observation

Use the existing F12 capture entry with the explicit `--floor-diagnostics`
argument in an isolated generated fixture. It also reuses the existing one-shot
three-second startup capture. This mode has no player UI, sampling loop, or
per-frame terrain hashing. Without either diagnostic argument, no capture is
scheduled or collected. Concurrent capture requests are coalesced.

For browser/itch developer QA, reuse `installEngineLaunchHook` from
`tests/tooling/engine_launch_hook.js` before the inner game frame loads the
exported engine, passing `args: ["--", "--floor-diagnostics"]` and a distinct
report key. For example, the existing browser harness can install the function
with `page.addInitScript(installEngineLaunchHook, {args: ["--", "--floor-diagnostics"],
reportKey: "floorDiagnosticLaunch"})`. No public query flag or web-shell change
is introduced. This requires an export containing this diagnostic change; it
does not add capability to an older deployed PCK. Use an authorized disposable
synthetic browser profile only. Do not fall back to an original profile if
isolated browser execution is unavailable.

In the actual game iframe's developer-console context, invoke
`LittleLeafFloorDiagnostics.capture()`. After the completed-frame capture,
inspect `JSON.parse(LittleLeafFloorDiagnostics.latest_json)`; the string holds
only the latest current/previous packet and may be copied by the developer.
The callback exists only in explicit floor mode. It is retained until its exact
registration is disposed; old scene cleanup cannot remove a newer callback.
There is no automatic upload, download, query activation, account access or
player control. The existing browser screenshot tool can record the visible
scene separately; the packet itself does not prove screenshot/GPU parity.
Hooked QA and the friend's ordinary online session are distinct evidence scopes.

Floor mode bypasses the legacy capture's `_save()` call and takes precedence
if both diagnostic flags are supplied. It does not disable ordinary gameplay
autosaving: a disposable profile and synthetic fixture remain mandatory. The
legacy `--capture-diagnostics` mode retains its existing save-before-capture
behavior and separate output filenames.

`user://diagnostics/floor_diagnostics.json` contains the current and immediately
previous successful observation; `LittleLeaf_Floor.png` is the latest completed
frame image. Capture once before and once during a disappearance. The payload
contains only per-style counts split between the included 12x9 base and
purchased expansion, diagnostic hashes, runtime/cache identities, geometry
counts, and native draw-node visibility/material/order/transform state. Mesh
region attribution uses the cached floor-cell order and is labelled incomplete
if its vertex count does not match that order. Completed-frame native mode
uses the renderer routing guards: stream submission is inactive after finish.
It excludes saves, raw floor dictionaries, wallet/service statistics, profile
identifiers, and accounts. At most four matching node records and 4,096 scanned
native slots are allowed. An incomplete scan is labelled, never treated as an
exact missing-node diagnosis. Runtime IDs are strings to avoid browser JSON
rounding; content hashes are non-cryptographic fingerprints.

A changed model count/hash identifies a data/state change. Stable model data
with stale mesh/cache state narrows invalidation. Stable data and geometry with
missing pixels requires image/render-state review; these packets do not prove
GPU visibility or identify an occluder. No automatic repair is performed.

The existing native-shape retention suite covers read-only capture, original
and expansion white tiles, injected silent record deletion, hidden/material/
duplicate node states, real stream-finish state, equal-revision model
replacement, equal-total but different-region styles, output/scan bounds,
JSON identity precision, explicit activation, zero progress-save calls in floor
mode, and preservation of the legacy capture path. Synthetic headless samples
establish diagnostic correctness only. The reported ordinary-play white-floor
disappearance remains unreproduced; browser rendering and release qualification
are separate. The existing web lifecycle suite also exercises exact embedded
bridge install/dispose ownership; the engine-launch test accepts the diagnostic
arguments and runs against actual exported JavaScript with Wasm startup stubbed.
Neither is a real-browser or WebGL qualification.
