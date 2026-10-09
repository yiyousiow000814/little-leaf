# Serialized atlas startup candidate

This isolated candidate changes only when the three existing native atlas bakes
run. A SceneTree-owned FIFO waits for a presented frame before the first bake and
between subsequent bakes. Each original `_build` implementation, 4× scale, alpha
conversion/repair, texture filtering, geometry and fallback is unchanged. The
intro timeline, gameplay clocks, audio, platform lifecycle and saves are untouched.
A game node can be replaced while its shared atlas is warming: the queue belongs
to the root, not that game. Headless requests still use their existing fallback.

Hypothesis: overlapping three initial procedural renders and three conversion /
readback / alpha-edge repair / uploads produces the measured cold-only spikes.
Serialization may reduce peak stalls and first-frame latency but increase total
atlas readiness time and time spent on original-geometry fallback. This is an
experiment, not an established improvement. It does not address the separate HUD
fade hitch, translation cache invalidation or browser audio unlocking.

## Acceptance checks

1. `test_atlas_warmup_queue.gd`: headless FIFO, no initial synchronous bake,
   duplicate/in-flight request suppression, failed-bake continuation, idle restart,
   shared root ownership and stale shared scheduler recovery.
2. Existing intro lifecycle, background and shell cache suites in the disposable
   integration runner. All engine calls honor the shared engine lock.
3. In the existing approved Xvfb / Mesa CI, run the unchanged startup profiler on
   baseline and candidate, two cold/retained-warm pairs each on the same runner.
   Compare first post-draw latency; welcome/descent p50/p95/max and >50/>100 ms
   counts; completion/bailout; readiness time. Reject a trade that only moves a
   similarly large spike into descent or leaves fallback active materially longer.
4. Separately (outside timed traces), run
   `godot --audio-driver Dummy --path . --script res://qa/check_atlas_warmup_parity.gd`.
   It compares exact RGBA bytes of concurrent baseline bakes with serialized bakes
   for all three atlases. Headless execution is rejected, not called parity.
5. Separately capture matching intro elapsed positions and settled restaurant in
   desktop/portrait and inspect fallback-to-atlas switches. Test skip/repeated
   skip/resize/background-resume, fresh and dense generated saves. Keep original
   player profiles entirely outside these checks.

No rendered improvement or output parity is claimed until CI evidence exists.

## Local verification

2026-10-09, Godot 4.6.3 headless, disposable generated profiles: import succeeded
without diagnostics; scheduler 10, background cache 983, shell cache 732 and intro
lifecycle 1,514 checks all passed (3,239 total). Evidence:
`/workspace/shared/startup-serialized-qa-20261009/summary.json`.
This is logic/command coverage, not renderer performance or pixel parity. The
render-only parity probe compiled during import but has not been rendered locally.
Full integration, browser audio and rendered transition captures remain unrun.

## Paired renderer acceptance job

The candidate workflow pins the PR98 baseline commit
`3291afc82244553d9958656aeb7c32809fff4009` in a separate checkout and alternates
baseline/candidate twice on one runner. Timed traces remain untouched by readback.
A separate disposable archive run captures the actual production main scene at
five fixed timeline positions, desktop and portrait, and checks identical PNG
bytes. The candidate also checks all three atlas RGBA hashes against concurrently
baked reference atlases. Frozen captures verify static output, not live timing,
input, browser audio or dense saves. Imports and source receipts stay isolated.
