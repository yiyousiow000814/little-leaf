# 0.1.10 simulation CPU audit and targeted fixes

Baseline: `43e1834464ed327c7c432c988401898f9582f3f2`. The frozen baseline and player profiles were not modified. All experiments used separate copies, synthetic state, Godot 4.6.3 headless, and isolated XDG directories. These measurements are CPU microbenchmarks, **not** whole-frame FPS, phone temperature, battery, browser GPU, or thermal evidence.

## Confirmed hotspots addressed

1. **Furniture scans inside BFS.** `CafeModel.path_between` expanded grid cells through `item_at`, scanning every item for each neighbor. It now gets one transient cell-occupancy snapshot per query, invalidated by revision plus content signatures. The snapshot contains booleans, not cached item Dictionaries. `get_item`/`item_at` remain authoritative, including replacement by a same-valued Dictionary. Staff BFS uses the same facts and retains its own direction ordering and x>=1 restriction.
2. **Full future staff-route checks every active frame.** The controller checked every remaining leg against all solid wall segments, even with unchanged geometry. A transient per-staff geometry/path signature skips only the redundant full-route scan. Immediate movement still checks walkability and the current segment on every frame. A changed path/layout forces complete validation. Validation state is not serialized.
3. **Unchanged failed FIFO admission every tick.** A settled queue head retried seat enumeration and access on every simulation step while every seat remained occupied. Failed admission is now memoized by static geometry, dining sets, operating state, per-guest table/chair/withdrawal/arrival-slot ownership, and visitor identity/position. Success clears the cache. Waiting deadlines, walking budgets, cancellation, FIFO selection and arrival cadence remain untouched.
4. **Optional checkout-slot searches for guests that never use the slot.** Checkout previously ran two reachability searches before skipping a sole paying/moving guest. Optional-slot calculation is now deferred until the eligible rank-one guest needs it. The rank-zero destination, cashier ownership, settlement, and slot choice are unchanged.
5. **Repeated seat-ID scans.** Seating enumeration builds a local first-match ID map rather than repeatedly traversing furniture for each pair. No persistent item references or changed ordering.

Static service path cache keys now include the geometry content signature, not only revision. New navigation entry points also invalidate the existing wall caches when direct fixture mutation is detected. Direct standalone `edge_blocked`/`segment_blocked` calls continue to require the existing `_notify()` mutation contract; content hashing is deliberately not inserted into every inner collision query.

## Reproduction

Use the same `qa/profile_simulation_cpu.gd` in two disposable projects (copy it to the baseline). Set OUTPUT to a new writable directory, SOURCE_LABEL to the tested commit, and XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME to disposable locations. Import first, then run:

```
godot --headless --path DISPOSABLE_PROJECT --editor --import
godot --headless --path DISPOSABLE_PROJECT --script res://qa/profile_simulation_cpu.gd
```

Serialize engine work with the shared engine lock. The script loads no saves and creates no gameplay scene. It warms five iterations, then samples three batches (30 BFS queries or 100 other queries each). Values below are medians of the three batch means. Extra `indexed_true` entries are exploratory comparison controls, not a production item-cache implementation.

| Synthetic workload | Before, microseconds/call | After, microseconds/call |
| --- | ---: | ---: |
| Full 18x18 BFS, 12 walkable rug items | 1031.70 | 544.40 |
| Full 18x18 BFS, 72 walkable rug items | 2552.30 | 535.27 |
| Full 18x18 BFS, 216 walkable rug items | 4947.00 | 549.47 |
| Stable 32-leg route, 36 walls | 1138.28 | 19.08 |
| Stable 32-leg route, 108 walls | 2801.48 | 24.52 |
| Stable one-leg route, no built walls | 3.36 | 12.75 |
| Full restaurant admission, 4 table pairs | 18.20 | 5.79 |
| Full restaurant admission, 16 table pairs | 97.17 | 13.85 |
| Full restaurant admission, 48 table pairs | 511.18 | 34.36 |
| Sole paying guest checkout, 216 items | 380.76 | 22.52 |

The smallest one-leg/no-built-wall test is slower because the new controller probe conservatively charges the complete geometry signature/snapshot checks to each call; the real controller shares that work across staff. This does not establish a whole-controller improvement. Dense route, BFS and unchanged admission savings are independently measured. Route tests use cardinal serpentine routes; invalidation/cold work is covered functionally, not claimed free.

## Coverage and remaining static suspects

- Customer AI: inspected phase clocks, movement, arrival/departure, chair egress and checkout. Actor-body blocking is deliberately disabled; no quadratic body-avoidance claim is made. Customer movement checks its current segment more than once, but removing those checks needs careful reroute/waypoint parity tests.
- Staff/service: inspected assignment, reservation, pass/sink workfaces, idle homes, route construction/validation, job transitions, payment contacts and meal deadlines. `_sync_service_guests` runs before/after model tick and again before staff animation; each pass creates temporary collections and retires references. This is a remaining allocation/scan candidate, not measured as a dominant hotspot. Any consolidation must preserve standalone animation callers and newly arriving guests.
- Idle fallback: unavailable homes can trigger whole-floor candidate scans and many cached path lookups. Initial homes are revision-cached, and staff count is bounded at 11. A nearest-first equivalent selection is a follow-up candidate requiring exact tie/order parity, especially blocked kitchens and off-duty staff.
- Cleaning: PR65's settled pose solver cache is present. Floor geometry has separate revision-keyed layout/work-cell caches. Dynamic work claims, mess-overlap checks, and dish/sink queues still require live checks; do not cache only by geometry. Mess count is bounded (12 generated, 24 accepted); sinks hold six dishes each, with 512 total accepted by the codec. No claim these bounded scans are the main heat source.
- Restaurant model: maximum owned grid is 18x18. `get_item`, `item_at`, `count_kind`, and best-stove scans remain linear outside the optimized traversals. Persistent reference indexing was intentionally avoided because direct same-value Dictionary replacement must remain identity-correct. A future explicit mutation-owned index needs broader model API enforcement.
- Traffic/pedestrians: eight cars, 32 ambient walkers (6/8 displayed depending on view), three bus visitors; offscreen rig suppression and road/bus visibility gating already exist. Geometry intersection for road visibility and temporary visibility arrays/dictionaries are bounded allocation candidates, not measured dominant costs. Departing real guests preserve their continuity outside the ambient display budget.
- Timers/signals: gameplay clocks are caller-driven; model tick slices delta in <=0.1s steps, caps input at 60s, and does not perform long offline catch-up. Do not change these semantics as a performance shortcut. Signals are event-driven; no per-frame reconnect loop found. Service callbacks and per-tick arrays create temporary allocations, but this audit found no proven unbounded simulation allocation leak.
- Legacy meshes/UI: the follow-on below removes hidden staff/service-prop work. UI refresh, render culling, atlas memory, Web lifecycle, saves and actual mobile thermal validation are separate audit tracks.

## Correctness gates

Focused suites cover navigation/admission invalidation, shell cache, outside FIFO queue persistence/fairness/deadlines, register edges, departing-route edits, floor claim retries, stove work reservations and single-guest patience. The new cache suite also checks direct furniture append/move/rug conversion, same-value item replacement identity, future-leg obstruction, path mutation, wall insertion/removal, arrival slot release, withdrawal, elapsed-only stability, rotation, door/shell-host change, new head and business closure.

Do not describe focused headless checks as full regression or visual parity. Final combined candidate needs its own exact-source aggregate gate and controlled browser/device measurements.


## Hidden legacy 3D follow-on

The illustrated mode now retains a lightweight stable Node3D per worker without constructing its invisible mesh children. Staff position, heading, service/art state and serialized data remain authoritative outside that node. Per-frame legacy position/rotation writes are skipped while 3D is disabled. Hidden service tableware is not scanned/recreated; any existing legacy props are retired when switching to illustrated mode.

Explicit legacy reenable lazily attaches the original staff art to the same Node3D identity and reconstructs tableware from current service ownership. A pending-mode flag synchronizes authoritative position/facing when reenabled while paused, without resetting normal legacy animation on each frame.

Measured fixture counts: four staff produce zero legacy person meshes/zero staff mesh children in illustrated startup; explicit fallback creates 52 staff visual children (plus one customer person). This is allocation-count evidence, not a measured whole-frame/thermal reduction. A 300-tick dual-mode comparison checks exact customer/staff/art/service/save state parity on every tick. It also checks original fallback visuals, stable node identities, no repeated staff-art creation, tableware retirement/recreation, and paused reenable positioning.

Final follow-on focused gate: six suites, 1,662 checks, no failures or diagnostic errors/warnings: legacy suppression (309), simulation cache (22), floor claim retry (123), dishwashing queue (1,002), single guest patience (189), and staff relocation service (17). The earlier CPU checkpoint separately passed eight suites/1,330 checks. These overlapping counts must not be presented as unique combined coverage.
