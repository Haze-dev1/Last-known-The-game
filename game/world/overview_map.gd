extends Control
## Overview map: generated map image with the Kowloon coverage polygon, loaded
## chunk rings, district jump points (click to jump) and the viewer marker.

var world: Node3D
var texture: ImageTexture
var map_info: Dictionary


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	map_info = world.index["map"]
	var packed := FileAccess.get_file_as_bytes(world.DATA_DIR + map_info["file"])
	var w := packed.decode_u32(4)
	var h := packed.decode_u32(8)
	var raw_size := packed.decode_u32(12)
	var raw := packed.slice(16).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, raw))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _map_rect() -> Rect2:
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var s := minf((size.x - 40) / tex_size.x, (size.y - 80) / tex_size.y)
	var sz := tex_size * s
	return Rect2((size - sz) * 0.5 + Vector2(0, 20), sz)


func _to_screen(x: float, z: float, r: Rect2) -> Vector2:
	var u := (x - float(map_info["x0"])) / (float(map_info["m_per_px"]) * texture.get_width())
	var v := (z - float(map_info["z0"])) / (float(map_info["m_per_px"]) * texture.get_height())
	return r.position + Vector2(u, v) * r.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.78))
	var r := _map_rect()
	draw_texture_rect(texture, r, false)
	var font := get_theme_default_font()
	var cs: float = world.chunk_size
	for key in world.chunks:
		var c: Dictionary = world.chunks[key]
		var a := _to_screen(c["i"] * cs, c["j"] * cs, r)
		var b := _to_screen((c["i"] + 1) * cs, (c["j"] + 1) * cs, r)
		var col := Color(0.4, 0.9, 0.5, 0.35) if c["near"] != null else Color(0.5, 0.7, 1.0, 0.08)
		draw_rect(Rect2(a, b - a), col, true)
		if c["body"] != null:
			draw_rect(Rect2(a, b - a), Color(1, 1, 0.4, 0.7), false, 1.0)
	for ring in world.index["coverage_polygon"]:
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(_to_screen(p[0], p[1], r))
		draw_polyline(pts, Color(1.0, 0.72, 0.25), 2.0)
	var jumps: Array = world.index["jump_points"]
	for k in jumps.size():
		var p: Array = jumps[k]["pos"]
		var s := _to_screen(p[0], p[2], r)
		draw_circle(s, 4.0, Color(1, 1, 1, 0.9))
		draw_string(font, s + Vector2(6, 4), jumps[k]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
	var v: Vector3 = world.viewer_position()
	var vs := _to_screen(v.x, v.z, r)
	draw_circle(vs, 7.0, Color(1, 0.2, 0.2))
	draw_string(font, Vector2(20, 26), "Kowloon coverage (amber): five Kowloon districts · green = detailed chunks loaded · yellow outline = collision · click a white point to jump · M/Esc close", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var r := _map_rect()
		var jumps: Array = world.index["jump_points"]
		var best := -1
		var best_d := 14.0
		for k in jumps.size():
			var p: Array = jumps[k]["pos"]
			var d := _to_screen(p[0], p[2], r).distance_to(event.position)
			if d < best_d:
				best_d = d
				best = k
		if best >= 0:
			world.call("_toggle_map")
			world.call("jump_to", best)
		accept_event()
