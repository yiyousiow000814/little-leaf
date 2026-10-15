shader_type canvas_item;
render_mode unshaded;
// Preserve original gold artwork. Mask only the brown image background outside
// its rounded silhouette, in source UV space so nine-patch stretching is safe.
uniform vec2 surface_size=vec2(1.0);
void fragment(){
 vec4 paint=texture(TEXTURE,UV)*COLOR;
 vec2 point=UV*vec2(1536.0,1024.0);
 vec2 center=vec2(768.0,507.5);
 vec2 half_size=vec2(737.0,439.5);
 float radius=90.0;
 vec2 q=abs(point-center)-(half_size-vec2(radius));
 float distance_to_rim=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
 // StyleBoxFlat quiet centre uses the white 1x1 texture and is not source art.
 if(TEXTURE_PIXEL_SIZE.x < 0.01){
  paint.a*=1.0-smoothstep(-0.75,0.75,distance_to_rim);
 }
 COLOR=paint;
}
