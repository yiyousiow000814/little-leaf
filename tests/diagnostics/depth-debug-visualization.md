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
continuous-frame regressions or approve PR189, artwork or a Golden reference.

After exact packet review and a serialized runtime grant:

```powershell
python tests/diagnostics/prepare_depth_debug.py --output <new-owned-directory>
python tests/diagnostics/run_depth_occlusion.py --prepared <same-directory> --engine <actual-official-Godot-4.6.3.exe> --shared-lock <task5/.little-leaf-engine.lock>
```

One run captures exactly three static overlay-off/on pairs: actor in front of
the existing oak, actor behind it, and chair item/back parts. Two initial frames
prepare the fixture; six are recorded. Reuse the existing combined 90-second
import/native deadline, owned-child kill/wait cleanup, shared/own byte-zero
locks, Dummy audio and redirected saveguard profiles. Busy means stop. No
browser/server/Auth, original saves, player profile, broad matrix or FPS claim.
Nonempty/required-state/script-error/drop/frame-ID guards remain fail-closed.
Normal players receive no debug UI or instrumentation.
