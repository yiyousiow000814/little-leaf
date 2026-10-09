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

All nine click/touch/Enter × enabled/disabled/zero cases, continuous running-clock
silent controls, finite-signal requirements, RMS thresholds, timing windows,
frame limits, fresh profiles, blocked external requests and screenshot/OCR gates
are unchanged. A pass establishes only the existing BGM-correlated WebAudio
signal claim. It does not establish physical audibility, tune identity, full
release qualification, startup performance or human visual acceptance.

## Scope and offline review

The new workflow runs only on `qa/welcome-system-chrome-artifact` and checks out
the triggering QA SHA. A push needs separate publication approval. Existing
`.github/workflows/welcome-audio.yml` and general CI are not edited. Do not open
a PR merely to trigger this diagnostic, because that also triggers general CI.

```
node tests/welcome_audio_test.js
node tests/welcome_audio_browser_identity_test.js
python3 -m unittest discover -s ci -p 'test_*.py' -v
```

Offline tests use synthetic archive/export fixtures and browser identity/CDP
mocks. No local browser is launched. CI retains diagnostic metadata, preflight,
exact browser identity, raw observations and screenshots on failure or success;
it does not upload profiles or republish the reused game export.
