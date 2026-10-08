# Retained static background commands

The world artist retains the static draw prefix (background rectangle, grass,
road and opposite pavement, near pavement, crossing) in one native CanvasItem
behind the original artist. Props, people, vehicles, indoor ground, furniture,
walls and trees retain their existing order in the original artist. This does
not bake an image, reduce resolution, change geometry or remove antialiasing.

The child CanvasItem inherits parent transforms, visibility, modulation and
relative depth. Nonstandard material, self-modulation, clipping, light mask,
visibility layer, sorting, outer transforms and legacy drawing modes use the
original renderer. Compatibility changes wake settled idle drawing. Repurposing
the artist as an icon or losing its game hides the prefix; leaving the tree and
final destruction release the RID. Returning to the tree recreates it.

Projection, viewport, opacity, detail, culling and mesh identity changes rebuild
the commands. Mesh resources remain referenced in the signature. Animation and
unchanged terrain revision updates do not rebuild them. `use_background_cache`
is available for comparison and defaults to true. Frame-rate policy is unchanged. Idle snapshots are enabled only for the current
main controller and subclasses with initialized snapshot dependencies; historical
or custom controllers conservatively keep redrawing rather than snapshotting
missing state.

## Verification

Godot 4.6.3, isolated synthetic profiles, dummy headless renderer:

```sh
python3 tests/run_integration_candidate.py --output /tmp/leaf-background-cache-final \
  --only test_background_cache test_render_idle test_render_visibility \
  test_art_raster_strokes test_environment test_bus_stop \
  test_environment_camera_access test_performance_shell_cache
```

Passed eight suites, 547,914 checks, with no engine/script diagnostics. The new
cache suite contributes 971 checks, including 180 exact ordered command
comparisons across three viewport sizes, five scales, three camera origins,
detail on/off and two opacities. It instruments current source submission calls
because Godot statically binds native drawing methods; it does not maintain a
second copy of the drawing geometry. Coverage includes invalidation counts,
legacy/custom fallback, settled-idle changes, early returns, destruction and
remove/re-add lifecycle.

An exploratory diagnostic run of the same native adapter measured 100 forced prefix rebuilds
at 231,040 microseconds total versus 382 microseconds for 100 unchanged retained
checks. Other engine checks overlapped, so these timings are not controlled
performance evidence. This isolates script/native command submission with the dummy renderer;
it is not a whole-frame benchmark, rendered screenshot comparison, GPU/thermal
measurement, or assurance of a particular device frame rate. Native GUI and Web
visual/performance verification remain separate checks.
