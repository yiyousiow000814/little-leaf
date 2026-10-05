# Actual Web wall-save compatibility gate

Implementation status: local offline guards and syntax checks only. The new native
layout preflight and actual browser scenarios have **not been executed**. A passing
native suite or deterministic storage fixture is not real browser proof.

The required CI job now builds the candidate once, checks out historical source
`9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc` separately, runs that checkout's own
tests/exporter once with the same pinned official Godot/template, and reuses the
shared Playwright 1.63.0 installation with the official Chrome channel. No game scripts, release version, prices,
timers, save formats or security settings are changed by this test patch.

## Inputs and boundaries

`tests/fixtures/wall-compatibility/contract.json` pins the original fixture bytes
and exact historical vault. Each run binds the clean candidate checkout's complete
production hash map to its staged source and verified export, and records that map
and both exact manifest digests in `preflight.json`. The browser requires that same
receipt, checks every export asset and production source again, and refuses a
source/receipt/manifest mismatch. This lets the behavior gate test each new candidate
without redundant hardcoded current-source hashes. The candidate vault now includes
the Inbox projection and is not declared identical to the historical vault.

Both full exports must have a `release-manifest.json` from their own existing
`ci/build_web.py`, marked `checksum-pinned-official-archives`. Commit identities,
source/packed bytes and installer receipts are checked. The helper derives click
coordinates from each exact source in a disposable native project, validates both
fixtures with the candidate codec, and confirms the expected one-tile edit.
This helper is never included in a shipped pack and is not browser evidence.

The hosted browser uses preinstalled official Google Chrome with its sandbox enabled, fresh ephemeral contexts, and different old/new
paths on one fresh loopback origin. Non-loopback requests are blocked. Only synthetic
signed-byte legacy data is seeded. The real historical vault creates the initial
identity, provenance and retained 1000-coin receipt. No real player save, production
origin, credentials or persistent browser profile is used.

Pass-through observation counts real IndexedDB mutations/transaction outcomes and
the actual controller's save callbacks. It preserves original arguments, receiver,
callback data and return value; it neither stubs the bridge nor changes validation.
Screenshots of existing Help are cropped to the exact panel and checked by locally
installed Tesseract with one OCR thread and a 30-second bound. Source
strings or native flags cannot substitute for rendered recovery text. Missing or
ambiguous OCR text fails the gate and retains its screenshot, crop and OCR output.

## Required scenarios

1. An actual old export opens a committed format-2 fixture, shows existing recovery
   Help and the invalid-wall diagnostic, retries twice, receives ordinary UI input,
   and stays unchanged through a real 16.5-second autosave observation. All authority,
   identity, previous, digest, receipt and legacy bytes must remain unchanged, with
   zero old-client mutation calls. A new actual export then reloads and completes a
   normal UI save while preserving walls, openings, wallet and receipt
2. An actual old engine first proves normal format-1 UI saves. It remains loaded at
   R while the actual new engine edits back segment 2 through the ordinary wall
   picker and confirmation UI, saving exactly R+1. The old normal UI action must
   receive `REVISION_CONFLICT`, show existing protection Help, and suppress repeated
   UI/lifecycle attempts. Old reload must reject the new format; new reload must
   validate and preserve it without compensation or opening changes

Case B verifies the rendered Build catalog, wall picker, selected half-wall product,
and exact one-tile confirmation before continuing. Native preflight supplies the
bounded OCR rectangles. Only idempotent Build category selection may retry while
the real opening tween still disables input; the confirmation is clicked once.
The gate requires zero new-client saves before that verified confirmation and
retains the expected/actual wall segment if the final state assertion fails.

The old stale-tab case uses the supported `--time-scale 0` argument. The new edit
uses `--time-scale 0.1` so real GUI tweens finish, while its autosave interval is
150 seconds. The old recovery/autosave case uses scale 1. No production timer is
changed. A legitimate new page-hide save is allowed to advance revision, then the
new page is closed before the forbidden-old-write snapshot is frozen.
The shared `engine_launch_hook.js` binds the actual exported shell instance before
startup; it forwards the original feature result, startup receiver, options and
return value while appending the official runtime arguments.

## Execution after authorization

The reusable `build-web.yml` requires every stage before the job can pass. It
retains the engine-tested Web export before browser validation; that early artifact
is not browser-pass evidence, and a later browser failure still fails the job. It installs
Tesseract and the English language data from the runner's Ubuntu repositories and
records its version. The hosted runner selects `PLAYWRIGHT_CHROMIUM_CHANNEL=chrome`
for both browser gates and installs only browser dependencies. The browser receipt
records the selected channel, actual browser and Playwright versions, and sandbox
state. This does not relax the sandbox or authorize a local denied launch.

For an already prepared pair of exact exports:

```sh
python3 ci/prepare_wall_compatibility.py \
  --old-source /path/to/exact-old-checkout \
  --old-build /path/to/old-web-build \
  --new-build /path/to/new-web-build \
  --output /path/to/new-web-build/evidence/wall-preflight

PLAYWRIGHT_CHROMIUM_CHANNEL=chrome \
PLAYWRIGHT_MODULE=/path/to/node_modules/playwright xvfb-run -a \
  node tests/wall_compatibility_browser.js \
  --old-source /path/to/exact-old-checkout \
  --old-web /path/to/old-web-build/web \
  --new-web /path/to/new-web-build/web \
  --layout-dir /path/to/new-web-build/evidence/wall-preflight \
  --output /path/to/new-web-build/evidence/wall-browser
```

Required: exact old/candidate checkouts, both verified exports, matching native
layout/preflight receipts, sandbox-capable official Chrome through Playwright 1.63.0, and
local Tesseract with English data. `GODOT_BIN`, `GODOT_TEMPLATE`, and
`GODOT_TOOLCHAIN_RECEIPT` identify the verified tools for the native preflight.
`PLAYWRIGHT_MODULE` is optional when Playwright resolves normally.
`TESSERACT_BIN` is optional when Tesseract is on PATH; it may be an absolute path
to a separately verified local installation. OCR is required, not an optional pass.

The Node runner supports Windows paths and needs no Xvfb on Windows. The existing
repository installer/export receipt contract is Linux-specific: Windows may run
the browser stage using transferred exact Linux exports and layout receipts, but
an unrelated Windows `--local-tools` export does not satisfy this gate. In
particular, a receipt/export pair for earlier `04decd2` cannot stand in for another
candidate's exact source. No active Windows task or successful browser assertion is
assumed.

## Retained evidence

Only sanitized JSON/logs, exact input/export hashes, authority/progress digests,
mutation/rejection counts, viewport PNGs and OCR text are retained. No browser
profiles or full IndexedDB dumps are attached. `wall-compatibility-browser.json`
sets `browser_verified: true` only after both real scenarios and script/browser
error checks pass. Keep the first CI run's failures visible; do not replace failing
UI/codec assertions with native flags or direct test-only commits.
