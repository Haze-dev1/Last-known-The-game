extends SceneTree

const Chapter = preload("res://chapters/chapter_01/chapter_01.gd")
const Scene = preload("res://chapters/chapter_01/chapter_01.tscn")
var chapter: Chapter
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func captured() -> bool:
	# The dummy display driver cannot capture a pointer. Desktop runs assert it.
	return DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var result: Error = root.get_texture().get_image().save_png("/tmp/" + filename)
		check(result == OK, "graphical frame captured: " + filename)

func aim(from: Vector3, at: Vector3) -> void:
	chapter.player.position = from
	chapter.player.rotation = Vector3.ZERO
	chapter.player.camera.rotation = Vector3.ZERO
	chapter.player.camera.look_at(at)
	await frames(3)

func add_chapter() -> void:
	chapter = Scene.instantiate() as Chapter
	chapter.checkpoint_path = "user://checks/foundation.json"
	root.add_child(chapter)
	chapter.start_new_game()
	# Test automation must not depend on the desktop keeping this window focused.
	# The focus-loss handler is exercised explicitly below; native focus is manual.
	root.focus_exited.disconnect(chapter._on_focus_lost)

func _run() -> void:
	add_chapter()
	await process_frame
	check(chapter.mode == Chapter.Mode.ARRIVAL and not chapter.player.movement_enabled, "arrival owns input")
	await create_timer(3.2).timeout
	check(chapter.mode == Chapter.Mode.WALK, "arrival naturally completes")
	var natural: Vector3 = chapter.player.position
	# Fresh scene tests the public skip input rather than calling the completion helper.
	chapter.queue_free()
	await process_frame
	add_chapter()
	await process_frame
	await key(KEY_E)
	check(chapter.mode == Chapter.Mode.WALK and chapter.player.position.distance_to(natural) < 0.1, "E skip and natural arrival restore same position")
	check(chapter.player.movement_enabled and captured(), "arrival restores movement and capture")
	await screenshot("last-known-street.png")
	chapter.player.rotation = Vector3.ZERO
	chapter.player.camera.rotation = Vector3.ZERO
	# Walk from the street, through the real entrance, to the workbench.
	Input.action_press("move_forward")
	await frames(400)
	Input.action_release("move_forward")
	await frames(2)
	check(chapter.player.position.z < -6.0 and chapter.player.position.z > -7.8, "WASD path crosses entrance and workbench collision stops movement")
	check(chapter.player.interaction_target() == "computer", "real raycast reaches computer")
	await key(KEY_E)
	check(not chapter.powered and chapter.mode == Chapter.Mode.WALK and chapter.evidence.is_empty(), "unpowered access rejected")
	check(chapter.feedback.text.begins_with("No power"), "no-power feedback shown")
	await screenshot("last-known-shop.png")
	await aim(Vector3(2.8, 0.02, 1.1), Vector3(2.8, 0.9, -0.8))
	check(chapter.player.interaction_target() == "power", "raycast reaches supply")
	await key(KEY_E)
	await key(KEY_E)
	check(chapter.powered and chapter.evidence.is_empty(), "reusable supply enables power without collecting clue")
	await aim(Vector3(0, 0.02, -6.5), Vector3(0, 1.45, -8.35))
	await key(KEY_E)
	check(chapter.mode == Chapter.Mode.COMPUTER and chapter.evidence == [Chapter.CLUE_ID], "powered computer opens and collects exactly one clue")
	check(not chapter.player.movement_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "computer releases capture and blocks movement")
	var stopped: Vector3 = chapter.player.position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(chapter.player.position.is_equal_approx(stopped), "held movement cannot move during computer interface")
	await screenshot("last-known-clue.png")
	await key(KEY_ESCAPE)
	check(chapter.mode == Chapter.Mode.WALK and captured(), "Escape leaves computer and recaptures mouse")
	await key(KEY_E)
	check(chapter.evidence.size() == 1, "repeated read does not duplicate clue")
	chapter.close_button.pressed.emit()
	check(chapter.mode == Chapter.Mode.WALK, "computer close button returns to walk")
	await key(KEY_ESCAPE)
	check(paused and chapter.mode == Chapter.Mode.PAUSE and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape pauses and releases mouse")
	stopped = chapter.player.position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(chapter.player.position.is_equal_approx(stopped), "pause blocks held movement")
	# Find the actual slider by type; changing it exercises the connected setting signal.
	for item: Node in chapter.pause_panel.get_child(0).get_children():
		if item is HSlider:
			(item as HSlider).value = 0.004
	check(is_equal_approx(chapter.player.mouse_sensitivity, 0.004), "sensitivity slider updates controller")
	await screenshot("last-known-pause.png")
	await key(KEY_ESCAPE)
	check(not paused and chapter.player.movement_enabled and captured(), "Escape resumes and recaptures mouse")
	var yaw: float = chapter.player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 0)
	Input.parse_input_event(motion)
	await process_frame
	if DisplayServer.get_name() != "headless":
		check(not is_equal_approx(yaw, chapter.player.rotation.y), "mouse motion changes first-person look")
	else:
		print("PENDING in headless: pointer capture and mouse look; run graphical check")
	# Exterior service margins must also have floor and a closed rear boundary.
	await aim(Vector3(5.5, 0.02, -1), Vector3(5.5, 1.62, -9))
	Input.action_press("move_forward")
	await frames(200)
	Input.action_release("move_forward")
	check(chapter.player.position.y > -0.1, "service margin has continuous collision floor")
	Input.action_press("move_forward")
	await frames(100)
	Input.action_release("move_forward")
	check(chapter.player.position.z > -9.7 and chapter.player.position.z < -9.0 and chapter.player.position.y > -0.1, "rear boundary prevents leaving the blockout")
	# A facade must occlude interaction; proximity alone must never grant access.
	await aim(Vector3(2.8, 0.02, -3.3), Vector3(2.8, 0.9, -0.8))
	check(chapter.player.interaction_target().is_empty(), "shop front wall occludes supply interaction")
	chapter._on_focus_lost()
	check(chapter.mode == Chapter.Mode.PAUSE, "focus loss pauses walking")
	chapter.resume_button.pressed.emit()
	check(chapter.mode == Chapter.Mode.WALK and not paused, "resume button restores walking")
	# Separate fresh state covers discovering power before inspecting the computer.
	chapter.queue_free()
	await process_frame
	add_chapter()
	await process_frame
	await key(KEY_ESCAPE)
	check(chapter.mode == Chapter.Mode.WALK, "Escape also skips arrival")
	await aim(Vector3(2.8, 0.02, 1.1), Vector3(2.8, 0.9, -0.8))
	await key(KEY_E)
	await aim(Vector3(0, 0.02, -6.5), Vector3(0, 1.45, -8.35))
	await key(KEY_E)
	check(chapter.evidence.size() == 1 and chapter.mode == Chapter.Mode.COMPUTER, "power-first discovery stays consistent")
	chapter.queue_free()
	await process_frame
	print("FOUNDATION CHECK: %d failures" % failures)
	quit(0 if failures == 0 else 1)
