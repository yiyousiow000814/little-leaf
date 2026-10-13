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
