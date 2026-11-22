# Actor frame budget, first cut

Base commit: `ac626bc9210d880570308df78cd3792c2618b1f6`. [Flow](actor-work.mmd) · [Timing ledger](actor-budget.xlsx).

Target: at most 1 ms/frame for the combined measured actor simulation and drawing workload, without changing service rules, movement, animation, or visual occlusion. The historical 26.969 ms/frame stress reference (30 guests, 22 staff, 600 frames) is not an exact-base comparison. No full-frame result for this patch is claimed.

- Guests carry the result of the first clear segment check into the loop once. The short proposed move, subsequent legs, rerouted legs, and obstructed/zero-delta handling still follow the original checks.
- Staff skip hashing the finished path when the route cursor has reached its end. Route storage, live claims, active-route validation, and stall rules are not changed.
- Order-table selection reuses the route length already established by the live work-cell verdict when both checks start at the same cell. A caller with a different start still performs the original second route check. Claims, rear-face order, and stall handling stay live.

Pinned Godot 4.6.3 headless: 2,075 assertions across six repository suites on the combined gameplay patch; the 85-input / three-atlas guard remains unchanged and passes. The order suite covers same-start, different-start, pinned rear, and live claim behavior. A private differential harness checked 8,004 state/trace cases, including detours, blocked starts, zero movement budget and multiple legs; 3,374 cases removed exactly one redundant check. Its nine alternating pairs on one occupied-grid walk case had median costs of 0.008997 and 0.006848 ms/call before and after, including fixture reset. These are local microbenchmarks, not savings per frame. No diagnostic instrumentation is part of the product changes.

The separate renderer candidate is not part of this gameplay patch. Its cooking-only gate passed four pinned headless suites (18,260 assertions) and matched ordered drawing commands/contact geometry for 3,312 cases. A mixed 22-staff workload with one cooking body plus one reach overlay performed 464 → 2 staff-row visits in the stove-heat lookup; an all-cook workload retains the old lookup count. Exact visual and atlas qualification is still required before adoption.
