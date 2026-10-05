# Original street endpoints

New visitors enter at the existing pavement ends `(−2.76, −82)` and
`(−2.76, 82)`, alternating by visit identity. The pavement remains `−82…82`
and the road remains `−84…84`. Camera movement and land purchases never move
an existing visitor or alter these endpoints. All approach movement uses the
existing 1.5-tile/second walking speed.

There are 32 independent ambient walkers on two pavement lanes. They cannot
reserve tables, enter the service ledger, generate payment, or affect demand.
Compact views initially admit at most six ambient walkers; other views admit
eight. Still-visible actors survive camera changes, with an absolute maximum
of eight, and a vacant slot cannot reveal someone in the middle of the view.
Only admitted nearby walkers animate. A departing guest continues visually from its
existing model endpoint to the road end, so table cleanup and payment timing
are unchanged.

## Saved routes

New visits record `street_route_format = little_leaf.street_endpoints.v1`
and their originating endpoint. The runtime validator permits extended
coordinates only on the exact incoming lane, within `−82…82`, with a
contiguous approach prefix or withdrawal suffix. Staff and interior-coordinate
limits are unchanged. Closing returns an unadmitted new guest to its own end.
Existing saved visits keep their old positions, routes and withdrawal behavior.
Layout reroutes may retain a consumed outer-lane prefix after the visitor is
seated. That same-end history remains valid; seated/service phases still cannot
use an extended current position or remaining route.

A 0.1.8 loader rejects a newer save while an actor is beyond its old coordinate
bounds; it leaves the active cafe and source file unchanged. This is a
backward-loading limitation, not a save migration. Release review must account
for it before publication.

## Verification

The standard integration runner includes `test_street_pedestrians` and
`test_street_endpoints`. Use isolated synthetic profiles as documented in the
development guide. The tests cover bounded ambient lifecycle, departure
continuation, both fixed endpoints, real movement speed, unchanged in-flight
actors on expansion, save/load, guarded route validation, closing, and old
in-flight compatibility.

The longer journey is intentional. In the six-seat, 30-minute stock-model
fixture, first seating changes from 12.4 to 59.9 simulation seconds; completed
visits change from 39 to 38. Arrival interval, maximum arriving guests, rewards
and service durations are unchanged. The fixture does not include worker
travel and is not a forecast for every layout.

Native evidence includes real minimum-zoom game views and a separately labeled
QA camera overview of the full original road. The QA overview is not a new
player zoom level. Fresh import/export, browser storage, full CI and physical
phone performance require their own checks.
