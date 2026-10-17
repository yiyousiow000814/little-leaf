# World depth and occlusion

This development contract documents the existing Little Leaf renderer and the
bounded evidence behind its exterior oak investigation. It supplies review and
regression requirements, not a new rendering framework, approved Golden image
set or certification of every object. The [roadmap](../roadmap.md#current-state)
owns current delivery and acceptance status; shared Art and agent guidance link
to this file rather than duplicating its rules.

The source map was inspected at main
`824a1aaee50e4e0a783054e400a8c46855cd3e9d` and checked against documentation base
`5cfa2f8632592d022b25c9f99c4191f1ce1cefb4`. The accepted oak repair in
[PR189](https://github.com/yiyousiow000814/little-leaf/pull/189) subsequently merged
as `6db1c726053f9e2071ca5b6e40629f2a371d2cb3`; current main includes it.
The dated observations below retain their original source scope. This document introduces
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
guests, parking cars and the representative oak at `(-13.1, 1.5)` share the
exterior ground-depth order before the cafe shell. The oak is enrolled once;
the existing actor/car tie order is retained. Other neighborhood scenery trees,
openings, sliced player walls, furniture and
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
documentation. These are historical qualification results. The later scoped
user visual approval and actual PR189 merge are recorded in that PR; they do
not broaden the original representative-route evidence to other objects.

| Case | Evidence boundary | Remaining requirement |
| --- | --- | --- |
| Actor versus authored oak | r4 defect and r5 representative front/back, return and diagonal route inspected; scoped repair accepted and merged in PR189 | Camera/expansion and crown/shell crossings |
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
manual pilot's diagnostic files originated in PR189 and are retained by
[PR197](https://github.com/yiyousiow000814/little-leaf/pull/197); the production
PR189 merge did not install them. They are not a main CI suite or permission
to rerun captures. Integrate a small deterministic
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

## Stove handle over chef head — requirement16 candidate

The user rejected PR333 at8d74a50 after inspecting actual before/after pixels:
the grip appeared lost and both pan and handle should be behind the character
from this view. That candidate's source review and tests were not visual
acceptance. Its original artifacts remain historical rejected evidence.

The revised queue uses the existing actor/station depth relationship: a complete
stove foreground is admitted only when the worker is behind its target (`split`)
and a preparation plate needs that local occluder. A worker in front naturally
occludes the whole vessel and handle in their original furniture pass. Plating
already uses idle art and keeps no obsolete whole-vessel redraw. The furniture
painter, complete handle/collar/grip and every geometry constant are restored
byte-for-byte to main11f4c869; the foreground no longer has a handle-exclusion
option. Legitimate rear-work foregrounds retain their full original handle.
No global head repaint, actor relocation, shortening, removal, pose, footprint,
contact or save change. Overlapped handle portions are naturally hidden by the
character; this does not promise every grip pixel remains visible from all views.

This reuses the current painter queue and existing `split` relation, with no new
cache, retained object, callback or lifecycle owner. Plating and front-worker
preparation omit an unnecessary queue entry; no measured FPS claim follows.

The revised native Godot4.6.3 GL/llvmpipe synthetic no-save fixture matches
rotation0/1/3 preparation/cooking/plating, normal zoom1 and the actual maximum
against original source302e77d and the rejected candidate. Cooking, all rotation3
controls and rotation1 preparation are exact RGBA matches to original. Rotation0
preparation now changes the complete vessel/actor boundary, not just the grip;
rotation0/1 plating retains the idle-visual queue correction. All18 camera,
logical/rendered actor, target and phase/clock records match. Original furniture
source identity and the existing22376 geometry assertions (including full-grip
foreground checks) protect exposed geometry. Canonical regeneration verifies
all3fixed atlas RGBA images; selective provenance updates preserve every atlas
PNG/import/asset record and prior proof. Required CI is separate.

The exact original IMG_0828 runtime phase/layout, all continuous phases and
browser/device surfaces remain unqualified. The parent reviewer inspected its
pixels; this lane received metadata/image pointer only. Revised appearance,
independent source review and mandatory CI remain pending. Keep Draft and all
merge/deployment holds; no Golden reference or prior acceptance is inferred.


## Accepted lid steam — requirement18 source closeout

This is preservation of the provisionally accepted stronger burst, with no new
effect design and no requirement17 delta. Original accepted source is
`839c984b5532854af69067f38b286cebf96d0fb4`, tree
`96e397304ab3c32232f5e1de3203330dc62a4042`. Uploaded MP4:2177013 bytes,
SHA256 `a7b7e218644467609f0ce462d0d9c8e2242e4f86b718f5d93b3f615f19c999e7`.
The user's “可以吧 暂时先这样” is a bounded provisional keep decision, not a
Golden Reference or full browser/device approval. The owner retains the accepted
native recordings (including pause/resume, two-mesh reuse and zero saves), prior
rejected versions and original449-check log SHA256
`69d861d7e40afadf5592bf9aa332ee10b7cacd1666e9a8c48b6b0a0e220892a9`.
Those original media were not copied or re-inspected during this closeout.

Exact supplied patch SHA256:
`caae35e1ef755cbc9406ae3f800c23b4c462b9f846622cea8b518852d1138f33`.
It applies to unchanged preimages on main `6a8cd095ea0ab61086d91427b84f84fc36884684`.
Local source commit `e6b38bcabc4fbe7e7ad079f3411d659ace1f243c`, tree
`485aaeb6fc8dabe7ace58455840e300271ecc4c4`, changes exactly four files:

| File | Accepted raw SHA256 |
| --- | --- |
| `game/scripts/rendering/cooking_tool_pose.gd` | `8149008d244fd174eae5b8a6507f3b1951800ebd5540e240f0d15e9afe946781` |
| `game/scripts/rendering/illustrated_furniture.gd` | `ef165839273899ed7f9d06160f6343ff4925ae08e1c3950e0bb43f4dd48567ad` |
| `tests/presentation/test_gentle_cooking.gd` | `580aadd310963c2c397b9209b93ba7918741f69de403e62ef75c1c58ef3249ac` |
| `tests/presentation/test_lid_steam.gd` | `6519906c2bccb097a0595033157511ac9b0ddc5b933b1fda73c62809f0745cc7` |

Focused code-health review covers the cook-clock envelope, behind-vessel drawing,
transform restoration and retained-resource ownership. The existing cook clock
drives continuous vapor and the short rim release; stop/reduced-motion/completion
use the existing envelope. The furniture RefCounted artist owns two lazily built
immutable meshes (125 vertices/192 triangles each), released with that owner.
Per draw, only transforms and alpha vary: six continuous draws, at most twelve
during release. No per-phase mesh variants, new persistent cache, simulation,
service, custody or save-state changes. No measured FPS/headroom claim follows.
The original CRLF bytes in illustrated_furniture are preserved; a CR-aware
whitespace check passes without changing repository Git settings.

Fresh focused headless checks on this exact commit pass10217 gentle-cooking and
449 lid-steam assertions, with zero engine warnings/errors and no save files.
The gentle fixture checks actual generated cooking, timer-preserving pause,
completion, ownership and reduced motion. The existing focused scripts are run
from disposable staged projects; they are not newly registered in the canonical
integration runner. No unrelated suite or visual matrix was repeated.

One fresh actual native original-three `_build` qualification passes on official
Godot4.6.3 `7d41c59c4` (executable SHA256
`f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3`),
X11 GL Compatibility, Mesa25.0.7-2+deb13u1 / llvmpipeLLVM19.1.7. Fixed committed
PNGs/imports and manifest expected RGBA remain the reference. Procedural,
imported, READY-runtime, direct-source and saved-PNG paths all match exactly:
furniture `ba615c7535d6e3806d1b6b27abf2c50575e59486c8b9ab8c08d4eadff401b5ac`,
moving `6dc71a1bde51fc5c514356e5188736d24b6edc54acfa15185091b31cfce69bbc`,
heads `d16a8ea4064eb3aa5fa1daa90f61731e1288aa1e5089b0a8b3d9b381b106c1d7`.

The supplied generic driver's comparison and closure logic is unchanged; only
expected source commit/tree and isolated paths differ. New driver SHA256:
`791618607d2a61b3cb82eb78a5da363e15f776fc4c014ce2181c0025975080b6`.
Unchanged components come from `d40fe870b56c1614a9ba84ade8c9cf5d4ae177d0`;
the historical source-bound wrapper is archived, never executed or modified.
No historical Mesa pin is imposed. The native log retains one unsupported-VSync
warning; import/decoding checks pass. This untimed atlas test makes no gameplay
instance or player-data request and does not qualify full-scene composition.

After reviewing every receipt and the80-input closure, only the two changed
renderer hashes are adopted. The other78 rows, all six fixed PNG/import bytes,
asset records and previous provenance remain; new provenance is append-only.
Runtime shared locks are released after owned Godot processes exit.
Qualification native receipt SHA256:
`3fb78aa9b98b0c202e614837f611cdaf8df693ddc9a049827d5ed4d4e70d43b7`;
summary SHA256 `c2f5895ad0cd6c1d368c909fa43d8809d59ff0fda73f9ed92abff051c40c817c`.
Final composition/source binding and automatic CI remain separate. No new Web,
phone, performance, release, tag, merge or deployment acceptance is claimed.


### Food-contact fixture follow-up after failed CI

Initial PR345 head `093f8cb13ae8435bea87e95f41caf26e96acdeef` fails automatic
[run38942952428 / engine3 job117115506022](https://github.com/yiyousiow000814/little-leaf/actions/runs/38942952428/job/117115506022)
on `test_food_contact`:7474checks,80 lid-presence failures,800missing
`art_draw_mesh` and80missing `art_local_begin` script errors. CI tested merge
`725c94efa1ee43082f9abe384d54192241001e7b` into unchanged main6a8cd095.
Raw failed job log SHA256 `748ee67b4f8b9ff9e0a56454be4f95e9cbc9840ba9aa65537ea791c7268fc312`;
original failed artifact12064441158 / SHA256
`2bf2f4d0f9623873836831a47e1f39787dededc9dd956a56f2e442b1c7034840`
remains attached to that run. No unchanged CI rerun is requested.

Before editing, the identical original fixture passes7474checks on unchanged
main `6a8cd095ea0ab61086d91427b84f84fc36884684` and reproduces all80failures on
accepted head093f8cb through the canonical disposable runner. Production Artist
already implements the missing calls; the fixture's primitive-only substitute
is obsolete for the accepted steam and lid tilt. Test-only commit
`36a95f29b0eef49080e4933a5876e3d92f89296b` implements those existing interfaces,
records retained-mesh tint through the same forbidden-food palette check and
models local transform save/restore. Every original assertion remains;808new
checks require transform restoration after every sampled vessel draw.
The focused canonical runner passes8282checks, zero failures/diagnostics.
Fixed test log SHA256 `487320e62656d2ff83c7906be3580c820fbccba16b1163b7f12defcbeb3ddadf`.

No production runtime or effect changes. All four accepted raw postimages,
all80 producer hashes, protected PNG/import bytes and the existing actual atlas
qualification remain unchanged. No new visual or atlas regeneration is needed
for this fixture-only delta. The failed CI and local old-fail/new-pass evidence
remain separate from the next exact-head automatic CI result. Keep Draft and
all merge/release/deployment holds.

### PR345 accepted-main integration status

PR345 merged as468cc49032c2b751b267f7b8d385f19b15414869,
tree48997fa186d9ec0b2cf0b782f1683f74926ca8ae, at2026-10-16T18:20:51Z.
The historical failed CI and fixture repair above are preserved. Accepted steam
postimages, its original atlas qualification and the repaired food-contact
fixture remain unchanged in the item30 composition. Merged-main automatic CI
is unverified here because read-only GitHub PR/run requests returned Forbidden;
no unchanged CI rerun or inferred success is recorded. Merge does not imply
release, tag, deployment or any broader user visual acceptance.
