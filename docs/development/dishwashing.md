# Dishwashing workflow

- Waiters reserve one reachable sink slot before collecting a dirty place setting, carry it to that sink, drop it, and wipe the table
- Each sink holds at most six dishes, including queued dishes, the one being washed, and reservations made by carrying/collecting waiters
- Cleaners wash one dish at a time for 20 simulation seconds. Pausing stops that clock; 2× speed doubles it. Walking or an obstructed workface never advances washing
- Within a sink, dishes are FIFO. Available cleaners choose separate reachable sinks. Waiters prefer the least-loaded reachable sink, with distance as the tie-breaker
- A cleaner already washing keeps the authored front workface. Waiters can drop at a clear reachable lateral edge while washing continues; each interaction cell remains exclusive. Waiting front drop-offs get the next turn before another wash
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
