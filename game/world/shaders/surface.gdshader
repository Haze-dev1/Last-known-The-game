shader_type spatial;
// Roads, paving, roofs, rail, structural concrete and props.
// kind: 1 road, 2 paving, 4 roof, 5 rail, 6 concrete, 7 vertex-coloured prop.
#include "res://world/shaders/noise.gdshaderinc"

uniform int kind = 1;
uniform sampler2D albedo_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale_a = 4.0;
uniform float scale_b = 3.0;

varying vec4 c0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	c0 = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 t = abs(NORMAL.y) > 0.7 ? vec3(1.0, 0.0, 0.0) : normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0)));
	TANGENT = t;
	BINORMAL = normalize(cross(NORMAL, t));
}

// world-space planar UV chosen by the dominant normal axis (cheap triplanar)
vec2 planar(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) return p.xz;
	if (a.x > a.z) return vec2(p.z, -p.y);
	return vec2(p.x, -p.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * 0.12);
	vec3 col;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rough = 0.9;
	float metal = 0.0;
	if (kind == 1) {
		float code = floor(c0.r * 255.0 / 20.0 + 0.5);
		float lanes = floor(c0.g * 255.0 / 30.0 + 0.5);
		float width = c0.b * 25.5;
		vec2 ruv = vec2(UV.x, UV.y) / scale_a;
		col = texture(albedo_a, ruv).rgb;
		col = mix(col, vec3(dot(col, vec3(0.33))), 0.5) * (0.62 + 0.3 * fbm(p * 0.05)); // sun-bleached, filthy asphalt
		nm = texture(normal_a, ruv).rgb;
		float paint = 0.0;
		if (lanes >= 2.0 && code >= 4.0) paint = max(paint, step(abs(UV.x), 0.08) * step(0.5, fract(UV.y / 9.0)));
		if (code >= 5.0) paint = max(paint, step(abs(abs(UV.x) - (width * 0.5 - 0.35)), 0.07));
		paint *= smoothstep(0.45, 0.8, vnoise(p * 0.6)) * 0.35; // flaked away
		col = mix(col, vec3(0.55, 0.53, 0.45), paint);
		// decades of growth: verges swallow the edges, moss mats and soil patches split the surface
		float edge = smoothstep(width * 0.5 - 2.5, width * 0.5, abs(UV.x));
		float crack = smoothstep(0.05, 0.0, abs(fbm(p * 0.22 + 3.0) - 0.5)) + smoothstep(0.04, 0.0, abs(fbm(p * 0.6 + 9.0) - 0.5)) * 0.7;
		float patches = smoothstep(0.48, 0.72, n + 0.25 * fbm(p * 0.03));
		float growth = clamp(edge * (0.5 + n) + crack + patches, 0.0, 1.0);
		vec3 moss = texture(albedo_b, p / scale_b).rgb * vec3(0.85, 1.05, 0.75);
		col = mix(col, moss, growth * 0.9);
		nm = mix(nm, texture(normal_b, p / scale_b).rgb, growth);
		col = mix(col, vec3(0.22, 0.17, 0.11), smoothstep(0.58, 0.85, fbm(p * 0.09 + 5.0)) * 0.55); // leaf litter and silt
		// potholes holding rainwater
		float hole = smoothstep(0.80, 0.86, fbm(p * 0.15 + 21.0));
		col = mix(col, vec3(0.05, 0.06, 0.05), hole * 0.8);
		rough = mix(mix(0.9, 0.97, growth), 0.05, hole);
	} else if (kind == 2) {
		vec3 a = texture(albedo_a, p / scale_a).rgb;
		vec3 b = texture(albedo_b, p / scale_b).rgb;
		float m = smoothstep(0.25, 0.55, n);
		col = mix(a * 0.8, b, m);
		nm = mix(texture(normal_a, p / scale_a).rgb, texture(normal_b, p / scale_b).rgb, m);
		// lifted and missing pavers expose soil
		vec2 cell = floor(p / 0.6);
		float gone = step(0.93, hash21(cell)) * smoothstep(0.3, 0.6, n);
		col = mix(col, vec3(0.16, 0.13, 0.09), gone);
		col *= 0.9 - 0.25 * step(0.8, hash21(cell + 7.0));
		col = mix(col, vec3(0.22, 0.17, 0.11), smoothstep(0.6, 0.85, fbm(p * 0.1 + 2.0)) * 0.5);
	} else if (kind == 4) {
		vec3 a = texture(albedo_a, p / scale_a).rgb;
		vec3 b = texture(albedo_b, p / scale_b).rgb;
		float m = smoothstep(0.45, 0.75, n + 0.15 * fbm(p * 0.6));
		col = mix(a * (0.7 + c0.rgb * 0.5), b, m);
		nm = mix(texture(normal_a, p / scale_a).rgb, texture(normal_b, p / scale_b).rgb, m);
		col = mix(col, col * 0.45, smoothstep(0.78, 0.92, fbm(p * 0.4)) * 0.6); // standing water stains
	} else if (kind == 5) {
		col = texture(albedo_a, p / scale_a).rgb;
		nm = texture(normal_a, p / scale_a).rgb;
		float m = smoothstep(0.5, 0.8, n);
		col = mix(col, texture(albedo_b, p / scale_b).rgb, m * 0.7);
	} else {
		vec2 tuv = planar(wpos, wnrm);
		vec3 a = texture(albedo_a, tuv / scale_a).rgb;
		nm = texture(normal_a, tuv / scale_a).rgb;
		if (kind == 6) {
			col = mix(a, c0.rgb * (0.6 + a), 0.35);
			col *= 1.0 - 0.3 * smoothstep(0.5, 0.85, fbm(vec2(p.x + p.y, wpos.y * 0.3)));
			float moss = smoothstep(0.6, 0.85, fbm(tuv * 0.2)) * step(0.5, wnrm.y + 0.6);
			col = mix(col, texture(albedo_b, tuv / scale_b).rgb, moss * 0.7);
		} else {
			vec3 rust = texture(albedo_b, tuv / scale_b).rgb;
			col = mix(c0.rgb * 0.9, rust, smoothstep(0.35, 0.8, fbm(tuv * 0.7)) * 0.75);
			metal = 0.35;
			rough = 0.7;
		}
	}
	ALBEDO = col;
	NORMAL_MAP = nm;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.35;
}
