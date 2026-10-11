# Manual World Depth & Occlusion pilot

This is a dev-only diagnostic, not ordinary CI, a release fixture or an accepted
depth contract. No tracked game/platform source is changed. The preparation
helper creates a new disposable project, adds explicit painter-order observation
hooks to its copied IllustratedCafe and freezes their diff/hash before any run.

It reuses the existing `role_fixture.gd` no-save startup, the authored exterior
oak/visibility rules observed by `test_expansion_tree_visibility.gd`, and actual
Decorate input handlers used by the current draw-boundary tests. The two cases
are actor front-to-back-to-front/diagonal tree edge and table/chair rotations
0..3 with drag, preview, confirm and cancel. Synthetic placement resets between
independent trials do not pretend to be player operations. Save calls are
suppressed by the existing fixture. No real customer generation/route is changed.

The native capture observes completed render frames, cropped overlay-off pixels,
world/projected anchors, computed depth, actual submission cursor and final
native sibling index/visibility. Original authored tree contours are exported
as diagnostic occlusion areas. PNG reads/writes affect frame duration; this is
not an FPS measurement or stable-60 claim. The frame buffer is bounded to720,
per-draw observations to128, and output is frozen before JSON export. A dropped
observation or missing visible actor/tree means incomplete evidence, not parity.

Only after owner/queue review of the prepared packet and runtime reservation:

```powershell
python tests/diagnostics/prepare_depth_occlusion.py --output <new-owned-directory>
python tests/diagnostics/run_depth_occlusion.py --prepared <same-directory> --engine <official-Godot-4.6.3.exe> --shared-lock <task5/.little-leaf-engine.lock>
```

The launcher uses a combined import+pilot90-second deadline, Dummy audio,
CREATE_NO_WINDOW and redirected APPDATA/LOCALAPPDATA/HOME/XDG disposable
directories whose path contains `saveguard`. It holds shared byte0 and its own
diagnostic byte0 through process exit, then writes a terminal lock/exit receipt.
It creates no browser/server, uses no Auth and preserves localhost8769. Keep
source identity, prepared diff/hash, failed runs and all frame evidence.
Pass the actual engine executable rather than a console wrapper that spawns it,
so owned-child abort/exit checks refer to the actual native engine process.
Zero frames, a missing pilot state, dropped observations or engine script errors
fail closed even if the process exits0.

Existing wall slicing, chair-back/torso/reach layers, atlas inputs and native
ordering are under observation. No YSort, depth offsets, geometry, collision,
economy, gameplay or renderer fix is introduced by this pilot. An eventual
`docs/development/depth-occlusion.md` contract requires verified actual evidence.
