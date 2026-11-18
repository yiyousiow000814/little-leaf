# Little Leaf: architecture contract before optimization

**Status: proposed design and acceptance criteria. No implementation or performance pass is claimed.** Current-source reference: [main at d81afcd5](https://github.com/yiyousiow000814/little-leaf/tree/d81afcd5b760eb4cc70eb941b4c28795f8c04df6). The all-functions atlas describes that revision’s GDScript. The separate [target workflow](target-workflow.mmd) describes the proposal. A change to this document does not change the game.

**Decision.** Keep one gameplay authority and the existing painter. Change who computes repeated facts and how long those facts live. Reject a shared object if it creates work before a consumer needs it, requires a second world model, or has no explicit invalidation boundary. Design the contracts and baseline first; do not start with isolated patches or a general cache rewrite.

## Owners, lifetimes and extension rules

| Owner | Publishes | Lifetime and prohibited operations |
|---|---|---|
| Simulation | Jobs, route/claim arbitration, custody, simulation clocks, records and serialized state | Authoritative. Finish the original ordered transition before another consumer reads it. A render helper must never reserve a route, transfer a plate, advance a timer, or write a save. |
| Simulation-side derived lookup, only where justified | Ordered task/owner lookups keyed by identity **and** job token | One logical synchronization or explicit mutation epoch. Two synchronizations separated by a model tick are different lifetimes. Rebuild at the new boundary unless all relevant edits are accounted for. Never reuse a draw snapshot here. |
| Presentation update | Smoothed stance, facing, hand placement, and visual transition history | Update on the existing visual clock. These are not gameplay facts. Read once where valid; preserve startup, pause/edit, load and missing-value fallbacks. |
| World draw | Visible entries; locally derived inputs needed by more than one consumer | One synchronous parent draw at most. First prefer a local value; if multiple entities need the same facts, one pass over the authoritative rows can feed an ordered, draw-scoped index. No frame-wide deep copy, singleton cache, or persistent map by bare numeric ID. |
| Painter and retained commands | Ordered original art, actual contacts, occlusion and picking data | The mixed order of walls, chairs, bodies, hands, props, spills and UI remains the painter’s responsibility. Stable commands do **not** imply static placement, contacts, eligibility or ownership. A deferred callback takes an owned value or validates current identity; never borrow draw-local state after the draw returns. |

For every proposed helper, state: **owner → inputs → first consumer → reuse consumers → expiry → invalid/missing behavior**. Show that the old computation is removed, not merely wrapped. Keep functions with different semantics separate, even if they traverse the same list. Use the original predicate, iteration/tie order, duplicates and no-match behavior. Do not eagerly compute expensive defaults before testing whether an existing value is available.

## Scaling contract

No quadratic work in any path that must scale with guests, staff, stations, furniture, or visible entries. Name each independent population. A nested staff-by-record loop is O(staff × records), even if current levels cap each count. An outer memo that still scans the roster once for each distinct key is not a bound on worst-case row visits.

For each scalable stage, specify a bound and counters. Prefer a single source traversal and indexed probes, or an ordered merge. Keyed lookup is **expected**, not guaranteed, constant time. Ordering E mixed entries may remain O(E log E); preserve its current comparator, tie behavior and depth. Count output-sensitive work separately: K real plate draws or matching rows still cost O(K). Count index setup, writes, empties, fallback, allocations and peak bytes; a hash map need not win when only one consumer asks. Never shift an unbounded scan into cold rebuilds, deferred callbacks or order repair without budgeting those paths too. Until known legacy exceptions are retired, record their bound, owner and migration gate; do not label the whole game compliant.

**Three examples, not three patch approvals:**

- **Service synchronization:** Pre- and post-model-tick retirement cannot share stale claims. Within a synchronization, an ordered aggregate keyed by guest ID and job token could replace scans of staff per record. Preserve held-record exclusions, claim predicates and when each station reference is cleared. With 30 eligible records and 22 staff at *each* of two synchronizations, the old nested loops inspect 1,320 staff rows; this is conditional arithmetic, not a measured timing or a cost of painting.
- **Table:** Derive a layout only when a plate or cup will paint; share it for that invocation. A local result alone does **not** remove the table-by-guest scan. If multiple tables need guest rows, build an ordered per-draw table-to-rows index once and keep first valid chair selection independent of the plate/cup predicate. Preserve preview, remembered direction, adjacent-chair fallback and plate-before-cup order.
- **Sink:** Supply the basin, dropping plate and cleaner’s hands with one eligible washer and one sorted queue per required sink/draw. If the number of sinks scales, partition relevant dishes and workers once, not once per sink. Keep the live lowering transition separate (including slot changes and the ownership threshold). Preserve the original water, occlusion, hand and stack order.

## Evidence and decision rule

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Source on [main](https://github.com/yiyousiow000814/little-leaf/blob/d81afcd5b760eb4cc70eb941b4c28795f8c04df6/game/scripts/rendering/illustrated_cafe.gd#L1791-L1813) | Character options, bound callback and appearance arguments are built before the retained-object decision. | The milliseconds saved by moving that decision. |
| [PR 353](https://github.com/yiyousiow000814/little-leaf/pull/353), experimental comparison at bf0cced | On its native X11/Mesa, atlas-ready ABBA comparison, selected parent plus native-callback CPU increased by +2.411 and +0.486 ms/frame in the two reported comparisons despite 23,546 → 10,801 nodes. It did not pass the timing comparison. | Not an end-to-end frame/GPU/Web result. The change retained upstream preparation and added owner/order bookkeeping; those are plausible costs, **not** individually measured causes. Do not sum with other studies. |
| Static operation models above | Which work can vanish and when it cannot. | Coverage, timing, actual FPS or correctness after a change. |

**Do not select persistent actor ownership by node count.** It must show why a valid early decision replaces old work before options/callback allocation, exact mixed order survives crossings without a second global repair, and stale identity/unsupported art safely falls back. If these conditions are unproven, keep the existing path. The preserved research snapshot, experimental PRs, and the default source revision are not interchangeable.

## Performance acceptance: delivered 60 FPS with 15% unused

A 60 Hz frame period is 16.6667 ms. With **at least 15% unused**, active critical-path work must fit **0.85 × 1000/60 = 14.166666… ms** (about 14.17 ms); reserve at least 2.50 ms. A VSync-paced frame interval near 16.67 ms does not by itself prove headroom. Conversely, a 14 ms CPU timer does not prove 60 presented FPS. Where CPU and GPU overlap, do not add their full durations; report each, their waits, and the measured or bounded critical path. Do not subtract genuine bottleneck stalls as if they were VSync sleep.

Proposed reproducible gate, to lock **before** implementation:

1. Declare the target hardware, OS, renderer/browser and refresh rate, build/revision, resolution, content hash, input trace and population of each supported scene. Include ordinary play, busy full service, camera movement, overlays/occlusion, and custody transitions; include cold launch/load, edits and first-visible spikes as separately labeled windows. A pass on an undeclared platform proves nothing about the others.
2. On each required live-play scenario, collect at least three repeatable 60-second measured windows after declared warm-up. Record actual presented-frame cadence against the 60 Hz deadlines, not just engine-reported FPS. Log missed deadlines and longest frame; no sustained/repeated misses may be averaged away. For an unqualified every-frame claim, **all** in-scope measured active frames must meet the 14.166666… ms ceiling and all expected 60 Hz presentation slots must be served (allow only documented timestamp precision). Report max plus p50/p95/p99. An agreed percentile-only target or cold-start exception must be explicitly labeled, not described as this pass.
3. Attribute simulation, presentation preparation, painter order, parent/native callbacks, renderer/GPU and wait separately where measurable; log populations, visits, allocations, fallback/invalidations, and memory peaks. Unknown GPU or presented-frame timing = **unverified**, not passed. A headless trace can prove logic, not graphics FPS.
4. Pair baseline and candidate on the same machine/workload/settings; alternate order. Compare gameplay ledger, simulated contact/hand-off timing, visual parity, hit/pick and sorter ties. Track transition and miss cases as well as steady-state hits. Keep raw traces and exact test revision. Never convert a row count or node delta into milliseconds.

## Migration and review gates

| Gate | Smallest reviewable scope | Evidence required to advance |
|---|---|---|
| 0. Architecture and baseline | No game changes. Approve ownership, expiry, workload matrix, measurement plan and allowed fallbacks. | Current Mermaid, Excel, commit and baseline provenance agree. Inventory unbounded paths, distinguish unknowns. |
| 1. Simulation boundary | One synchronization owner and one explicit expiry; preserve both sides of the model tick. | Equal authoritative history/save behavior; scaling counters reject staff × records. Stop or revert on ordering, token or custody mismatch. |
| 2. Presentation boundary | One table or sink feature slice at a time, keeping painter & contact consumers in place. | Original art, identity, ordering, picking and hand-offs match; counters show old scans actually disappear. Check zero/one/many consumers. |
| 3. Renderer revisit, only if justified | Only a measured remaining bottleneck; one eligible actor path with immediate stock fallback. | Charged early-guard cost for both hits and misses; parity through crossings, overlays, camera/scale, load/removal and fallback. No expensive global commit substituted for old work. |
| 4. Release decision | Actual target builds on the declared matrix. | Independent correctness and frame/headroom gates above both pass. Otherwise remain a candidate and report the limiting stage. |

**Per-change deliverables:** Update the actual Mermaid atlas and the Excel function/call/complexity/evidence inventory together with every change; refresh the target Mermaid when the architecture changes. Mark documentation-only changes as such rather than implying runtime change. Record base SHA, candidate source SHA, graph/extractor revision, scope, changed nodes/edges, affected complexity bounds, and any unresolved/dynamic dispatch. Distinguish direct calls, callback registration and possible dispatch. Link raw measured evidence to its own revision, hardware, workload and date; label analytical estimates *projected*. If code and artifacts refer to different source revisions or evidence has no provenance, the review remains open.
