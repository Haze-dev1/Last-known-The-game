shader_type spatial;
// Roads, paving, rail ballast, roofs, structural concrete and props share this shader.
// kind: 1 road, 2 paving, 4 roof, 5 rail, 6 concrete, 7 vertex-coloured prop.
#include "res://world/shaders/noise.gdshaderinc"

uniform int kind = 1;
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
	float n = fbm(p * 0.12);
	float fine = vnoise(p * 3.0);
	vec3 col;
	float rough = 0.92;
	if (kind == 1) {
		float code = floor(c0.r * 255.0 / 20.0 + 0.5);
		float lanes = floor(c0.g * 255.0 / 30.0 + 0.5);
		float width = c0.b * 25.5;
		col = vec3(0.21, 0.21, 0.205) * (0.85 + 0.3 * fine) + 0.06 * n;
		float u = UV.x;
		float v = UV.y;
		float paint = 0.0;
		if (lanes >= 2.0 && code >= 4.0) {
			paint = max(paint, step(abs(u), 0.08) * step(0.5, fract(v / 9.0)));
		}
		if (code >= 5.0) {
			paint = max(paint, step(abs(abs(u) - (width * 0.5 - 0.35)), 0.07));
		}
		paint *= smoothstep(0.25, 0.6, vnoise(p * 0.8)); // worn paint
		col = mix(col, vec3(0.62, 0.58, 0.44), paint * 0.75);
		float crack = smoothstep(0.025, 0.0, abs(fbm(p * 0.28 + 3.0) - 0.5));
		float edge = smoothstep(width * 0.5 - 1.2, width * 0.5, abs(u));
		float growth = clamp(crack * 0.8 + edge * smoothstep(0.45, 0.75, n), 0.0, 1.0);
		col = mix(col, vec3(0.20, 0.26, 0.12), growth * 0.75);
		col = mix(col, vec3(0.26, 0.22, 0.16), smoothstep(0.6, 0.85, n) * 0.35); // leaf litter
	} else if (kind == 2) {
		vec2 g = abs(fract(p / 0.6) - 0.5);
		float joint = smoothstep(0.43, 0.5, max(g.x, g.y));
		col = mix(vec3(0.50, 0.46, 0.42), vec3(0.47, 0.40, 0.36), hash21(floor(p / 0.6)));
		col *= 0.88 + 0.2 * fine;
		col = mix(col, vec3(0.19, 0.25, 0.12), joint * smoothstep(0.35, 0.7, n));
		col = mix(col, vec3(0.24, 0.30, 0.15), smoothstep(0.7, 0.9, n) * 0.6);
	} else if (kind == 4) {
		col = c0.rgb * (0.9 + 0.2 * fine);
		col = mix(col, vec3(0.20, 0.24, 0.15), smoothstep(0.55, 0.85, n) * 0.5); // rooftop moss and puddles
		col = mix(col, vec3(0.12, 0.13, 0.12), smoothstep(0.75, 0.9, fbm(p * 0.4)) * 0.4);
	} else if (kind == 5) {
		col = mix(vec3(0.33, 0.30, 0.27), vec3(0.25, 0.22, 0.20), vnoise(p * 7.0));
		col = mix(col, vec3(0.22, 0.28, 0.13), smoothstep(0.5, 0.8, n) * 0.7);
	} else if (kind == 6) {
		col = c0.rgb * (0.88 + 0.22 * fine);
		col *= 1.0 - 0.3 * smoothstep(0.5, 0.85, fbm(vec2(p.x + p.y, wpos.y * 0.3)));
	} else {
		col = c0.rgb * (0.85 + 0.2 * fine);
		col *= 1.0 - 0.25 * smoothstep(0.55, 0.85, n);
		rough = 0.75;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
