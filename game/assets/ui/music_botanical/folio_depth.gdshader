shader_type canvas_item;
render_mode unshaded;
// Static retained paper/metal relief. No noise, clock or animated shimmer.
uniform vec2 surface_size = vec2(1.0);
uniform bool beveled_frame = false;
varying vec2 face_point;
void vertex() { face_point = VERTEX; }
void fragment() {
 vec2 p = clamp(face_point / max(surface_size,vec2(1.0)),vec2(0.0),vec2(1.0));
 float edge = min(min(p.x,1.0-p.x),min(p.y,1.0-p.y));
 float roll = smoothstep(0.0,0.055,edge);
 float center_light = 0.018 * (1.0-length((p-vec2(0.36,0.32))*vec2(0.7,0.5)));
 float lower_warmth = smoothstep(0.5,1.0,p.y);
 vec3 relief = vec3(0.962,0.950,0.927) + vec3(0.036,0.044,0.058)*roll;
 relief += center_light;
 relief -= vec3(0.0,0.009,0.024)*lower_warmth;
 if (beveled_frame) {
  // Only the existing folio/tray bands receive directional relief. The paper
  // centre and original outer raster frame retain their previous material.
  vec2 pixels = p*surface_size;
  float top_left = min(pixels.x,pixels.y);
  float bottom_right = min(surface_size.x-pixels.x,surface_size.y-pixels.y);
  float rim_distance = min(top_left,bottom_right);
  float band = 1.0-smoothstep(12.0,18.0,rim_distance);
  float direction = smoothstep(-3.0,3.0,bottom_right-top_left);
  float roll_light = 0.5+0.5*cos((rim_distance-2.0)*1.05);
  vec3 rim_light = mix(vec3(0.83,0.79,0.70),vec3(1.08,1.055,1.0),direction);
  rim_light += vec3(0.11,0.09,0.045)*roll_light;
  relief = mix(relief,rim_light,band);
 }
 COLOR = vec4(COLOR.rgb * relief,COLOR.a);
}
