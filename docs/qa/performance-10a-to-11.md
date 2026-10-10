# 10a clean closeout and 11 performance handoff

Updated: 2026-10-10. Repository: `yiyousiow000814/little-leaf`.
PR: https://github.com/yiyousiow000814/little-leaf/pull/128

## User decision and gates

The user permits the remaining stable-60 FPS work to move to milestone 11 so
10a can proceed. They explicitly require a **clean functional closeout**, not
a pause leaving optimization-induced bugs enabled. Missing car colors, objects
disappearing, characters flashing through walls, incorrect painter order and
camera interaction regressions must be fixed or their causing change withdrawn.

The performance target is still unmet. Player settings are 30/60. Stable 60
must eventually cover Welcome's first moving frame, natural unskipped startup,
at least 10 seconds after cafe appearance and human-speed pan/zoom across the
supported range. An average near 60 is not acceptance. Desktop evidence does
not establish iPhone 16 Pro Max/Samsung S24 performance or thermals.

**Closeout status: local engine, Web operation and continuous-frame rendering
regressions passed; remote CI pending.** The stable-60 gate has
not passed. The source-bound receipt is `performance-10a-validation.json`.

## Source selection

The local workspace is
`C:/Users/yiyou/Documents/Codex/2026-10-10/dots`.

- Delivery worktree: `perf-fix`, branch `fix/retained-canvas-resources-10a`.
- Base and last verified remote PR head: `833e3d5bbc91403c3fc4c9dcc0c614ebd1e79dfb`.
  Recheck the remote before pushing; other work may have advanced it.
- The selected rendering source is
  `investigation/native-readable-camera-candidate/source`, using the official
  Godot 4.6.3 nonthreaded Web template and the existing tested presentation fix.
  Its 18 changed/new rendering files were copied into `perf-fix` for closeout.
- `investigation/10a-closeout-before-integration/files.json` records their
  before/after hashes; existing versions are preserved beside it. Prior dirty
  work was preserved. No experimental engine binary was copied into production.
- The selected source previously passed 184 original/candidate frame pairs with
  maximum channel difference 1/255 and no pixels over that bound. The final
  production source also passed 192 moving wall/door occlusion pairs. These are scoped
  scene comparisons, not proof that every possible game scene is correct.
- Native Linux X11 atlas regeneration of the selected source produced all three
  atlases with exact RGBA equality. Before refreshing the production manifest,
  all 120 dependency hashes were checked against the actually regenerated source.
  Receipt: `investigation/10a-closeout-atlas-source-receipt.json`.

The selected changes preserve packed-array ownership, actual SceneTree painter
ordering on the first frame, original geometry/color/stroke rules, transformed
camera state restoration, scale-aware atlas coverage and native fallbacks for
unsupported transforms/geometry. They retain existing meshes and static parts
instead of rebuilding them on camera translation/scale changes. Review the
actual diff and tests rather than assuming every directory named “candidate”
contains these changes.

## Confirmed performance findings for 11

1. Godot 4.6.3 nonthreaded Web has two frame-delay paths. In the tested official
   source, `OS_Web::add_frame_delay` calls the native wait under
   `#ifndef PROXY_TO_PTHREAD_ENABLED`, while `web_main.cpp` already schedules
   capped frames. The 60-cap diagnostic observed roughly 64k–83k clock calls per
   frame. An isolated guard correction removed this busy wait (about 29 clock
   calls/frame), but it did **not** prove stable 60 or complete engine parity.
   Keep this as an engine investigation, not a shipped fix.
2. Redraw/invalidation, repeated geometry work and render submission contribute
   separately. Camera motion previously invalidated retained geometry; mutable
   packed arrays could change a cached fill after submission; native painter
   indices could be overwritten when new scene children were inserted. These
   mechanisms explain why performance work also caused visual regressions.
3. In an instrumented matched-engine diagnostic, normal/zoomed scenes spent
   roughly 3–5 ms on the root drawing script, 3–5 ms on character redraws and
   1.5–2 ms on main processing, before remaining engine/browser/GPU work.
   Root sections included about 1.8–2.1 ms in entity drawing, 0.9–1.1 ms in the
   street/tree section, 0.6–0.7 ms in shell submission and 0.35 ms in entity
   preparation/sorting. These are inclusive scoped timings from that run;
   nested function times must not be added twice.
4. Character shoe work was approximately 0.7–0.9 ms/frame across about 20–24
   shoes. This is a possible remaining reuse opportunity, not evidence that
   shoes alone explain all low FPS. Root entity ordering uses an ordinary
   sort; there is no measured evidence here for an exponential algorithm.
5. WebGL inventory showed roughly 438–495 draws/frame and thousands of vertex
   attribute operations. Counts were collected under instrumentation and are
   not valid FPS acceptance results. Do not indiscriminately remove GL queries:
   Chromium's framebuffer-binding query was verified as cached, not an assumed
   GPU stall.
6. The isolated engine's frame scheduler can carry catch-up debt for up to a
   second, producing rates above 60 after slow periods. No scheduler correction
   was implemented. Do not use the rebound to hide the preceding slow interval.

## Experiments that must not be promoted

- `native-primitive-batch-candidate`: about 8% fewer draw calls but slower actual
  performance; rejected despite passing its scoped pixel comparisons.
- Shrinking the post-intro admission band: did not improve the measured FPS;
  reverted in the diagnostic source.
- `native-retained-shoe-candidate`, `native-shoe-drawlist-parity`, and
  `native-retained-shell-candidate`: not delivery sources. Their latest parity
  runs did not meet the existing comparison bound (up to 14/255 at one pixel,
  with additional low-zoom differences). Do not enable them during closeout.
- Those three experiments used a custom-built engine and showed very similar
  differing pixel locations, including locations far outside shoes. The cause
  of those differences was **not established**; a matched-engine baseline
  comparison is required before attributing them to a particular experiment.
- `native-matched-camera-fixed` / `native-engine-camera-fixed`: experimental
  engine exports. A visible desktop run still fell to about 43 FPS after Home;
  that interval was recorded visible/focused. A later visible diagnostic became
  hidden and was deliberately aborted. Do not conflate the two runs or dismiss
  the earlier foreground drop as hidden-window throttling.

## Local evidence index

All paths below are relative to the workspace above, not repository assets.
They are retained for reproducibility; do not delete or overwrite past runs.

| Evidence | Path |
| --- | --- |
| Selected source pixel comparisons | `investigation/native-readable-camera-parity/pixel-differences.json` |
| Final moving wall/door comparisons | `investigation/native-10a-closeout-occlusion/pixel-differences.json` |
| Native regenerated atlases | `investigation/native-readable-camera-candidate-linux-atlases/source/atlas-parity.json` |
| Original engine clock diagnostic | `investigation/native-clock-diagnostic/clock-diagnostic.json` |
| Isolated corrected-guard diagnostic | `investigation/native-engine-clock-fixed/clock-diagnostic.json` |
| Full visible experimental-engine timeline | `investigation/native-matched-camera-fixed/acceptance-visible-desktop/playtest-check.json` |
| Character cost breakdown | `investigation/native-home-cost-profile/home-cost-breakdown-desktop/playtest-check.json` |
| Root drawing section breakdown | `investigation/native-home-cost-profile/home-cost-sections-desktop/playtest-check.json` |
| Failed closeout test attempt | `investigation/10a-clean-closeout-integration/summary.json` |
| Closeout integration rerun | `investigation/10a-clean-closeout-integration-v2/summary.json` |
| Subsequent focused engine runs | `investigation/10a-clean-closeout-remaining{,-v2,-v3}/summary.json` |
| Source-checked coverage index (not a CI export gate) | `investigation/10a-closeout-check-coverage.json` |
| Linux CI unit tests | `investigation/10a-closeout-ci-linux-final.log` |
| Final Web operation regression | `investigation/native-10a-closeout/closeout-desktop-v2/playtest-check.json` |

The first closeout integration attempt caught a test recorder with an obsolete
two-argument `draw_rect` signature. Its assertion count alone appeared clean,
but script errors invalidated the run. The recorder now accepts and records
the full drawing parameters; the runner continues to reject script errors.

The local engine coverage index verifies all 124 suites/start cases against
identical production-file hashes, with 1,235,482 passing assertions. It refers
to successful individual suites across preserved runs after correcting obsolete
test contracts; failed runs remain failed. It is deliberately not a replacement
for the complete same-run CI export gate. The 157 CI Python tests also pass in
an isolated Linux checkout with real repository history and normal Git text
line endings. Windows-only shell/chmod/symlink failures were not waived as passes.

Test contract repairs preserve the visual and settings requirements: mock draw
recorders accept the full native argument list; saved 120 FPS migrates to 60
without losing other preferences; magnified offscreen art must use source
geometry before it re-enters the viewport. Normal-resolution offscreen art
continues using the atlas. The geometry ownership/lifetime suites are included
in the permanent integration runner.

The final official-template Web operation run used a disposable profile in
Headless Chrome 151, ANGLE D3D11 / RTX 3090, 1360x880 DPR1. It completed natural
startup without clicks/keys/skips, 10.5 seconds of cafe observation, 26 paced
pan/zoom actions including both zoom limits and Home, and actual menu clicks
selecting 30 then 60. There were no script/browser errors; the owned browser
closed. Buffers contain 8,382 completed game frames and were frozen before log
export/screenshots. `closeout-desktop-v2/fps-complete-curve.png` retains the
whole diagnostic timeline. It shows remaining camera slow intervals; it is
not foreground-desktop or phone performance acceptance. The post-export
screenshot's FPS label includes logging/readback stalls and is not a benchmark.

The first operation attempt completed the gestures but its automated Home/Enter
menu selection failed. A separate screenshot probe confirmed the real popup;
the rerun clicked its 30/60 rows successfully. Preserve that failed attempt
rather than reporting it as passed. No game fix was needed for that probe.

For 11, resume from the delivered source and its final evidence, isolate one
measured cause at a time, and check identical poses/first frames before accepting
a speedup. Keep engine experiments separate from game-source experiments. Refer
to `AGENTS.md` and the installed `little-leaf-performance` skill for the continuing
design and measurement requirements.
