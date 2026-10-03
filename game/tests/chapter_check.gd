extends SceneTree

const Chapter = preload("res://chapters/chapter_01/chapter_01.gd")
const Scene = preload("res://chapters/chapter_01/chapter_01.tscn")
const Checkpoint = preload("res://chapters/chapter_01/checkpoint.gd")
const PATH := "user://checks/chapter.json"
var chapter: Chapter
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

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

func add_chapter() -> void:
	chapter = Scene.instantiate() as Chapter
	chapter.checkpoint_path = PATH
	root.add_child(chapter)
	root.focus_exited.disconnect(chapter._on_focus_lost)
	# Native pointer motion must not steer scripted routes; foundation checks mouse look.
	chapter.player.set_process_unhandled_input(false)

func reload_chapter() -> void:
	chapter.queue_free()
	await process_frame
	add_chapter()
	chapter.continue_game()
	await process_frame

func aim(from: Vector3, to: Vector3) -> void:
	chapter.player.position = from
	chapter.player.rotation = Vector3.ZERO
	chapter.player.camera.rotation = Vector3.ZERO
	chapter.player.camera.look_at(to)
	await frames(3)

func read_at(id: String, from: Vector3, to: Vector3) -> void:
	await aim(from, to)
	check(chapter.player.interaction_target() == id, "ray reaches " + id)
	await key(KEY_E)
	check(chapter.mode == Chapter.Mode.COMPUTER and chapter.evidence.has(id), "inspect collects " + id)
	await key(KEY_ESCAPE)
	if chapter.mode == Chapter.Mode.DISCOVERY:
		await key(KEY_E)

func capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/" + filename) == OK, "capture " + filename)

func _run() -> void:
	var store := Checkpoint.new()
	check(store.clear(PATH), "isolated test checkpoint cleared")
	add_chapter()
	check(chapter.mode == Chapter.Mode.START_MENU and chapter.continue_button.disabled, "fresh title has no Continue")
	chapter.new_button.pressed.emit()
	await key(KEY_E)
	await aim(Vector3(0, 0.05, 11.2), Vector3(0, 1.3, 13.5))
	await key(KEY_E)
	check(not chapter.chapter_complete and chapter.mode == Chapter.Mode.WALK, "departure rejected before investigation")
	# Physical street-to-stair traversal, not teleporting across the vertical route.
	chapter.player.position = Vector3(5, 0.05, 1)
	chapter.player.rotation = Vector3.ZERO
	chapter.player.camera.rotation = Vector3.ZERO
	Input.action_press("move_forward")
	await frames(300)
	Input.action_release("move_forward")
	check(chapter.player.position.y > 3.2 and chapter.player.position.z < -8.8, "service stair ascends to apartment landing")
	Input.action_press("move_left")
	await frames(65)
	Input.action_release("move_left")
	check(chapter.player.position.x < 3.0 and chapter.player.position.y > 3.2, "landing doorway enters upstairs apartment")
	await aim(chapter.player.position, Vector3(0, 4.9, -5))
	await capture("last-known-apartment.png")
	# Read upstairs evidence first; it cannot establish survival without the other records.
	await read_at("address_list", Vector3(1.8, 3.45, -2.6), Vector3(1.8, 4.85, -4))
	await read_at("return_photo", Vector3(-2.5, 3.45, -7), Vector3(-2.5, 4.9, -8.5))
	check(not chapter.corroborated() and not chapter.can_depart(), "photo and onward address alone do not prove chronology")
	await key(KEY_J)
	check(chapter.mode == Chapter.Mode.JOURNAL and paused and not chapter.player.movement_enabled, "journal owns input and pauses")
	check(chapter.journal_body.text.contains("unconfirmed"), "journal separates unconfirmed interpretation")
	await capture("last-known-journal-unconfirmed.png")
	await key(KEY_ESCAPE)
	await reload_chapter()
	check(chapter.evidence.size() == 2 and chapter.location == "apartment" and chapter.mode == Chapter.Mode.WALK, "relaunch restores upstairs evidence and safe anchor")
	await read_at("acceptance_letter", Vector3(-2.4, 3.45, -2.6), Vector3(-2.4, 4.5, -3.9))
	check(chapter.evidence.size() == 3 and not chapter.can_depart(), "optional letter never substitutes for prerequisites")
	# Walk back through the doorway and descend the stair route.
	chapter.player.position = Vector3(2.7, 3.45, -9.25)
	chapter.player.rotation = Vector3.ZERO
	chapter.player.camera.rotation = Vector3.ZERO
	Input.action_press("move_right")
	await frames(45)
	Input.action_release("move_right")
	Input.action_press("move_back")
	await frames(220)
	Input.action_release("move_back")
	check(chapter.player.position.y < 0.2 and chapter.player.position.z > 0.5, "service stair descends back to street")
	await read_at("closure_notice", Vector3(-2.7, 0.05, -7.8), Vector3(-2.7, 1.5, -9.65))
	check(not chapter.corroborated(), "physical records still require saved shop note")
	await aim(Vector3(2.8, 0.05, 1.1), Vector3(2.8, 0.9, -0.8))
	await key(KEY_E)
	await reload_chapter()
	check(chapter.powered and chapter.evidence.size() == 4, "power and partial investigation survive relaunch")
	await aim(Vector3(0, 0.05, -6.5), Vector3(0, 1.45, -8.35))
	await key(KEY_E)
	check(chapter.corroborated() and chapter.can_depart() and chapter.mode == Chapter.Mode.COMPUTER, "all essential records enable corroboration and onward lead")
	await key(KEY_ESCAPE)
	check(chapter.mode == Chapter.Mode.DISCOVERY and not chapter.player.movement_enabled, "first corroboration triggers first-person discovery")
	var rotation: Vector3 = chapter.discovery_rotation
	await create_timer(1.8).timeout
	check(chapter.mode == Chapter.Mode.WALK and chapter.player.camera.rotation.is_equal_approx(rotation), "natural discovery restores original camera and input")
	await key(KEY_J)
	check(chapter.journal_body.text.contains("return after") and chapter.journal_body.text.contains("later fate remains unknown"), "journal shows corroborated return without asserting final fate")
	await capture("last-known-journal.png")
	await key(KEY_J)
	await read_at("return_photo", Vector3(-2.5, 3.45, -7), Vector3(-2.5, 4.9, -8.5))
	check(chapter.evidence.size() == 5 and chapter.mode == Chapter.Mode.WALK, "repeated read stays unique and does not replay discovery")
	await key(KEY_ESCAPE)
	chapter.sensitivity_slider.value = 0.004
	await key(KEY_ESCAPE)
	await reload_chapter()
	check(chapter.discovery_seen and is_equal_approx(chapter.player.mouse_sensitivity, 0.004), "discovery flag and sensitivity restored")
	# Verify manual checkpoint state uses a safe anchor even while on the stair.
	chapter.player.position = Vector3(5, 1.8, -5)
	check(chapter.save_checkpoint(), "manual checkpoint saves mid-route")
	await reload_chapter()
	check(chapter.player.position.x < 4.0 and chapter.player.position.y >= 0, "continue avoids restoring inside stair geometry")
	await aim(Vector3(0, 0.05, 11.2), Vector3(0, 1.3, 13.5))
	await key(KEY_E)
	check(chapter.chapter_complete and chapter.mode == Chapter.Mode.ENDING and paused, "departure records chapter completion and ending")
	await capture("last-known-ending.png")
	await reload_chapter()
	check(chapter.chapter_complete and chapter.mode == Chapter.Mode.ENDING and chapter.evidence.size() == 5, "completed chapter restores ending with all evidence")
	await key(KEY_ESCAPE)
	check(chapter.player.movement_enabled and not paused, "ending Escape returns to exploration")
	# A corrupt primary recovers the preceding valid snapshot; corrupt files are never silently reset.
	var corrupt := FileAccess.open(PATH, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var recovered: Dictionary = store.read(PATH)
	check(not recovered.is_empty() and store.message.contains("backup"), "damaged primary recovers valid backup")
	check(store.write(PATH, recovered), "recovered checkpoint can be saved without copying damaged primary")
	var saved: Dictionary = store.read(PATH)
	var inconsistent: Dictionary = saved.duplicate(true)
	inconsistent.evidence = []
	inconsistent.chapter_complete = true
	check(not store.valid(inconsistent), "inconsistent completion rejected")
	inconsistent = saved.duplicate(true)
	inconsistent.evidence.append("unrecognized")
	check(not store.valid(inconsistent), "unknown evidence rejected")
	inconsistent = saved.duplicate(true)
	inconsistent.version = 2
	check(not store.valid(inconsistent), "future schema rejected")
	inconsistent = saved.duplicate(true)
	inconsistent.version = true
	check(not store.valid(inconsistent), "boolean schema version rejected")
	inconsistent = saved.duplicate(true)
	inconsistent.sensitivity = "fast"
	check(not store.valid(inconsistent), "malformed sensitivity rejected")
	var protected: String = "user://checks/chapter-protected.json"
	check(store.clear(protected), "protected test slot cleared")
	check(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(protected)) == OK, "write failure fixture created")
	check(not store.write(protected, saved) and store.message.contains("failed"), "save write failure reports error instead of success")
	var original_path: String = chapter.checkpoint_path
	chapter.checkpoint_path = protected
	await key(KEY_ESCAPE)
	chapter._return_to_menu()
	check(chapter.mode == Chapter.Mode.PAUSE, "failed save prevents leaving unsaved session for title")
	chapter.quit_button.pressed.emit()
	check(chapter.confirming_quit and chapter.quit_button.text.contains("without saving"), "failed Quit save requires explicit unsaved-exit confirmation")
	chapter.checkpoint_path = original_path
	await key(KEY_ESCAPE)
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(protected)) == OK, "failure fixture removed")
	store.clear(protected)
	# Both corrupt files must disable Continue while preserving the files.
	for suffix: String in ["", ".bak"]:
		corrupt = FileAccess.open(PATH + suffix, FileAccess.WRITE)
		corrupt.store_string("invalid")
		corrupt.close()
	chapter.queue_free()
	await process_frame
	add_chapter()
	check(chapter.continue_button.disabled and chapter.start_status.text.contains("preserved"), "unrecoverable checkpoint disables Continue and explains recovery")
	chapter.new_button.pressed.emit()
	check(chapter.mode == Chapter.Mode.START_MENU and FileAccess.file_exists(PATH), "New expedition requires confirmation before replacing progress")
	chapter.new_button.pressed.emit()
	await key(KEY_E)
	check(chapter.evidence.is_empty() and not chapter.powered and not chapter.chapter_complete, "confirmed restart clears only chapter progress")
	# Explicitly verify the discovery skip returns the same pose without replay after restore.
	for id: String in ["closure_notice", "return_photo"]:
		chapter.interact(id)
		chapter.close_record()
	chapter.interact("power")
	chapter.interact("computer")
	chapter.close_record()
	rotation = chapter.player.camera.rotation
	check(chapter.mode == Chapter.Mode.DISCOVERY, "fresh corroboration can trigger discovery again")
	await key(KEY_ESCAPE)
	check(chapter.mode == Chapter.Mode.WALK and chapter.player.camera.rotation.is_equal_approx(rotation), "skipped discovery restores pose and walking")
	chapter.queue_free()
	await process_frame
	store.clear(PATH)
	print("CHAPTER CHECK: %d failures" % failures)
	quit(0 if failures == 0 else 1)
