# Inactive resumable routing scheduler

This local candidate addresses the 284ms synthetic exhaustive search recorded for
PR125 head `d9c06035ed4bf66e95ff5a8ff496b140f0dc870e`. The published synchronous
planner remains available; the candidate follower now optionally consumes the
scheduler for invalid-route replans. No production caller imports the scheduler;
save formats, economy, claims, role ownership and service timing are unchanged.
The specifically blocked private reception source was not accessed.

## Boundary and API

`cafe_navigation_scheduler_candidate.gd` schedules transient searches, not actors.
The caller prepares and retains immutable snapshots outside the tick, assigns a
single integer layout epoch shared across its geometry domains, and increases
that epoch for any routing-relevant layout change. Different role snapshots can
share the epoch while retaining their original owned-cell boundaries. Epochs must
not be reused while an old request can remain outstanding. Mutating a snapshot
in place without changing the epoch violates this API. Snapshot construction and
caller-owned snapshot/result destruction are outside the work budget.

The accepted snapshot is the foundation's cells/solids/edges/barriers dictionary,
with at most 4,096 cells and a revision of at most 16 integers (the current model
adapter supplies 11). Snapshot entries retain the existing trusted geometry
contract; this module is not a persistence validator. The unchanged foundation
still accepts its previous inputs. These scheduler admission restrictions do not
change an old reader or allocate a save/capability version.

* `submit(snapshot, origin, goal, epoch)` returns a monotonic request ID, or zero
  when the 256 retained-request slots are occupied. Submission stores references
  and performs no search or deep snapshot copy. Completed results consume a slot
  until the caller takes them; cancelled structures release incrementally.
* `tick(current_epoch, work_budget=128, time_budget_usec=2000)` rotates one work
  unit per request. The work limit is clamped to 0..4,096. Zero elapsed budget
  disables the cooperative deadline for deterministic tests. Zero work does
  nothing. A changed epoch terminates stale searches before another search unit.
* `cancel(id)` prevents pending or completed-undelivered routes from delivery.
  Cleanup shares the same fair work queue instead of clearing large dictionaries.
* `inspect(id)` returns status and counters. `take_result(id, current_epoch)`
  transfers a terminal result once, refuses stale completed routes, and returns
  pending/unknown where appropriate. Consumers still check task ownership before
  movement; this scheduler introduces no endpoint claim authority.

## What a work unit does

A unit performs one bounded initialization, frontier pop, eight-direction neighbor
setup, one rectangle sweep, relaxation, predecessor trace step, reverse swap,
length addition, or cleanup removal. A diagonal checks the same four cardinal
edges and five sweeps as the published planner. Even a large barrier list is
visited one rectangle per unit. Heap operations use the foundation's deterministic
f/h/x/y ordering, with logarithmic work on the bounded graph. There is no bulk
route reconstruction or route reversal at completion. Cleanup removes one heap
entry, touched cell or partial/discarded route point per unit.

Round-robin service includes cleanup and preserves the cursor when a tick yields,
so a one-unit tick cannot keep favoring the first request. A live request cannot
starve behind another request's large barrier scan or completed route cleanup.
Backpressure is explicit; a caller must retry a rejected submission. A request's
heap, predecessor and current geometric check survive each yield, so completion
does not restart A*. For valid snapshots, the result matches the synchronous
planner's status, route, cost, metric length, revision and expansion count.

The elapsed deadline is checked between units, not during one primitive. OS
scheduling, allocator latency, dictionary operations and heap work can overrun
that deadline. This is a bounded-work, cooperative candidate, not a hard
real-time guarantee or representative hardware FPS acceptance. Production
integration still needs its own frame workload/snapshot lifecycle measurements.

## Verification

### Follower consumption slice (roadmap09.03)

Based on PR125 `439aba98ce67f27e8fb21cf13b65ccf15eaf11b6`, `advance`
accepts optional `scheduler` and `epoch` arguments after the existing arguments.
Omitting them retains synchronous behavior for old candidate callers. With a
scheduler, an invalid route at an exact safe center submits one request and
returns `pending` without searching or moving. The owner ticks that same scheduler
separately under its shared budget. A pending follower holds position and consumes
one completed result. Layout epoch/revision, task token, endpoint and origin
must still match; the existing endpoint ownership callback approves movement.
An obsolete request is cancelled and consumed before retry. Claim loss and a
terminal replacement plan also clear it. `cancel_replan(state)` is required when
abandoning a follower; its transient request records the owning scheduler, and
the caller continues ticking that scheduler's cleanup. Passing a scheduler is
still supported for existing candidate callers.

Changing scheduler instances or returning to the old synchronous advance API
cancels and consumes the original request before proceeding. Numeric request IDs
are scoped to their recorded scheduler, so equal IDs on two instances cannot
deliver another actor's route. The owner retains abandoned scheduler instances
until their cooperative cleanup finishes. Snapshots remain immutable and epochs
monotonic as specified above.
`backpressure` holds position for a later retry; search errors are returned to
the caller. For scheduled callers, a changed layout that invalidates only future
legs permits finishing the still-legal current segment within the movement
budget. All four diagonal edges, corner cells and body sweeps must still pass.
Movement stops exactly at its next center, submits a replan there and discards
the unused frame movement budget instead of following the invalid tail. A
blocked current leg or an off-segment position stops without rounding/snapping.
Legacy synchronous callers retain their original mid-segment stop behavior.
No claims, task allocation, endpoint selection or service timings are introduced.
Remaining-route validation and snapshot construction are still synchronous;
this slice bounds search work only, not the entire controller/frame workload.

The shared model owner confirmed no model/reception/codec API change is needed.
Reviewed composite `2cbd7118fb3561716b2506b790b3f0abcaab7c11` retains authoritative
Main service locks, chef pickup outputs and stove/counter ownership. This slice
uses synthetic snapshots and does not activate its old `from_model` adapter on
that composite. The adapter now consumes the existing segmented
`collision_wall_hosts()` when available, retaining the original whole-shell API
for older PR125 models. Modular cabinets remain one cell in every rotation;
their body barriers require no footprint enlargement. Reception08.01–08.05
source/endpoints, actual role
consumers, docking, codecs and production activation remain prerequisite gates.
The unavailable historical reception source is not recreated here.

Acceptance for this bounded slice: pending searches do no movement or synchronous
A*, completion resumes the existing follower once, stale task/layout/claim/
endpoint/origin results cannot move it, unreachable goals report failure, retained
slots are reclaimed and the original advance signature continues working.
Use `--only-follower` for these focused regressions; no full scheduler matrix or
FPS measurement is required for this consumption change.

The representative changed-tail fixture starts partway along a diagonal, inserts
a future obstacle, reaches the next safe waypoint, completes a scheduled replan,
then changes the layout again before delivery. The stale result cannot move the
actor; the new detour's legs are checked with the same corner/segment rules and
reach the original endpoint. Separate current-leg corner/edge/frame variants
must stop without displacement. Scheduler replacement with equal numeric IDs,
owner-recorded abandonment and legacy fallback verify no retained delivery leaks.
These are transient controller tests, not persisted diagonal save acceptance.

### Frozen model geometry adapter

`run_navigation_model_adapter_candidate.py` accepts an explicit `--model-repo`
and immutable `--model-commit`, extracts only that source's scripts/data into a
disposable project and overlays the candidate/test from `--source-commit` (or
working files). The model is a read-only dependency; it is not copied into the
routing branch or edited. It redirects every platform profile directory and
records all extracted dependency/candidate hashes. Main never runs.

The focused fixture on reviewed composite
`2cbd7118fb3561716b2506b790b3f0abcaab7c11` checks removed shell segments, surviving
neighbors, relocated original/purchased walls, a door clipped across shell
segments, frame body clearance, window solidity, each one-cell cabinet in all
rotations, blocked adjacent cabinet seams, rug traversal and frozen snapshots.
Model ownership, economy and authoritative item/wall data remain unchanged by
snapshot construction. This accepts the tested geometric projection only;
actual reception/claim/docking, diagonal replay/load/refusal contracts and
combined source acceptance remain separate. No historical cardinal reader is
relaxed and no capability version is assigned here.

Run the synthetic-only runner with `--godot`, a new `--output` directory and
optionally `--source-commit` to extract a frozen Git revision. It copies only the
two inactive routing modules and the scheduler test into a disposable project,
redirects platform profile directories, and records source/log hashes. It never
launches the game or accesses saves/cloud services.

Tests cover independently completed searches at work budgets 1/7/128, seeded
obstacle maps, all four diagonal edges and a frame barrier, eight-way fair
progress during 2,048-barrier scans, cancellation before search/during sweep/
after completion, changed layout epochs before and after completion, simultaneous
4,096-cell detour/no-path searches, 512/513-point routes, incremental cleanup,
admission backpressure, invalid snapshots and deadline yielding.

Frozen receipt and measured tick results are recorded in the review packet.
Native pixels, gameplay diagonal movement, actual endpoint docking/claims,
private reception integration, codecs, browser diagonal behavior and FPS remain
not run. No public push, main merge or release is authorized by this candidate.
