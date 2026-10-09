# Inactive resumable routing scheduler

This local candidate addresses the 284ms synthetic exhaustive search recorded for
PR125 head `d9c06035ed4bf66e95ff5a8ff496b140f0dc870e`. The published synchronous
planner/follower is unchanged. No production caller imports the new scheduler;
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
