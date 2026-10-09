# Chef output pickup

New meals use the cooking stove as their ready-plate output. There is one
physical output slot per stove. The chef plates and deposits there; the waiter
collects at the existing contact threshold and carries that same plate to its
customer. A stove holding an output cannot start another meal. The chef yields
its idle workface while a plate or waiter pickup occupies it.

Service counters are no longer offered for purchase or supplied in public fresh
starts. Existing counters remain owned, movable when unused, and retain their
normal resale value. No automatic refund or deletion occurs. Existing reserved
counter handoffs and plates already on counters finish in place. In-flight
unreserved meals finish at their original stove. The historical reset_new test
layout intentionally retains counters to exercise old layouts.

The existing four cooking stages and saved identifiers remain readable. Direct
output uses the existing station plate owner and meal_station_id; old counter
state uses meal_pass_id/pass_reserved. The codec rejects duplicate stove output
plates. Active jobs and stored dishes lock their furnishing against moving or
selling. Blocked paths retain the plate and order token rather than discarding,
duplicating, or teleporting a dish. Pausing continues to use the existing service
clock gate. This implements the requested visible interaction pattern, not any
claim about Restaurant City's private implementation.

Run `test_direct_chef_pickup`, `test_fresh_service`, and
`test_stove_pause_service` through the disposable integration runner. These are
engine/state checks; rendered handoff inspection is separate.

The stove-only handoff pose uses fixed 5.5/6.5-pixel arm segments and the
same .65 ownership threshold as service. The held plate reaches the exact
stored-plate anchor before its owner changes. Production visual CI captures
56 frozen frames across four rotations and two zoom levels. It records actual
paths, ownership and contact geometry, and round-trips generated saves before
and after waiter contact. Pixel review remains a separate acceptance step.

Physical output support is verified independently of draw order. The original
14×6.4 meal plate and original pan use opposite supported worktop corners;
burner, pot, lid and food share the pot anchor. Ceramic and pot outlines remain
inside the one-tile top and do not intersect in any rotation. The metal stem
connects the displaced pot to the reachable front grip while keeping its wood
grip dimensions. The pickup stance shifts slightly sideways within its original
work tile. Plate size is unchanged at the stove, in hand, on the table and sink.
