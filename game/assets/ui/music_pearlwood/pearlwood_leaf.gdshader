shader_type canvas_item;
render_mode unshaded;

uniform vec4 source_region = vec4(0.0, 0.0, 1.0, 1.0);
// Local height units. A fixed, subdivided mesh supplies the curve; no geometry
// is rebuilt during animation. The lower 12% and the planted root never move.
uniform float tip_bend = 0.0;
varying vec4 layer_tint;

void vertex() {
	layer_tint = COLOR;
	float free_tip = pow(clamp((0.88 - UV.y) / 0.88, 0.0, 1.0), 2.2);
	VERTEX.x += tip_bend * free_tip;
}

void fragment() {
	vec4 paint = texture(TEXTURE, source_region.xy + UV * source_region.zw);
	if (paint.a <= 2.0 / 255.0) {
		discard;
	}
	COLOR = paint * layer_tint;
}
