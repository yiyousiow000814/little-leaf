# Outside waiting for a table

When a normal four-simulation-second arrival attempt cannot assign a reachable
free table (including the existing two-arriving-guest cap), up to two real
prospective visitors walk in from the original street ends. Partial successful
direct arrivals retain their existing behavior. Once outside requests exist,
later attempts join the bounded queue instead of overtaking it for a table.

There are at most six outside actors, including visitors returning to the street.
Each owns a distinct waiting spot on the public pavement at x=-1.6,
z=7.5+1.1*slot. The approach uses the established x=-2.76 street lane and
1.5-tile/second walk speed, with cardinal segments; waiting spots stay clear of
the door crossing and the x=-.85 departure lane. Ambient walkers ease onto
parallel pavement lanes around occupied spots. They retain their decorative role.

The oldest live request receives the next free reachable table when its approach
has finished and the existing arriving cap permits entry. It keeps its identity
and exact position, walks to the entrance through the current geometry, and
reserves the table and chair once. A table remains occupied through its actual
departure and cleanup. Free but unreachable seats do not admit a visitor.

Outside waiting is 90 simulation seconds after reaching a waiting spot. Approach
time does not count. Closing and outside timeout produce a physical return to
the visitor's original street endpoint, without a bill, service payload, litter,
or cleanup task. Returning actors count against the capacity, so rapid reopening
cannot accumulate unbounded canceled visitors. Queue movement follows ordinary
pause, Decorate, and speed controls; no offline queue catch-up is introduced.

Dining service records begin only at table assignment. The existing seated anger
at 70 seconds and unfinished-meal departure at 120 seconds remain unchanged.
The outside clock is never copied into those records. Rewards, prices, wages,
meal duration, original endpoints and walking speed retain their existing values.

## Save contract

The existing enclosing version 15 and dining runtime remain unchanged. A separate
optional `outside_queue` object uses `little_leaf.outside_queue.v1`. Missing data
means an empty queue. The finite codec validates the format, bounded count,
strictly increasing and globally unique visitor IDs, next-ID bound, exclusive
slots, clock limits, exterior coordinates, canonical cardinal routes, current
route positions and unassigned table/chair sentinels before replacing any state.
Closing snapshots contain only returning outside visitors. Loading never writes
the source file. Promotion produces an ordinary validated dining guest.

A 0.1.9 reader ignores the optional outside array: dining visits and wallet still
load, but outside visitors disappear on downgrade. Its shared next-ID remains
advanced, preventing identity reuse. This is a documented backward-loading
limitation; preservation of new outside state requires the new reader.

## Tradeoffs

Waiting spots remain fixed when a visitor leaves; people do not teleport or
shuffle to close gaps. Admission order is arrival identity, not proximity to the
door. The default six spots extend beyond a close camera view; panning shows the
whole line. Six and 90 seconds are modest initial bounds, not demand/economy
calibration. This can increase actual throughput in busy layouts by admitting a
waiting visitor immediately after cleanup, without changing per-meal economics.

Existing dining actors retain the established body-collision policy. The queue
uses spaced, reserved public positions and the existing wall-safe entrance
routing; it does not introduce a general pedestrian traffic/collision solver.
No parking or bus behavior is included.

## Evidence

`test_outside_queue` is part of the standard disposable integration runner. It
checks bounded arrivals, FIFO cleanup admission, reachability, cancellation,
90-second timeout, save/load and atomic invalid-input rejection, old missing
fields, service isolation, pause/Decorate/2x, and seated patience.

The actual historical-reader harness is
`python tests/run_queue_backward_compat.py --output <new-directory>`. It archives
the exact baseline and compares the complete wallet/dining runtime before and
after that reader resaves the new synthetic queue file.

Tracked [motion evidence](qa/outside-queue/before-after.gif) and its
[one-second trace](qa/outside-queue/motion-trace.json) show zero baseline outside
requests and six candidate requests by t=12. In the same full-room fixture,
candidate visitor 3 seats at t=75 after cleanup; baseline visitor 3 is still on
the long street approach at t=86. Both keep coins=1200 and served=0 throughout
the controlled comparison. The GIF is accelerated; frame labels show actual
simulation time. Initial samples t=0,4,12 precede every second from t=40 to86.

`python tests/run_outside_queue_capture.py --output <new-directory>` runs the
same native rendered fixture on exact v0.1.9 commit
`11c1f8d904b0c4c9a2565cbd557d1552b4ba9401` and the candidate. Set `GODOT_BIN` to
Godot 4.6.3. Both use disposable project copies and generated profiles. The full
stock room holds meal progress for the comparison; first-table cleanup starts
at t=64 and physically completes at t=68. This controlled fixture demonstrates
motion and table release, not ordinary production throughput or staff service.
