shader_type spatial;
// Alpha-scissored leaf cards (trees, shrubs, ferns, grass, ivy) with wind sway and
// leaf translucency. Instance/vertex COLOR tints the card.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float alpha_cut = 0.45;
uniform float wind = 1.0;
uniform float sway_height = 6.0;
uniform vec3 translucency = vec3(0.30, 0.36, 0.14);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	float t = TIME * 1.1 + wp.x * 0.13 + wp.z * 0.11;
	float sway = (sin(t) * 0.6 + sin(t * 2.7 + wp.y) * 0.25) * wind * 0.08 * h * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.7;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	BACKLIGHT = translucency * COLOR.rgb;
}
