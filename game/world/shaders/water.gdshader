shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://world/shaders/noise.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.05;
	float n = fbm(p * 0.05 + vec2(t, t * 0.7)) + 0.5 * vnoise(p * 0.4 - vec2(t * 3.0));
	vec3 nrm = normalize(vec3((n - 0.75) * 0.25, 1.0, (vnoise(p * 0.3 + t) - 0.5) * 0.25));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	ALBEDO = mix(vec3(0.03, 0.06, 0.06), vec3(0.06, 0.09, 0.08), n);
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
}
