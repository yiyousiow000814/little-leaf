# Stove work-space reservations

The 0.1.9 candidate treats a stove's working front as required service floor.
Decorate shows that square in the same red floor map used for other required
spaces, even when the stove is not selected. Selecting or previewing a stove
keeps its own rotated working square red.

The reservation protects a usable work space, not an invisible wall. Staff and
customers can still walk through it, and walkable rugs remain allowed. Multiple
stoves may share an open work square; the existing runtime staff reservations
still arbitrate who uses it. Neither the background colors nor the selected
marker creates collision geometry.

## Authoring rules

- New furniture, moves and rotations cannot block an existing stove's front or
  cut off its connection to staff-accessible floor
- A new or moved stove needs an owned, reachable, unblocked working front
- Wall placement, wall moves and doorway edits cannot newly close the stove's
  working edge or route
- Furniture hover, drag confirmation and immediate R rotation use the existing
  atomic edit plan; invalid attempts do not charge, move actors or save
- The floor map remains cached by committed geometry, independent of hover
  selection; no full placement scan is added to rendering

## Older layouts

The save format is unchanged. Existing blocked stoves load and save intact;
there is no automatic deletion, movement or rearrangement. Unrelated edits and
partial repairs stay possible. Clearing a wall and furniture can be done in
either order. An existing issue does not permit creating a new obstruction or
moving the stove to a different blocked work tile. Service pause and recovery
continue to handle old blocked layouts without adding bottom notifications.

## Verification

Full headless suite:

    python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa

Focused model, controller and native GL screenshots:

    python3 tests/run_stove_work_reservation.py --output /tmp/stove-work-qa --native

Both commands use disposable projects and generated profiles. When a fresh
asset import is unavailable, the focused runner can use --import-cache followed
by a source project whose asset inputs and .import metadata match byte-for-byte.
It copies only imported assets and marks clean import unverified. The normal
fresh-import CI/build remains required before publication.
