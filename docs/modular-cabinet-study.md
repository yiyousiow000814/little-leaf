# Modular cabinet footprint study

Review-only, dependent on `feat/gentle-cooking-011`. No merge or deployment is
implied. Frozen before source: `10be07b77f16f868eec5fa7c4ae5fcb384b586b6`,
tree `1a591fbe726aa205b7bb237779c2221eed8e20e2`.

## Controlled change

The counter, drink station, sink and checkout use the range's one-cell top:
78 × 39 artwork pixels in every rotation (39/34 units on both local axes).
Previously their widths were 54.4, 57.12, 59.84 and 56.44 pixels respectively.
Doors are constructed from the new cabinet width; this is procedural geometry,
not a screen-space image resize. Equipment and ordinary dish sizes stay intact.
A lower recessed plinth is .66 cell wide; the upper carcass remains one cell.
Three retained atlas crops expand to preserve the complete new silhouettes.

The sink requires a contact adjustment: its former .55-cell inward stance put
its rendered root inside the new upper cabinet. The candidate uses .43, leaving
the root .57 cell from the sink center. The sink assembly translates by exactly
(.55 − .43) × 39/34 artwork units toward that working face. Thus the fixed-length
hands, dish, water and basin preserve their old relative positions, while the
feet are outside the full upper box and have physical toe space at the plinth.
The narrowest measured settled-shoe clearance to that plinth is .0255 cell;
native screenshots must still be reviewed for actual layering and stance.

Checkout contact pads move symmetrically from ±.35 to ±.46 artwork units
on the larger top; their existing short-arm solver calculates the matching
stance. The terminal and receipt geometry stay unchanged.

Logical occupied cells, routes, workface selection, timing, prices and saved
state are untouched. Character head/body/limb proportions, stove geometry,
chairs, tables, plants and small decoration are untouched. The separate body
proportion experiment is not incorporated here.

## Evidence

Run the focused engine suites with the shared engine lock:

```
python3 tests/run_integration_candidate.py --output <new-output> --lock <shared-lock> --only test_modular_cabinets test_sink_basin_visual test_sink_wash_action test_beverage_accessory_depth test_register_edge test_stove_full_tile capture_modular_cabinets
```

The read-only `modular-cabinet-visual.yml` workflow uses the existing pinned
Godot 4.6.3 and Xvfb/Mesa capture route. It renders the exact same fixture on
pinned before and exact after commits, with separate generated profiles and
native staging, never a player save. Its 40-image matrix per source covers
four directions, adjacent modules, wall/corner modules and actual service
jobs for sink, beverage and checkout, at normal and medium zoom. Receipts bind
source trees, file hashes, cameras, active contacts and planted-foot samples.
No sparse-frame animation is constructed. These images are proposals for user
review; passing engine or capture checks does not mean product acceptance.

## Grounding correction after screenshot review

The user correctly identified a floating appearance at checkout: the source-6
outer box occluded the entire narrow plinth in isometric projection. The second
controlled pair uses `c5cb7eb7fef03ac54daa4bd69639b558069db012` as its before
source. It adds four small real floor-reaching corner supports to each of the
four cabinet types, with contact shadows only beneath those supports. The
central toe recess and all top/work/contact geometry remain unchanged. Check
actual shoe polygons against both the plinth and all four support footprints.
These are unchanged-character-scale proposals, not proof for larger characters.

## Equal ground-side audit

Main `f30200e6979eda549d6d925300bc40c347a42e48` uses rectangular artwork
(top width × depth in world cells): counter .741026 × .653846, beverage
.784615 × .680000, sink .819487 × .714872, checkout .784615 × .662564,
and stove .793333 × .706154. Logical occupancy was nevertheless one square cell.
The candidate with its stove dependency has five true 1 × 1-cell tops. The
focused test inverse-projects every actual drawn top edge, checking unit length
and alignment with a world grid axis for all four rotations. A 2:1 screen
bounding box alone cannot establish equal world sides. The .66 × .66-cell
plinth and .078462 × .078462-cell corner posts are deliberately smaller support
contours; they do not change the top or logical occupancy. Chairs, round tables,
plants and small decoration remain separate naturally spaced designs.
