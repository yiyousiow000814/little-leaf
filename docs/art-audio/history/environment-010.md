# Latest environment slice

This is the latest nonparking environment from frozen integration reference 08af6a1 (tree f5e0be2), stacked on the camera/props slice. It is not a merge of the historical PR64 head.

Included: fixed-grid curved sidewalk, continuous kerb cap and road-facing sides, latest bus and shelter construction, bounded bus-stop pedestrians, fixed-endpoint ambient road traffic, sparse varied greenery, grass forms, and conservative environment rendering/culling. The accepted camera bounds are reused through the camera-only helper; no full-map-edge camera proposal is restored.

Parking is intentionally deferred. There is no parking purchase hook, lot pavement, bay markings, driveway, pedestrian link rendering, parking vehicle rendering, or parking model change in this slice. Geometry constants remain only where needed to preserve the original accepted camera range. The later parking feature must carry ownership-gated rendering and cache invalidation from 7beb353. Restoring the unconditional parking landscape from historical source is not acceptable.

## Verification and evidence

The source's original screenshots and motion records are preserved byte-for-byte in environment-010/. They are historical evidence of the source integration, not screenshots of this extracted candidate. Their original report is preserved as environment-010-source-history.md and includes parking and earlier camera claims outside this slice; it must not be treated as this candidate's completion report.

Focused engine regressions cover environment geometry, bus-stop motion, camera access, camera-oracle equality, visible-command culling parity, and no early parking geometry. New actual rendered capture is unverified: the available CUA window-list action was denied, and this extraction does not retry or bypass it. Headless geometry results are not visual approval.

Generic actor/tree culling, retained background caching, render-idle invalidation, and shell caching are owned by the performance slice. cafe_render_visibility.gd is an identical shared pure helper; environment drawing uses its own conservative fallback before the renderer gains the generic method. The after-environment performance patch must preserve the environment draw order and include bus/road motion in idle invalidation.

## Edge-culling correction

The latest source inherited a redundant fixed-size ambient-car prefilter that could reject bodywork still inside the viewport. The successor removes only that prefilter and retains draw_car's existing conservative projected-footprint test. A direct traffic-entry-point versus car-renderer command regression covers portrait/landscape/desktop, ordinary/detail projection, multiple zooms, the proven (-64,200) anchor, both travel directions, and fully offscreen cars. The test failed before the fix; this is command-level geometry evidence, not a new visual capture.
