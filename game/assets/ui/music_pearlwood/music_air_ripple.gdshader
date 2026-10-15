shader_type canvas_item;
render_mode unshaded;
// A transparent-centred pressure wave, not an opaque expanding disc.
uniform float age = 2.0;
uniform float music_energy = 0.0;
void fragment() {
 float t = clamp(age / 0.95, 0.0, 1.0);
 vec2 p = (UV - vec2(0.5)) * 2.0;
 float d = length(p);
 float radius = 0.07 + 0.76 * (1.0 - pow(1.0 - t, 2.1));
 float width = mix(0.016, 0.037, t);
 float crest = exp(-pow((d - radius) / width, 2.0));
 float veil = exp(-pow((d - radius + 0.023) / (width * 2.8), 2.0));
 float wake = exp(-pow((d - radius * 0.76) / (width * 0.8), 2.0)) * 0.22;
 float contact = exp(-d * d / 0.003) * exp(-t * 25.0);
 float direction = 0.74 + 0.26 * dot(normalize(p + vec2(0.0001)), normalize(vec2(-0.6,-0.8)));
 float envelope = pow(1.0 - t, 1.7) * smoothstep(0.0, 0.045, t);
 vec3 pearl = mix(vec3(0.78,0.91,0.82),vec3(1.0,0.98,0.84),crest);
 float alpha = (crest * (0.26 + 0.08 * music_energy) * direction + veil * 0.075 + wake * 0.12) * envelope + contact * 0.22;
 COLOR = vec4(pearl, alpha * (1.0 - smoothstep(0.88,1.0,d)));
}
