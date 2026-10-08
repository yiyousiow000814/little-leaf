# 0.1.10 Web lifecycle and frame policy

Audited baseline: `43e1834464ed327c7c432c988401898f9582f3f2`. This patch is independent of the CPU/query and rendering patches and does not change artwork, resolution, simulation speed, economy, save schemas or storage authority.

## Findings and changes

- Production had no frame cap; the old performance fixture explicitly used 60. Godot 4.6.3 with the exact project settings reported `Engine.max_fps=0`, vsync enabled, and low-processor mode disabled. Production now defaults to **60 FPS**. Settings provides **60 / 120 FPS**, retained in the existing independent preference store. Missing or unsupported values use 60. This is a cap, not a guarantee of achieved FPS; screen/browser refresh and workload still limit it. The setting explains that 120 can consume more battery and produce more heat.
- DOM hide/pagehide previously canceled input and attempted one save, but did not suspend game processing. Hidden pages now preserve the user's service-pause state and prior node process mode, disable the game subtree, and restore that mode on visible/pageshow. The existing pre-suspension save remains best effort. A newly installed lifecycle in an already-hidden page also suspends. The first resumed controller/illustration delta is discarded rather than advancing simulation by background elapsed time. The intro intentionally retains its existing finish-on-long-stall behavior, so background return cannot trap input behind a prolonged intro. The rendering patch must call `game.effective_frame_delta(delta)` from the illustration process as well.
- Music crossfades previously left the outgoing looping track playing at -60 dB indefinitely. On completion, inactive players stop; their positions are retained for a later return. Replaced fades cannot stop the currently selected track.
- Normal Web autosave previously performed a storage transaction every >15 seconds even when paused and unchanged. Only periodic normal-Web submissions may now skip an **exactly identical, previously acknowledged payload** after the complete native model validation. Errors force retry; compensation credit forces submission; pending edits retain the existing queue/acknowledgement rules. Explicit saves and lifecycle saves still commit. CrazyGames retains its existing five-second dirty cadence. This avoids writes, not validation/serialization CPU work; active simulation changes the payload and still saves normally. The additional retained payload strings are bounded to the confirmed and in-flight saves, not an accumulating history.
- Volume sliders previously wrote preferences synchronously on every value event. Audio updates remain immediate, but one restartable 0.2-second Timer coalesces persistence. Drag end, the settings Close button, page suspension and native close flush the final value. Persistence failures retain the existing error presentation.

## Existing safeguards retained

The main viewport already disables legacy 3D rendering, so the configured 3D MSAA is not a normal-game active AA cost. Actual 2D MSAA defaults to zero. Both Web presets use the same pinned Godot 4.6.3 non-threaded template, full-window canvas policy, GL Compatibility and no PWA. The normal Web shell does not load CrazyGames SDK; CrazyGames uses its own shell and lazy music pack. No custom recurring JavaScript interval was found. Save diagnostics retain at most 240 events, the vault retains one previous authority record, and lifecycle listener disposal is bounded. This is not proof that no memory leak exists elsewhere.

## Remaining resolution and startup costs

The exact exported Godot JS uses full `devicePixelRatio` with `allow_hidpi=true`. Executing its sizing function with a mocked 390×844 CSS viewport yielded:

- DPR 1: 390×844, 329,160 backing pixels
- DPR 2: 780×1688, 1,316,640 pixels
- DPR 3: 1170×2532, 2,962,440 pixels

This is deterministic sizing evidence, **not a GPU/phone benchmark**. The existing logical UI content scaling does not cap backing pixels. Resolution is deliberately unchanged to preserve image quality. A separately approved quality setting could limit world-render resolution while keeping UI sharp; it needs actual small-screen readability and input-coordinate tests.

Exact baseline exports retain a 37,700,666-byte WASM, normal Web 17,990,144-byte PCK, or CrazyGames 8,765,372-byte initial PCK plus 9,257,228-byte lazy music pack. These are uncompressed file bytes, not wire transfer or resident-memory measurements. Music loading is one-shot; disabling music stops playback but the platform currently still fetches its pack once gameplay begins. These are startup/memory costs, not demonstrated causes of sustained heat. Enabling workers/threads or changing texture compression is not an automatic safe fix and is not part of this patch.

## Validation

`tests/test_web_performance.gd` checks preferences migration/reload, 60/120/invalid settings, 100 slider changes coalescing into one write, hidden state/process-mode restoration, discarded resume delta, stale crossfade protection, outgoing stop/position retention, identical periodic-save suppression, explicit saves, mutations, write failures/retry, validation failures, platform exclusion and compensation settlement. A second focused pass adds actual model/runtime serialization: unchanged paused snapshots skip writes, while animation-time and wallet changes still submit.

`tests/web_performance_lifecycle.js` executes the exact production embedded DOM code with mock targets: 100 reinstalls still have seven listeners, disposal removes them, hide/pagehide coalesce one save, visible/pageshow notify resume, and initial-hidden installation notifies suspension. It also checks the exact preference adapter with mock storage, preserving old CFG text and round-tripping the new display key. It is included in the Web CI Node gate.

Focused headless run: **10 suites, 4,694 checks passed**, including new Web performance, CrazyGames acknowledgement, intro lifecycle, HUD layout, mobile toolbar, startup retry, autosave feedback/adversarial, Inbox cache and compensation Inbox. The adversarial JSON-error diagnostic is expected by the existing runner. Seven Node suites passed: lifecycle, CrazyGames storage, legacy byte storage, save-log observers/privacy, connection recovery and compensation Inbox storage.

Reproduce with an unused output directory and the shared engine lock:

```sh
GODOT_BIN=/path/to/pinned/godot python tests/run_integration_candidate.py \
  --lock /workspace/scratch/6cfb791ccd66/.cloud-engine.lock \
  --output /tmp/little-leaf-web-performance-new \
  --only test_web_performance test_autosave_feedback test_autosave_feedback_adversarial \
  test_crazygames_ack test_intro_lifecycle_headless test_mobile_toolbar test_hud_layout \
  test_compensation_inbox test_inbox_save_cache test_startup_retry
node tests/web_performance_lifecycle.js
```

Full combined regression and both pinned exports must run after integrating the rendering and CPU patches. Actual cloud browser launch is blocked by the current environment; no rendered UI, real browser suspension/audio proof, mobile FPS, energy or temperature improvement is claimed. Keep the existing pause on graphical benchmarks. Once an approved graphical environment is available, validate 60/120 on 60/120-Hz devices, old preference migration, repeated background/foreground while playing/paused/dragging/saving, audio crossfade interruption, high-DPR readable settings layout, and a sustained same-device/same-brightness/same-scene thermal/power comparison.
