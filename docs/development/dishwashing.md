# Dishwashing workflow

- Waiters reserve one reachable sink slot before collecting a dirty place setting, carry it to that sink, drop it, and wipe the table
- Each sink holds at most six dishes, including queued dishes, the one being washed, and reservations made by carrying/collecting waiters
- Cleaners wash one dish at a time for 20 simulation seconds. Pausing stops that clock; 2× speed doubles it. Walking or an obstructed workface never advances washing
- Within a sink, dishes are FIFO. Available cleaners choose separate reachable sinks. Waiters prefer the least-loaded reachable sink, with distance as the tie-breaker
- A cleaner already washing keeps its front workface. One waiter can deposit from the outer corner of that front cell while washing continues, or use a clear reachable lateral edge. Front sharing is limited to one washing cleaner and one depositing waiter at the same sink; other bodies, work claims and physical obstructions still block the drop. Two droppers or two washers cannot share a contact
- A carrying waiter switches to another reachable sink with capacity and an available drop side when its reserved sink is full or unusable. If every side is temporarily occupied, it retains its capacity reservation and held dish, then retries. Switching sinks restarts the physical drop gesture; the janitor's queue and wash progress are unchanged
- When all sinks are full or inaccessible, the waiter retains the table/hand payload and retries. A reservation is released when an unstarted collection is canceled
- A queued dish is independent of its diner, so the table can be reused after drop-off and wiping. The visible sink pile counts queued and currently washed dishes, never reservations still in transit
- Selling a sink with a reservation, queued dish, or active washing job is blocked. Moving it keeps the same item identity and dish queue; the worker follows the new workface and preserves progress

## Save contract

The outer save version and filename remain v15. The internal service format advances from 3 to 4 so older builds reject new queues instead of silently dropping them. The new reader accepts old service formats and migrates old in-flight sink payloads into the independent queue. An old wash retains its completed fraction of the 20-second duration. Dirty dishes in hand keep their staff identity until physically dropped

Format 4 requires `service.dishwashing`, containing its format marker, monotonically increasing `next_id`, `completed` count, and dishes with `id`, `sink_id`, and `elapsed`. A guest record uses `dish_sink_id` only while reserving transport capacity, then `dish_id` plus `plate_owner="dish_queue"` after handoff. A cleaner uses `job_kind="wash"`, `job_dish_id`, and the matching token. Validation rejects over-capacity sinks, duplicate dish IDs/owners, mismatched elapsed time, missing sinks, wrong staff roles, and missing ledgers before replacing a live model

## Verification

Run the focused regression entry point documented in `docs/README.md`. Relevant suites are `test_dishwashing_queue`, `test_role_boundaries`, and `test_role_release`; select those that observe the affected behavior. All tests use synthetic profiles and suppress normal saves. `tests/diagnostics/capture_dishwashing.gd` captures only the synthetic game viewport; `OUTPUT` selects its capture directory

## Single-basin visual revision

The decorative drying rack, ornamental upright dishes, and side bottle are removed. One centered basin fits the unchanged plate footprint. The near-facing faucet is redrawn in front of the stack at rotations 90° and 180° so the pile cannot cut its stem in half. This changes art only: station footprint, item IDs, queue, capacity, durations, service ownership and saves are unchanged.

## Recessed basin and raised tap

The bowl now has an opening at the rim, shaded vertical interior walls, and a floor more than five art pixels lower. Its lower dishes are clipped to the real aperture, with the near rim drawn in front. The taller tap's outlet clears the projected top of six dishes by more than eight art pixels in every rotation. Its stem remains behind the stack in rear-facing rotations; it is not forced to the foreground. Plate size, station footprint and all functional core files remain unchanged.

## Automatic water and two-hand washing

Water is a read-only presentation of an actual cleaner wash job at the sink workface. It stops when the worker leaves, the job ends, or the game is paused/decorated. There is no tap-opening animation or manual valve lever. The 20-second job clock drives lifting one active plate, short scrubbing, rinsing and lowering/removal. Waiting plates remain separately stacked and still count toward the same six-slot capacity. Fixed-length bent arms use the accepted arm-occlusion mask; one hand supports the rim and the other touches the sponge to the dish. Foam stays inside the active dish and fades during rinsing. The water contact is solved on that tilted dish, not the queued pile. The five functional core files remain unchanged by this visual revision.

## Continuous drop contact

The existing drop clock moves the carried plate to the basin opening at the .65 ownership beat, then lowers it into its own queue slot while empty hands withdraw. The sink-local aperture and foreground rim mask the lowering plate; world entity sorting stays unchanged. The original short-arm solver, plate and held-glass details are reused. Post-contact animated dishes are excluded from static drawing by dish ID, so concurrent drops have distinct slots. A presentation-only lowering sample per active staff member rebases the remaining path when the queue advances; inactive staff entries are pruned during motion updates. This state is bounded by the staff roster and is never saved. Native and Web transition evidence remains required before visual acceptance; dependency rebinding requires exact canonical generated/imported/decoded atlas parity.

Front deposits reuse the .75-second gesture and the same .65 contact beat. A per-staff-frame value snapshot preserves each contact claim when an earlier worker completes its job; it is discarded after that frame and never saved. The renderer uses its existing smoothed stance offset to separate the front waiter from the washer. Focused queue regressions cover both roster orders, completion, pause, generated-save reload, competing claims and legacy cleaner transport. Rendered reach and body clearance remain separate acceptance gates.


## Front handoff contact and ceramic occlusion candidate

The front depositor reuses the full-cell washing shoe inset and retains the existing lateral separation. Its unchanged short arm releases the plate above the reachable inside corner of the basin, then the existing lowering path settles it into its owned FIFO slot. The .65 ownership beat, .75-second gesture, 20-second wash, capacity, job clocks and saves are unchanged. Side deposits retain their original center target.

The front rim is painted before above-opening dishes; submerged fills remain clipped to the real aperture. Ceramic outlines clip their original contours rather than stroking artificial intersection edges. A front-facing faucet remains the final foreground layer. The carried drink omits only its surface-shadow ellipse; resting cups and all other cup art are unchanged.

This small Art/Technical Art/Animation repair reuses the current sink geometry, short-arm solver, clipping path and native draw ownership. It adds no assets, persistent objects, saved state, audio or new rendering framework. The extra short contour intersection runs only for a clipped plate; retained ownership and cache invalidation remain with the existing renderer. Performance, production atlas/export qualification and explicit user appearance acceptance are separate gates.

Source-bound native comparisons on main `f884a584244d9453b90a7c4bb2dc7d7f33861e7d` plus PR303 `f726772ab802af894d18892c2166506288c469ff`, PR304 `1bcdbcd11e451502498524670effc31c59476654`, and the local repair passed 56 front-handoff observations across four rotations, including both dishes completing once in FIFO order. At the captured .60 pre-release phase the nearest-hand error fell from 7.53–8.92 art pixels to zero in all four rotations. Native wrappers of the existing modular-cabinet and basin suites passed 196 and 3835 checks, including shoe clearance, original-contour clipping and held/resting cup-shadow controls. The first new test-wrapper signature failure is retained as failed evidence, not reclassified. These comparisons used explicit uncached native furniture, disposable profiles and unchanged production render functions; they do not qualify the production furniture atlas, Web export, full CI or user acceptance.

## Table clearing after chair departure (candidate)

The requested behavior is to let a waiter clear a finished diner's place setting after the diner physically leaves the chair, without waiting for checkout or the shop exit. Seated checkout overflow, a chair dismount and movement back to an assigned seat are not departure. The existing chair/table clearance distances still apply. Waiter table stages 0–2 may run alongside that same visit's cashier payment; two table workers may not own the same cleanup. Cleaner floor eligibility, station workface claims, sink reservations/capacity, pickup rules, durations and presentation are unchanged.

Cleaning does not settle or cancel the bill. The visit, checkout ticket/token and dining booking remain owned until their existing lifecycle releases them; a cleaned but unpaid table is not advertised as available. Actual cashier contact remains the only new-visit settlement path. This is an eligibility and ownership repair, not a scheduling-priority rewrite or an early seat-reuse feature. A two-table source probe on the original implementation already selects the next eligible table on the next staff tick, without a mandatory return home.

Service format 6 explicitly permits departed, unpaid checkout visits with dishes in the waiter's hand, in the independent sink queue, or already washed, and with a partially or fully wiped table. Validation ties those states to the waiter, compatible cleanup stage and existing dish ledger. Original service 3–5 checkout invariants are checked before migration. Outer save v15, optional layout-hold v16, filenames and checkout format are unchanged. Older readers reject service 6 before replacing live state; they must not silently read a new state as service 5. Their existing unsupported-save protection remains authoritative.

This candidate reuses the existing checkout, dishwashing, cleanup and persistence components. It adds no assets, saved fields, retained resources, route search, new per-frame scan or cache. The already-running assignment scan adds only the phase and independent-job predicates; duplicate cleanup ownership is checked only during save validation. A one-line phase bypass was rejected because both the visit-wide job lock and save validation would otherwise disagree with the new state.

Focused source-bound Godot 4.6.3 verification uses generated profiles only: `test_early_table_cleanup` covers actual chair departure, concurrent cashier/waiter contact, collection/carry/drop/wipe/completion, real save/reload at each stage, unchanged identity/debt/bookings, malformed states and exactly-once later settlement. The same fixture fails the new eligibility assertion on main `6a8cd095ea0ab61086d91427b84f84fc36884684`. Existing `test_dishwashing_queue`, `test_role_boundaries` and `test_role_release` remain the related regressions. Native source tests and an original-main reader refusal probe are not browser/export, fresh-import or visual acceptance. User gameplay acceptance, merge and publication remain separate gates.
