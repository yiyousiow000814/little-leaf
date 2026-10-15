# Developer-only depth visualization

This opt-in diagnostic fills the display gap in the existing depth probe. The
probe already exports world/projected anchors, computed depth, object/part IDs,
submission cursor, actual completed-frame native indices, visibility/generation
and authored tree contours. The overlay displays those existing observations;
it does not calculate sorting depth, change pass enrollment or fix occlusion.

No game/platform files load it. The preparation command stages a disposable
project with the existing probe hooks. A separate CanvasLayer displays cyan
ground anchors, IDs/parts and a read-only observed-order panel. Orange outlines
trace the existing authored trunk/crown with the actual `_tree` scale/placement;
they are visual occlusion contours, not collision shapes or model footprints.
Other object occlusion areas are not fabricated. A chair exposes its existing
item/back part identities but no invented furniture silhouette.

The display identifies the exact preceding completed frame used for its
annotations. It freezes copies of those observations and never modifies the
artist, its caches, model, movement or saved state. Overlay-off and overlay-on
files are separate evidence. An overlay can hide pixels; only the off frames
can support an occlusion judgment. This static display check does not replace
continuous-frame regressions or approve artwork or a Golden reference. PR189's
representative oak repair was separately accepted and merged as `6db1c726`.
This overlay observes that current ordering without changing it.

The five shared probe/preparation/capture/launcher/pilot-guide files originated
in PR189's diagnostic packet but were excluded from its production-only merge.
PR197 retains those helpers once, with current nested fixture/rendering/world
paths, and adds only the opt-in display/static capture preparation. Normal
`stage_project(tests=False)` excludes all diagnostics.

Historical PR197 evidence remains unchanged: r2 stopped on its Windows receipt
newline mismatch, r3 had incomplete screenshots, and corrected r4 inspected six
original frames (three off/on pairs). The qualified r4 capture SHA256 is
`01e350a8a1da86ba339257e84c26ca0a8c646dab82958a0311e8bca425bad6a2`.
Those frames establish the historical static developer display only. They do
not qualify current-main pixels, startup, continuous occlusion or FPS. This
source integration does not repeat or relabel those runtime results.

After exact packet review and a serialized runtime grant:

```powershell
python tests/diagnostics/prepare_depth_debug.py --output <new-owned-directory>
python tests/diagnostics/run_depth_occlusion.py --prepared <same-directory> --engine <actual-official-Godot-4.6.3.exe> --shared-lock <task5/.little-leaf-engine.lock>
```

One run captures exactly three static overlay-off/on pairs: actor in front of
the existing oak, actor behind it, and chair item/back parts. The diagnostic uses
the existing `--skip-intro` option so startup's opaque preparation cover is not
part of this static display check; it does not qualify first-use startup. Two
initial frames prepare the fixture; six are recorded. Reuse the combined 90-second
import/native deadline, owned-child kill/wait cleanup, shared/own byte-zero
locks, Dummy audio and redirected saveguard profiles. Busy means stop. No
browser/server/Auth, original saves, player profile, broad matrix or FPS claim.
Nonempty/required-state/script-error/drop/frame-ID guards remain fail-closed.
Normal players receive no debug UI or instrumentation.
