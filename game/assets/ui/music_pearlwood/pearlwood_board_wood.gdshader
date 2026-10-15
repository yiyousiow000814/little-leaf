shader_type canvas_item;
render_mode unshaded;

#include "res://assets/ui/music_pearlwood/original_wood_treatment.gdshaderinc"

uniform float material_reveal : hint_range(0.0, 1.0) = 0.0;
uniform float rim_repair : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

vec3 honeywood(float value) {
	// A matte stained-wood ramp, driven by the ORIGINAL knots and grain.
	// Stronger local contrast preserves wood detail; no metallic reflection,
	// broad white shine, second bevel, screen texture, or replacement geometry.
	float y = clamp((value - 0.58) * 1.25 + 0.625, 0.0, 1.0);
	if (y < 0.30) {
		return mix(vec3(0.31, 0.24, 0.155), vec3(0.60, 0.43, 0.25), y / 0.30);
	}
	if (y < 0.70) {
		return mix(vec3(0.60, 0.43, 0.25), vec3(0.90, 0.78, 0.55), (y - 0.30) / 0.40);
	}
	return mix(vec3(0.90, 0.78, 0.55), vec3(0.985, 0.945, 0.82), (y - 0.70) / 0.30);
}

vec2 restored_rim_uv(vec2 uv) {
	// The original foliage obscures three tiny depressions in the painted rim.
	// Continue the neighboring ORIGINAL bevel through only those root patches.
	// This local source resampling is not a replacement outline/round rectangle:
	// the unoccluded rim, grain, nine-patch geometry, and source bytes stay fixed.
	vec2 p = uv * vec2(512.0, 158.0);
	float top_left = 5.3 * smoothstep(44.0, 56.0, p.x)
		* (1.0 - smoothstep(56.0, 67.0, p.x));
	float top_right = 7.0 * smoothstep(441.0, 451.0, p.x)
		* (1.0 - smoothstep(464.0, 480.0, p.x));
	float top_band = 1.0 - smoothstep(16.0, 30.0, p.y);
	float right_root = 1.5 * smoothstep(45.0, 51.0, p.y)
		* (1.0 - smoothstep(55.0, 63.0, p.y)) * smoothstep(478.0, 490.0, p.x);
	float left_root = 2.3 * smoothstep(130.0, 138.0, p.y)
		* (1.0 - smoothstep(140.0, 151.0, p.y))
		* (1.0 - smoothstep(29.0, 43.0, p.x));
	p += vec2(left_root - right_root, (top_left + top_right) * top_band) * rim_repair;
	return p / vec2(512.0, 158.0);
}

void fragment() {
	vec4 source = texture(TEXTURE, restored_rim_uv(UV));
	// The four source-derived leaf meshes remain behind this same fixed rim.
	// Outside former leaf-root patches, every original wood texel retains its alpha.
	float wood_alpha = source.a * (1.0 - original_foliage(source.rgb));
	vec3 ordinary = original_wood_treatment(source.rgb);
	float y = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 premium = honeywood(y);
	// A restrained gilded tint only on the already-painted bright bevel.
	float bevel = smoothstep(0.76, 0.91, y);
	premium = mix(premium, vec3(0.95, 0.85, 0.63), bevel * 0.10);
	COLOR = vec4(mix(ordinary, premium, material_reveal), wood_alpha) * item_tint;
}
