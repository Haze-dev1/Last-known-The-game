shader_type spatial;
// Ground: COLOR = texture weights (grass, forest floor, mud/scrub, wet); remainder = hard paving.
// UV2-packed: class id, slope*2.8, overgrowth amount.
#include "res://world/shaders/noise.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec4 c0;
varying vec4 c1;
varying vec3 wpos;

void vertex() {
	c0 = COLOR;
	c1 = vec4(mod(UV2.x, 256.0), mod(UV2.y, 256.0), floor(UV2.x / 256.0), floor(UV2.y / 256.0)) / 255.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv = p / 3.0;
	// break visible tiling with a slowly rotated second sample
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / 4.3;
	float macro = fbm(p * 0.03);
	float n = fbm(p * 0.12);
	vec4 w = c0;
	float slope = c1.g * 255.0 / 2.8;
	float veg = c1.b;
	// patchy growth creeps into hard ground
	float creep = smoothstep(0.55 - veg * 0.4, 0.85, n + 0.2 * macro) * clamp(veg + 0.1, 0.0, 1.0);
	w.x = max(w.x, creep * (1.0 - w.y) * 0.9);
	float hard = clamp(1.0 - (w.x + w.y + w.z + w.w), 0.0, 1.0);
	vec3 g = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv2).rgb, 0.5) * vec3(0.82, 1.05, 0.70);
	vec3 f = mix(texture(forest_albedo, uv).rgb, texture(forest_albedo, uv2).rgb, 0.5);
	vec3 m = texture(mud_albedo, uv).rgb;
	bool steep = slope > 33.0;
	vec3 h = steep ? texture(concrete_albedo, uv * 0.7).rgb * vec3(0.95, 0.93, 0.85) : texture(pavers_albedo, uv * 0.8).rgb;
	vec3 wt = texture(wet_albedo, uv).rgb * 0.55;
	vec3 col = g * w.x + f * w.y + m * w.z + wt * w.w + h * hard;
	col /= max(w.x + w.y + w.z + w.w + hard, 1e-3);
	col *= 0.85 + 0.3 * macro;
	vec3 nm = texture(grass_normal, uv).rgb * w.x + texture(forest_normal, uv).rgb * w.y + texture(mud_normal, uv).rgb * w.z
		+ (steep ? texture(concrete_normal, uv * 0.7).rgb : texture(pavers_normal, uv * 0.8).rgb) * hard + vec3(0.5, 0.5, 1.0) * w.w;
	nm /= max(w.x + w.y + w.z + w.w + hard, 1e-3);
	ALBEDO = col;
	NORMAL_MAP = nm;
	ROUGHNESS = mix(0.95, 0.35, w.w);
	SPECULAR = 0.3;
}
