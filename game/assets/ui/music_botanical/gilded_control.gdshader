shader_type canvas_item;
render_mode unshaded;
// Retained ivory/sage inset and rounded gold rim. All ink stays in the hit box.
// Directional, static light; there is no animation, noise or texture allocation.
uniform vec2 surface_size = vec2(1.0);
uniform vec2 paint_inset = vec2(0.0);
uniform bool green_face = false;
uniform bool selected = false;
uniform bool hovered = false;
uniform bool disabled = false;
varying vec2 face_point;

float rounded_distance(vec2 p, vec2 half_size, float radius) {
 vec2 q = abs(p) - half_size + vec2(radius);
 return length(max(q,vec2(0.0))) + min(max(q.x,q.y),0.0) - radius;
}

void vertex() { face_point = VERTEX; }
void fragment() {
 vec2 face_size = max(surface_size - 2.0*paint_inset,vec2(1.0));
 vec2 p = face_point - surface_size*0.5;
 float radius = min(face_size.x,face_size.y)*0.5;
 float distance = rounded_distance(p,face_size*0.5-vec2(1.0),max(radius-1.0,0.0));
 float bevel_scale = clamp(face_size.y/60.0,0.55,1.0);
 float depth = -distance/bevel_scale;
 float y = clamp((p.y+face_size.y*0.5)/face_size.y,0.0,1.0);
 float x = clamp((p.x+face_size.x*0.5)/face_size.x,0.0,1.0);
 float light = clamp(0.64-0.48*y-0.13*x,0.0,1.0);
 vec3 edge = mix(vec3(0.43,0.28,0.11),vec3(0.87,0.65,0.29),light+0.18);
 vec3 gold = mix(vec3(0.63,0.40,0.15),vec3(1.0,0.88,0.57),1.0-y*0.80);
 vec3 rim = mix(edge,gold,smoothstep(0.6,1.9,depth));
 rim = mix(rim,vec3(1.0,0.96,0.80),smoothstep(1.8,2.7,depth)*(1.0-smoothstep(3.0,3.8,depth)));
 rim = mix(rim,mix(vec3(0.66,0.48,0.25),vec3(0.86,0.70,0.41),1.0-y),smoothstep(3.8,4.8,depth));
 vec3 ivory = mix(vec3(1.0,0.976,0.905),vec3(0.947,0.885,0.744),pow(y,1.7));
 vec3 amber = mix(vec3(1.0,0.888,0.572),vec3(0.925,0.673,0.302),pow(y,1.25));
 vec3 sage = mix(vec3(0.335,0.439,0.300),vec3(0.177,0.285,0.202),y);
 vec3 face = green_face ? sage : (selected ? amber : ivory);
 float bloom = exp(-dot((vec2(x,y)-vec2(0.34,0.20))*vec2(2.0,2.6),(vec2(x,y)-vec2(0.34,0.20))*vec2(2.0,2.6)));
 face += vec3(0.024,0.021,0.010)*bloom;
 if (hovered) { face = mix(face,vec3(1.0,0.97,0.85),green_face ? 0.08 : 0.12); }
 vec3 color = mix(rim,face,smoothstep(5.2,6.0,depth));
 // A narrow upper inner reflection and lower contact shadow give a raised face.
 float inner_lip = smoothstep(5.5,6.1,depth)*(1.0-smoothstep(6.2,7.1,depth));
 color += vec3(0.10,0.08,0.035)*inner_lip*(1.0-y);
 color -= vec3(0.045,0.035,0.018)*inner_lip*y;
 if (disabled) { color = mix(color,vec3(dot(color,vec3(0.3,0.59,0.11))),0.65); }
 COLOR = vec4(color,1.0-smoothstep(-0.5,0.6,distance));
}
