shader_type canvas_item;
render_mode unshaded;

uniform vec4 quiet_rects[8];
uniform int quiet_count = 0;
varying vec2 local_point;
varying vec4 vertex_modulate;

void vertex() {
    local_point = VERTEX;
    vertex_modulate = COLOR;
}

void fragment() {
    vec4 ink = texture(TEXTURE, UV) * vertex_modulate;
    float coverage = 1.0;
    for (int i = 0; i < 8; i++) {
        if (i >= quiet_count) { break; }
        vec2 outside = max(max(quiet_rects[i].xy - local_point,
            local_point - quiet_rects[i].zw), vec2(0.0));
        coverage *= smoothstep(0.0, 7.0, length(outside));
    }
    COLOR = vec4(ink.rgb, ink.a * coverage);
}
