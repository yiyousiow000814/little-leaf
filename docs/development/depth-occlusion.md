# World depth and occlusion

This contract records the renderer inspected on main
`824a1aaee50e4e0a783054e400a8c46855cd3e9d` and the bounded diagnostic
`f52deca6e582d7229435c40ad2ccb007ade599ef`. It describes existing rules and
required evidence for changes; it does not certify every object or report a
released fix. The [roadmap](../roadmap.md) owns current product status.

## Anchors and ordering

Use world ground contact to determine mutual depth. In the present isometric
projection, increasing world `x + z` projects toward the foreground. A canopy,
head, image rectangle or screen-space bounding-box bottom is not a replacement
for that ground anchor. Keep logical position, smoothed render position and
projected anchor distinct when observing movement; record which position feeds
the comparator. Camera pan/zoom changes projection, not world ownership.

Current `IllustratedCafe._draw` has several explicit painter passes. Street
actors, exterior guests and parking cars sort among themselves before the cafe
shell. Neighborhood scenery trees, openings, sliced player walls, furniture
and interior actors enter the later entity queue. Rear foliage and bus shelter
occupants have their own boundaries. A depth value only orders entries inside
its own queue: two overlapping entities in different passes do not share a
comparator merely because both calculate `x + z`.

For entities that can pass in front of and behind each other, a repair must
establish a common ordering boundary or an explicit justified split. Preserve
correct shell/roof boundaries. Do not replace these relationships with blanket
YSort, arbitrary offsets or a whole-pass move. An eligible entity must be drawn
once, including during first-frame creation, dragging and camera changes.

## Existing parts to preserve

Furniture centers currently use `x + z + 1`, including meal-chair displacement.
Chair/bench backs are separate parts: body depth plus `.38` for rotations0/3,
minus `.38` for1/2. Interior actor bodies use smoothed ground position plus
`.15`. Service reach parts are submitted above their actual target surface;
some station foreground parts intentionally cover that reach. These are
existing scoped relationships, not offsets to copy to unrelated artwork.

Player wall depth entries are segmented; opening geometry and wall apertures
must remain consistent with the corresponding floor/world coordinates.
Preserve authored trunk, crown, shadows and furniture geometry. Diagnostic
occlusion contours may identify the authored layers; they do not authorize
new collision shapes or a redesigned tree.

Native canvas children follow submission-cursor order. `_insert_native_canvas_child`
inserts the child in scene-tree painter order before its first rendered frame;
`_finish_native_objects` hides prior-generation nodes. Retained objects can
reuse appearance commands while translating. Reuse must preserve current
generation, visibility, part identity and actual sibling order; a correctly
computed scalar depth alone does not establish correct rendered occlusion.

## Verified bounded findings

The native GL pilot captured359 consecutive completed frames with no diagnostic
overlay, all43 required states, no dropped observations and a synthetic wallet
unchanged at1200. It used a no-save fixture and no Auth. PNG capture overhead
means this is not an FPS result.

The exterior oak at world `(-13.1, 1.5)` incorrectly covers the actor's head/face
when that actor is in front. Across191 tree frames, actor minus tree ground
depth changes from-1.4 to+1.4, yet the actor is submitted and rendered earlier
in every frame. At sample0 the actor depth is-10.20000243, tree-11.60000038;
their completed native sibling indices are31 and62. The cross-pass boundary
above explains this observed failure. No general native sibling-order failure
is established by this case.

Table and chair rotations0..3 were inspected across168 selected, preview,
confirm and cancel frames in separated placements. No disappearing back or
duplicate body was observed. All8 first-confirm/first-cancel PNG pairs are
byte-identical. This does not establish correctness for seated actors, service
reach, overlapping furniture, every wall or another renderer adapter.

## Change and acceptance boundary

Before a renderer fix, freeze its exact source and narrowly staged diagnostic
diff. Observe continuous actual completed frames at front/back crossings and
diagonal silhouette edges. For Decorate, cover four rotations, selection,
drag/preview, confirm and cancel, preserving the model and wallet. Keep source
ordering, actual submission order and inspected pixels as separate evidence.

Dev-only observations should identify object/part ID, world position, projected
ground anchor, computed depth, submission cursor, actual completed-frame sibling
order, visibility and generation. Inspect overlay-off images as well. A script
error, zero frames, missing required state or dropped observation fails closed,
even when the engine returns0. Preserve failed receipts with additive correction.

Use disposable redirected profiles, suppress fixture saves, and coordinate the
shared runtime lock through owned-process exit and teardown. Do not use a
player's account or storage. Changes to IllustratedCafe or its producer
dependencies require fresh source-bound visual qualification; predecessor
atlas proof and passing tests cannot qualify changed renderer source. See the
[rendering contract](../testing/rendering-performance.md). Art approval cannot
waive an observed depth regression.

The next narrow candidate is a common exterior ordering stream for the affected
street actors and greenery, with explicit shell eligibility and once-only
submission. It remains a proposal. Broad actor-tree, wall, seated-service,
cache/adapter and first-pan/zoom acceptance remain open; no production fix is
claimed by the diagnostic.
