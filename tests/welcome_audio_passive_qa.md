# Passive observation and retained failure diagnostics

PR114's run 37940190514 collected all nine audio profiles, then failed because
whole-screen sparse OCR did not find `Esc to skip` in its first visual profile.
The retained PNG visibly contains the text. This is separate from f690 run
37943088876, where bundled Chromium could not initialize its sandbox and no
music trial ran. The existing explicit official Chrome154 route remains in use;
no sandbox or autoplay setting is weakened.

All page observations now use CDP `Runtime.evaluate` with `userGesture:false`,
including preference seeding and readiness polling. Playwright 1.63's ordinary
evaluate requests user activation; an isolated browser reproduction observed
inactive -> active without any input. That makes ordinary evaluate unsuitable
for the pre-gesture audio baseline. The observer, graph, real input path and
all numeric signal/coverage/frame limits remain unchanged.

Whole screenshots are preserved. After capture stops, the welcome title still
uses whole-image OCR; the hint uses an unscaled crop of those same original
pixels with single-line OCR. Crop coordinates, source PNG digest, crop digest
and recognized text are retained. Missing or wrong text still fails; no fuzzy
match or source-string substitute is accepted. Cropping adds no timed screenshot.

`browser-events.jsonl` records phase changes, all console levels (including
autoplay warnings), page exceptions, request failures, HTTP statuses and crashes.
Failure reports include phase, kind and stack, and are written before profile
cleanup. Raw audio/context/input/frame observations are retained on failure.
CI prints the error stack instead of only returning exit code 1. These logs do
not record physical speaker output or every Godot music state transition.

The separate Windows headless f690 reproduction passed click/touch/Enter with
enabled, disabled and zero-volume settings (nine profiles), with no pre-input
signal and sustained enabled post-input output. Its 10 export files and all 276
production inputs match the immutable manifest/Git source. This is supplemental
diagnostic evidence, not a replacement for this PR's older pinned artifact,
headed Linux/OCR checks, or current composed-candidate acceptance.
