# Plain solid modular cabinet study

Review-only, dependent on `feat/gentle-cooking-011`. No merge, deployment or
visual approval is implied. The current paired capture compares exact before
commit `88f48a2f0793e46eb2e23693fbaa2647751dfa62`, tree
`ca0ab75061ab011cd9b9fd2029f0c037039b1907`, with the exact candidate head.
That before revision contains the rejected feet/recessed-base design; it is a
comparison reference, not the desired design.

## Current design

Counter, drink station, sink and checkout have continuous solid cabinet bodies
that reach floor height zero. There are no feet, corner posts, contact-shadow
supports or additional recessed/designed plinths. Each body and top spans a true
1 × 1 tile in all four rotations: 78 × 39 projected pixels, using 39/34 artwork
units on each axis. Doors are constructed from cabinet width, not image scaling.
The stove dependency also provides a true square one-tile top.

Counter, sink and beverage worktops keep the existing actual height20. Checkout
height26, reduced from29, is a review candidate only. Its equipment translates
vertically intact while the body remains grounded. It is not a selected final
height. Ordinary dish sizes and character scale/proportions are unchanged.

## Grounded service contacts

The former uniform sink inset .43 required a recessed base. The initial
plain-body WIP inset .27 cleared shoes but left a hand gap in two views. The
current presentation-only sink inset is .27 in rotations0/3 and .362 in
rotations1/2. Actual shoe polygons stay outside the full body; both fixed-length
arms contact the active dish through scrub/rinse. Sink basin, tap, dish and water
geometry are otherwise retained from the existing dependency.

Checkout contact pads sit inside the top near each working edge: local Z -.48
for cashier and .51 for customer. The short-arm solver uses those actual
surfaces and checkout height to find its outward stance. Settled shoe outlines,
not just actor roots, must clear the solid cabinet. General counter/beverage
presentation inset is .27. These offsets do not change logical staff positions,
occupied cells, routes, workface selection, timing, prices, economy or saved state.

No global character enlargement is incorporated. The separate mathematical
contact study evaluates1.0,1.25 and1.40 uniformly about the ground anchor; it
is diagnostic, not rendered evidence or acceptance of either larger scale.
Larger characters require further contact work and visual review. Dining round
tables, chairs, plants and small decoration remain out of scope.

## Verification and visual review

Run focused engine suites with the shared lock:

```
python3 tests/run_integration_candidate.py --output <new-output> --lock <shared-lock> --only test_modular_cabinets test_sink_basin_visual test_sink_wash_action test_beverage_accessory_depth test_register_edge test_stove_full_tile capture_modular_cabinets
```

The geometry test inverse-projects every actual top edge and the lower edges
of the continuous body faces. It checks unit ground-edge lengths, grid-axis
alignment and floor corners in every rotation. A 2:1 projected bounding box
alone is insufficient. The capture fixture intersects actual shoe polygons
with the entire square body, not the rejected smaller plinth/support contours.

The existing read-only `modular-cabinet-visual.yml` workflow uses pinned Godot
4.6.3 with GitHub Ubuntu Xvfb/Mesa. It renders the same generated fixture on the
pinned before and exact after commits, isolating profiles and native staging;
no player save is used. Forty images per source cover four directions,
adjacent and wall/corner modules, actual sink/beverage/checkout service jobs,
and normal/medium zoom. Receipts bind source trees, file hashes, camera state,
active contacts and foot samples. The before-source overlap check remains
informational because it intentionally depicts rejected geometry.

Native captures must still be reviewed for the cashier height, uninterrupted
floor contact, shoe occlusion, natural stance and payment-pad placement. Engine
and capture success do not constitute visual product approval. Earlier recessed
plinth and corner-foot proposals are superseded and must not be restored.
