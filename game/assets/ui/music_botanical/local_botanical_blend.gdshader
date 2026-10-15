shader_type canvas_item;
render_mode unshaded;
// Local source regions meet the native folio through a short real alpha taper.
// This affects the rendered ornament, never hit areas or geometry assertions.
uniform vec2 surface_size = vec2(1.0);
uniform vec4 edge_fade = vec4(10.0);
varying vec2 local_point;
varying vec4 vertex_modulate;
void vertex() { local_point = VERTEX; vertex_modulate = COLOR; }
void fragment() {
 vec4 ink = texture(TEXTURE,UV) * vertex_modulate;
 vec4 distance_to_edge = vec4(local_point,surface_size-local_point);
 vec4 cover = smoothstep(vec4(0.0),max(edge_fade,vec4(0.01)),distance_to_edge);
 COLOR = vec4(ink.rgb,ink.a*cover.x*cover.y*cover.z*cover.w);
}
