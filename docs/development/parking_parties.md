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

The focused functional run uses only generated synthetic profiles: parking compatibility, 1–4 members, partial return save/load, staggered return, real Main service/payment/queue patience/abort, pause/Decorate/background suspension, traffic gap and malformed snapshot checks. The existing focused parking rendering checks also pass. Actual native PNGs and their source hashes, clocks and synthetic fixture records are in `docs/testing/history/parking-parties/`.

The PNG fixture skips the existing tutorial through its own public action and updates the HUD at each capture. It drives the actual Main service and staff functions and production drawing code, with save writes suppressed. It is an instrumented simulation, not ordinary-speed continuous playback or an FPS qualification. Independent visual review, user verification and integrated review with the other 0.1.11 slices remain pending.


## Continuous review follow-up

The independent consecutive-frame review rejected the current passenger transitions. The first fox becomes wholly visible beside the car at 30.200s, followed by the bear and rabbit at 30.800s and 31.400s. The last returning fox is wholly removed at about 155.800s while its previous feet remain outside the car side. `door_point` is 0.82 tiles beside the car center (the body half-width is 0.60); walking visibility begins/ends at this point without a body/door occlusion transition. Staggered boarding and the all-original-members departure guard hold in the generated four-member case, but this does not accept the visible transitions. Draft visual acceptance remains blocked.

The first MovieWriter run initialized at the default 1360x880 before the fixture changed the viewport to 1654x951. Its contact sheets support finding the abrupt whole-sprite transition, but the resized movie does not qualify original art proportions, and two close-up crops missed the actors. A corrected launch must set the recording resolution before MovieWriter starts. These recordings and clocks remain outside tracked source.

The occasional native fixture exit warning was traced with verbose ownership evidence to one stopped `AudioStreamMP3`/`AudioStreamPlaybackMP3` pair still alive after the first process frame. After 250ms both released; scene, model, illustration and purchase modal weak references were also gone. The focused fixture now waits for this release and asserts owned weak references have cleared before quitting. The native run passed 38 checks without an ObjectDB leak warning; the headless run passed 37. This changes fixture teardown only, adds no production timer and makes no claim about unrelated application lifetimes.


## Doorway correction candidate

The successor moves a new walking origin/boarding endpoint to the parked cabin center and adds a 1.4-tile cardinal side step before the existing aisle path. The same side step is traversed in reverse on return; members remain walking until they reach the hidden cabin endpoint, and departure still waits for all original members. No ID, appearance recipe, car dimensions, simulation clock or global save schema changes.

During only that side step, `parking_door_plane` describes the car's existing 0.60-tile side. The street-passenger painter calls `parking_passenger_portal`, which retains the original character callback under a local side-plane mask. It changes visibility, not character or car scale, pose geometry, identity, color or opacity. A portal reuses an existing native painter slot with one retained character child; the illustration owns both. The moving rectangle is excluded from the retained character appearance key. Reusing the slot for an ordinary object disables its clipping. The focused ownership check verifies that both nodes are freed with their owning illustration.

Historical v1/v2 door routes remain strictly accepted. An invisible, unstarted historical walk is upgraded when the member first exits; an already moving return retains its current position and original traversed route, with a final segment appended into the cabin. Already moving inward routes retain their saved motion, and future returns use the new route. Save validation still checks canonical or specifically allowed historical geometry against actual custody.

Four affected focused suites pass 2617 checks: party/custody and new doorway/node release checks94, rendering485, actual Main service2014, malformed snapshot validation24. The first short native preview verifies MovieWriter1654x951 at30fps by setting the disposable project's viewport before startup; progressive doorway emergence is visible. Complete continuous boarding/departure review and user/integration acceptance remain pending at this candidate checkpoint. Historical rejected recordings and packets remain retained separately. The comparison path with native object retention disabled is not visually qualified by this native retained-renderer evidence.


## Integrated bus and traffic closeout

The owner-approved transient bus holder advances through the same model traffic tick as the existing road and parking pool. Bus approach/rejoin reservations and oriented body clearance preserve existing road occupants' priority. Six fixed bus presentation passengers consume accepted bus progress; renderer observation and first-draw reference synchronization never advance its clock. Pause/Decorate retain state and restore vehicle visibility. Bus dimensions, original solid body and natural far-side doorway occlusion are retained. No new arrival/background timer or saved bus envelope is introduced.

Successful load deep-copies the validated saved road pool and recreates only the offscreen transient bus. Failed load is atomic. Original party/member/appearance custody, parking portal correction, saved road positions/IDs/direction/color, global save version and codec remain preserved.

The766eeb2 parking correction has a bounded independent pass across all four dense disembark windows, ten boarding windows and the complete193.867-second1654x951 native cycle. The earlier whole-sprite-pop and wrong-resolution movies remain rejected historical evidence. The integrated35cbe1c bus45-second30fps cycle and six dense doorway windows have separately reviewed frames; user ordinary-speed playback acceptance remains pending.

Exact467a1364 canonical run38101263431 verifies881raw Git blobs,124dependencies and exact original three-atlas RGBA equality. Manifest-only7272f9e3 binds that proof; no image/import/guard change.662 focused behavior/render checks and17 private actual-Main ordinary-Web lifecycle/traffic checks pass. The latter uses300 fixed1/30 steps and five inspected1280x720 frames; it does not establish real-time browser cadence, ordinary startup/authentication, full-session completion, FPS, memory soak or release qualification. Existing DraftPR158 retains automatic final CI and user/composed-source acceptance gates.

CI clearance correction after PR158 b168be6: the original shelter artwork is translated 0.5 world units toward the lawn through the existing draw_props projection hook. Obstacle bounds and roof classification use the same offset; passengers use the now-clear curb-side aisle and clear the end post before turning behind the glass. The first low planting pocket moves outside the expanded paving. Bus shape/path/door anchor, turning curb clearance, saved pool and party identities are unchanged. Static bench/sign drawing functions stay untouched for PR162 composition. The obsolete fixed kerb sample cap is derived from both actual curved spans plus the six straight/ramp strips; original pedestrian clearance assertions remain intact. Targeted/native/canonical/final CI receipts must be read at the corrected exact source before acceptance.

## Finite final-road departure

A declared coupled traffic fixture exposed a circular wait: a fully boarded car
on the last straight road segment followed the periodic image of a through-road
car behind the street seam. That road car waited behind a new parking arrival,
which the existing single-maneuver selection held until the departure retired.
The final 35-point departure now considers only physically forward road cars.
Arrivals, earlier maneuver segments and ordinary road followers retain cyclic
following; a physical forward blocker still stops the departing car. Existing
speed, clearance, merge arbitration, membership, endpoint and snapshot fields
remain authoritative. The additive traffic argument defaults to the old rule.

The exact isolated `822525ab` baseline/candidate fixture passed 72 checks with
and without the transient bus. It reproduced the declared wait and retired the
candidate at its existing endpoint after 27 fixed 1/30 steps. This is mechanism
and recurrence evidence, not recovery of the unknown leader in the earlier
natural recording and not a naturally completed paid visit. The tracked
`test_parking_finite_departure` retains the same declared candidate input without
shipping duplicate historical production helpers.

The current-main composition preserves the approved 50,000 new-purchase price
and historical paid-cost refunds. `Main`, the runtime codec/save contract,
project configuration and ambient traffic body remain current-main bytes.
The new authoritative road helper lives in `scripts/world/`; its literal
consumers move together. The original `822525ab` source and evidence are frozen.
Current-source engine, atlas, natural paid-party journey, user playback and
merge/release acceptance are separate gates; old receipts do not qualify the
composition. No economy, customer dispatch, service timer, save version, art or
traffic priority rule is added by the finite-leg correction.

The bounded change follows the [Living World contract](../design/living-world.md)
and the existing [Feature Design Quality Gate](../design/README.md#feature-design-quality-gate).
It adds one predicate and one argument at an existing traffic boundary, with no
new retained objects, per-frame search, cache or invalidation. Audio, UI, assets
and rendered geometry are unchanged by this correction. The code-health review
covers only the existing allowance and final-leg dispatch; wider traffic or
path rewrites remain outside this fix.

## Composition with the merged script namespaces

The isolated restack uses reviewed main `7368f0bb0c69185d8ec927c2c5f6d1dc2bdad4d5`
(tree `9dc468bd3c47f4eea7d40fa96f3b75392c3ab0f9`) and the frozen Car source
`378f6855eaabb47963f07e8864f3954a27d6269c`. Existing domains and Script UIDs
remain intact. Parking, its road helper and the fixed sign live in `world/`;
the retained passenger portal lives beside its existing native painter in
`rendering/`. Runtime/test preload consumers use the actual merged paths.
Only `main.gd` and `minimal_start.gd` remain at the script root.

Main, MinimalStart, RuntimeCodec, SaveContract, ambient traffic, project
configuration, the existing atlas manifest and the canonical roadmap retain the
reviewed main's contents. The model receives the existing PR158 snapshot,
restore and purchase-boundary hunks once. The finite departure rule and the
party/bus/portal bodies retain their frozen behavior; this composition changes
resource names and preserves current accepted code rather than importing an
old whole-file implementation.

The earlier 67 gameplay checks and 22 corrected initial-layout checks belong to
the pinned `378f6855` composition. They are retained mechanism and setup evidence,
not a fresh qualification of this namespace restack. The failed register-blocking
fixture remains preserved; the corrected private fixture purchases its third
set at `(9,6)` through the unchanged placement API. No customer or payment is
forced. Fresh exact-source atlas/import qualification and the existing natural
paid-member/same-party boarding-and-retirement observation remain pending.
Per-member payments, abandonment and unreached states must remain explicit;
one member's payment does not establish that all members completed service.
User playback, experience acceptance, publication, merge and release are separate.
