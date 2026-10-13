shader_type canvas_item;

// Centerline geometry scales with the camera. Authored stroke and feather
// offsets remain screen-sized, matching the original world contour renderer.
uniform float geometry_scale = 1.0;

void vertex() {
    VERTEX = VERTEX * geometry_scale + UV;
    UV = vec2(0.0);
}
