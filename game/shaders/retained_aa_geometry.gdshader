shader_type canvas_item;

// Preserve Godot's positive-width AA rule while retaining geometry across
// uniform camera scales: only the feather remains fixed in raster pixels.
uniform float stroke_width = 0.7;

void vertex() {
    float raster_scale = max(length((CANVAS_MATRIX * MODEL_MATRIX)[0].xy), 1.0);
    VERTEX += UV * min(stroke_width * raster_scale, 1.0) / raster_scale;
    UV = vec2(0.0);
}
