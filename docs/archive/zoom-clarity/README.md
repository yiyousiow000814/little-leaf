# Clear close-up rendering

The game's antialiased source strokes were transformed after Godot generated
its feather geometry. At approximately 4× effective drawing scale, this expanded
a 0.7-unit outline's fade to about 3.5 screen pixels. The same softness was baked
into the existing 4× caches; increasing those texture sizes alone would not
remove it.

The renderer now submits magnified antialiased strokes in raster coordinates,
retaining the authored centerlines, widths, fill shapes, palette and ordering.
The complete artist/canvas transform is restored after each stroke. Mirrored
uniform scale is supported; singular, nonuniform and sheared transforms use the
original path. Non-antialiased facial marks retain their original treatment.

At maximum inspection zoom, visible pieces whose screen scale exceeds the 4×
cache resolution use their existing vector geometry. Ordinary and offscreen
pieces remain cached. No texture is enlarged or rebuilt on zoom, no imported
art is changed, and no gameplay/save/camera behavior is modified.

## Validation

- Paired native Godot 4.6.3 Compatibility captures at desktop normal, desktop 4.6×,
  portrait 4.6×, desktop maximum and portrait maximum, with all four rotations
- 40 matched pairs retain identical positions, recipe elapsed time, camera scale
  and viewport size; fresh generated fixtures suppress save writes
- Retained atlas bytes remain 33,824,768. Draw counts at normal/4.6× are unchanged;
  maximum views increase from 659–664 to 791–809 in this fixture
- 115 transform/cache-selection checks, 182 hat geometry checks and 59,204
  food-contact checks pass. These counts describe assertions, not visual tests
- Native logs preserve existing driver VSync and exit-only ObjectDB warnings
- Web runtime validation is not claimed; its previously recorded protocol
  blocker is unaffected by this render-only change

Native screenshots and source/hash binding are delivered in the separate
review archive. The exact original e01 source and earlier review histories
remain preserved.

## Mechanism references

- https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/servers/rendering/renderer_canvas_cull.cpp
- https://docs.godotengine.org/en/stable/tutorials/2d/2d_antialiasing.html

2D MSAA is unavailable in this project's Compatibility renderer; this change
does not switch renderers or enable unsupported MSAA.
