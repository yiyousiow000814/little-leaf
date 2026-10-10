# Memory regression standard

This standard applies to renderer, export/runtime, resource-cache and lifecycle
changes that can affect allocation or retention. Use the smallest workload that
observes the affected mechanism. Current release readiness belongs in the
[roadmap](../roadmap.md); a completed short diagnostic never certifies all leaks
absent. Preserve official toolchain, atlas, source and save acceptance gates.

## Ordinary CI: fast deterministic lifecycle checks

The normal tooling discovery includes
`test_bound_web_gl_handles.py::test_live_handles_and_retained_capacity_under_repeated_lifecycle`.
It applies the real patch implementation to a small pinned-function fixture and
runs the existing Node lifecycle test for 20,000 cycles. Native GPU deletion is
stubbed; the fixture hash allowance exists only inside the test. Production
export hash/anchor guards stay mandatory. No engine, browser, save or cloud
session is started by this check.

The test keeps three live survivors and permits one temporary object per target
table. Its fixed initial global-ID namespace gives buffer/VAO/sync capacity
5/6/7 after warmup; all later identical cycles must retain those lengths. Live
identities, positive IDs, duplicate/zero/invalid deletion, buffer-binding cleanup,
cleared object names and sync errors are checked. The global counter must stop
at its justified fixture value (9 after two unrelated texture allocations).
These numeric bounds belong to this fixture, not to arbitrary real cafe scenes.
The deletion stub counts calls without retaining every deleted object itself.

For other resource-owning changes, add a similarly short ownership regression
that checks release and repeated lifecycle behavior. Use existing ordinary CI
discovery; do not add a long browser soak or a broad matrix to every PR. A test
that only recreates the implementation, counts elapsed time, or checks allocation
without observing release does not establish a memory regression boundary.

## Release gate: focused browser soak and trend evidence

For a release containing a memory-affecting change, run a source-bound real
browser soak in an owned disposable profile. Warm up the chosen scene until its
live resource inventory has settled, then observe at least 30 minutes of the
specific affected workload. This duration is a minimum observation window for
slower growth than the reproduced three-minute leak; it is not a proof that no
longer-term leak exists. Longer or state-dependent symptoms require a longer
focused run. A shorter urgent diagnostic must be marked incomplete against this
gate and must not silently become the future baseline.

Select relevant resource/scene/reload triggers from the change: repeated scene
entry/exit, creation/deletion, camera/cache invalidation, supported context
recreation, or page reload/close. Exercise at least ten identical cycles of each
selected lifecycle and prove that prior objects, callbacks and page resources
are released. Do not turn this into a default cross-product matrix. Repeated
reload must distinguish per-page JS retention from total owned-browser/process
retention; a fresh page alone can hide a retained old context. Unsupported
transitions remain explicit gaps. Keep other owned renderers/profilers outside
the timed window, block cloud access unless that exact path is authorized, and
never inspect or clear original player storage.

Record exact source commit/tree, export manifest and file hashes, engine/template
provenance, browser/device, viewport/DPR, profile/fixture, visibility/focus,
workload, warmup and elapsed time. Keep timestamped intermediate samples and
before/after collections, not just two screenshots. Forced GC is diagnostic only
in the disposable test page: record its API/success and let unsupported collection
remain a limitation. Do not add forced GC to gameplay or call ordinary heap dips
equivalent to post-GC evidence.

Measure both live inventory and retained capacity: JS used heap after collection,
Wasm bytes, targeted GL table lengths/live/free counts, and the relevant
texture/mesh/node/listener/audio/cache ownership counters. Include process/GPU
measurements only with their attribution limits; a shared GPU process cannot
identify one page's owner. Freeze measurement buffers before exporting evidence.

For a repeatable settled workload, table capacity and free pools must stabilize
after the maximum simultaneous live inventory is reached. Growth on every
identical allocation/deletion cycle with unchanged live peaks is a failure even
when the live count returns to zero. Extra retained slots can reflect the shared
global namespace or a new legitimate live high-water mark; explain that demand
instead of treating capacity as a live-object count.

Heap/resource budgets must be written before judging the candidate and justified
by the matched control's measured collection noise, known retained live additions
and repeated-cycle high-water marks. Block on reproducible post-GC growth beyond
that stated budget or continued capacity growth after live peaks settle. Do not
invent a universal MiB limit, normalize the leak into the budget, extrapolate a
three-minute rate to an entire day, or equate stable Wasm with stable JS/GPU.
If no adequate control/noise bound exists, report the release gate unqualified.

## Measured fingerprint and acceptance boundary

The [WebGL candidate](webgl-memory.md) supplies the initial measured mechanism:
the deployed runtime retained another 73.83 MiB after collection in 181 seconds.
On the same current-main artifact and matched 180-second workload, deletion-name
reuse reduced buffer capacity from 62,200 to 4,612 with 2,774 live objects at both
endpoints; post-GC heap growth changed from 1,073,160 to 385,476 bytes. Exact live
VAO/sync counts also matched. This supports the fix and the deterministic bounds;
it does not qualify the longer soak, all-scene parity, context recreation,
mobile/hosted behavior or every possible OOM contributor.

Keep code review, deterministic checks, inspected frames, soak/trends, complete
CI, merge and release separate. Preserve raw evidence/hashes and editable probes
outside tracked source. A failed experiment remains visible; refreshing a guard,
atlas reference or baseline to make a failing run pass requires its existing
qualification and review. Fix or withdraw a regression before acceptance.
