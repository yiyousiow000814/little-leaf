shader_type canvas_item;
render_mode unshaded;

uniform vec4 source_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float label_angle = 0.0;
// Actual spindle in the supplied 1254x1254 source, normalized to its crop.
uniform vec2 spindle_uv = vec2(0.499115, 0.499115);
varying vec4 layer_tint;

void vertex() {
	layer_tint = COLOR;
}

void fragment() {
	vec2 centered = UV - spindle_uv;
	float cosine = cos(label_angle);
	float sine = sin(label_angle);
	vec2 turned = vec2(cosine * centered.x + sine * centered.y,
		-sine * centered.x + cosine * centered.y) + spindle_uv;
	vec4 stationary_paint = texture(TEXTURE, source_region.xy + UV * source_region.zw);
	vec4 label_paint = texture(TEXTURE, source_region.xy + turned * source_region.zw);
	// Rotate the circular label before the scene's fixed projection. The outer
	// grooves, edge, ellipse and painted lighting remain entirely stationary.
	float label_mask = 1.0 - smoothstep(0.166, 0.178, length(centered));
	vec4 paint = mix(stationary_paint, label_paint, label_mask);
	if (paint.a <= 2.0 / 255.0) {
		discard;
	}
	COLOR = paint * layer_tint;
}
