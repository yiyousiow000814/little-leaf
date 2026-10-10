# Little Leaf development requirements

## Performance is part of feature design

For gameplay, art, UI, animation, camera and rendering changes, consider frame
cost before implementation. State what changes every frame, what can remain in
Godot's retained drawing resources, and exactly what invalidates each cache.
Prefer existing engine facilities over a second custom renderer. Do not rebuild
unchanged geometry, repeatedly assign unchanged materials, or copy/replay a
static scene's commands merely because a character moves or the camera pans.
Keep resource ownership explicit and caches bounded. Preserve painter order.

The current player-facing frame-rate options are **30 and 60**. The target is
stable 60 FPS from the first moving Welcome frame, through the unskipped intro,
and during normal-speed camera movement and the full supported zoom range.
Loading/login may prepare expensive resources before animation starts. Seek
measured headroom; a 60 cap or an average near 60 does not demonstrate it.

Visual correctness is a separate acceptance gate. Performance changes must not
change artwork, color, detail, alpha edges, object presence, animation timing,
or character/wall/furniture occlusion. A faster build with a rendering regression
is not an improvement. Withdraw a failing optimization or fix and verify it.

## Evidence for rendering and performance changes

- Verify the exact checkout, exported artifact, engine/template, browser, port,
  viewport and DPR. Do not substitute a different build or native FPS for Web FPS.
- Capture completed game frames and frame times. Include the entire natural
  Welcome/intro plus at least 10 seconds after the cafe appears, and normal
  camera gestures (roughly 220 px over 1.5 seconds, 400 ms per wheel notch, with
  settling time). Cover both zoom limits, direction changes and returning Home.
- Report the full curve, slow intervals, p95/max frame time and context. Do not
  hide first-use stalls or claim success from a whole-run average. An uncapped
  private probe can measure headroom; it is not a player-facing option.
- Freeze measurement buffers before exporting logs or taking screenshots. Do
  not benchmark alongside builds or other owned rendering tests. Record window
  visibility/focus and background load; a hidden window is not foreground proof.
- Compare original and candidate rendered frames at matching deterministic
  poses, including consecutive first frames after moving/zooming, vehicles,
  doors/walls, staff/kitchen actions and both sides of cache/atlas thresholds.
  Investigate pixel differences; do not replace a baseline just to pass.
- Atlas changes require actual native regeneration and the existing exact RGBA
  verification before refreshing source manifests. Headless unit tests alone
  do not verify rendered pixels. Custom engine builds need separate parity and
  reproducible provenance; game-source parity cannot validate a different engine.
- Run the applicable regression suites on the delivered source. Keep diagnostic
  overrides and experimental rendering paths out of the shipping build.

Desktop validation does not prove phone frame rate, thermals or battery use.
The named phone targets are iPhone 16 Pro Max and Samsung S24; identify untested
devices honestly. Preserve the same design efficiency on mobile.

## Milestone status

See [the 10a to 11 performance handoff](docs/qa/performance-10a-to-11.md) when
continuing this work. The user allows remaining FPS work to move to 11, but
**10a must not close with bugs introduced by optimization**. Keep functional
closeout distinct from the still-unmet stable-60 performance target. Do not
silently claim either gate has passed or merge/deploy without authorization.
