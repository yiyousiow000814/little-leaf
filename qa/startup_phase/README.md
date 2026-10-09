# Diagnostic-only real-Web startup UI/music subphases

This is a local, unpublished test tool based on production source commit
`29974be8f124832083d4b2852131ad9ea32abe24`. It is not a runtime optimization,
release export, browser acceptance result, or replacement for existing release CI.
Production checkout files and CI workflows are not edited. Only disposable staged
`main.tscn` substitutes the script resource; `project.godot` still boots that same
single `LittleLeafCafe` Node3D scene normally. The ordinary Web shell, storage
bootstrap, main controller, `_load_startup` and `WebSave.load_startup` remain real.
No MinimalStart replacement, fresh-review flag, mocked vault, or save suppression
is introduced. Real fresh browser storage is provided by a new disposable context.

## Boundaries and interpretation

The instrumented subclass calls `super()` once for `_ready`, `_load_startup`,
`_setup_world`, `_rebuild_room`, `_rebuild_furniture` and `_restore_service_runtime`.
For `_build_ui` and `_setup_music`, `subphases.py` extracts exact method bodies
from the immutable production source and inserts only in-memory mark statements.
Stripping those inserted statements must reproduce each original method byte for
byte or preparation fails. This diagnostic-only substitution is never applied to
production files. Changed source anchors fail closed rather than guessing. A preallocated 128-entry integer buffer records
monotonic microseconds in memory. No diagnostic JS bridge, dictionaries, JSON,
logging, screenshots, or trace hooks run at method boundaries. The first
`frame_post_draw` callback is registered before inherited `_ready` and timestamps
before the base Web-ready notification. A deferred callback then emits exactly
one JSON object to `window.__littleLeafStartupPhasePacket`. The native fallback
prints one JSON packet only if a genuine post-draw signal occurred. Headless
normally has no such signal; missing packets are not manufactured.

`packet.schema.json` documents v2; `validate.js` checks exact source/overlay
identity, expected nested order, one call per method, freshness, real Web save
readiness, monotonicity, and no overflow. Durations are inclusive elapsed method
spans, not isolated CPU time. `_ready` includes nested methods and must not be
added to them. The unwrapped residual includes controller glue and probe overhead.
Fifteen subphase spans cover UI header, Settings, catalog/tray, build tools and
compact UI; and each music track’s resource load, stream duplication and player
node setup, plus initial service-track switching. These spans nest inside UI/music
parents and must not be added to the parent spans or `_ready`. The load boundary
includes whatever resource work Godot performs; it does not alone prove decoding.
The first post-draw signal does not prove display presentation or GPU completion.

The only observed pre-`_ready` interval is the first mark's value relative to
Godot's monotonic timer origin. It includes unknown engine/scene work and the
extra subclass's parsing/initialization/allocation. It is not time since browser
navigation. Browser `performance.now()` records loader removal, rAF callbacks and
packet receipt independently. No clocks are silently aligned; neither domain
can identify a WASM, GDScript, download, asset, or shader share of pre-ready time.

## Control and unavoidable overhead

Both staged projects have identical entry scene structure and production input
bytes, except for the contents of `qa/startup_phase/main.gd`. The control is an
empty subclass of the real controller and emits no packet. Both differ from the
release's direct script reference. The instrumented variant additionally changes
script parse/export size, allocates the mark buffer before `_ready`, copies two method bodies (changing parsing cost even when executable statements
match), adds virtual wrapper dispatch/timer writes and a draw-signal subscription, and serializes and
bridges after first draw. Post-draw emission can affect subsequent loader/rAF
observations. The supplied rAF timestamp can be stale; only actual callback execution
time at/after observed loader removal identifies the loader-absent scheduling phase. The shared browser collector also has overhead, present in both.

Use same-run control/instrumented/instrumented/control ordering with fresh cafe
storage for both cold and warm HTTP-cache navigation. Report raw paired deltas
and spread; never subtract an invented per-mark cost. HTTP warmth is not warm
Godot atlas state: each navigation makes new engine/atlas objects. Native results
cannot qualify Web startup. No performance number is claimed by this handoff.

## Offline preparation and tests

Use a new output directory outside the checkout. Python/Node tests need no network,
engine, browser, player saves, or installed packages:

```sh
python3 -m unittest discover -s tests/startup_phase -p 'test_*.py' -v
node tests/startup_phase/test_validate.js
python3 qa/startup_phase/prepare.py --expected-source "$(git rev-parse HEAD)" --output /tmp/little-leaf-phase-pair
```

`pair.json`, frozen `overlay-source/`, and each `diagnostic-manifest.json` preserve
source commit/tree, the complete original production SHA-256 map, exact diagnostic
project input hashes, all helper/template hashes, pair and per-mode overlay IDs.
Changing any helper changes the pair identity; recreate the pair after edits.
Actual exported files additionally get byte counts and SHA-256 digests.
The output intentionally contains no `release-manifest.json`; existing release
validators reject it. `diagnostic_only=true`, `release_qualified=false`, and
`release_qualification_prohibited=true` remain unconditional, even if CI passes.

## Authorized CI execution handoff (not executed in a local browser)

These commands are instructions for the separately authorized existing CI runner;
this change adds no workflow, publishes nothing, and does not authorize execution.
Use the repository's existing checksum-pinned installer/toolchain receipt,
Godot 4.6.3 and matching non-threaded Web release template. Never change sandbox
settings or route around a denied browser/display action.

1. Keep the production checkout detached at the selected pinned source commit.
   Local evidence uses `29974be8f124832083d4b2852131ad9ea32abe24`; the existing
   publication receipt maps it to remote `6eaac7542c6df5c57ab6a8dc9f17b26e3dd4318e`,
   both with tree `bf1c2a8859da44c2c08daf24a34e4ab053fee5a3`. For GitHub CI,
   check out that remote commit and verify the tree equals this value. Its
   commit-bound pair/overlay IDs will intentionally differ from this local pair.
   Copy the
   supplied `qa/startup_phase/` and `tests/startup_phase/` overlay directories into
   that checkout as untracked diagnostic files, preserving their provided hashes.
   Do not commit them and then claim that new HEAD is the pinned production source.
   If a future reviewed source commit is intentionally chosen, pass its exact
   `--expected-source` and generate new source/pair/overlay identities; old evidence
   cannot transfer. Run the offline tests against this exact overlay package.
2. Install/locate tools with the existing approved CI setup, then export both:

```sh
python3 qa/startup_phase/prepare.py \
  --expected-source 6eaac7542c6df5c57ab6a8dc9f17b26e3dd4318e \
  --output "$RUNNER_TEMP/startup-phase-pair" --export \
  --engine-lock "$RUNNER_TEMP/startup-phase-engine.lock" \
  --godot "${GODOT_BIN:-godot}" --template "$GODOT_TEMPLATE" \
  --toolchain-receipt "$GODOT_TOOLCHAIN_RECEIPT"
```

Export takes the lock, uses isolated HOME/APPDATA/XDG saveguard directories per
mode, checks import/export errors, and verifies original staged inputs afterward.
For this shared cloud executor, coordinate and use
`/workspace/scratch/6cfb791ccd66/.cloud-engine.lock` instead of an unrelated lock.
Do not use native GUI or real profiles. Local unverified toolchains are recorded
as such and cannot become release-qualified.

3. In the existing approved Ubuntu CI Xvfb/Chrome route, with the existing pinned
Playwright module, run:

```sh
PLAYWRIGHT_CHROMIUM_CHANNEL=chrome \
PLAYWRIGHT_MODULE="$RUNNER_TEMP/startup-browser-tools/node_modules/playwright" \
  xvfb-run -a node qa/startup_phase/run_browser.js \
  --source-root "$PWD" --pair "$RUNNER_TEMP/startup-phase-pair" \
  --output "$RUNNER_TEMP/startup-phase-browser"
```

The runner verifies every source/helper/export hash before opening the browser,
retains the normal Chromium sandbox, verifies every request stayed on its disposable loopback origin,
uses no user profile or external service, leaves request routing disabled so HTTP cache works, and checks the actual vault reports
`source=fresh` on every trial. It clears only that new origin's generated storage
between cold/warm trials while preserving HTTP cache. No traces, screenshots,
input or audio reads contaminate timing. The output preserves raw marks, inclusive
summaries, callback timestamps, cache evidence, engine/browser/GPU identity,
source/overlay bindings and errors. Uncaught page errors, console errors and Godot
`ERROR:`/`SCRIPT ERROR:` messages fail the trial; no noise allowlist is currently used.
Failed trial observations and error messages remain in the report. A passing packet is required only for the
instrumented case; any control packet is a failure.

4. Retain the whole pair, frozen helpers, import/export logs, both manifests,
raw `startup-phases.json` and diagnostic-only label. Do not feed them to release
qualification or make release/visual/audio/FPS claims. Actual browser execution
remains pending until an authorized CI run produces and validates this evidence.
