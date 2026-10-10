# Welcome audio QA (actual browser pending)

This harness tests the ordinary-Web first-gesture candidate. It does not alter
production code, publish, request audio permission, resume an AudioContext, play
a test tone, synthesize a DOM gesture, mute/unmute browser output, or set an
autoplay policy. Do not run it through another access route after a browser
URL-policy denial. It is prepared for an authorized CI browser environment.

## Offline tests

```
node tests/welcome_audio_test.js
node --check tests/welcome_audio_browser.js
node --check tests/welcome_audio_observer.js
node --check tests/welcome_audio_helpers.js
```

These use synthetic observations and mocked browser nodes. Passing these checks
is not a browser pass, music identification, listening test or visual acceptance.

## Integrate and run later

1. Use an explicit clean `--source-root` checkout. Entry/skip behavior is
   protected by `test_intro_lifecycle_headless.gd`; this diagnostic binds source
   identity without requiring a particular script spelling or intro constants.
2. Reuse a successful **Check and build Web** run for that exact commit. Dispatch
   `.github/workflows/welcome-audio.yml` on the built commit with `web_run_id` and
   `web_artifact_id`. PR Web exports use the merge commit, not the API head SHA:
   the reusable `build-web.yml` reference and artifact name bind the actual built
   SHA. The requested checkout may have a different SHA only when the complete
   Git trees (including build/test inputs) match. Both identities are retained.
   `ci/reuse_welcome_web.py` checks the successful run, successful attempt,
   ordinary-Web artifact ID/name, expiry, exact manifest commit, entire production
   hash map and packed file sizes/SHA-256 before opening a browser. The pinned
   download action selects the validated artifact ID directly. Missing or
   mismatched evidence fails; there is no automatic engine/export fallback.
   Run the ordinary Web gate once when no valid artifact exists.
3. Install Playwright 1.63.0 and its bundled Chromium. Existing workflow setup
   installs Chromium dependencies but uses system Chrome for other gates. This
   probe requires the pinned bundled Chromium, with no channel or executable
   override. Add its installation explicitly:

   ```sh
   npm install --prefix "$RUNNER_TEMP/inbox-browser-tools" --ignore-scripts --no-audit --no-fund playwright@1.63.0
   "$RUNNER_TEMP/inbox-browser-tools/node_modules/.bin/playwright" install --with-deps chromium
   sudo apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-eng
   PLAYWRIGHT_MODULE="$RUNNER_TEMP/inbox-browser-tools/node_modules/playwright" \
     xvfb-run -a node tests/welcome_audio_browser.js \
       --source-root "$GITHUB_WORKSPACE" \
       --web-build "$RUNNER_TEMP/web-build/web" \
       --output "$RUNNER_TEMP/web-build/evidence/welcome-audio"
   ```

4. Budget four minutes for the nine browser cases after installation. Preserve
   the evidence directory on failure as well as success. Review the screenshots
   before claiming visual acceptance. The manual workflow runs the offline
   commands and actual browser command after exact-artifact preflight.
   Preparing the workflow locally does not authorize publishing or running it.

## Evidence and gates

- Every case gets a new disposable browser context and fresh localhost origin
  storage. Only generated preferences are seeded, using the real
  `little-leaf.preferences.v1` JSON `{format: 1, text: CFG}` format. No cafe save,
  account, cloud bridge or player data is used. Nonlocal requests are blocked.
- Click, touchscreen tap and Enter each run with BGM enabled at 70%, BGM disabled,
  and BGM enabled at zero volume. SFX is disabled and zero-volume in all cases.
  Both the real preferences boot result and the initial fresh-vault result are
  retained. Later normal generated autosaves are permitted.
- Playwright's ordinary input API supplies the sole trusted gesture. Enter uses
  focus without a preliminary click. Touch activation is checked at touchend,
  since touchstart need not activate the page. Trusted-event timestamps,
  activation state and AudioContext state changes are recorded.
- The observer forwards the original AudioNode connection unchanged, then adds
  an unconnected analyser branch. All routes to the same context destination
  are summed into the same analyser so cancelling parallel routes do not create
  false positive output. Existing routes, gains and playback are untouched.
  The gate requires one summed destination context. Every touched destination
  must remain connected throughout the trial; any
  disconnect makes the result inconclusive and fails the gate.
- Audio must initially be suspended and quiet, then run only after the first
  gesture. Observed AC RMS must exceed 0.0001 for at least 200 ms on an advancing
  audio clock, with no sample gap over 100 ms. DC and isolated spikes do not count.
  Both silent controls must remain at or below 0.00001 throughout the fixed
  50–2200 ms post-gesture interval. Every measured sample must report `running`,
  with a strictly advancing AudioContext clock and monotonically increasing
  observation time. Require at least 20 samples, no observation gap over 100 ms,
  and a sample within 100 ms of each interval edge. The context-state history
  must show `running` by the interval start and no suspension/closure anywhere
  in the interval, including between samples. Historical activation alone,
  frozen clocks, sparse samples or uncovered interval edges are inconclusive.
  The enabled/control peak ratio must be at least 10 (20 dB amplitude contrast).
  These are conservative detection thresholds, not loudness measurements.
- The first gesture must occur within one second of loader removal. The confirmed
  signal must precede an early screenshot no later than 2.5 seconds after input,
  well inside the normal 5.5-second descent. Early pixels must still OCR as
  `Welcome to` and `Tap again`. Frames with gaps of 250 ms or greater fail closed
  rather than treating a stall-triggered intro finish as successful descent.
- Full screenshots cover before input, early welcome/audio, three seconds after
  input, and 6.5 seconds after input. Every screenshot has before/after browser
  monotonic timestamps and a hash. OCR must find the initial welcome/hint, then
  the post-input welcome/hint, and must no longer find the welcome title in the
  last screenshot. Final motion and visual quality still require review.
- The report binds the harness files, source commit, exact export manifest and
  service MP3 SHA-256. It records pinned Chromium revision/version and actual
  command-line checks for sandboxing, absence of mute and autoplay overrides.

## What a future pass would and would not establish

A `passed-bgm-correlated-signal` report establishes destination-bound non-DC
WebAudio signal after ordinary activation, causally associated with BGM controls
and captured while welcome pixels remain visible. It does not establish sound
at the OS mixer, physical speaker or a listener's ears. Screenshots/taps add
observation overhead, so this is not a startup performance test.

Exact stream identity is explicitly `unproven`: binding the MP3 source bytes does
not prove that those bytes generated the observed samples. This small probe does
not extract Godot's decoded stream or compare a decoded hash-bound MP3/reference
spectrum. It requires both independent silent controls instead. A stream swap
within the BGM bus could still pass; identify the actual tune by a separate
reference-matching or listening test before claiming service-track identity.

Analyser time-domain data is downmixed; phase-cancelling stereo can produce a
false negative. A blocked/silent output device can also differ from graph output.
A disconnect, failed OCR, timing stall, missing tap, unexpected activation policy
or active noise in a silent control fails closed. Diagnose using retained raw
observations; do not lower the gate or add a resume/autoplay bypass to get a pass.

The parallel unconnected analyser behavior follows the
[Web Audio specification](https://www.w3.org/TR/webaudio-1.0/#AnalyserNode).
Browser launch options follow the
[Playwright BrowserType reference](https://playwright.dev/docs/api/class-browsertype).

## Coherent 10a candidate and bounded CI

The candidate is assembled directly on immutable 10a save/UI base
`9d29138f9c53bb874be3e1f5872368bbcaa82a1f` (local equivalent
`33643b238adbcceb0ba9bbf6030fd0b5e13d3bf8`, tree
`6cc904d4dfd45fadcb6d8ca5fee09b504ec96384`). Explicit patches import PR105's
three lossless atlases, PR107's opaque readiness/HUD warm-up, and the first-
gesture behavior from `fa31bf3`. The combined intro retains preparation input
consumption before interpreting the first independent entrance gesture. Existing
save ownership, validation, logger, release notes and recovery UI are preserved.
No 11 gameplay or new art is included.

Preparation now polls the existing native recovery controller and rechecks
immediately before deferred reveal. Ownership/account loss cancels pending art
preparation, preserves pause/write fences and pending data, and reveals recovery
Help rather than a welcome/descent. Only terminal atlas work and two final
post-draw frames release ordinary preparation; the existing bounded timeout
falls back to original geometry without authorizing gameplay or save recovery.

The intended UX moves required preparation into initial loading before welcome.
Actual counts are reported without fake percentages. A known finite engine-start
main-thread callback gap remains; hiding it is not a claim that every loading
frame is responsive. The measured goal is the user's opening/welcome/descent
interval, not a new steady-state restaurant FPS requirement. Software-renderer
measurements do not establish user-hardware FPS.

`.github/workflows/welcome-audio.yml` is an explicit manual diagnostic. It
requires IDs for a successful exact-source ordinary-Web run and its unexpired
artifact. The complete engine/export gate and browser save regressions stay in
`build-web.yml` and run once there. Audio QA reuses that checked artifact and
retains its source-binding receipt alongside the unchanged audio observations.
It fails closed without rebuilding when source identity or evidence is missing.

The independent manual final-startup comparison workflow pins the immutable 9d29138
base and exact PR111 QA toolkit `aedf46c452a3e05d0c84e8be0d6a4f6949f3c1a4`.
Both products are freshly exported with symmetric diagnostic/control subclasses.
Its timing window has no screenshots, profiling, input or audio sampling; packet
serialization follows the window. It cannot replace this audio gate or the
unchanged general save/UI Web CI, and its overlays never enter release exports.

Before publication, rebind atlas source provenance only after exact three-atlas
rendered equality on this coherent runtime. Prior standalone audio parity is
historical evidence, not proof for this integration. Keep the failed/superseded
intermediate receipts and the final exact-source receipt distinct. A draft and
CI results confer no merge, release, deployment or live-player-data permission.

### Assumptions that must fail closed in actual CI

- The runner must support a sandboxed bundled Chromium. If Ubuntu sandbox/user-
  namespace restrictions prevent launch, report the failure; do not disable the
  sandbox or change host security settings to obtain a pass.
- The production shell must remove `#status` after its first rendered frame. The
  passive observer uses that removal as its initial-visibility timestamp, and
  the initial screenshot must actually contain the welcome and hint.
- Default fresh-origin autoplay behavior must create a suspended context, then
  normal input must activate it in every case, including both silent controls.
  A control must stay running for the complete measured interval, with the
  advancing-clock and gap/edge coverage checks above. A prior running transition
  followed by suspended or frozen samples is inconclusive, not a pass.
- The engine must expose one stable summed destination route. Missing routes,
  multiple contexts, source disconnects, DC-only output, silence, premature
  output or nonfinite observations fail; no graph repairs or test tones.
- Screenshot overhead, software rendering, font rasterization or OCR may fail
  the existing less-than-one-second first-input, 2.5-second early-evidence,
  100-ms sample-gap or 250-ms frame-gap contracts. Retain and diagnose those
  observations. Do not relax thresholds, fade timing, or OCR to make CI green.

Offline preparation does not resolve any of these actual-browser assumptions.
