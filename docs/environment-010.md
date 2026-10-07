# v0.1.10 environment groundwork

The approved concept places a compact four-bay lot just behind the cafe, with an open low-planted buffer,
directly joining the existing entrance-side road. This implementation keeps the
game's original 2D vector illustration, muted sage/cream colours and tree artwork.
It widens the single road, adds its opposite sidewalk, bus shelter and short bus
lay-by, and adds six irregularly spaced scenery trees and small low planting
pockets. There is no second road or extended parking driveway.

## Ownership and integration

The rear lot is render-only: world `Rect2(-0.26,-8.7,12.26,4.9)`. Its entire depth
is negative, outside all current cafe floor/expansion cells. The mouth is
`Rect2(-3.26,-5.7,3.0,1.8)`: one short flush crossing over the existing sidewalk,
with a pedestrian strip marked through it. Aisle and bays lie within the lot. The lot ends at z=-3.8. At the normal isometric ratio, a full-height rear wall
rises 128 pixels while each negative-z tile separates ground from that wall
silhouette by 39 pixels. The front lot edge therefore clears the projected wall
by 20.2 pixels before camera scaling, so the entire lot and cars can be seen.
The intervening strip remains lawn with three restrained low planting pockets.
A 1.2-tile-wide pedestrian link occupies x=-0.26..0.94, z=-3.8..-0.26;
no tall trees, planting obstacle or extra vehicle access road occupies it.
Three parked vehicles are static scenery; the first bay remains visibly empty.
They do not represent admitted customers or purchased parking.

`exterior_environment.gd::parking_hooks()` exposes the lot, mouth, bay anchors and
pedestrian exit. Both purchase and customer-parking flags are false, price is
null, and parcel policy is pending. No catalog product, price, land purchase,
save schema or customer allocation is added. The queue/customer worker must
connect a later approved parking lifecycle to authoritative admissions; ambient
cars must never be repurposed as guests without that integration.

The suggested next decision is a dedicated exterior parking parcel covering this
negative-depth lot. It preserves existing owned tiles and every expansion option.
Approve its land price and fit-out price separately; neither is selected here.
An alternative is an exterior permit that retains municipal parcel ownership,
with only the parking fit-out purchased in Decorate. This also preserves cafe
land, but requires a decision on whether the permit expires or remains permanent.
Reusing any current cafe expansion parcel would require relocating the approved
lot, so it does not match this layout.

## Runtime boundary

`ambient_road_traffic.gd` owns eight fixed presentation-only cars in two lanes.
They recycle only at the unchanged remote road endpoints. The clock freezes
when the road is offscreen and follows the existing edit/pause/intro/recovery/
small-viewport activity gate. Drawing culls individual offscreen vehicles. The
bus stands in a short lay-by outside those lanes. There are no physical bodies,
timers, service records, reservations, wallet entries or saved traffic state.

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
