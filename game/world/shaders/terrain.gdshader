shader_type spatial;
// Ground: land-use colour from the pipeline (COLOR.rgb), overgrowth amount (COLOR.a).
#include "res://world/shaders/noise.gdshaderinc"

varying vec4 c0;
varying vec4 c1;
varying vec3 wpos;

void vertex() {
	c0 = COLOR;
	c1 = vec4(mod(UV2.x, 256.0), mod(UV2.y, 256.0), floor(UV2.x / 256.0), floor(UV2.y / 256.0)) / 255.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float cls = floor(c1.r * 255.0 + 0.5);
	float n1 = fbm(p * 0.09);
	float n2 = vnoise(p * 0.7);
	vec3 base = c0.rgb * (0.86 + 0.28 * n2);
	float veg = c0.a;
	// patches of growth: clustered, never a uniform carpet
	float growth = smoothstep(0.62 - veg * 0.5, 0.95 - veg * 0.3, n1 + 0.15 * n2);
	vec3 green = mix(vec3(0.20, 0.27, 0.12), vec3(0.33, 0.37, 0.17), vnoise(p * 0.23));
	vec3 col = mix(base, green, growth * clamp(veg + 0.15, 0.0, 1.0));
	if (cls < 0.5 || abs(cls - 6.0) < 0.5 || abs(cls - 11.0) < 0.5) {
		// paved / industrial / shotcrete: slab joints and cracks with moss
		vec2 g = abs(fract(p / vec2(2.4, 2.4)) - 0.5);
		float joint = smoothstep(0.47, 0.5, max(g.x, g.y));
		float crack = smoothstep(0.02, 0.0, abs(fbm(p * 0.35) - 0.5));
		col = mix(col, vec3(0.18, 0.22, 0.13), (joint * 0.35 + crack * 0.6) * clamp(veg * 2.0, 0.2, 1.0));
		col *= 0.93 + 0.1 * vnoise(p * 2.1);
	}
	if (abs(cls - 5.0) < 0.5) {
		col = mix(col, vec3(0.10, 0.15, 0.13), 0.55);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
