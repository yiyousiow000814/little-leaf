# Welcome / restaurant startup diagnostic (0.1.11 investigation)

Baseline: `9b25095abbcc06c437652c1a0f4bc89d576b3e9f` (parent's deployed-source equivalence: `b8b80ee`). The diagnostic does not change runtime code, saves, art, settings, frame cap, or platform lifecycle.

## What the source proves

- Ordinary Web/Firebase: `main.gd:131` constructs the world and UI, then `_setup_music` synchronously loads and duplicates all three MP3s, creates players and starts a 1.2-second fade before welcome exists. Settings apply audio preferences after this. No explicit first-gesture-aware fade restart exists in game code. This is *not* the CrazyGames late-download path. Whether browser audio was suspended is unmeasured.
- CrazyGames only: `_process` calls `platform_music.begin()` only after the intro stops and the platform marks gameplay started. The separate pack is then fetched and all tracks initialized. Moving download earlier needs separate platform-policy review; do not change gameplayStart/loadingStop semantics to get audio.
- `IllustratedCafe._ready` / shop thumbnails request furniture, moving-art and head atlases. All use deferred bakes across initial render frames: procedural geometry, straight-alpha GPU pass, GPU image readback, `fix_alpha_edges`, and texture upload. They can overlap the welcome. Existing `warmup_ms` is total elapsed bake latency, not isolated CPU or GPU time.
- Intro descent changes `artist.origin` each frame. Both background and shell cache signatures include that origin, so they rebuild during the descent despite static geometry. The world is also drawn under the fully opaque first-second welcome.
- The default intro timeline is 6.5 seconds, with descent beginning at 1 second. Delta >1 second causes immediate finish. Report this bailout separately from a complete descent.

These observations identify targets, not the user's measured frame rate or a proved bottleneck.

## Native diagnostic

`qa/profile_startup_transition.gd` instantiates the actual main class with a generated fresh model, blocks progress writes and records real initialization methods. It records each process interval, observed intro phase, atlas states, background/shell rebuild counters and post-draw timestamps. It does not read a player save. Use isolated HOME and XDG directories and `--visual-qa --fresh-review` to isolate preferences too.

Run with Godot 4.6.3 after an ordinary successful import in the same checkout:

    python3 qa/run_startup_profile.py --output /absolute/new/evidence/path

Use the established GitHub CI Xvfb/GL environment for real rendering. Do not attempt a local display or socket bypass. Add `--headless` only for compilation/logic diagnostics: output explicitly marks `renderer_measured=false`; zero draw events and atlas headless fallbacks cannot measure renderer performance. `startup_us` excludes GDScript preload/parse time before scene instantiation and excludes real browser storage/account initialization. A fresh model does not represent a dense returning save.

The runner hashes runtime inputs and the probe, isolates all preference/save directories, and collects two 12-second trials. The first starts cold atlas objects; the second explicitly resets Intro.shown_this_session and recreates the generated fresh model while retaining shared atlas objects. Restarting the executable is *not* warm atlas evidence. Browser warm HTTP cache is a separate dimension.

## Exact-source browser evidence to collect in CI

Use the existing `verifyExport` helper to verify release manifest commit, every exported file hash and production source map before launch. Record the diagnostic helper hash separately; baseline runtime must be unchanged. Use ordinary Web export for Firebase, not CrazyGames.

- Fresh isolated browser context, no autoplay-bypass flags; run cold HTTP cache, then reload same context for warm HTTP cache. Record any generated save and do not call a warm HTTP run a fresh-profile comparison unless the generated save is deliberately reset in this disposable origin.
- Collect rAF interval timestamps and Long Task entries from an init script; browser rAF is a scheduling metric, not proof the game rendered each frame. Keep it separate from Godot frame-post-draw metrics.
- Record loader removal / first visible welcome, finish/bailout, first trusted gesture, audio-context state changes and actual audio onset separately. Do not infer audible music from player.playing or a successful network fetch.
- Run no-gesture auto-descent; first-gesture skip; touch and key skip; repeated skip/release; background/resume during welcome; audio muted by stored preference; fresh and dense generated restaurants. A first trusted gesture skips today's welcome, so an audible onset in the restaurant alone does not prove deferred loading.
- Keep timed traces free of screenshot/readback calls. In a separate visually matched run capture welcome, 25/50/75% descent and settled restaurant at desktop and portrait sizes. Compare matching timeline positions and inspect crop edges, depth and pointer ownership.
- Report per phase sample count, interval p50/p95/p99/max, counts >33.3/50/100 ms, first-frame latency, atlas transitions and cache rebuild deltas. Include cold/warm trial identity, viewport, browser/GPU/OS, source commit/hash, muted/autoplay/gesture state. Retain raw traces. Repeated paired baseline/candidate runs on the same runner are needed; CI results cannot stand in for phone measurements.

## Small optimization order

1. Measure atlas bake overlap and descent cache rebuild contribution first. If concurrent bake/readback dominates early frames, serialize atlas preparation while keeping original geometry fallback, unchanged 4x output and no indefinite welcome gate. Compare cold peak latency and total ready time: serialization can trade a smaller peak for longer fallback rendering and is not automatically an improvement.
2. If static-cache rebuilds dominate descent, prototype translation-only cache reuse. Keep exact per-frame culling, viewport-filling background and shell AA/transform behavior. Merely removing origin from the key is incorrect because commands are screen-space and culling changes as the world descends. Extend the existing recording parity tests to every descent position before render comparison.
3. A smaller independent candidate is moving welcome size/font/layout assignment to viewport-change handling while retaining per-frame opacity/cloud motion. This avoids repeated theme/layout invalidation without changing visuals, but its cost must be measured; do not claim it fixes atlas stalls.
4. Audio: split preparation from playback/fade. Prepare service music during welcome; start/restart the fade only after the browser's valid gesture/unlock and when enabled, preserving mute/volume and platform pause policy. Lazy loading inactive tracks is plausible but needs transition/readiness tests and can otherwise move a hitch into later play. Do not promise pre-gesture autoplay.

Keep each candidate separately reviewable. No runtime optimization has been applied or published by this diagnostic.

## Local diagnostic validation (not rendered performance)

Godot 4.6.3 headless run on the exact baseline plus these diagnostic files passed both 12-second trials. The process observed a full descent in both. Each descent had 330 process samples; background rebuild delta was 329 and shell rebuild delta 658, confirming nearly every descending frame invalidates one background and two shell slots. Both deltas were zero during settled restaurant observations. Draw-post events were zero and atlases used their headless fallback, so no GPU/phone/browser FPS or audio-onset conclusion follows.

Focused existing headless suites passed: intro lifecycle 1,514 checks; background cache 983 checks (180 command-parity cases); shell cache 732 checks. Full integration, browser playback and rendered visual comparison have not been run. The first full import was killed by the environment; validation recovered by reusing only the logo's generated cache after byte-for-byte comparison of the source PNG and `.import` settings with an existing checkout. No imported cache is part of this diagnostic change.

## Rendered CI baseline handoff

`startup-profile.yml` uses the existing pinned checkout/upload actions, checksum-pinned Godot installer, Ubuntu 24.04 and standard Mesa/Xvfb route. The job is capped at 15 minutes; import at 300 seconds and each pair at 90 seconds. It runs two independent process pairs, each with cold atlas objects followed by the same retained warm atlas objects. Pair 2 may benefit from driver/disk caches; neither pair claims an OS-cold or browser-cold state. All audio uses Dummy: MP3 preparation is included, audible onset is not measured.

Each pair records the exact commit, source hashes, installed-engine checksum receipt, OS, adapter, rendering method, initial atlas state and atlas instance IDs. CI requires a completely clean original checkout and imports a separate exact-commit archive for each pair. Every archived source file is hashed and must remain unchanged before and after measurement. Generated script UID and PNG import sidecars are separately hashed, require a matching archived source file, and stay inside the disposable snapshot. Rendering acceptance requires post-draw intervals, all three atlases ready, identical atlas IDs across the pair, and ready atlases at the start of the warm trial. Raw process/draw timestamps are retained alongside per-phase summaries; cross-phase draw intervals remain in the overall summary. A process sample labels the phase observed at its endpoint, so boundary intervals are not isolated phase CPU timings.

Successful execution establishes a software-rendered native baseline only. It does not establish that the full descent completed (check `completed_descent_observed`), the causal share of atlas/cache/layout work, visual parity, browser audio behavior, or device FPS. No screenshot readbacks are added to timed runs. Actual rendered numbers must come from the workflow artifact after publication; local validation remains headless.

Import isolation correction: the initial CI run successfully measured pair 1, then its second-pair guard rejected generated PNG import sidecars in documentation and OCR fixtures. A fresh local import reproduced 246 added metadata files (182 script UIDs and 64 PNG import sidecars), with no modified original files. Independent exact-source snapshots prevent this generated metadata from contaminating later pairs; the clean-checkout guard is stricter, not relaxed.
