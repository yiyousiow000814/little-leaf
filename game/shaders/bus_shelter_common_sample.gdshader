// Asset-local retained BACK material; native runtime validation is pending.
// Preserve the original accepted WHOLE/FRONT/BACK bytes and common full-canvas UV.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D whole_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D front_texture : source_color, filter_linear, repeat_disable;
varying vec4 part_tint;

void vertex() {
    // Fragment COLOR already includes TEXTURE. Retain the primitive/node tint
    // separately so WHOLE, FRONT and BACK receive it exactly once.
    part_tint = COLOR;
}

void fragment() {
    vec4 whole = texture(whole_texture, UV) * part_tint;
    vec4 front = texture(front_texture, UV) * part_tint;
    float through_front = 1.0 - front.a;
    if (through_front <= 0.000001) {
        // Fully opaque FRONT hides this fragment of BACK.
        COLOR = texture(TEXTURE, UV) * part_tint;
    } else {
        float back_alpha = clamp((whole.a - front.a) / through_front, 0.0, 1.0);
        vec3 back_premult = (whole.rgb * whole.a - front.rgb * front.a) / through_front;
        back_premult = clamp(back_premult, vec3(0.0), vec3(back_alpha));
        vec3 back_rgb = back_alpha > 0.000001 ? back_premult / back_alpha : vec3(0.0);
        COLOR = vec4(back_rgb, back_alpha);
    }
}
