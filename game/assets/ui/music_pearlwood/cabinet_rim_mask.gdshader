shader_type canvas_item;
render_mode unshaded;
// Complementary masks follow the existing painted front rim. Original source
// pixels are drawn by exactly one layer; the front lip can occlude petal roots.
uniform vec4 source_region = vec4(0.0,0.0,1.0,1.0);
uniform float front_layer = 0.0;
varying vec4 layer_tint;
void vertex() { layer_tint = COLOR; }
void fragment() {
 vec2 source_uv = source_region.xy + UV*source_region.zw;
 vec2 source_point = source_uv / TEXTURE_PIXEL_SIZE;
 float side = (source_point.x-724.5)/638.5;
 float front_rim = 600.0-132.0*side*side;
 bool is_front = source_point.y >= front_rim;
 if ((front_layer > 0.5) != is_front) { discard; }
 vec4 paint = texture(TEXTURE,source_uv);
 if (paint.a <= 2.0/255.0) { discard; }
 COLOR = paint*layer_tint;
}
