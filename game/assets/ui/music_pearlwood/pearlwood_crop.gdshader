shader_type canvas_item;
render_mode unshaded;

// Retained source-region sampling. The untouched experimental PNGs contain
// isolated alpha=1 pixels: do not let those become broad visible ink bounds.
uniform vec4 source_region = vec4(0.0, 0.0, 1.0, 1.0);
varying vec4 layer_tint;

void vertex() {
	layer_tint = COLOR;
}

void fragment() {
	vec4 paint = texture(TEXTURE, source_region.xy + UV * source_region.zw);
	if (paint.a <= 2.0 / 255.0) {
		discard;
	}
	COLOR = paint * layer_tint;
}
