# Parking visitor parties

Candidate for 0.1.11. The fixed map For Sale sign opens a purchase review during normal play. This implementation is not user acceptance or merge authorization.

A parking car owns one to four original members until all have boarded and the physical car exits. The existing arrival dispatcher creates a bounded party; there is no extra arrival/background timer. The fixed lot still has four bays and shares the six prospective-visitor limit with the ordinary outside queue.

## Identity and custody

The parking subsystem format is `little_leaf.parking.v2`; the global save schema and runtime codec are unchanged. A car has `id` (its first original member ID), `bay`, car phase/position/heading/route/index, `cancelled`, and `members`. Each member has immutable positive `id == member_id == appearance_sequence`, `car_id`, `bay`, `species_index == id % 3`, and `appearance_recipe == original_guest_v1`, plus slot, member phase, cancellation, and walking origin/position/heading/route/index.

Member phases are `in_car`, `walking_in`, `queued`, `dining`, `walking_return`, and `boarded`. `dining` means admitted guest custody, including an arriving or pending guest; it does not mean arrival at a chair. Queue/guest dictionaries carry exact `parking_car_id`, `parking_member_id`, appearance sequence, species and recipe bindings. No routing or service token is replaced with a car/array index.

`Parking.find(model, guest_id)` returns the original member. `Parking.admitted` binds that exact admitted guest. `Parking.start_return(model, guest_id, actual_position)` starts only that member's return to the original car. Dirty/cleaning guest records can retain table cleanup custody after the person returns; they are excluded from the visible pedestrian list. A car cannot depart before every original member is `boarded`.

The current original isometric renderer derives species and clothes from the stable guest ID. This slice preserves that recipe across all legs and save/load; it does not activate PR129's bear-only wardrobe provider or PR153's optional sprite boundary. Cache eviction and unrelated ID allocation do not replace an existing member's ID/appearance sequence.

## Traffic and motion

Eight through-road cars and up to four parking cars use the model's existing service tick, all at 2.8 tiles/s. The road pool is bounded, retains its original lane/color/direction identity, follows actual preceding cars with a 4.5-tile center gap, and yields to a committed parking merge. A departing parking car waits at the aisle until the physical road gap permits its merge; it does not reacquire the gap halfway through the curve. Rendering reads the authoritative pool rather than advancing a second presentation clock.

Parking routes are allocated once per maneuver, with 16 fixed segments per quarter-circle. Cars back to the right out of a bay while preserving the parked front, then drive left along the aisle and turn onto the road. During reversing, body/axle direction is opposite the velocity but collinear with it. World anchors rotate together; artwork heights, dimensions and colors stay original. Only oriented parking cars select near/far wheels and side order from the transformed depth. Ambient straight-road drawing remains unchanged.

## Restore validation

`Parking.validate` checks membership against actual guests and queue custody before applying a restore. It rejects changed identity/species/owner, missing v2 guest bindings, duplicate members/bays/slots, premature departure, malformed motion/route points, and malformed or overlapping road pools. A v2 traffic snapshot is required and cannot be silently regenerated. Missing historical parking data and valid v1 single-driver records migrate in memory, preserving original IDs and in-flight legacy routes; source save bytes are never rewritten by load.

The bounded traffic snapshot is contained in the parking subsystem envelope. Model changes are limited to its field/reset, `Parking.snapshot(self)` at save, and `Parking.restore_traffic` after validated load. This does not relax generic codec, cardinal guest routing, pending mobility, checkout custody or table ownership rules.

## Candidate checks

The fixed sign shares one world anchor between drawing and hit testing. Existing world input distinguishes a tap from a pan and cancels held taps on focus loss or pinch; parcel purchase and furnishing input remain intact. The purchase review uses the existing registered modal, including cancellation and viewport sizing. Buying checks the model price and ownership atomically, saves once and replaces the sign with the existing four-bay drawing. Insufficient funds and save recovery block buying. Unowned parking is absent from Decorate; the existing owned sale review/refund policy remains. A normal-play purchase does not grant a Decorate-session full refund.

The sign adds a constant small draw list and no timers, caches, scene nodes or simulation fields. Its owning illustration redraws through the existing path; ownership changes remove the sign. Modal controls are retained with the shop and freed with the scene. Focused actual Main input checks cover cancellation, pan, focus loss, insufficient funds, recovery, repeat activation, save/reload, usable bays and narrow/short viewport geometry. Native PNGs for this flow are retained outside source in the delivery packet.

The focused functional run uses only generated synthetic profiles: parking compatibility, 1–4 members, partial return save/load, staggered return, real Main service/payment/queue patience/abort, pause/Decorate/background suspension, traffic gap and malformed snapshot checks. The existing focused parking rendering checks also pass. Actual native PNGs and their source hashes, clocks and synthetic fixture records are in `docs/testing/evidence/parking-parties/`.

The PNG fixture skips the existing tutorial through its own public action and updates the HUD at each capture. It drives the actual Main service and staff functions and production drawing code, with save writes suppressed. It is an instrumented simulation, not ordinary-speed continuous playback or an FPS qualification. Independent visual review, user verification and integrated review with the other 0.1.11 slices remain pending.
