extends RefCounted
## Finite exterior drawing extents. These bounds grant no buildable land.
## Cover the finite map plus supported camera inspection margins.
const CAMERA_WORLD_BOUNDS=Rect2(-24,-24,64,64)
const PAVEMENT_Z_MIN=-82
const PAVEMENT_Z_MAX=82
const STREET_Z_MIN=-84
const STREET_Z_MAX=84
const MARK_Z_MIN=-82 # Same modulo-3 phase as the original -28 start.
const MARK_Z_MAX=82
const GRASS_MIN=-32
const GRASS_MAX=52

# Rendering coverage only: simulation routes/spawns retain the constants above.
const RENDER_PAVEMENT_Z_MIN=-318
const RENDER_PAVEMENT_Z_MAX=318
const RENDER_STREET_Z_MIN=-320
const RENDER_STREET_Z_MAX=320
const RENDER_MARK_Z_MIN=-319 # Preserve the original modulo-3 marking phase.
const RENDER_MARK_Z_MAX=319
