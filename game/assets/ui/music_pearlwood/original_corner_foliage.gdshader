shader_type canvas_item;
render_mode unshaded;

#include "res://assets/ui/music_pearlwood/original_wood_treatment.gdshaderinc"

uniform vec2 board_size = vec2(512.0, 158.0);
uniform vec2 source_origin = vec2(0.0);
uniform vec2 source_root = vec2(43.0, 33.0);
uniform float retraction : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_tint;

float nine_patch_axis(float point, float source_length, float destination_length) {
	if (point <= 64.0) { return point; }
	if (point >= source_length - 64.0) { return destination_length - source_length + point; }
	return 64.0 + (point - 64.0) * (destination_length - 128.0) / (source_length - 128.0);
}

vec2 board_point(vec2 point) {
	return vec2(nine_patch_axis(point.x, 512.0, board_size.x),
		nine_patch_axis(point.y, 158.0, board_size.y));
}

void vertex() {
	item_tint = COLOR;
	vec2 root = board_point(source_root) - board_point(source_origin);
	vec2 point = board_point(source_origin + VERTEX) - board_point(source_origin);
	vec2 arm = point - root;
	vec2 outward = normalize(source_root - vec2(256.0, 79.0));
	// Corner roots stay planted beneath the original wooden rim. The exposed
	// tips lead the curl, then the folded lamina withdraws under the opaque rim.
	// This is retained vertex deformation, never an opacity fade or board scale.
	float free_tip = clamp(length(arm) / 45.0, 0.0, 1.0);
	float turn = sin(retraction * 3.14159265) * free_tip * 0.72;
	vec2 curled = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * arm;
	float length_left = mix(1.0, 0.025, retraction);
	float tip_roll = 1.0 - 0.30 * sin(retraction * 3.14159265) * free_tip;
	VERTEX = root + curled * length_left * tip_roll
		- outward * sin(retraction * 3.14159265) * free_tip * free_tip * 5.0;
}

void fragment() {
	vec2 source_uv = (source_origin + UV * vec2(72.0, 64.0)) / vec2(512.0, 158.0);
	vec4 source = texture(TEXTURE, source_uv);
	float leaf_alpha = source.a * original_foliage(source.rgb);
	COLOR = vec4(original_wood_treatment(source.rgb), leaf_alpha) * item_tint;
}
