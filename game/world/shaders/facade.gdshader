shader_type spatial;
// Weathered Kowloon facade. UV.x = metres along footprint perimeter (runs along TANGENT),
// UV.y = metres above ground. COLOR: tint rgb + style (a * 255 / 32);
// UV2-packed: seed, height/2, flags (1 shopfront, 2 creeper).
// Windows use interior mapping: a fake room box behind the glass gives real parallax depth.
#include "res://world/shaders/noise.gdshaderinc"

uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tiles_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tiles_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shutter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shutter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec4 c0;
varying vec4 c1;

void vertex() {
	c0 = COLOR;
	c1 = vec4(mod(UV2.x, 256.0), mod(UV2.y, 256.0), floor(UV2.x / 256.0), floor(UV2.y / 256.0)) / 255.0;
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0)) + vec3(1e-5));
	BINORMAL = vec3(0.0, -1.0, 0.0);
}

float luma(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

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
	vec2 tuv = vec2(uv.x, -uv.y) / 2.5;
	vec3 base;
	vec3 nmap;
	if ((style == 0 && seed > 0.45) || (style == 5 && seed < 0.5)) {
		base = texture(tiles_albedo, tuv * 1.6).rgb;
		nmap = texture(tiles_normal, tuv * 1.6).rgb;
	} else if (style == 2 || style == 4 || style >= 5) {
		base = texture(concrete_albedo, tuv).rgb;
		nmap = texture(concrete_normal, tuv).rgb;
	} else {
		base = texture(plaster_albedo, tuv).rgb;
		nmap = texture(plaster_normal, tuv).rgb;
	}
	// Kowloon paint and tile colours: push saturation, keep albedo below bright white
	vec3 tint = mix(vec3(luma(c0.rgb)), c0.rgb, 1.9) * 0.82;
	// keep the photo texture's detail but take the building's own paint colour
	// the photo texture supplies grain and stains; the building keeps its own paint colour
	bool tiled = (style == 0 && seed > 0.45) || (style == 5 && seed < 0.5);
	float grain = luma(base) / 0.5;
	vec3 col = tint * mix(1.0, grain, tiled ? 0.55 : 0.35);
	col = mix(col, base * tint * 1.6, tiled ? 0.25 : 0.08);
	float rough = 0.88;
	float metal = 0.0;
	float fl = floor(uv.y / floor_h);
	float bx = floor(uv.x / bay);
	vec2 cell = vec2(fract(uv.x / bay), fract(uv.y / floor_h));
	float rnd = hash21(vec2(bx, fl) + seed * 31.0);
	bool ground_floor = uv.y < 4.6;
	float x0 = (1.0 - win_w) * 0.5;
	float y0 = 0.28;
	bool is_win = cell.x > x0 && cell.x < 1.0 - x0 && cell.y > y0 && cell.y < y0 + win_h && !ground_floor && uv.y < height - 1.2;
	float px = max(fwidth(uv.x) / bay, fwidth(uv.y) / floor_h);
	float detail = 1.0 - smoothstep(0.10, 0.40, px);
	if (is_win && detail > 0.0) {
		vec2 w = vec2((cell.x - x0) / win_w, (cell.y - y0) / win_h);
		float frame = step(w.x, 0.05) + step(0.95, w.x) + step(w.y, 0.06) + step(0.94, w.y) + step(abs(w.x - 0.5), 0.02);
		// interior mapping: ray from the glass into a box room
		vec3 v_ts = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, -BINORMAL), dot(VIEW, NORMAL)));
		vec3 d = -v_ts;
		float aspect = (win_w * bay) / max(win_h * floor_h, 0.01);
		vec3 o = vec3(w * 2.0 - 1.0, 0.0);
		d.x /= aspect;
		float depth = 1.6;
		vec3 inv = 1.0 / (d + vec3(1e-4));
		float tx = (sign(d.x) - o.x) * inv.x;
		float ty = (sign(d.y) - o.y) * inv.y;
		float tz = (-depth - o.z) * inv.z;
		float t = min(min(tx, ty), tz);
		vec3 h = o + d * t;
		float lit = 0.10 + 0.14 * rnd;
		vec3 room;
		if (t == tz) {
			room = vec3(0.55, 0.52, 0.46) * lit * (0.7 + 0.3 * vnoise(h.xy * 3.0 + rnd * 20.0));
			if (rnd > 0.7) room = mix(room, vec3(0.30, 0.18, 0.12) * lit * 2.0, step(0.2, h.x) * step(h.y, 0.3));
		} else if (t == ty) {
			room = (h.y < 0.0 ? vec3(0.35, 0.28, 0.22) : vec3(0.6)) * lit * 0.8;
		} else {
			room = vec3(0.48, 0.46, 0.42) * lit * 0.7;
		}
		room *= smoothstep(-depth, 0.0, h.z) * 0.6 + 0.4;
		bool broken = rnd < 0.28;
		float fres = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 4.0);
		vec3 glass = broken ? room : mix(room, vec3(0.30, 0.33, 0.35), 0.04 + 0.38 * fres) * (0.85 + 0.15 * vnoise(uv * 4.0));
		if (rnd > 0.88) glass = mix(glass, vec3(0.42, 0.38, 0.30), 0.6);
		vec3 frame_col = rnd > 0.5 ? vec3(0.20, 0.21, 0.20) : tint * 0.42;
		vec3 wcol = frame > 0.5 ? frame_col : glass;
		col = mix(col, wcol, detail);
		rough = mix(rough, frame > 0.5 ? 0.6 : (broken ? 0.9 : 0.08), detail);
		metal = frame > 0.5 ? 0.3 * detail : 0.0;
		nmap = mix(nmap, vec3(0.5, 0.5, 1.0), detail);
	} else if (!ground_floor && style != 5 && style < 6 && cell.y < 0.24 && cell.y > 0.08 && rnd > 0.58 && abs(cell.x - 0.5) < 0.18) {
		col = mix(col, vec3(0.62, 0.61, 0.57) * (0.7 + rnd * 0.25) * (0.8 + 0.2 * step(0.5, fract(uv.x * 8.0))), detail);
	}
	// distant cells resolve to the average facade tone instead of aliasing
	col = mix(mix(tint * 0.72, vec3(0.08), win_w * win_h * 0.7), col, detail);
	if (ground_floor && (flags & 1) != 0) {
		vec2 suv = vec2(uv.x / 3.2, -uv.y / 3.2);
		if (uv.y < 3.4) {
			vec3 sh = texture(shutter_albedo, suv).rgb;
			col = mix(sh, vec3(luma(sh)) * vec3(0.62, 0.50, 0.42), 0.65);
			nmap = texture(shutter_normal, suv).rgb;
			metal = 0.4;
			rough = 0.75;
		} else {
			col *= 0.55;
		}
	} else if (ground_floor) {
		col *= 0.82;
	}
	col *= 1.0 - 0.2 * smoothstep(0.035, 0.0, cell.y) * detail;
	// three decades of monsoon: rain streaks, black mould runs under sills, runoff below the roofline
	float streak = fbm(vec2(uv.x * 1.4, uv.y * 0.05 + seed * 9.0));
	col *= 1.0 - 0.45 * smoothstep(0.42, 0.85, streak);
	float under_sill = step(x0, cell.x) * step(cell.x, 1.0 - x0) * smoothstep(y0, 0.0, cell.y) * step(4.6, uv.y);
	col *= 1.0 - 0.5 * under_sill * smoothstep(0.35, 0.7, vnoise(vec2(uv.x * 3.0, uv.y * 0.4))) * detail;
	col *= 1.0 - 0.35 * smoothstep(height - 7.0, height, uv.y) * smoothstep(0.3, 0.7, vnoise(vec2(uv.x * 0.9, seed * 40.0)));
	float grime = fbm(uv * vec2(0.07, 0.025) + seed * 17.0);
	col *= 0.62 + 0.45 * grime;

	float moss_mask = clamp(smoothstep(2.6, 0.0, uv.y) + smoothstep(0.62, 0.8, fbm(uv * 0.12 + seed * 7.0)) * 0.8, 0.0, 1.0);
	vec3 moss = texture(moss_albedo, tuv * 0.8).rgb;
	col = mix(col, moss * 0.85, moss_mask * 0.75);
	nmap = mix(nmap, texture(moss_normal, tuv * 0.8).rgb, moss_mask * 0.6);
	if ((flags & 2) != 0) {
		float vine = fbm(uv * 0.35 + seed * 13.0) - uv.y * 0.03;
		col = mix(col, moss * vec3(0.7, 0.95, 0.6), smoothstep(0.42, 0.5, vine));
	}
	ALBEDO = col;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
}
