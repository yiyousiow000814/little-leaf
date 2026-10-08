# v0.1.10 environment groundwork

The approved concept places a compact four-bay lot just behind the cafe, with an open low-planted buffer,
directly joining the existing entrance-side road. This implementation keeps the
game's original 2D vector illustration and muted sage/cream colours. Original oak
art sits alongside authored airy, columnar and sapling silhouettes.
It widens the single road, adds its opposite sidewalk, bus shelter and short bus
lay-by, and adds six irregularly spaced scenery trees and small low planting
pockets. There is no second road or extended parking driveway.

The ordinary bus shelter has a plain cream roof connected to four sage posts,
quiet back/end glazing, a wood seat/backrest with grounded legs, and a separate
bus pictogram sign beyond its open boarding side. Its clear boarding corridor is
1.0 tiles wide. Ground planting draws before elevated shelter parts, preventing
the previous bush-over-roof overpaint. No green roof is intended.

Six sparse tree positions retain the existing depth/owned-land rules. Four tree
silhouettes and three low planting forms (fan grass, shrub and fern) vary branch
structure, leaf direction, height and density. Lawn marks have deterministic fan,
upright and wind-swept forms. There is no added RNG or denser forest.

## Ownership and integration

The fixed exterior lot is a separately purchasable upgrade: world `Rect2(-0.26,-8.7,12.26,4.9)`. Its entire depth
is negative, outside all current cafe floor/expansion cells. The mouth is
`Rect2(-3.26,-5.7,3.0,1.8)`: one short flush crossing over the existing sidewalk,
with a pedestrian strip marked through it. Aisle and bays lie within the lot. The lot ends at z=-3.8. At the normal isometric ratio, a full-height rear wall
rises 128 pixels while each negative-z tile separates ground from that wall
silhouette by 39 pixels. The front lot edge therefore clears the projected wall
by 20.2 pixels before camera scaling, so the entire lot and cars can be seen.
The intervening strip remains lawn with three restrained low planting pockets.
A 1.2-tile-wide pedestrian link occupies x=-0.26..0.94, z=-3.8..-0.26;
no tall trees, planting obstacle or extra vehicle access road occupies it.
The initial unowned lot is empty. Its former three static parked props have been
removed; after purchase only authoritative customer trips occupy the four bays.

`exterior_environment.gd::parking_hooks()` exposes unchanged geometry with
purchase/customer-parking enabled and the configurable 2,000-coin price. The
selected product is a permanent fixed exterior upgrade, not a cafe expansion
parcel or movable furniture. It has no separate land fee or recurring charge.
See [parking behavior and save contract](parking.md) for same-session refunds,
resale guards, shared demand/queue bounds and persistence.

## Runtime boundary

`ambient_road_traffic.gd` owns eight fixed presentation-only cars in two lanes.
They recycle only at the unchanged remote road endpoints. The clock freezes
when the road is offscreen and follows the existing edit/pause/intro/recovery/
small-viewport activity gate. Drawing culls individual offscreen vehicles. The
bus stands in a short lay-by outside those lanes. There are no physical bodies,
timers, service records, reservations, wallet entries or saved ambient traffic state.
Real customer parking is separately owned by `cafe_parking.gd` and continues
offscreen under the simulation clock.

Trees join the existing depth-sorted entity list. The original owned-floor and
visible-Decorate-parcel suppression applies to their ground anchors; planting
draws beneath installed floor finishes. Neither scenery nor the lot blocks
movement or purchasing expansion. Existing guest street endpoints and pavement
lanes remain unchanged.

## Authoritative images and restoration

Both actual local image pixels were inspected before implementation. Existing
Library identities were verified through their local alternate data streams and
owner receipts, then the bytes were copied into this task without editing the
owner's files.

| Reference | Library identity | SHA-256 |
| --- | --- | --- |
| Approved sparse concept | `libfile_8cb692295ac081918aa0722976af9f34` | `10f345c0b2c71b3f814ac497f85b2c477c85977b3a1063eb7afe735dd0d9fc3f` |
| Annotated parking location | `libfile_872f8fd152808191a80390fe124c371f` | `5790f3dbd9e072bf9c1fa92e99f362ab15e7e3c9b769b533312c928cf255b141` |

The implementation is based on exact v0.1.9 commit
`11c1f8d904b0c4c9a2565cbd557d1552b4ba9401`. Restore into a fresh checkout at
that commit and apply the archived patch, or check out the draft PR's branch.
The Library archive retains editable GDScript, both original images, hash
receipts, tests, screenshots and restoration instructions. No generated concept
bitmap replaces the live scene, and no original player save was read or written.

## Validation

`test_environment.gd` checks disabled economy hooks, lot separation from cafe
land, direct road mouth, bounded one-hour traffic, pause/invalid-time/offscreen
freeze and frame-slicing cadence. Existing economy, expansion and street save suites
check their authoritative state boundaries. It is included in
the full disposable-profile integration runner.

`capture_environment.gd` creates a synthetic fresh scene with seed 8124 and
suppressed saving. Before/after use the same 1654x951 viewport, origin `(800,345)`,
tile `(33.54,16.77)`, zoom `1`, and scale `0.86`; both captures freeze simulation.
Run only from disposable project copies with a workspace-local custom user
directory and isolated APPDATA/LOCALAPPDATA. The stock game's saves are unrelated
to this fixture. See the accompanying validation receipt for final results.

Same-angle actual game renders: [before](environment-010/before.png),
[after](environment-010/after.png). See [validation receipt](environment-010/validation.json).

Bus review: [layout before](environment-010/layout-before-bus-revision.png),
[enlarged bus before](environment-010/bus-before.png),
[enlarged bus after](environment-010/bus-after.png). Both detail images are native
720x460 Godot renders at the same projection, not image edits. The single review
session captures the layout and both bus details in 16 frames. For a before
comparison, supply BUS_BEFORE_SCRIPT with the previous 38618c1 environment source
in a disposable fixture; this legacy fixture is not runtime game code.

Latest parking/green-buffer review: [layout before](environment-010/layout-before-green-buffer.png),
[layout after](environment-010/after.png). Both are actual normal-angle game renders
with identical fixed capture settings. The latest isolated 16-frame capture shows
all bays and parked cars clear of the rear wall, with low planting in the open lawn.

Shelter/vegetation review: [whole scene before](environment-010/layout-before-shelter.png),
[whole scene after](environment-010/after.png), [shelter before](environment-010/shelter-before.png),
[shelter after](environment-010/shelter-after.png), [vegetation gallery](environment-010/greenery-after.png).
Close-ups are native 960x640 renders from the same isolated 16-frame session.
The user's additional screenshot `libfile_cdbcf7ab4df88191bc51ffc16ec8cc9d`
could not be transferred (HTTP 403); no caption substituted for its unseen pixels.
The independently rendered existing scene directly demonstrated the roof
overpaint and unsupported-seat defects. Pixel review supplements the behavior
tests; stylistic acceptance remains a user review decision.

## Continuous bus-stop sidewalk and bounded pedestrians

The opposite sidewalk continues into the shelter using the same alternating tile
colours and seam rows at ground height zero. Its lawnward extension overlaps the
existing sidewalk; no separate raised slab or seam crosses the bus bay. A continuous
curb at x=-10.55 has a flush opening at z=9.65..10.7, aligned with the actual
curb-side bus door (-10.345,10.1). The bus's visible road-facing side has windows.
The bench/glazing sit behind waiting positions; posts/sign leave a one-tile
through corridor and unobstructed paths between sidewalk, waiting area and door.

`bus_stop_pedestrians.gd` owns exactly three presentation visitors rendered by the
existing original illustrated character/motion system. They approach along
x=-11.35, wait at x=-12, board through the flush door opening, remain hidden
aboard, and alight back to the sidewalk. They recycle at unchanged remote street
endpoints, with at most three motion rigs. The clock follows the existing activity
gate and freezes offscreen. They do not enter cafe admissions, queues, wallets,
seats, reservations or saves. `test_bus_stop.gd` verifies an hour of route bounds,
0.35-tile obstacle clearance, all five states, invalid time/offscreen freeze,
frame slicing and unchanged authoritative model state.

Actual same-angle [revision before](environment-010/layout-before-stop.png) and
[after](environment-010/after.png), plus lossless native APNG [detail before](environment-010/stop-before-motion.png)
and [detail after](environment-010/stop-after-motion.png), show the connection and
waiting/walking. Download the APNGs for single-play animation if a web preview
shows only their first frame. The separate native Library review ZIP
`libfile_5f6e2f768a508191b06efe1eeb02e488` contains 64 raw frames, an HTML replay/scrub
viewer, four APNGs, exact position records and a hash manifest (16,627,470 bytes;
SHA-256 `f768792688ba4f3a8c6f44a41e560c60993f7d354307eb7cc9ad3165f98e74c0`).
There are sixteen real samples at 0.5-second intervals: eight seconds of normal
presentation, without interpolation. Cafe authority is frozen while only ambient
presentation clocks advance. The rejected art-direction sample is not used.

To reproduce, use `tests/capture_stop_motion.gd` in a disposable project/profile,
with STOP_BEFORE_ART and STOP_BEFORE_ENV pointing at archived previous-revision comparison
fixtures, and STOP_MOTION_OUTPUT pointing at an existing workspace folder. The
normal projection matches previous captures; the native close-up is 1240x760,
origin (2200,600), tile (78,39), scale 2. Coordinate a graphics slot first.
Full final engine regression: 78 processes, 1,186,448 checks passed. Focused stop,
environment, expansion and street checks: 534,028 passed. Tests establish behavior;
they do not establish user visual acceptance.

## Authoritative annotated connection refinement

The user supplied `libfile_5fc5f6982cbc8191a5fbde0aae7a2af8`,
image(20261007-085459).png (1354x957, 155,658 bytes). The supported Library
transfer succeeded, and its actual pixels were inspected against the native
07e9ab1 scene. SHA-256: `4ea6b331ae2e40c0e489596322bf2139c3cdbc0e1ff977411e5d5acfefa37c0b`
The exact identity and hash are also recorded in validation.json.
Its four black annotations describe curved transitions along both the lawn-side
pavement edge and the curb/bus-bay edge. Existing straight apron corners and short
bay wedges have been replaced by smooth easing curves at both ends. Shelter,
bus, waiting positions, parking layout and original illustrated palette stay fixed.

Both edges start from ordinary sidewalk at z=1.9, reach the unchanged shelter
plateau at z=4.9, leave it at z=11.3 and rejoin ordinary sidewalk at z=15.3.
The cubic transition has zero slope at all joins and shoulders. Width stays at
least three tiles; no paving enters the road's through lanes. Cached tile-row
polygons and longitudinal seams follow the same curves, at height zero. The flush
door gap and exactly three bounded original-character visitors remain intact.
Walking checks now use the actual curved pavement boundary.

Actual same-angle [normal before](environment-010/layout-before-curve.png) /
[after](environment-010/after.png), [close-up before](environment-010/curve-before.png) /
[after](environment-010/curve-after.png), and single-play native APNG
[before](environment-010/curve-before-motion.png) / [after](environment-010/curve-after-motion.png)
are preserved. Both sides include identical walking/waiting people. The native
Library motion ZIP `libfile_8d3b0ba6c9d48191bafa11209986d60e` retains all 64 raw
frames, four lossless APNGs, state records, a replay/scrub HTML viewer and SHA
manifest: 18,291,766 bytes; SHA-256
`a1fcd0e3f0fc3d84b253094fd6c8fbb9a1feb1cca4dea3eb174c7e0fc4614da2`.
It contains sixteen actual samples at 0.5-second intervals, eight seconds at
normal presentation speed, without interpolation. For reproduction, the current
capture script uses archived 07e9ab1 before fixtures; older source archive versions
retain their matching earlier capture scripts and comparison fixtures.

Full final engine regression: 78 processes, 1,187,812 checks passed. Focused
environment/stop/expansion/street suites: 535,392 checks passed. New checks cover
join tangents, minimum pavement width, through-road preservation and valid tile/bay
triangulation, alongside the full hour of bounded pedestrian routes. User visual
acceptance is separate from these checks. No cafe model/economy/save changes.


## Fixed original tile grid at curved edges

The cf89cda close-up showed elongated tiles because each longitudinal seam was
computed as the curved lawn edge plus a column offset. This moved a whole column
sideways with every row, bending its grid and shearing the projected tiles. The
actual before/after pixels were inspected; a generic geometry pass did not establish
that the distorted grid looked correct. The cf89cda source, CI, image and restoration
checkpoint remains preserved in native Library archive version4.

The correction retains the same continuous outer curves, but places every field
tile on the original fixed world grid: x origin -11.76, integer z rows, 1x1 cells.
Cached cell polygons are intersections of those square cells with the unchanged
curved row masks. Edge pieces are cut rather than enlarged. Longitudinal seams are
straight constant-x segments clipped at the edge; shared seams are cached once.
The ordinary approach sidewalk continues this same grid. Palette, ground height,
shelter, bus, waiting positions, bounded people and parking are unchanged. No switch
to concrete or removal of the approved outer transition was selected.

Actual same-scale [enlarged before](environment-010/grid-before.png) /
[after](environment-010/grid-after.png) show original regular isometric diamonds
inside, with partial cut pieces only at the perimeter. [Normal before](environment-010/layout-before-grid.png) /
[after](environment-010/after.png) retain the same camera. Lossless native single-play
APNG [before](environment-010/grid-before-motion.png) /
[after](environment-010/grid-after-motion.png) retain the same original characters.
The native Library bundle `libfile_3178101bd3348191ac144f699272a5e0` contains all64 raw
frames, four APNGs, HTML replay/scrub, position records and hash manifest:18,443,258
bytes; SHA256 `644dbd9b45091490cd09d26fc1246ed4e9844647c186823161da2ac77d795afd`.
There are16 real samples at0.5-second intervals, eight seconds without interpolation.
The before fixtures are exact cf89cda source with only fixed projection/reference
preload changes. The current capture script supports that before/after comparison.

Full final Godot regression:78 processes,1,188,387 checks passed. The five relevant
suites within that run pass535,967 checks. New checks verify fixed1x1 cell bounds,
clipping inside those cells, straight seams and unchanged original isometric tile
sizes at both normal and enlarged projections. Actual pixel inspection supplements
these checks; final user visual acceptance remains separate. No cafe economy, save,
customer admission or authoritative queue changes.
