shader_type spatial;
// Shared weathered facade. UV.x = metres along footprint perimeter, UV.y = metres above ground.
// COLOR: tint rgb + style (a * 255 / 32); UV2-packed: seed, height/2, flags (1 shopfront, 2 creeper).
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
	int style = int(floor(c0.a * 255.0 / 32.0));
	float seed = c1.r;
	int flags = int(floor(c1.b * 255.0 + 0.5));
	float height = c1.g * 510.0;
	float floor_h = 3.0;
	float bay = 2.6 + seed * 1.2;
	float win_w = 0.55;
	float win_h = 0.5;
	if (style == 1) { floor_h = 3.3; bay = 3.2 + seed; win_w = 0.5; win_h = 0.55; }
	else if (style == 2) { floor_h = 4.4; bay = 4.5; win_w = 0.86; win_h = 0.38; }
	else if (style == 3) { floor_h = 2.8; bay = 2.2 + seed * 0.4; win_w = 0.5; win_h = 0.45; }
	else if (style == 4) { floor_h = 4.6; bay = 6.0; win_w = 0.3; win_h = 0.25; }
	else if (style == 5) { floor_h = 3.9; bay = 1.6; win_w = 0.9; win_h = 0.72; }
	else if (style >= 6) { floor_h = 3.5; bay = 3.0; win_w = 0.0; win_h = 0.0; }
	vec2 uv = UV;
	float fl = floor(uv.y / floor_h);
	float bx = floor(uv.x / bay);
	vec2 cell = vec2(fract(uv.x / bay), fract(uv.y / floor_h));
	float rnd = hash21(vec2(bx, fl) + seed * 31.0);
	vec3 tint = c0.rgb;
	// mosaic tiles / board marks
	float tile = vnoise(uv * vec2(6.0, 6.0)) * 0.05;
	vec3 col = tint * (0.95 + tile);
	bool ground_floor = uv.y < 4.6;
	bool is_win = cell.x > (1.0 - win_w) * 0.5 && cell.x < 1.0 - (1.0 - win_w) * 0.5 && cell.y > 0.28 && cell.y < 0.28 + win_h && !ground_floor && uv.y < height - 1.2;
	if (is_win) {
		vec3 dark = vec3(0.05, 0.06, 0.06) + rnd * 0.05;
		if (rnd > 0.82) dark = vec3(0.22, 0.26, 0.28);   // remaining glass catches the sky
		if (rnd < 0.10) dark = vec3(0.30, 0.30, 0.27);   // boarded or curtained
		col = dark;
		// window frame
		float fx = abs(cell.x - 0.5) / (win_w * 0.5);
		if (fx > 0.93) col = tint * 0.7;
	} else if (!ground_floor && style != 5 && style < 6 && cell.y < 0.24 && cell.y > 0.08 && rnd > 0.58 && abs(cell.x - 0.5) < 0.18) {
		col = vec3(0.62, 0.61, 0.57) * (0.8 + rnd * 0.2); // air-conditioner box
	}
	if (ground_floor && (flags & 1) != 0) {
		float shutter = step(0.5, fract(uv.y * 6.0)) * 0.08;
		vec3 metal = mix(vec3(0.42, 0.41, 0.38), vec3(0.40, 0.27, 0.18), vnoise(uv * vec2(0.8, 2.0)));
		col = (uv.y < 3.4) ? metal * (0.85 + shutter) : tint * 0.55;
	} else if (ground_floor) {
		col *= 0.8;
	}
	// floor slab lines
	col *= 1.0 - 0.12 * smoothstep(0.03, 0.0, cell.y);
	// vertical rain streaks below windows and a damp, mossy base
	float streak = fbm(vec2(uv.x * 1.3, uv.y * 0.06 + seed * 9.0));
	col *= 1.0 - 0.32 * smoothstep(0.45, 0.85, streak);
	float base_damp = smoothstep(1.8, 0.0, uv.y);
	col = mix(col, vec3(0.16, 0.19, 0.12), base_damp * 0.55);
	if ((flags & 2) != 0) {
		float vine = fbm(uv * 0.35 + seed * 13.0) - uv.y * 0.035;
		col = mix(col, mix(vec3(0.16, 0.25, 0.10), vec3(0.26, 0.33, 0.14), vnoise(uv * 3.0)), smoothstep(0.42, 0.5, vine));
	}
	// beyond a few pixels per bay the window grid aliases; fade to its average tone
	float px = max(fwidth(uv.x) / bay, fwidth(uv.y) / floor_h);
	vec3 avg = mix(tint * 0.78, vec3(0.1), win_w * win_h * 0.8);
	col = mix(col, avg * (1.0 - 0.25 * smoothstep(0.45, 0.85, streak)), smoothstep(0.12, 0.45, px));
	ALBEDO = col;
	ROUGHNESS = is_win ? 0.35 : 0.9;
	SPECULAR = is_win ? 0.5 : 0.25;
}
