# Opaque loading / HUD readiness follow-up

This local follow-up is based on the pre-baked candidate, not the rejected FIFO
scheduler. The separate first-gesture patch is not included yet.

On rendered launches with an active intro, the opening cover remains opaque while
the three atlas states become terminal and two actual draw passes warm the normal
HUD. The intro and world motion clocks stay at their original start. The Web loader
is released only after the next actual welcome frame. The native cover uses the
existing logo and reports the actual ready/3 count, never a fabricated percentage.

After8 seconds of pending preparation, unfinished atlases become failed fallback;
their temporary targets are released, and resumed/deferred bake continuations
cannot upload or restart. Original geometry remains available. This timeout is
checked between frames; it cannot preempt a single synchronous renderer call.
An interrupted preparation still releases to the ordinary restored restaurant HUD.
Held loading inputs and their releases remain owned. No save, account, audio or
platform notification policy is changed. The first visible frame discards loading
elapsed time rather than fast-forwarding gameplay or immediately ending the intro.

The native probe reports opening_preparation separately from welcome/descent and
records first_visible_game_post_draw_us plus preparation duration/counts/timeout.
A shorter visible stall is not described as less total loading work.

Local logic evidence: initial3,221 checks passed,95 synthetic DOM shell checks
passed, and final1,552 imported-resource/readiness/intro checks passed with no
engine errors. Evidence is in readiness-gate-qa-20261009 and
readiness-final-local-qa. Native visual/parity/timing and real browser acceptance
are still required; no smoothness improvement is claimed from these checks.

## Common diagnostic controls
The native workflow uses the same source-bound probe and summarizer against the
unchanged QA98 baseline, pre-baked-only df115a0, and this readiness candidate.
Each product commit is archived cleanly; the identical QA-only injected script
and runner have separate hashes, and original archive files remain verified.
Each trial pair has fresh temporary HOME/XDG/cache/profile directories. Memory
counters are collected on all three controls. Actual atlas regeneration and ten
fixed-position captures remain separate from uninstrumented timing samples.
Native cloud editor observations are preliminary only because editor import and
shader-cache history are not a fresh CI control. The local 1315x851 render had
no descent interval above 100 ms, but this does not prove exported-Web performance.

## Final readiness ordering check
Only post-draw events after all atlas states were sampled terminal count toward
release. Ten earlier warming draws plus one final-ready draw keep the cover; the
second final-ready draw releases it. Cancellation is tested at all three await
positions in each of the three real atlas builders; resumption cannot upload a
texture or retain a pending viewport. Final focused checks: 42 readiness, 16
pre-baked imports, 1,514 intro lifecycle, all passing without engine diagnostics.
