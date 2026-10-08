# Retained shell draw preparation

The indoor floor was already reduced to two retained mesh submissions. This
second pass therefore targets the remaining procedural shell preparation.
`cafe_shell_draw_cache.gd` records the exact shell helper calls in two bounded
per-artist slots and replays them in their original position, before the corner
cap and sorted entities. It does not retain a bitmap or native CanvasItem.
Native drawing submission count, textures, UVs, colors and ordered geometry are
unchanged. `poly` and `line` still apply current opacity and raster/AA transforms.

Invalidation compares deep snapshots of host geometry and segment runs,
attachments, built walls, origin, tile projection, UI scale, zoom, wall detail
and the two palette inputs. Simulation time and unrelated model revision do
not invalidate. Preview changes, removal/cancellation, nested in-place edits
and reset do invalidate. Unknown shell hosts use the direct renderer; storage
never grows beyond the back and west shell entries.

## Evidence

Godot 4.6.3 headless isolated generated profiles. `test_shell_draw_cache` passes
705 checks. It compares the unchanged `illustrated_openings.draw_shell` command
stream against first and warmed cached draws across five scales, two detail
levels, four materials, two heights and both shell hosts, plus mixed segment
runs and invalidation cases. Texture resource identity and UV order are part
of the equality comparison. The two integration call positions are checked.

Five isolated recorder runs of 1,000 draws of a mixed-material, mixed-height
west shell with its starter doorway produced:

- Original preparation: 154840, 162975, 159837, 152902, 158760 microseconds
- Warm cache/replay: 15254, 15940, 15556, 15206, 15642 microseconds
- Coordinate projections: 70,000 original versus zero cached
- Helper commands: unchanged, 18 per draw

These are script preparation timings with a recording view. They are not full
frame times, a GUI/GPU measurement, a browser measurement or a phone/thermal
claim. Existing artwork, resolution and animation fidelity are unchanged.

Run the focused regression set with:

```
python3 tests/run_integration_candidate.py --output ../performance-evidence/interior-pass2 \
  --only test_shell_draw_cache test_background_cache test_render_idle \
  test_shell_segment_model test_shell_segment_ui test_opening_jamb_occlusion \
  test_art_raster_strokes test_environment test_bus_stop
```

## Empty-attachment dependency specialization

When attachments are empty, `solid_panels` calls `cuts`, whose only built-wall
read is inside the attachment loop. The cache therefore omits the unrelated
built-wall snapshot in this case. The complete supplied host remains a key
input, including endpoints and segment runs, so wall-induced shell shortening
still invalidates. Any attachment restores the full built-wall dependency.
This is an exact dependency reduction, without a wall-count threshold.

The extended suite passes 732 checks, adding dense synthetic wall mutations,
empty-to-present attachment transitions and host endpoint changes. Four focused
suites pass 8,321 checks with no diagnostics. A synthetic 200-record stress
fixture (not a gameplay-valid layout claim) with a mixed-run west shell and no
attachments measured 101756–132852 microseconds per 1,000 original draws versus
12723–15140 cached. The purpose is to verify wall-count-independent warm key
work; these timings remain recorder-only preparation measurements.
