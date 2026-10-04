extends SceneTree
## Kowloon world checks against the real streamed scene.
##   godot --headless --path game --script res://tests/world_check.gd
##   godot --path game --script res://tests/world_check.gd              (graphical, adds timing)
##   godot --path game --script res://tests/world_check.gd -- capture   (screenshots + route benchmark)

const Scene = preload("res://world/world.tscn")
var world: Node3D
var failures := 0
var out_dir := "/tmp/last-known-world"


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func frames(count: int) -> void:
	for _i in count:
		await process_frame


func wait_landed(limit_s: float = 20.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while world.awaiting_ground and Time.get_ticks_msec() - t0 < limit_s * 1000.0:
		await process_frame
	await physics_frame
	await physics_frame
	return not world.awaiting_ground


func wait_streamed(limit_s: float = 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit_s * 1000.0:
		await process_frame
		if world.pending.is_empty() and world.results.is_empty() and world.stats["missing"] == 0:
			await frames(3)
			if world.pending.is_empty():
				return


func ground_below(p: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p + Vector3(0, -6.0, 0))
	q.exclude = [world.player.get_rid()]
	return not space.intersect_ray(q).is_empty()


func mem_mib() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0


func hold(action: String, seconds: float) -> void:
	# Re-assert every frame: Godot releases held actions when the native window loses focus.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		Input.action_press(action)
		await physics_frame
	Input.action_release(action)


func _run() -> void:
	var capture := OS.get_cmdline_user_args().has("capture")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var t_load := Time.get_ticks_msec()
	world = Scene.instantiate()
	root.add_child(world)
	world.player.set_process_unhandled_input(false)  # native pointer must not steer scripted routes
	check(not world.index.is_empty(), "world index loaded")
	check(world.index["chunks"].size() > 800, "chunk index covers Kowloon (%d chunks)" % world.index["chunks"].size())
	var landed := await wait_landed(30.0)
	print("INFO: first landing after %d ms" % (Time.get_ticks_msec() - t_load))
	check(landed, "initial spawn receives collision and walking is enabled")
	if OS.get_cmdline_user_args().has("diag"):
		await _diag()
		quit(0)
		return
	if OS.get_cmdline_user_args().has("bench"):
		await _bench()
		print("WORLD CHECK: %d failures" % failures)
		quit(1 if failures > 0 else 0)
		return
	if OS.get_cmdline_user_args().has("capture-only"):
		await _capture()
		print("WORLD CHECK: %d failures" % failures)
		quit(1 if failures > 0 else 0)
		return
	check(ground_below(world.player.global_position), "ground collision under initial spawn")
	await wait_streamed()
	print("INFO: start area streamed after %d ms; near %d far %d" % [Time.get_ticks_msec() - t_load, world.stats["loaded_near"], world.stats["loaded_far"]])

	# --- every district jump point, twice: landing, ground, bounded streaming memory
	var jumps: Array = world.index["jump_points"]
	var peak_first := 0.0
	var peak_second := 0.0
	var max_near := 0
	var districts := {}
	for lap in 2:
		for k in jumps.size():
			world.jump_to(k)
			var ok := await wait_landed(20.0)
			var p: Vector3 = world.player.global_position
			if lap == 0:
				check(ok and ground_below(p), "jump %s lands on collision" % jumps[k]["name"])
				check(world.in_bounds(p), "jump %s inside coverage boundary" % jumps[k]["name"])
				districts[jumps[k]["district"]] = true
			await frames(2)
			max_near = maxi(max_near, world.stats["loaded_near"])
			if lap == 0:
				peak_first = maxf(peak_first, mem_mib())
			else:
				peak_second = maxf(peak_second, mem_mib())
	print("INFO: static memory peak lap1 %.0f MiB, lap2 %.0f MiB; max near chunks %d; unloads %d" % [peak_first, peak_second, max_near, world.stats["unloads"]])
	check(districts.size() == 5, "jump points reach all five Kowloon districts (%s)" % ", ".join(districts.keys()))
	check(peak_second <= peak_first * 1.15 + 64.0, "revisiting all districts does not accumulate memory")
	check(max_near <= 30, "near ring stays within the hysteresis bound of 30 chunks (%d)" % max_near)
	check(world.stats["unloads"] > 50, "distant chunks unload during district travel")
	var orphan_bodies := 0
	for key in world.chunks:
		var c: Dictionary = world.chunks[key]
		if c["body"] != null and world._rect_distance(c["i"], c["j"], world.viewer_position()) > world.collision_radius * 1.5:
			orphan_bodies += 1
	check(orphan_bodies == 0, "no stale collision bodies outside the collision ring")

	# --- walking: several districts, four headings each; count chunk-boundary crossings and falls
	var walk_names := ["Mong Kok", "Sham Shui Po", "Kwun Tong", "Kowloon City", "Wong Tai Sin", "Tsim Sha Tsui", "Ho Man Tin", "Sau Mau Ping"]
	var crossings := 0
	var falls := 0
	var best_moves := []
	for n in walk_names:
		var k: int = world._jump_named(n)
		var best := 0.0
		for heading in 4:
			world.jump_to(k)
			await wait_landed(20.0)
			world.player.rotation.y = heading * PI / 2.0
			var start: Vector3 = world.player.global_position
			var start_key: String = world._chunk_key(start)
			await hold("move_forward", 4.0)
			var end: Vector3 = world.player.global_position
			var moved := Vector2(end.x - start.x, end.z - start.z).length()
			best = maxf(best, moved)
			if world._chunk_key(end) != start_key:
				crossings += 1
			if not ground_below(end) or world.awaiting_ground or end.y < -20.0:
				falls += 1
				print("INFO: fall at %s heading %d: %s -> %s awaiting %s" % [n, heading, str(start), str(end), str(world.awaiting_ground)])
		best_moves.append("%s %.1f m" % [n, best])
		print("INFO: %s descent/climb per heading recorded in-route; final y %.1f" % [n, world.player.global_position.y])
		check(best > 6.0, "walking moves through %s (best %.1f m in 4 s; steep estates are slower)" % [n, best])
	print("INFO: walk distances " + ", ".join(best_moves))
	check(falls == 0, "walking never fell through the world (%d)" % falls)
	print("INFO: chunk boundary crossings while walking: %d" % crossings)

	# --- deliberate chunk-seam walk: start 6 m before a boundary on a street, walk across
	var seam_ok := false
	for key in world.index["safe_points"]:
		var parts: PackedStringArray = (key as String).split("_")
		for sp in world.index["safe_points"][key]:
			var x0: float = int(parts[0]) * world.chunk_size
			if absf(sp[0] - x0) < 14.0:
				world.teleport(Vector3(sp[0], sp[1], sp[2]))
				await wait_landed(20.0)
				var dir := -1.0 if sp[0] > x0 else 1.0
				world.player.rotation.y = -dir * PI / 2.0  # face across the seam (+x is -z rotated)
				var s0: String = world._chunk_key(world.player.global_position)
				var y0: float = world.player.global_position.y
				await hold("move_forward", 6.0)
				var p: Vector3 = world.player.global_position
				if world._chunk_key(p) != s0 and p.y > y0 - 4.0 and not world.awaiting_ground:
					seam_ok = true
			if seam_ok:
				break
		if seam_ok:
			break
	check(seam_ok, "walked across a chunk seam on a street without falling")

	# --- boundary and recovery
	world.player.global_position = Vector3(-12000, 5, 0)
	await frames(3)
	check(world.in_bounds(world.player.global_position) or world.awaiting_ground, "leaving the coverage polygon returns the walker")
	world.player.global_position = Vector3(0, -80, 0)
	await frames(3)
	var rec := await wait_landed(20.0)
	check(rec and world.player.global_position.y > -10.0, "falling below the world recovers to a safe street")
	world.recover("check")
	check(await wait_landed(20.0), "manual recovery lands on collision")

	# --- developer flight across the whole city, west to east and back
	world.set_flying(true)
	check(world.flying and world.flight_camera.current, "developer flight mode active")
	var west := Vector3(-5600, 420, 0)
	var east := Vector3(6300, 420, -1500)
	var t_route := Time.get_ticks_msec()
	var frame_ms: Array[float] = []
	for leg in [[west, east], [east, west]]:
		for s in 120:
			world.flight_camera.global_position = (leg[0] as Vector3).lerp(leg[1], s / 119.0)
			var tf := Time.get_ticks_usec()
			await process_frame
			frame_ms.append((Time.get_ticks_usec() - tf) / 1000.0)
	frame_ms.sort()
	print("INFO: flight sweep %d ms, median frame %.1f ms, p95 %.1f ms, near %d far %d, mem %.0f MiB" % [
		Time.get_ticks_msec() - t_route, frame_ms[frame_ms.size() / 2], frame_ms[int(frame_ms.size() * 0.95)],
		world.stats["loaded_near"], world.stats["loaded_far"], mem_mib()])
	check(world.stats["loaded_near"] <= 30, "flight sweep keeps near ring bounded")
	world.set_flying(false)
	check(await wait_landed(20.0), "landing from flight finds ground")

	if capture:
		await _capture()

	print("WORLD CHECK: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## Screenshots of representative places plus a timed walking-height route.
func _capture() -> void:
	var shots := [
		# name, camera position, look-at target, flying
		["aerial_overview", Vector3(-600, 1500, 3600), Vector3(300, 0, -400), true],
		["mong_kok_street", "Mong Kok", Vector3.ZERO, false],
		["sham_shui_po_street", "Sham Shui Po", Vector3.ZERO, false],
		["kwun_tong_industrial", "Kwun Tong Business Area", Vector3.ZERO, false],
		["tsim_sha_tsui_waterfront", Vector3(-1250, 22, 2950), Vector3(-1150, 8, 2350), true],
		["kai_tak_aerial", Vector3(2400, 260, 800), Vector3(3400, 0, 1600), true],
		["lion_rock_slopes", Vector3(250, 280, -2550), Vector3(330, 380, -3780), true],
		["wong_tai_sin_estate", "Wong Tai Sin", Vector3.ZERO, false],
		["kowloon_city_park", "Kowloon City", Vector3.ZERO, false],
		["mong_kok_aerial", Vector3(-1000, 140, 300), Vector3(-1500, 20, -400), true],
	]
	for s in shots:
		print("INFO: preparing %s" % s[0])
		if s[1] is String:
			world.set_flying(false)
			world.jump_to(world._jump_named(s[1]))
			await wait_landed(20.0)
			await wait_streamed()
			world.player.rotation.y = _open_heading()
			world.player.camera.rotation.x = 0.08
		else:
			world.set_flying(true)
			world.flight_camera.global_position = s[1]
			world.flight_camera.look_at(s[2])
			world._update_streaming(true)
			await wait_streamed()
		await frames(30)
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, s[0]])
		print("INFO: captured %s at %s (fps %d) t=%d ms" % [s[0], str(world.viewer_position()), Engine.get_frames_per_second(), Time.get_ticks_msec()])
	# walking-height frame timing in a dense street
	world.set_flying(false)
	world.jump_to(world._jump_named("Mong Kok"))
	await wait_landed(20.0)
	await wait_streamed()
	var times: Array[float] = []
	for heading in 8:
		world.player.rotation.y = heading * PI / 4.0
		for f in 90:
			var tf := Time.get_ticks_usec()
			await process_frame
			times.append((Time.get_ticks_usec() - tf) / 1000.0)
	times.sort()
	print("INFO: dense street (Mong Kok) 720 frames: median %.2f ms, p95 %.2f ms, max %.2f ms, viewport %s" % [
		times[times.size() / 2], times[int(times.size() * 0.95)], times[-1], str(root.get_visible_rect().size)])


## Heading with the longest clear line of sight at eye height (a street, not a wall).
func _open_heading() -> float:
	var space := world.get_world_3d().direct_space_state
	var p: Vector3 = world.player.global_position + Vector3(0, 1.6, 0)
	var best := 0.0
	var best_d := -1.0
	for k in 16:
		var a := k * TAU / 16.0
		var dir := Vector3(-sin(a), 0, -cos(a))
		var q := PhysicsRayQueryParameters3D.create(p, p + dir * 200.0)
		q.exclude = [world.player.get_rid()]
		var hit := space.intersect_ray(q)
		var d := 200.0 if hit.is_empty() else p.distance_to(hit["position"])
		if d > best_d:
			best_d = d
			best = a
	return best


func _stats(label: String, times: Array[float]) -> void:
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	print("BENCH: %s: %d frames, mean %.2f ms (%.0f FPS), median %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.2f ms, mem %.0f MiB, near %d far %d" % [
		label, times.size(), total / times.size(), 1000.0 * times.size() / total, times[times.size() / 2],
		times[int(times.size() * 0.95)], times[int(times.size() * 0.99)], times[-1], mem_mib(),
		world.stats["loaded_near"], world.stats["loaded_far"]])


## 1080p, vsync off: dense street, a walking route, a low flight across the city, and jump load times.
func _bench() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Tiling window managers ignore window_set_size; fullscreen gives the monitor's native size.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await frames(30)
	# render the 3D view at 1920x1080 regardless of the panel size (UI stays native)
	var win := DisplayServer.window_get_size()
	world.render_scale = clampf(1920.0 / win.x, 0.25, 1.0)
	world.apply_quality(world.quality)
	await frames(10)
	print("BENCH: window %s, 3D render %dx%d (scale %.3f), renderer %s, adapter %s" % [str(win), int(win.x * world.render_scale), int(win.y * world.render_scale), world.render_scale, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	for level in 3:
		world.apply_quality(level)
		world.jump_to(world._jump_named("Mong Kok"))
		await wait_landed(20.0)
		await wait_streamed()
		var qt: Array[float] = []
		for heading in 8:
			world.player.rotation.y = heading * PI / 4.0
			for f in 90:
				var tq := Time.get_ticks_usec()
				await process_frame
				qt.append((Time.get_ticks_usec() - tq) / 1000.0)
		_stats("quality %s, dense street Mong Kok 360 deg" % ["low", "medium", "high"][level], qt)
	world.apply_quality(1)
	world.jump_to(world._jump_named("Mong Kok"))
	await wait_landed(20.0)
	await wait_streamed()
	var times: Array[float] = []
	for heading in 8:
		world.player.rotation.y = heading * PI / 4.0
		for f in 120:
			var tf := Time.get_ticks_usec()
			await process_frame
			times.append((Time.get_ticks_usec() - tf) / 1000.0)
	_stats("dense street Mong Kok standing 360 deg", times)
	times = []
	world.player.rotation.y = _open_heading()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		Input.action_press("move_forward")
		var tf := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec() - tf) / 1000.0)
	Input.action_release("move_forward")
	_stats("walking route 20 s from Mong Kok", times)
	world.set_flying(true)
	times = []
	var a := Vector3(-4500, 120, -1500)
	var b := Vector3(5200, 120, 600)
	world.flight_camera.global_position = a
	world.flight_camera.look_at(b)
	for s in 1800:
		world.flight_camera.global_position = a.lerp(b, s / 1799.0)
		var tf := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec() - tf) / 1000.0)
	_stats("low flight 120 m across Kowloon west-east (~5.4 m/frame)", times)
	world.set_flying(false)
	await wait_landed(20.0)
	var loads: Array[float] = []
	for n in ["Sham Shui Po", "Kwun Tong", "Tsim Sha Tsui", "Wong Tai Sin", "Kai Tak", "Lai Chi Kok", "Lam Tin", "Hung Hom"]:
		var tj := Time.get_ticks_msec()
		world.jump_to(world._jump_named(n))
		await wait_landed(20.0)
		var landed_ms := Time.get_ticks_msec() - tj
		await wait_streamed()
		loads.append(Time.get_ticks_msec() - tj)
		print("BENCH: jump %s: walkable after %d ms, surroundings streamed after %d ms" % [n, landed_ms, loads[-1]])


func _ms(frames_n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for f in frames_n:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames_n


## Frame-time attribution at a street: toggles one feature at a time.
func _diag() -> void:
	world.jump_to(world._jump_named("Mong Kok"))
	await wait_landed(20.0)
	await wait_streamed()
	world.player.rotation.y = _open_heading()
	await frames(20)
	print("DIAG: baseline %.1f ms" % await _ms(30))
	var env: Environment = world.environment
	var multis := []
	for n in world.chunk_root.get_children():
		for c in n.get_children():
			if c is MultiMeshInstance3D:
				multis.append(c)
	for m in multis: m.visible = false
	print("DIAG: instances hidden %.1f ms" % await _ms(30))
	for m in multis: m.visible = true
	world.sun_light.shadow_enabled = false
	print("DIAG: sun shadows off %.1f ms" % await _ms(30))
	world.sun_light.shadow_enabled = true
	env.volumetric_fog_enabled = false
	print("DIAG: volumetric off %.1f ms" % await _ms(30))
	env.ssr_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	print("DIAG: + ssr/ssao/ssil off %.1f ms" % await _ms(30))
	var ivy: Material = world.assets.materials[8]
	for n in world.chunk_root.get_children():
		for c in n.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh.surface_get_material(0) == ivy:
				c.visible = false
	print("DIAG: + ivy hidden %.1f ms" % await _ms(30))
	var facade: Material = world.assets.materials[3]
	for n in world.chunk_root.get_children():
		for c in n.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh.surface_get_material(0) == facade:
				c.visible = false
	print("DIAG: + facades hidden %.1f ms" % await _ms(30))
