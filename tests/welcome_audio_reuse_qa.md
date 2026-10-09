# Immutable-artifact welcome audio diagnostic on official Chrome

This separately reviewed QA-only workflow reuses ordinary-Web artifact
11618320268 from run 37933440818. It does not rebuild, publish, deploy, or qualify
a release. The source run can still be active or fail unrelated gates; neither
status is promoted into a complete-CI claim.

## Frozen identity

- Repository: `yiyousiow000814/little-leaf`
- Artifact: `11618320268`; run: `37933440818`
- Run head: `8d63f936245602628386026732a6dd030dce0fc9`
- Tested merge/export commit: `a6b8a3de4fb0f39529886b426fd7820a2c3c2ddc`
- Exact source tree: `08bd2d87c4969dce910c7907682f4653b0110b65`
- ZIP SHA256: `a70dde4aad2564f9fdfd9069019c2d16da4969a03d25d99a42dd380d069225df`
- Export manifest SHA256: `5006f66ff1de43e712cc4b21fd3154d67dd0d5b2cad9d887b373c2a658571be7`

A QA checkout and separate immutable merge checkout preserve the manifest's
exact commit identity. Preflight verifies artifact/run metadata, actual ZIP
bytes, safe archive members, exact merge commit/tree, official export toolchain,
packed smoke, every exported file and the complete production byte map against
both checkouts. Expiry, missing objects/artifacts, unavailable metadata or any
mismatch fail before browser launch. No alternate artifact or source is tried.

## Explicit browser correction

The preceding audio attempt reached its checked export but its bundled Chromium
153 failed before navigation because the runner could not provide that binary's
sandbox. This workflow explicitly selects Playwright 1.63.0's `chrome` channel
via `WELCOME_AUDIO_BROWSER=system-chrome`, using the runner's official
`/opt/google/chrome/chrome`. It requires a `Google Chrome 154.x.x.x` version
string and records the exact installed patch version and executable SHA256.
The launched version and actual command-line executable must match exactly.
There is no bundled/system fallback. The ordinary harness default remains its
pinned bundled Chromium; existing PR and general CI workflows are unchanged.

Sandboxing stays enabled. No host security setting, autoplay policy, engagement,
context resume, test tone or automation flag is added. The existing Playwright
mute default is removed as before. Command-line identity first uses
`Browser.getBrowserCommandLine`; a known unavailable/missing-automation response
uses read-only `SystemInfo.getInfo.commandLine`, with quote-aware parsing and
identical sandbox/mute/autoplay checks. Missing or malformed identity fails.
No flags are added to make the introspection method succeed.

All nine click/touch/Enter × enabled/disabled/zero comparisons, continuous
running-clock silent controls, finite-signal requirements, RMS thresholds,
timing windows, frame limits, fresh profiles and blocked external requests are
retained. Measurement is screenshot-free until input+2500 ms; later images
follow the stopped measurement. Nine additional fresh visual-only profiles
retain actual pre-input and early-welcome OCR, with the same early-image
2500 ms deadline. Those profiles are explicitly separate: no same-profile early
image/audio proof is claimed. Phase timestamps and raw rAF timestamps remain.

Activation now distinguishes `gesture-unlocked`, `default-autoplay-allowed`,
and `unresolved`. Suspended/quiet prerequisites remain strict for the unlock
path. A valid default-autoplay path still requires all nine timely signal and
silent-settings comparisons; it explicitly leaves blocked-context unlock
`unverified-not-exercised`. Mixed or unresolved evidence cannot earn a pass. It does not establish physical audibility, tune identity, full
release qualification, startup performance or human visual acceptance.

## Scope and offline review

The new workflow runs only on `qa/welcome-system-chrome-artifact` and checks out
the triggering QA SHA. A push needs separate publication approval. Existing
`.github/workflows/welcome-audio.yml` and general CI are not edited. Do not open
a PR merely to trigger this diagnostic, because that also triggers general CI.

```
node tests/welcome_audio_test.js
node tests/welcome_audio_capture_test.js
node tests/welcome_audio_browser_identity_test.js
python3 -m unittest discover -s ci -p 'test_*.py' -v
```

Offline tests use synthetic archive/export fixtures and browser identity/CDP
mocks. No local browser is launched. CI retains diagnostic metadata, preflight,
exact browser identity, raw observations and screenshots on failure or success;
it does not upload profiles or republish the reused game export.

## Observed diagnostic limitation

Run 37937211805 reached official sandboxed Chrome 154 but its first pre-input
screenshot took 871 ms and delayed input beyond the unchanged one-second gate.
That screenshot is now confined to the independent visual-only profile. The
same raw trial already had a running AudioContext and nonzero output before
input, so it cannot prove blocked-context gesture unlock. Its observed sampler
gaps were 203–254 ms, including gaps before the screenshot. Removing screenshot
interference does not establish that the 100 ms signal/control coverage limit
will pass. Preserve the limit and report inadequate coverage as inconclusive;
no audio-thread sampler, policy override or runtime timing change is included.
