# World depth and occlusion

This development contract documents the existing Little Leaf renderer and the
bounded evidence behind its exterior oak investigation. It supplies review and
regression requirements, not a new rendering framework, approved Golden image
set or certification of every object. The [roadmap](../roadmap.md#current-state)
owns current delivery and acceptance status; shared Art and agent guidance link
to this file rather than duplicating its rules.

The source map was inspected at main
`824a1aaee50e4e0a783054e400a8c46855cd3e9d` and checked against documentation base
`5cfa2f8632592d022b25c9f99c4191f1ce1cefb4`. The unmerged oak candidate in
[PR189](https://github.com/yiyousiow000814/little-leaf/pull/189) is evidence for
one repair, not the default implementation on main. This document introduces
no renderer, model, collision, save or artwork change.

## Ground anchors, footprints and parts

Use world ground contact to determine mutual depth. In the present isometric
projection, increasing world `x + z` projects toward the foreground. Godot's
world `z` is represented by the second component of the renderer's `Vector2`.
A canopy, head, image rectangle or screen-space bounding-box bottom is not a
replacement for that anchor. Camera pan/zoom changes projection, not world
ownership. Keep logical position, smoothed render position and projected ground
anchor distinct; record which position actually feeds each comparator.

An object's model footprint, placement/picking region, visual silhouette and
occluding parts have different jobs. Record their relationship before changing
one. Do not infer a new collision footprint from a crown or sprite rectangle,
or move the model to compensate for a painter-order bug. Existing placement
and movement rules remain authoritative; this contract does not approve new
footprint dimensions. An object spanning several cells may require separately
ordered parts where another object crosses it. A single scalar for its whole
image is not proof of correct overlap.

In [IllustratedCafe](../../game/scripts/rendering/illustrated_cafe.gd), furniture centers
currently use `x + z + 1`, including meal-chair displacement. Chair/bench backs
are separate parts: body depth plus `.38` for rotations 0/3, minus `.38` for 1/2.
Interior actor bodies use smoothed ground position plus `.15`. Service reach
parts are submitted above their actual target surface; station foreground
parts can intentionally cover that reach. These are existing scoped
relationships, not offsets to copy to unrelated artwork. A new split needs an
identified surface, stable part identity and a concrete crossing case.

[Player walls](../../game/scripts/rendering/illustrated_walls.gd) have segmented depth
entries; [openings](../../game/scripts/rendering/illustrated_openings.gd) and wall
apertures must agree with the corresponding floor/world coordinates. Preserve
authored trunks, crowns, shadows and furniture geometry. Developer contours
can expose existing layers; they do not authorize redesigned artwork.

## Ordering boundaries and retained ownership

`IllustratedCafe._draw` uses explicit painter passes. Street actors, exterior
guests and parking cars sort among themselves before the cafe shell.
Neighborhood scenery trees, openings, sliced player walls, furniture and
interior actors enter a later entity queue. Rear foliage and bus shelter
occupants have separate boundaries. A depth value orders entries only inside
its queue: overlapping entities in different passes do not share a comparator
merely because both calculate `x + z`.

For objects that can pass in front of and behind each other, establish a common
ordering boundary or a justified part split. Preserve working shell/roof
relationships and existing tie rules. Do not substitute blanket YSort,
arbitrary offsets or moving an entire pass. Enrollment and exclusion must be
paired so an entity draws exactly once, including empty queues, creation,
selection/drag and first-frame visibility changes.

Native canvas children follow submission-cursor order.
`_insert_native_canvas_child` inserts the child in scene-tree painter order
before its first rendered frame; `_finish_native_objects` hides prior-generation
nodes. [Native draw nodes](../../game/scripts/rendering/cafe_native_draw_node.gd) can
reuse appearance commands while translating. Reuse must preserve current
generation, visibility, part identity and actual sibling order. A correct
scalar depth does not establish correct rendered occlusion.

Cache review must identify the owner, key, invalidating events, reuse path and
teardown of each affected resource. Separate appearance/geometry reuse from
placement and painter order: moving across another object may require new
submission order even when appearance commands stay valid. Check visibility,
part membership, rotation, material/opacity, projection and generation against
the actual cache's dependencies. For example,
[shell command replay](../../game/scripts/rendering/cafe_shell_draw_cache.gd) belongs at
the original shell boundary and retains its projection/attachment dependencies.
Atlas reuse must preserve scale/detail admission and first visible frames.
This is a review requirement, not evidence that every cache or adapter has
passed these cases. Follow the existing
[rendering contract](../testing/rendering-performance.md) and
[memory ownership contract](../testing/memory-regression.md).

## Verified findings and remaining uncertainty

The failed r3 capture produced zero valid frames with a script error. Its raw
receipt and additive failure correction remain preserved; it provides no
occlusion evidence. The repaired r4 diagnostic source was
`f52deca6e582d7229435c40ad2ccb007ade599ef`.

The r4 native GL pilot recorded 359 consecutive completed frames with no
diagnostic overlay, all 43 required fixture states, no dropped observations
and a synthetic wallet unchanged at 1200. It used a no-save fixture and no
Auth. PNG capture overhead means it is not an FPS result.

The oak at world `(-13.1, 1.5)` incorrectly covered the foreground actor's
head/face. Across 191 tree frames, actor-minus-tree ground depth changed from
-1.4 to +1.4, yet the actor was submitted and rendered earlier in every frame.
At sample 0 their depths were -10.20000243 and -11.60000038, and completed
native sibling indices were 31 and 62. Separate painter passes explain this
observed failure. The native order followed submission; a generalized native
sibling-order failure was not established.

The r5 runtime `3ab8f55dae06f7b1d2154dea608489119e597f77` enrolled only that
authored oak in the existing exterior stream, once, retaining the actor/car
sort and other boundaries. It recorded 330 consecutive actual frames and all
43 states. All 162 tree-route frames had the expected actual native order;
inspected before/after PNGs show the foreground head/face in front and the
background actor behind. The 40 Decorate state crops and 15 visible shelter-edge
regions were pixel-identical to the baseline; all 8 confirm/cancel PNG pairs
matched. These observations establish the representative route only.

Fresh [source qualification38122914116](https://github.com/yiyousiow000814/little-leaf/actions/runs/38122914116)
passed for `102aae5e0bcb49f4a2e21b91c6cb4328ea4528bd`, including 120 rendered
dependencies and original atlas RGBA. The manifest-only successor
`ec0ac56ee64dff4bb9972fe7544755265477a278`, tree
`3bc92ea7640cf3dd25d9e9bdf2372d9f426be7b9`, passed all 13 mandatory gates in
[CI38123104864](https://github.com/yiyousiow000814/little-leaf/actions/runs/38123104864);
optional Firebase skipped. No new runtime or qualification was run for this
documentation. User visual approval of PR189 remains pending; CI and atlas
parity do not approve the new oak placement or authorize its merge.

| Case | Evidence boundary | Remaining requirement |
| --- | --- | --- |
| Actor versus authored oak | r4 defect and r5 representative front/back, return and diagonal route inspected | User approval; camera/expansion and crown/shell crossings |
| Decorate table/chair | Four rotations with selected/preview/confirm/cancel frames in separated placements; no disappearing back or duplicate body observed | Overlapping furniture, seated actors and drag across another occluder |
| Shelter edge | 15 local visible edge/occupant regions unchanged | Full roof-entry/exit transition and other viewpoints |
| Other trees and wall/opening intersections | Existing source relationships identified | Continuous crossing evidence; no generalized failure proven |
| Service reach and station parts | Existing split behavior identified in source | Seated/reach/foreground-part regression pixels |
| Cache/atlas/adapter lifecycle | Submission and retention ownership inspected in source | First pan/zoom, creation/reuse/removal and affected fallback paths |

Potential crown/shell overlap after changing a tree's pass remains an acceptance
question, not a confirmed regression. Do not label hypotheses as root causes,
or extend one successful route to all trees, cameras, renderer adapters or
service interactions. Missing evidence above is a focused future gate, not an
instruction to start a broad capture matrix now.

## Deterministic continuous-frame regression

Before implementation, freeze the exact source/tree and a narrowly staged
diagnostic diff. Specify fixed synthetic identities, poses/routes, world
positions, camera/viewport, rotations, render settings and expected ordering
relationships. Choose a bounded frame/state budget for the affected case; the
43 states above are this pilot's coverage, not a universal minimum.

Observe consecutive actual completed frames through both sides of a crossing,
the equal-depth/tie boundary, direction reversal and diagonal silhouette edges.
For affected Decorate work, cover four rotations, selection, drag/preview,
confirm and cancel, checking both the transient preview and first committed
frame. Preserve the full model/wallet; confirm/cancel must not duplicate or
silently alter the object. Add first creation, hide/show, reuse/removal,
pan/zoom and cache/fallback boundaries only when the changed path requires them.

Keep three evidence layers separate: comparator/pass relationship in source,
actual submission and completed-frame order, and inspected overlay-off pixels.
Assertions should detect missing/duplicate parts and stale visibility as well
as pair ordering. Retain exact frame/state IDs and before/after files; isolated
screenshots cannot establish continuous correctness. Browser rAF or an emitted
log row alone does not prove the game completed that frame.

Fail closed on script errors, zero frames, missing required cases, dropped or
non-increasing observations, or unmatched source identity, even if the process
returns 0. Preserve failed receipts with additive corrections. The existing
manual pilot's diagnostic files are present in PR189; they are not an installed
main CI suite or permission to rerun captures. Integrate a small deterministic
regression with an actual affected change; do not rerun unchanged implementation
solely to publish this contract. Required release gates remain intact.

## Developer-only diagnostics and visual acceptance

Diagnostics may expose object/part ID, logical and render world position,
projected ground anchor, footprint/occlusion contour, computed depth, pass,
submission cursor, actual completed-frame sibling index, visibility and
generation. Keep them developer-only, bounded and disabled in player flows.
Inspect overlay-off frames so labels or debug shapes cannot hide a defect.
Use disposable redirected profiles, suppress fixture saves and use synthetic
data without player Auth. Coordinate the shared runtime lock through owned
process exit and teardown; never diagnose with original player storage.

**Pixel Parity** applies when artwork and presentation are intended to stay
unchanged: compare matched deterministic frames and preserve original geometry,
colors, alpha edges, timing and object presence. Investigate differences rather
than updating the reference to make a check pass. Producer-dependent source
changes need fresh source-bound visual qualification; predecessor atlas proof
or a passing unit test cannot qualify changed renderer source. Atlas equality
alone does not test composed scene depth.

**Intentional-art acceptance** requires an explicit scoped art change and human
approval of its actual in-game composition. Retain the prior reference, document
the intended difference, and verify unaffected pixels/behavior separately.
Art approval cannot waive depth, duplicate-part, missing-object, save or lifecycle
regressions. An occlusion repair likewise records intended crossing differences
and requires inspected game pixels; unchanged atlas art is only one gate.

No final Golden set, new pixel tolerance or automatic reference-promotion rule
is approved here. Keep source-bound comparison controls, user acceptance,
required CI, merge and release as distinct states. See
[assets and licenses](../art-audio/README.md) for retained art provenance.
