extends Node3D
## Kowloon world exploration entry point: streams generated chunks around the
## viewer, provides walking, a developer free-flight mode, district jumps, an
## overview map and stuck/out-of-bounds recovery.

const DATA_DIR := "res://world/data/"
const PlayerScript := preload("res://player/player.gd")
const OverviewMap := preload("res://world/overview_map.gd")

@export var near_radius := 480.0
@export var far_radius := 3400.0
@export var collision_radius := 200.0
@export var max_parallel_loads := 4

var index: Dictionary = {}
var assets: WorldAssets
var chunk_size := 256.0
var sea_level := 1.2
var player: CharacterBody3D
var flight_camera: Camera3D
var flying := false
var hud: Label
var notice: Label
var notice_time := 0.0
var overview: Control
var pause_panel: PanelContainer
var jump_index := 0
var awaiting_ground := true
var last_safe := Vector3.ZERO
var boundary: Array[PackedVector2Array] = []
var chunk_root: Node3D

# key -> {"i","j","near": Node3D, "far": Node3D, "body": StaticBody3D, "near_data": ChunkData}
var chunks := {}
var pending := {}  # "n_i_j"/"f_i_j" -> task id
var results := {}  # finished ChunkData waiting for the main thread
var results_mutex := Mutex.new()
var stream_timer := 0.0
var stats := {"loaded_near": 0, "loaded_far": 0, "bodies": 0, "unloads": 0, "missing": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_inputs()
	var text := FileAccess.get_file_as_string(DATA_DIR + "world_index.json")
	if text.is_empty():
		push_error("World data missing: run tools/world/build.py")
		return
	index = JSON.parse_string(text)
	chunk_size = float(index["chunk_size"])
	sea_level = float(index["sea_level"])
	for ring in index["boundary_polygon"]:
		var poly := PackedVector2Array()
		for p in ring:
			poly.append(Vector2(p[0], p[1]))
		boundary.append(poly)
	assets = WorldAssets.new()
	_build_environment()
	chunk_root = Node3D.new()
	chunk_root.name = "Chunks"
	add_child(chunk_root)
	_build_background()
	player = PlayerScript.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.floor_snap_length = 0.5
	player.floor_max_angle = deg_to_rad(50.0)
	player.camera.far = 6000.0
	player.camera.near = 0.08
	flight_camera = Camera3D.new()
	flight_camera.far = 9000.0
	add_child(flight_camera)
	_build_ui()
	var start: Array = index["jump_points"][_jump_named("Mong Kok")]["pos"]
	teleport(Vector3(start[0], start[1], start[2]))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("Kowloon world: %d chunks indexed, %d jump points" % [index["chunks"].size(), index["jump_points"].size()])


func _bind_inputs() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"world_flight": KEY_F, "world_map": KEY_M, "world_recover": KEY_R, "world_next": KEY_BRACKETRIGHT,
		"world_prev": KEY_BRACKETLEFT, "world_up": KEY_SPACE, "world_down": KEY_CTRL, "world_fast": KEY_SHIFT}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = bindings[action]
			InputMap.action_add_event(action, ev)


func _jump_named(n: String) -> int:
	var jumps: Array = index["jump_points"]
	for k in jumps.size():
		if jumps[k]["name"] == n:
			return k
	return 0


# ------------------------------------------------------------------ scene setup
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.46, 0.53, 0.58)
	sky_mat.sky_horizon_color = Color(0.72, 0.74, 0.70)
	sky_mat.ground_horizon_color = Color(0.55, 0.57, 0.53)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.25)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.69, 0.66)
	env.fog_density = 0.00009  # humid haze; geography stays legible for kilometres
	env.fog_aerial_perspective = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	water.mesh = plane
	water.material_override = assets.water_material
	water.position = Vector3(0, sea_level, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _build_background() -> void:
	var data := ChunkData.load_file(DATA_DIR + "background.bin", false)
	data.build_resources(assets.materials, assets.instance_meshes)
	for mesh in data.meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Background"
		add_child(mi)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)
	notice = Label.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.anchor_top = 0.8
	notice.position.x = -300
	notice.size = Vector2(600, 30)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	layer.add_child(notice)
	overview = OverviewMap.new()
	overview.world = self
	overview.visible = false
	overview.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overview)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.visible = false
	var box := VBoxContainer.new()
	pause_panel.add_child(box)
	var title := Label.new()
	title.text = "Kowloon world exploration — paused"
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_set_paused.bind(false))
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	layer.add_child(pause_panel)
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS


func show_notice(text: String, seconds: float = 3.0) -> void:
	notice.text = text
	notice_time = seconds


# ------------------------------------------------------------------ input and modes
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if overview.visible:
			_toggle_map()
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("world_map"):
		_toggle_map()
	elif overview.visible:
		return
	elif event.is_action_pressed("world_flight"):
		set_flying(not flying)
	elif event.is_action_pressed("world_recover"):
		recover("Recovered to the nearest safe street")
	elif event.is_action_pressed("world_next"):
		jump_to((jump_index + 1) % index["jump_points"].size())
	elif event.is_action_pressed("world_prev"):
		jump_to((jump_index - 1 + index["jump_points"].size()) % index["jump_points"].size())
	elif flying and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		flight_camera.rotation.y -= m.relative.x * 0.002
		flight_camera.rotation.x = clampf(flight_camera.rotation.x - m.relative.y * 0.002, -1.5, 1.5)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_panel.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _toggle_map() -> void:
	overview.visible = not overview.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if overview.visible else Input.MOUSE_MODE_CAPTURED
	player.movement_enabled = not overview.visible and not flying and not awaiting_ground


func set_flying(on: bool) -> void:
	if on == flying:
		return
	flying = on
	if on:
		flight_camera.global_transform = player.camera.global_transform
		flight_camera.current = true
		player.movement_enabled = false
		player.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		show_notice("DEVELOPER FLIGHT — inspection only (F to land)")
	else:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.visible = true
		var p := flight_camera.global_position
		player.rotation.y = flight_camera.rotation.y
		player.camera.current = true
		teleport(Vector3(p.x, p.y, p.z), true)


## Moves the walker; it waits (frozen) until collision has streamed in beneath it.
func teleport(pos: Vector3, drop_from_above: bool = false) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.movement_enabled = false
	awaiting_ground = true
	set_meta("drop_from_above", drop_from_above)
	flight_camera.global_position = pos + Vector3(0, 1.6, 0)
	_update_streaming(true)


func jump_to(k: int) -> void:
	jump_index = k
	var j: Dictionary = index["jump_points"][k]
	var p: Array = j["pos"]
	if flying:
		flight_camera.global_position = Vector3(p[0], p[1] + 60.0, p[2] + 60.0)
		flight_camera.look_at(Vector3(p[0], p[1], p[2]))
		_update_streaming(true)
	else:
		teleport(Vector3(p[0], p[1], p[2]))
	show_notice("%s · %s" % [j["name"], j["district"]])


func recover(message: String) -> void:
	var here := viewer_position()
	var best := Vector3.ZERO
	var best_d := INF
	var safe: Dictionary = index["safe_points"]
	var ci := floori(here.x / chunk_size)
	var cj := floori(here.z / chunk_size)
	for r in range(0, 12):
		for i in range(ci - r, ci + r + 1):
			for j in range(cj - r, cj + r + 1):
				if maxi(absi(i - ci), absi(j - cj)) != r:
					continue
				var key := "%d_%d" % [i, j]
				if not safe.has(key):
					continue
				for p in safe[key]:
					var v := Vector3(p[0], p[1], p[2])
					var d := v.distance_to(here)
					if d < best_d:
						best_d = d
						best = v
		if best_d < INF:
			break
	if best_d == INF:
		var s: Array = index["jump_points"][0]["pos"]
		best = Vector3(s[0], s[1], s[2])
	if flying:
		set_flying(false)
	teleport(best)
	show_notice(message)


func viewer_position() -> Vector3:
	return flight_camera.global_position if flying else player.global_position


func in_bounds(p: Vector3) -> bool:
	for poly in boundary:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
			return true
	return false


func district_at(p: Vector3) -> String:
	for d in index["districts"]:
		for ring in d["polygon"]:
			var poly := PackedVector2Array()
			for q in ring:
				poly.append(Vector2(q[0], q[1]))
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
				return d["name"]
	return "outside Kowloon"


func _process(delta: float) -> void:
	if index.is_empty():
		return
	_apply_results(3)
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.1
		_update_streaming(false)
	if flying:
		_fly(delta)
	elif awaiting_ground:
		_try_land()
	else:
		_walk_guards()
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0:
			notice.text = ""
	_update_hud()


func _fly(delta: float) -> void:
	if overview.visible or get_tree().paused:
		return
	var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := flight_camera.global_basis * Vector3(axes.x, 0, axes.y)
	dir.y += Input.get_axis("world_down", "world_up")
	var speed := 160.0 if Input.is_action_pressed("world_fast") else 35.0
	flight_camera.global_position += dir * speed * delta


func _try_land() -> void:
	var key := _chunk_key(player.global_position)
	if chunks.has(key) and chunks[key].get("body") != null:
		if get_meta("drop_from_above", false):
			var space := get_world_3d().direct_space_state
			var p := player.global_position
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 900, p.z), Vector3(p.x, -60, p.z))
			var hit := space.intersect_ray(q)
			if hit:
				player.global_position = hit["position"] + Vector3(0, 0.1, 0)
			set_meta("drop_from_above", false)
		awaiting_ground = false
		last_safe = player.global_position
		player.movement_enabled = not overview.visible and not get_tree().paused
	elif not chunks.has(key) and not index["chunks"].has(key):
		recover("No surveyed ground here")


func _walk_guards() -> void:
	var p := player.global_position
	if p.y < sea_level - 0.8 or p.y < -40.0:
		recover("The water is too deep here — returned to a safe street")
	elif not in_bounds(p):
		player.global_position = last_safe
		player.velocity = Vector3.ZERO
		show_notice("Edge of the surveyed Kowloon area")
	elif player.is_on_floor():
		last_safe = p


func _update_hud() -> void:
	var p := viewer_position()
	var mode := "DEVELOPER FLIGHT (inspection tool, Shift fast, Space/Ctrl up/down)" if flying else ("Waiting for ground…" if awaiting_ground else "Walking")
	hud.text = "%s\n%s · x %.0f  y %.1f  z %.0f\nFPS %d · chunks near %d / far %d · collision %d · static mem %.0f MiB\nM map · F flight · R recover · [ ] district jumps · Esc pause" % [
		mode, district_at(p), p.x, p.y, p.z, Engine.get_frames_per_second(), stats["loaded_near"], stats["loaded_far"],
		stats["bodies"], Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]


# ------------------------------------------------------------------ streaming
func _chunk_key(p: Vector3) -> String:
	return "%d_%d" % [floori(p.x / chunk_size), floori(p.z / chunk_size)]


func _rect_distance(i: int, j: int, p: Vector3) -> float:
	var x0 := i * chunk_size
	var z0 := j * chunk_size
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + chunk_size))
	var dz := maxf(maxf(z0 - p.z, 0.0), p.z - (z0 + chunk_size))
	return sqrt(dx * dx + dz * dz)


func _update_streaming(immediate: bool) -> void:
	var p := viewer_position()
	var reach := int(ceil(far_radius / chunk_size)) + 1
	var ci := floori(p.x / chunk_size)
	var cj := floori(p.z / chunk_size)
	var want: Array = []
	for i in range(ci - reach, ci + reach + 1):
		for j in range(cj - reach, cj + reach + 1):
			var key := "%d_%d" % [i, j]
			if not index["chunks"].has(key):
				continue
			var d := _rect_distance(i, j, p)
			if d <= far_radius:
				want.append([d, key, i, j])
	want.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var missing := 0
	for w in want:
		var key: String = w[1]
		if not chunks.has(key):
			chunks[key] = {"i": w[2], "j": w[3], "near": null, "far": null, "body": null}
		var d: float = w[0]
		var c: Dictionary = chunks[key]
		if d <= near_radius and c["near"] == null:
			missing += 1
			_request("n_" + key, d <= collision_radius + 64.0)
		if c["far"] == null:
			missing += 1
			_request("f_" + key, false)
	stats["missing"] = missing
	# unload with hysteresis so the boundary does not thrash
	for key in chunks.keys():
		var c: Dictionary = chunks[key]
		var d := _rect_distance(c["i"], c["j"], p)
		if c["near"] != null and d > near_radius * 1.25:
			_drop_near(c)
		elif c["body"] != null and d > collision_radius * 1.5:
			c["body"].queue_free()
			c["body"] = null
			stats["bodies"] -= 1
		elif c["body"] == null and c["near"] != null and d <= collision_radius and c.get("near_data") != null:
			_build_collision(c)
		if d > far_radius * 1.15:
			_drop_near(c)
			if c["far"] != null:
				c["far"].queue_free()
				stats["loaded_far"] -= 1
			chunks.erase(key)
			stats["unloads"] += 1
	if immediate:
		_apply_results(1000)


func _request(file_key: String, collision: bool) -> void:
	if pending.has(file_key) or pending.size() >= max_parallel_loads * 8:
		return
	var path := DATA_DIR + "chunks/" + file_key + ".bin"
	var task := WorkerThreadPool.add_task(_load_task.bind(file_key, path, collision), false, "chunk " + file_key)
	pending[file_key] = task


func _load_task(file_key: String, path: String, collision: bool) -> void:
	var data := ChunkData.load_file(path, collision or file_key.begins_with("n_"))
	results_mutex.lock()
	results[file_key] = data
	results_mutex.unlock()


## Attaches finished loads to the scene tree; budget limits per-frame hitches.
func _apply_results(budget: int) -> void:
	results_mutex.lock()
	var ready_keys := results.keys()
	results_mutex.unlock()
	for file_key in ready_keys:
		if budget <= 0:
			break
		results_mutex.lock()
		var data: ChunkData = results[file_key]
		results.erase(file_key)
		results_mutex.unlock()
		WorkerThreadPool.wait_for_task_completion(pending[file_key])
		pending.erase(file_key)
		var key := (file_key as String).substr(2)
		if not chunks.has(key) or not data.ok:
			continue
		var c: Dictionary = chunks[key]
		var near: bool = (file_key as String).begins_with("n_")
		if (near and c["near"] != null) or (not near and c["far"] != null):
			continue
		data.build_resources(assets.materials, assets.instance_meshes)
		var node := _instantiate(data, near)
		node.name = file_key
		chunk_root.add_child(node)
		budget -= 1
		if near:
			c["near"] = node
			c["near_data"] = data
			stats["loaded_near"] += 1
			if c["far"] != null:
				c["far"].visible = false
			if _rect_distance(c["i"], c["j"], viewer_position()) <= collision_radius + 64.0:
				_build_collision(c)
		else:
			c["far"] = node
			node.visible = c["near"] == null
			stats["loaded_far"] += 1


func _instantiate(data: ChunkData, near: bool) -> Node3D:
	var root := Node3D.new()
	for mesh in data.meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if not near:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for mm in data.multimeshes:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# small ground cover fades out early; trees stay to the near-ring edge
		var grass := mm.mesh == assets.instance_meshes[3] or mm.mesh == assets.instance_meshes[8] or mm.mesh == assets.instance_meshes[2]
		mmi.visibility_range_end = 140.0 if grass else 0.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if grass or not near else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)
	return root


func _build_collision(c: Dictionary) -> void:
	var data: ChunkData = c.get("near_data")
	if data == null or c["body"] != null:
		return
	var body := StaticBody3D.new()
	for faces in data.collide_faces:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	var b := data.boxes
	for k in range(0, b.size(), 7):
		var shape := BoxShape3D.new()
		shape.size = Vector3(b[k + 3], b[k + 4], b[k + 5]) * 2.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.UP, b[k + 6]), Vector3(b[k], b[k + 1], b[k + 2]))
		body.add_child(cs)
	chunk_root.add_child(body)
	c["body"] = body
	stats["bodies"] += 1


func _drop_near(c: Dictionary) -> void:
	if c["near"] == null:
		return
	c["near"].queue_free()
	c["near"] = null
	c["near_data"] = null
	stats["loaded_near"] -= 1
	if c["body"] != null:
		c["body"].queue_free()
		c["body"] = null
		stats["bodies"] -= 1
	if c["far"] != null:
		c["far"].visible = true
