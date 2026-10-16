shader_type canvas_item;
render_mode unshaded;
// Local source regions meet the native folio through a short real alpha taper.
// This affects the rendered ornament, never hit areas or geometry assertions.
uniform vec2 surface_size = vec2(1.0);
uniform vec4 edge_fade = vec4(10.0);
uniform vec4 quiet_rects[8];
uniform int quiet_count = 0;
varying vec2 local_point;
varying vec4 vertex_modulate;
void vertex() { local_point = VERTEX; vertex_modulate = COLOR; }
void fragment() {
 vec4 ink = texture(TEXTURE,UV) * vertex_modulate;
 vec4 distance_to_edge = vec4(local_point,surface_size-local_point);
 vec4 cover = smoothstep(vec4(0.0),max(edge_fade,vec4(0.01)),distance_to_edge);
 float coverage = cover.x*cover.y*cover.z*cover.w;
 for (int i=0; i<8; i++) {
  if (i>=quiet_count) { break; }
  vec2 outside=max(max(quiet_rects[i].xy-local_point,local_point-quiet_rects[i].zw),vec2(0.0));
  coverage*=smoothstep(0.0,7.0,length(outside));
 }
 COLOR = vec4(ink.rgb,ink.a*coverage);
}
