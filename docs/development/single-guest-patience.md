# Single-diner meal waiting and departure

This local 0.1.9 policy replaces the earlier 120-second, three-second reaction.
The diner becomes angry at 70 simulation seconds after seating. The existing
centered vector angry face remains visible until food is physically handed over
at the table. The accepted bubble body, tail, size and position are unchanged.

At 120 seconds, an unfinished meal is canceled and the diner leaves without
payment. Food that has already finished cooking, reached the pass, or is being
carried for this diner exempts the visit from departure. It does not clear anger:
only the actual food-table handoff does that. An unserved departing diner retains
the angry face while their actor is visible.

## Simulation ordering and readiness

`service.records[].meal_wait_seconds` is independent of `customer.elapsed`,
which is clamped while physical staff service is incomplete. It advances using
unpaused, speed-scaled simulation time, capped at 60 seconds per update like the
model. No offline time or approach travel is counted. A seating-transition update
starts at zero, conservatively granting at most one update of grace.

After model movement, all staff actions and physical contacts run before meal
deadlines are resolved. Autosave follows that resolution. Cooking completion or
food handoff in the same update therefore wins a tie with the deadline.

Readiness comes from the matching guest/service token and the existing completed
cooking job stage (plating or later), a plate at the guest's reserved pass, or the
matching waiter's carried finished meal. Elapsed estimates and another guest's
tray cannot grant the exception. The waiter's existing serving contact at 65%
transfers plate ownership to the table and immediately stops waiting and anger,
before the delivery job itself finishes.

## Atomic cancellation and physical exit

Only the abandoned visit's unfinished service jobs are canceled. Their old token,
paths, workface/pass/station and checkout claims are released, then the service
token is invalidated once. Existing cleanup jobs retain their payload/progress
under the new token. Other visits, independent floor messes and dish queues are
untouched. Unfinished kitchen food and undelivered drink are discarded; a cup
already on the table still follows real collection, sink drop-off and washing.

The model records `customer.meal_abandoned=true` and uses the existing physical
chair dismount and exit routing. It never enters meal payment. If the chair is
being relocated, the diner finishes that actual seating route before dismounting;
position is never reset or teleported. A blocked exit retries safely. The table
and seat remain reserved through departure and any required cleanup.

## Save compatibility

The enclosing save remains version 15. Service format is now 5 so an older reader
rejects unpaid deadline-departure state rather than misinterpreting it. Existing
service 3-to-4 dish migration still runs before the final service-5 normalization.

The wait clock remains a finite number in `[0, 1000000000]`. Existing validated
clocks survive reload. A missing clock defaults to zero, with no inferred prior
waiting. A missing abandonment flag defaults to false. Loading does not itself
cancel a visit: the next unpaused staff frame resolves any due deadline after
that frame's real service contacts. New departure snapshots require the service-5
marker, an unpaid valid departure/cleanup or pending-relocation phase, a clock of
at least 120 seconds, no unfinished service job, and no meal/pass/checkout claims.

Current saves preserve partial cooking, carried ready food, relocation, dismount,
walking exits, delivered cups and independent cleanup. Purchase values, wallet,
wages, receipts, customer identities and unrelated jobs keep their contracts.

## Verification and scope

Run `test_single_guest_patience` through the disposable integration runner. It
covers the 69.99/70 and 119.99/120 boundaries; persistent anger; same-frame cooking
and handoff priority; matching-token readiness; exact cancellation; unpaid exits;
blocked/replanned movement; relocation; cup-only cleanup; partial save/load;
legacy service migration; and pause/time scale. Related checkout, dishwashing,
role, relocation, rendering and save regression suites remain necessary.

Earlier 3f2e9cd full-pass evidence validates the old policy only. No group handling
or economy changes are included in this policy change.
