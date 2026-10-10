# Fresh ordinary-Web tutorial gate

`tests/fresh_tutorial_browser.js` runs one isolated, first-time-player journey
against the exact ordinary Web export. It uses a new Chromium context and a new
localhost origin with no saved state. It does not install an engine hook, change
launch arguments, skip the intro/tutorial, seed storage, accelerate time, create
guests, or call gameplay methods.

The gate waits for the ordinary intro and initial autosave while the café is
closed. It clicks the actual Open, Staff, Staff Done, Decorate, return, and final
Done controls. It requires screenshots and OCR of the guide at those stages,
a naturally seated guest receiving an order, the meal-on-the-way cue, genuine first
payment, and completion through the real final control. Acknowledged production
save snapshots are read only. Across the journey, earned money must equal real
meals, the wallet must reconcile with those earnings and normal wages, furniture
must remain unchanged, and the guide cannot complete before payment.

The source of coordinates is `test_interactive_tutorial.gd`'s `web_layout`
receipt at 1360 × 880. This receipt contains only control centers, guide bounds,
text, tutorial steps, and baseline economy constants. It is not a saved profile
and is never injected into the browser. The aggregate runner hashes emitted
result files. The browser requires the exact coordinate hash in the full engine
report and the exact report hash in `release-manifest.json`, checks the source
commit and production hashes, and verifies exported asset hashes before launch.

## CI invocation

The existing complete engine suite and ordinary export remain prerequisites:

```sh
python3 tests/run_integration_candidate.py --output "$RUNNER_TEMP/engine-evidence"
python3 ci/build_web.py --output "$RUNNER_TEMP/web-build" \
  --test-report "$RUNNER_TEMP/engine-evidence/summary.json"
PLAYWRIGHT_MODULE="$RUNNER_TEMP/inbox-browser-tools/node_modules/playwright" \
PLAYWRIGHT_CHROMIUM_CHANNEL=chrome \
xvfb-run -a node tests/fresh_tutorial_browser.js \
  --web-build "$RUNNER_TEMP/web-build/web" \
  --output "$RUNNER_TEMP/web-build/evidence/fresh-tutorial-browser" \
  --layout-report "$RUNNER_TEMP/engine-evidence/test_interactive_tutorial-result.json" \
  --engine-report "$RUNNER_TEMP/engine-evidence/summary.json"
```

Use the workflow's checksum-pinned Godot and official Web template, pinned
Playwright 1.63.0, sandboxed Chrome under Xvfb, and Tesseract English. Startup,
opening, arrival, order and genuine payment retain their 220-second service cap
and all existing per-stage deadlines. Only a payment observed before that cap
starts a separate completion allowance: 25 seconds for the title, 25 seconds for
exact Done OCR, and 30 seconds for the completed save, at most 80 seconds total.
The real final click and final screenshot must also fit that allowance. It cannot
be restarted; the complete journey is capped at 300 seconds. The six-minute CI
step includes retained-image OCR, setup and cleanup; the job remains 55 minutes.
Normal autosave latency is over
15 seconds; tutorial transitions also save normally. Expect roughly two minutes
of real gameplay including startup and the initial closed autosave.

The report, OCR text, stage screenshots, and failure screenshot are retained in
`web-build/evidence/fresh-tutorial-browser/`. Existing compatibility, Inbox,
save-log, and WebKit recovery gates are unchanged and remain mandatory.

The compact guide mixes a cue, small progress text and a separate action label.
OCR uses sparse segmentation (`--psm 11`). If the required phrases are absent,
one adaptive-threshold attempt reads the same unchanged screenshot. CI checks
the exact failed-run card crop and a native ordering screenshot before the live
journey; their source and byte hashes are in `tests/fixtures/tutorial-ocr/`.
Those image regressions prove recognition only. They cannot prove browser play.
Each live stage records its crop, attempts, both OCR outputs and any operation
error before another wait; it does not start a new capture with less than one
second remaining. Exact text, real control, normal-time and economy requirements
are unchanged.

The completion title and its small Done action are verified separately. The
button crop is the44×44 target centered on the existing native-derived point,
fully inside the source-bound card. A detached canvas repeats each original
pixel2× for OCR; the raw screenshot remains available. The button must read
exactly `Done`, so `Dor`, similar spellings and unrelated text cannot pass.
The original real click, durable completed-state check and unchanged payment
balance check still follow. Retained CI #101 pixels supply positive and
title-only negative image regressions; recognition tests alone do not establish
successful dismissal in a browser.

CI run 37823116282 reached genuine payment at 211.731 seconds, but its remaining
220-second shared budget expired before Done OCR could attempt recognition.
The separate completion allowance fixes that verification-budget defect without
extending service time. Deterministic clock regressions cover late valid payment,
expired service, missing completion text, phase expiry and the overall ceiling;
the original exact-label negative fixtures and economy assertions still apply.

## Transient moving-cue evidence

The order guide initially says `Guest on the way…` while the natural guest is
arriving. `Your waiter takes the order` is visible only between that phase and
the genuine `order_done` transition, which changes the guide to `Meal on the way`.
Serial full-frame OCR can spend that entire interval recognizing an older frame.
The retained final frame from run 37839992841 shows the meal cue and a seated
customer; the run overwrote earlier captures, so it cannot prove what those
pixels showed or measure how long the waiter cue was readable.

After the real return click, the gate immediately starts a raw screenshot
sequence, with 500 ms between captures, concurrently with one asynchronous
Tesseract process. It reads only ordinary acknowledged saves. On the first
saved seated order, OCR revisits unread frames immediately preceding that save,
newest first. Both moving phrases still need their own exact rendered evidence;
a later meal, order, or payment never proves that the waiter cue was visible.
The matched waiter frame must precede a distinct matched meal frame, regardless
of which OCR result finishes first.
Scaling occurs only when recognizing an archived image, on the same detached
2× nearest-neighbor canvas. A first-mode OCR timeout still permits the bounded
adaptive attempt on those same pixels. Gameplay continues naturally throughout.

The return save keeps its 30 s limit. Arrival OCR has 45 s from the return click;
order observation has at most 45 s after arrival recognition; the meal has 20 s
from its first genuinely observed order. Earlier observations do not restart
those deadlines. Both capture and OCR must finish within the unchanged 220 s
service budget. The existing 80 s completion and 300 s overall caps, real final
Done control and payment/economy assertions are unchanged. Snapshot, capture,
and recognition callbacks also have operation deadlines; a failed observer
cancels its peer and any pending OCR subprocess. Late callbacks cannot resume
writing evidence after cancellation.

Every raw capture has a unique filename, capture start/end timestamps,
before/after acknowledged-save revisions, SHA-256, and the verified
source/export binding hash. Processed frames retain each OCR mode/output,
recognition time, and separately hashed 2× input. Successful stage aliases copy
the matched frame rather than taking a later screenshot. Failures retain the
whole sequence, including unrecognized frames. The sequence is bounded by 220
raw frames and a 128 MiB evidence-size limit (checked after each write), and never
runs more than one OCR process. These are failure bounds, not new gameplay time.

Fast regressions exercise delayed recognition across a short cue, independent
wrong/missing labels, missing genuine saves/orders, capture/input/source
binding failures, hung callbacks, reversed/same-frame cues, frame/byte bounds,
and expired local/service budgets. Existing
real OCR fixtures remain unchanged. Synthetic timing tests and retained image
recognition are not a live browser pass. Hosted CI must establish the actual
ordinary-Web journey. The new timestamps can help investigate cue readability;
sparse matched samples alone must not be reported as its full visible duration.

## Local checks without a display

```sh
node --check tests/fresh_tutorial_browser.js
node tests/fresh_tutorial_browser_test.js
node tests/fresh_tutorial_browser_test.js --ocr-fixtures # needs Tesseract English
node tests/wall_compatibility_helpers_test.js
python3 -m unittest discover -s tests/tooling -t . -p 'test_*.py' -v
python3 tests/run_integration_candidate.py --only test_interactive_tutorial \
  --output /tmp/fresh-tutorial-coordinate-evidence
```

A focused engine run supplies layout validation only. It is not a browser pass
or a substitute for the complete aggregate required by the export. The actual
rendered browser gate must run on a display-capable CI worker before claiming
that the fresh ordinary-Web journey passed.
