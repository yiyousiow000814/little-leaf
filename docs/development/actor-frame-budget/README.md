# Actor frame budget, first cut

Base commit: `ac626bc9210d880570308df78cd3792c2618b1f6`. [Flow](actor-work.mmd) · [Timing ledger](actor-budget.xlsx).

Target: at most 1 ms/frame for the combined measured actor simulation and drawing workload, without changing service rules, movement, animation, or visual occlusion. The historical 26.969 ms/frame stress reference (30 guests, 22 staff, 600 frames) is not an exact-base comparison. No full-frame result for this patch is claimed.

- Guests carry the result of the first clear segment check into the loop once. The short proposed move, subsequent legs, rerouted legs, and obstructed/zero-delta handling still follow the original checks.
- Staff skip hashing the finished path when the route cursor has reached its end. Route storage, live claims, active-route validation, and stall rules are not changed.
- Order-table selection reuses the route length already established by the live work-cell verdict when both checks start at the same cell. A caller with a different start still performs the original second route check. Claims, rear-face order, and stall handling stay live.

Pinned Godot 4.6.3 headless: 2,075 assertions across six repository suites on the combined gameplay patch; the 85-input / three-atlas guard remains unchanged and passes. The order suite covers same-start, different-start, pinned rear, and live claim behavior. A private differential harness checked 8,004 state/trace cases, including detours, blocked starts, zero movement budget and multiple legs; 3,374 cases removed exactly one redundant check. Its nine alternating pairs on one occupied-grid walk case had median costs of 0.008997 and 0.006848 ms/call before and after, including fixture reset. These are local microbenchmarks, not savings per frame. No diagnostic instrumentation is part of the product changes.

The separate renderer candidate is not part of this gameplay patch. Its cooking-only gate passed four pinned headless suites (18,260 assertions) and matched ordered drawing commands/contact geometry for 3,312 cases. A mixed 22-staff workload with one cooking body plus one reach overlay performed 464 → 2 staff-row visits in the stove-heat lookup; an all-cook workload retains the old lookup count. Exact visual and atlas qualification is still required before adoption.

## Workface follow-up: reviewed locally, not a release candidate

The control and candidate in each comparison run the same fixed 600-tick
headless workload (30 guests, 22 staff, 67 items, 12 starting litter). Each
pair is an independent before/after test of its own source step, not an
additive FPS estimate. See the **Workface sweep A-B** sheet for all four runs
per step. The checkout membership candidate selects work positions in about 2.48 ms/tick,
including 1.42 ms for table work. Neither the 0.5 ms selection target nor the
1 ms combined actor-frame target is verified.

The execution sweep shares furniture geometry and checkout membership only
within one uninterrupted scope. The ordered cell index filters peer candidates
but does not decide whether someone owns a cell. Contenders, work reach, route
distance, work rankings, and actual claims remain live. Publishing a worker
updates the current sweep's membership. Discard the sweep projections before
the synchronous checkout settlement callback; the next query builds from the
current layout and reservations. Out-of-sweep reads use authoritative state.
Same-cell churn can still expose a quadratic path, so there is no general
no-quadratic guarantee.

The checkout membership change reduces the checkout scan from O(F×G) to
O(F+G) across one uninterrupted sweep with F queries and G guests. Instrumented
table checkout scans were 15,856 before and 267 after, with equivalent work
counts and final state. The final candidate passed 2,948 native checks and a
targeted live callback regression. Source is not pushed: refreshed source-bound
atlas/pixel evidence and the normal CI gate are required first. No diagnostics
belong in the production source.

## Prepared occupancy, pinned headless check

Two workface predicates can reuse the navigation occupancy map already prepared
for the current staff tick. They retain x bounds, owned-floor checks and the
first-item/rug precedence. There is no new map or content hash per probe. Before
the checkout callback the view is invalidated, and subsequent checks that tick
use the authoritative item scan. Ordinary calls outside the prepared scope also
use that scan.

On pinned Godot 4.6.3 with the unchanged UI sources, the headless ABBA test
averaged 2.376 → 2.107 ms/tick in total selection (11.3% lower). Table selection
averaged 1.362 → 1.194 and floor selection 0.661 → 0.604 ms/tick. Each run's
600-tick workload matched, with 26,492 selections, 206 route searches,
identical final state and zero saves. Nine occupancy cases and the checkout
callback regression passed; omitting invalidation reproduced a wrong cell.
See the **Workface sweep A-B** tab for the four exact runs and **Occupancy A-B
exploratory** for the separate, noisier Godot 4.7.2 comparison. This is not a
full-frame FPS result, a 0.5 ms pass, or a published change.

## Prepared route geometry, pinned headless check

Workface route queries reuse the already prepared navigation signature while
inside the valid synchronous sweep. They keep the same starting-cell cache
keys, result lengths, and tie-breaking. Outside the scope, and after the
checkout callback, they compute the current signature through the original
path. The change does not hoist assignment signatures or inner route searches.

In a separate pinned Godot 4.6.3 ABBA using prepared occupancy as the control,
total selection averaged 2.161 → 1.897 ms/tick. Table selection averaged
1.228 → 1.065 and floor selection 0.619 → 0.571 ms/tick. All four 600-tick
runs retained the exact observed workload and final state. The real checkout
callback read the updated signature; disabling invalidation exposed stale
route keys. See the **Workface sweep A-B** tab. This is a workface measurement
only, not a full-frame FPS result, the 0.5 ms target, or a published change.

## Draft successor on the integrated main branch

This source-only successor is based on `3e58b3f9c8a5fbc627b28303564c716ff4825195`.
It preserves the #398 guest segment change and combines it with the measured
staff workface changes. Earlier workface rows isolate staff costs on the
pre-guest-change model. A new pinned Godot 4.6.3 ABBA keeps the **same #398
guest model on both sides** and changes only Main's route-geometry reuse.
Selection averaged **2.149 → 1.908 ms/tick**, table **1.217 → 1.064** and floor
**0.620 → 0.577**. All four 600-tick runs matched observed work (26,492
selections, 206 route searches), final state, and zero saves. This is not
an estimate of the guest improvement or a full-frame result. Mail and Storage
tests bind the new current Main separately; historical pixel and atlas receipts
remain unchanged.
