# Table floor-contact study (0.1.11)

This bounded visual candidate targets the user's report that tables also look as if they float. It depends on the gentle-cooking art source at remote commit `10be07b77f16f868eec5fa7c4ae5fcb384b586b6`. It is not a deployment or approval to merge.

## Changed presentation

- Basic oak already had four floor-height supports. It now has four small, restrained 2:1 contact patches at those exact foot anchors, painted behind all supports.
- Cottage and refined table supports now end at floor height zero instead of one art unit above it. Their small contact patches share the same rotated world anchors.
- The retro pedestal's bottom disk now sits at floor height zero, with one restrained contact shadow.
- Tabletop contours, top height, upper support attachments, tableware and service anchors, dining docking, item footprint, collision, and saves are unchanged. Freestanding tables have not been expanded to fill a tile.

## Coordinates

The fixed isometric camera projects equal world x/z grid steps with a 39/19.5 screen basis. Furniture geometry has a separate 34/17 art basis; a full tile in that helper is 39/34 units on both axes. Both projections are 2:1; screen width and height are not world width and depth. Camera movement is pan/zoom, while the four-direction checks rotate furniture and the dining association.

The existing basic/retro round tabletop uses radii (25,12), about 4% flatter than an exact projected circle (25,12.5). That contour remains untouched in this grounding-only candidate. It is a separate scale-standard follow-up.

## Verification

Focused engine checks: `test_table_ground_contact`, `test_table_ground_capture`, dining placement/docking/occlusion/service-plane, chair ground contact, and art raster strokes. Run through the disposable-profile integration runner and the shared engine lock.

Native source-bound comparisons use `ci/capture_table_ground_contact.py` and the dedicated feature workflow. The exact same generated fixture is applied to the pinned base and candidate. Each source produces 64 source-geometry images (four table styles, four directions, empty/occupied, normal/medium zoom) plus eight basic-table medium-zoom cached images. Cached captures assert that the actual `table_body` atlas layer drew; a silent fallback fails capture. Paired gameplay-state hashes and camera origins must match, with zero save calls. Native artifacts retain exact source/fixture hashes and PNG digests. Pixel inspection is still required before claiming the visual concern is resolved.
