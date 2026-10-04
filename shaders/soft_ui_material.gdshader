shader_type canvas_item;
render_mode unshaded;

// Original artwork only. Never attach to a Control that also draws live type.
// One sample; no screen texture, blur, UV change, texture copy, or alpha change.
uniform int surface_kind : hint_enum("Illustration", "Cream face", "Sage face") = 0;
uniform float treatment_strength : hint_range(0.0, 1.0) = 1.0;
uniform float wood_lift : hint_range(0.0, 0.12) = 0.045;
uniform float preserve_dark_details : hint_range(0.0, 1.0) = 0.0;

uniform vec4 birch_ink : source_color = vec4(0.310, 0.294, 0.243, 1.0);
uniform vec4 birch_shadow : source_color = vec4(0.600, 0.541, 0.431, 1.0);
uniform vec4 birch_body : source_color = vec4(0.878, 0.800, 0.655, 1.0);
uniform vec4 birch_light : source_color = vec4(0.957, 0.933, 0.847, 1.0);
uniform vec4 cream_ink : source_color = vec4(0.451, 0.412, 0.353, 1.0);
uniform vec4 cream_shadow : source_color = vec4(0.749, 0.690, 0.600, 1.0);
uniform vec4 cream_body : source_color = vec4(0.965, 0.927, 0.854, 1.0);
uniform vec4 cream_light : source_color = vec4(0.985, 0.963, 0.913, 1.0);

// Vertex COLOR contains CanvasItem modulation and per-draw tint, before texture
// multiplication. Apply this AFTER the remap so disabled/hover/open-state tints
// retain their relative effect and are not brightened away by the palette ramp.
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

vec3 birch_ramp(float value) {
	float y = clamp(value + wood_lift, 0.0, 1.0);
	if (y < 0.30) {
		return mix(birch_ink.rgb, birch_shadow.rgb, y / 0.30);
	}
	if (y < 0.68) {
		return mix(birch_shadow.rgb, birch_body.rgb, (y - 0.30) / 0.38);
	}
	return mix(birch_body.rgb, birch_light.rgb, (y - 0.68) / 0.32);
}

vec3 cream_ramp(float value) {
	float y = clamp(value, 0.0, 1.0);
	if (y < 0.55) {
		return mix(cream_ink.rgb, cream_shadow.rgb, y / 0.55);
	}
	if (y < 0.86) {
		return mix(cream_shadow.rgb, cream_body.rgb, (y - 0.55) / 0.31);
	}
	return mix(cream_body.rgb, cream_light.rgb, (y - 0.86) / 0.14);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 rgb = source.rgb;
	float y = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 result;
	if (surface_kind == 1) {
		// A face-only mode: baked edge/bevel contrast becomes a shallow cream rim.
		result = cream_ramp(y);
	} else {
		float warm = smoothstep(0.045, 0.145, rgb.r - rgb.b)
			* smoothstep(0.010, 0.045, rgb.r - rgb.g);
		float green = smoothstep(0.006, 0.055, rgb.g - rgb.r)
			* smoothstep(0.028, 0.100, rgb.g - rgb.b);
		// Cool/neutral icon pieces keep their hue at reduced saturation. The ramp
		// lifts painted outlines without blurring or broadening their silhouettes.
		vec3 neutral = vec3(0.13 + 0.82 * y) + (rgb - vec3(y)) * 0.62;
		neutral = mix(neutral, cream_ramp(y), smoothstep(0.70, 0.92, y));
		vec3 wood = birch_ramp(y);
		result = mix(neutral, wood, warm);
		// Selected sage stays dark enough for the independently rendered cream
		// caption. Illustration greens are lifted slightly more for softer leaves.
		float sage_lift = surface_kind == 2 ? 0.014 : 0.033;
		float sage_chroma = surface_kind == 2 ? 0.62 : 0.55;
		vec3 sage = vec3(y) + (rgb - vec3(y)) * sage_chroma
			+ vec3(sage_lift + 0.006, sage_lift, sage_lift + 0.002);
		if (surface_kind == 2) {
			// Leave headroom for the existing 1.06x hover tint behind small text.
			sage *= 0.95;
		}
		result = mix(result, sage, green);
		// A sage texture's bright cream rim must remain bright. It is a distinct
		// state cue; it is deliberately excluded from the green interior remap.
		if (surface_kind == 2) {
			result = mix(cream_ramp(y), result, green);
		}
	}
	// Useful for a tiny face/gear illustration, not for broad wood surfaces.
	float detail = preserve_dark_details * (1.0 - smoothstep(0.13, 0.31, y));
	result = mix(result, rgb, detail);
	result = mix(rgb, clamp(result, vec3(0.0), vec3(1.0)), treatment_strength);
	COLOR = vec4(result, source.a) * item_tint;
}
