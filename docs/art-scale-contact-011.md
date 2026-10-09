# Art scale and contact standard · 0.1.11

This is the shared contract for character, furniture and interaction art. The
approved direction is larger **whole characters** relative to the grid and
furniture, with natural internal proportions, and full footprints for appropriate
modular cabinets. Final numerical scale choices are **not yet accepted**. The
rejected torso/leg-stretch A/B study must not become the implementation baseline.
This document changes no runtime geometry and does not certify the candidates.

## Coordinate and footprint basis

One logical cell is the placement/routing unit, not a sprite's bounding box.
At neutral UI scale and zoom, `illustrated_cafe.gd` uses ground half-axes
`(39, 19.5)`: `P(x,z) = (39(x-z), 19.5(x+z))`. A full cell projects to a
78 × 39 diamond. `illustrated_furniture.gd::point` uses `(34,17)` art axes;
therefore a full-cell cabinet spans `39/34` on **each** furniture-local axis.
Rotate its ground coordinates first; height remains vertical on screen. A
screen-width-only stretch is not a valid footprint correction.

Record height conversion separately. `kitchen_worktop_geometry.gd::height`
maps source worktop 29 to presentation height 20, preserves heights at/below 1,
and translates equipment above the worktop by −9. Source height, presentation
height and screenshot pixels are different units. Camera zoom, UI scale and
wall-detail mode (whose world projection has an extra 1.55 height factor) must
be included in a measurement receipt. Compare ratios only in the same mode.

- **Full modular:** counters, sink cabinets, beverage bases and checkout cabinets
  intended to join form continuous top edges on neighboring cells. A recessed
  plinth/toe space may be smaller than the top. Specify both contours and the
  worker's approach side; do not equate top footprint with solid ground volume.
- **Naturally spaced:** chairs, plants, decor and freestanding/round tables retain
  purposeful negative space. Do not enlarge them automatically to fill a tile.
  Record their own visible contour, support contacts and usable surface.
- Placement, route occupancy, saved positions and interaction identity remain
  model-owned. Presentation changes must not silently resize these contracts.

## Ratio registry: observed, proposed, accepted

Use presentation art units before camera scaling. `G=78` is the full-cell
projected width; `H` is a named character's ground-to-top standing silhouette,
including its stated ears/hat. Store body crown and accessory limits separately
when judging anatomy or door clearance. These are source observations, not a
mandate to preserve today's ratios.

| Quantity | Observed source baseline | Candidate / accepted target |
| --- | --- | --- |
| Grid and furniture basis | G=78, depth=39; art axes 34/17 | Keep explicit conversion; no new target |
| Whole-character scale S | S=1; head center y=−38, ellipse radii 13.1 × 12.7; compact arm 10.5, standing leg 9.5 | Uniform whole-art scale; **S unchosen** |
| Standing H | Bunny 72, fox 60, bear 54.4; chef-hat silhouette 63.5 | Re-measure each species/outfit/direction at chosen S |
| H/G | Bunny .923; fox .769; bear .697; chef hat .814 | Unchosen |
| Dining service plane T | T=27; decorative top relief 27.8125 | T/H and tabletop footprint must be reviewed together |
| Basic chair seat C | C=18; C/T=.667 | C/H, seat depth and seated hip contact unchosen |
| Station heights K | Per-kind body, top and contact planes below | Each K/H is separate and unchosen |
| Pot food/rim plane / shoulder | Food/rim center 32; standing shoulder heights 24/26.5 | Re-solve reachable grip, not limb length |
| Door D | D=97 | D/H and ear/hat clearance unchosen |
| Modular top coverage | Counter 54.4/G=.697; beverage 57.12/G=.732; sink 59.84/G=.767; checkout 56.44/G=.724 | PR #91: full 78 × 39 tops; numerical acceptance pending |

Core constants above were checked against main
`f30200e6979eda549d6d925300bc40c347a42e48`. Silhouette/rim and modular-comparison
measurements also use the frozen full-tile study
`10be07b77f16f868eec5fa7c4ae5fcb384b586b6`; that study is **not main**.
Relevant sources are `compact_character_pose.gd`, `directional_character_art.gd`,
`dining_placement.gd`, `illustrated_furniture.gd`, `kitchen_worktop_geometry.gd`
and `illustrated_cafe.gd` under `scripts/`.

### Station height planes (main f30200e6)

All rows below are traced in the full main commit named above. `height(h)` is
`kitchen_worktop_geometry.gd::height`; raw screen Y is not a height measurement.

| Kind and source function | Source height → presentation height | Meaning |
| --- | --- | --- |
| Counter `illustrated_furniture.gd::cabinet` | 29 → 20 | Cabinet body/top, no raised working slab |
| Beverage `::_beverage_base` | 29 → 20; tray 30 → 21 | Cabinet top versus separate drip tray (rail at 30.4 → 21.4) |
| Sink `::_draw_item_legacy`, kitchen geometry constants | 29 → 20; rim 30 → 21; opening 30.2 → 21.2 | Cabinet top, basin rim and opening are distinct |
| Sink `::sink_plate_anchor` in kitchen geometry | 23.5 → 16.267857 | Dish-stack support inside the basin, not rim height |
| Stove `illustrated_furniture.gd::_stove_base` | Body 29 → 20; slab 31 → 22; support 34 → 25 | Cabinet, cooking surface slab and pan support |
| Stove `::stove_food_surface`, `::stove_pan` | Food 41 → 32; rim center at height(34)+7 = 32 | Food contact/rim-center plane, not the slab |
| Checkout `cafe_checkout_art.gd::draw_register`, `::contact_surface` | Body/top 29; cashier pad 30; guest pad 31.2 | No kitchen-height conversion for checkout |

Thus the earlier “surface 22” and “rim 32” describe the stove, while 20 is the
kitchen cabinet height. A visual join between different-height module types
needs an explicit design decision; matching their ground widths alone does not
make their top elevations equal. The frozen full-tile/cabinet candidates keep
these height distinctions; re-audit any later source that changes them.

A discussed S=1.25–1.40 range is exploration only. For example, 72×1.40=100.8
exceeds the current door height 97 before clearance. This is a compatibility
warning, not a recommendation to pick 1.40 or enlarge every door. Compare the
actual projected opening and animated silhouette in the same camera mode.

PR #91's cabinet candidate uses a .66-cell recessed plinth, upper box starting
at source height 6 (kitchen presentation 4.392857; checkout remains 6), and
sink working inset .43 instead of .55. Its sink assembly
moves with its hand/dish/water contacts. Those values were studied at S=1 only;
none qualifies a larger combined character. For each future accepted row, add
value/unit, scope, source SHA, fixture/camera receipt and explicit approval
reference. Until then its accepted field is **unset**.

## Shared contact geometry

Keep a single transform chain from logical cell → presentation stance → whole
character scale → local pose → screen. Scale the complete silhouette, limbs,
clothes and local anchors together around the declared foot/root anchor; keep
head/body/limb proportions intact. Surface targets belong to furniture geometry
and must be transformed into the character's pose space before solving reach.
Never fix an unreachable pan, plate or terminal by stretching an arm or leg.
Keep solver-specific lengths explicit: compact limbs use arm 10.5; the cooking
grip solver uses upper arm 5.5 plus forearm 6.5. Uniform whole-character scaling
multiplies those fixed lengths together; it does not replace them with one
universal reach.

The same resolved coordinates must drive both drawing and contact checks:
foot sole and shadow at the floor; seated hip on the seat; hand on tool grip;
tool tip against its working surface; carried plate/tray and contents against
their support. Include shoe/prop polygons and antialias bounds, not just anchor
points. A successful hand-distance check alone cannot prove no cabinet overlap.

Stationary preparation, cooking, waiting at the stove and plating use one
station-facing stance/inset while the worker remains assigned to that work
position. Do not choose a different inset only because the heat becomes active.
A pose/action transition must not move the feet or reinterpret approach motion
as a new heading. Track physical travel heading separately from work-facing;
use an explicit transition when a real approach/departure is required. The
full-tile study's cooking inset .32 is an observed candidate, not a universal
inset for every station.

Occlusion is part of contact: near rims may hide tool tips, a chair/table may
hide the appropriate leg/body region, and far limbs must remain behind the
body. Use shared depth/clip geometry across main and overlay passes. Recheck
atlas bounds, culling and shadows after scaling so ears, held dishes and feet
are neither clipped nor painted twice.

## Canonical same-scene acceptance fixture

Adopt one deterministic, generated restaurant with no player save access. Its
layout contains a joined counter→beverage→sink→checkout→stove strip, a matching
wall-corner strip, a table with occupied/empty chairs on all use sides, a plant
and round-table spacing example, and a working door with a one-cell aisle.
Place bunny, fox and bear guests plus a hat-wearing cook together so comparisons
share scale. Freeze layout, model state, species/outfit, seed and action clocks.

Capture the exact same fixture on baseline and candidate at all four ground
rotations, normal play zoom, useful medium/review zoom and maximum inspection
zoom. Keep a complete-character view at review zoom; a cropped maximum-zoom
close-up cannot establish whole-character proportions. Record viewport, UI
scale, zoom, pan/origin, wall-detail mode, source commit/tree, fixture hash and
per-frame phase. Preserve full uncropped originals and a paired-source receipt;
label any crops or annotated comparisons. Use actual game rendering, not a
redrawn illustration, to make acceptance decisions.

The fixture should exercise standing and stationary prep→cook→plate, approach
and departure, ordinary walking/turning, carrying and handoff, sitting/eating/
drinking/dismounting, sink/drink/checkout use and door traversal. Review foot
planting, heading continuity, hand contacts, seat support, aisle/door clearance
and depth ordering together. Test build-mode selection/rotation/placement and
normal-play clicking at the visible bounds: art growth must not create stale
hit regions, blocked UI, wrong-object selection or clipped camera edges.

For motion claims, record continuous timestamped playback through transitions
and a complete action cycle, including frame cadence and speed. A few separated
PNGs only establish those static states. Keep geometric tests, rendered static
checks, temporal review and browser/UI checks as separate results with explicit
passed/failed/not-run status; never summarize partial evidence as “all passed.”

## Evidence available and remaining decision

The cabinet comparison pairs study base `10be07b7` with candidate `e3af25d0`
(80 images and `paired-source-receipt.json`). Its adjacent and wall-corner
frames show the proposed continuous tops; four-direction working scenes cover
sink, beverage and checkout at S=1. The owner reports zero shoe/plinth polygon
overlap in those 12 scenes. This does not prove combined-scale clearance.
The cooking comparison `2173e827` → `96e8d3b0` contains 52 PNGs; it is static
appearance evidence, not proof of smooth movement.

Reference-game imagery informs the desired human-to-room relationship only.
Its camera, internal units and source formulas are unknown; do not claim to
recover them from screenshots. Keep third-party raw references and private
links outside repository artifacts. Publish only authorized Little Leaf source
and original-game evidence.

Next acceptance decision: choose whole-character and furniture ratios together
from the canonical scene, then requalify contact, motion, occlusion, door and UI
behavior on the **combined** source. No final ratios or combined acceptance are
recorded by this documentation PR.
