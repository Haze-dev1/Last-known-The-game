extends SceneTree

const Scene = preload("res://chapters/chapter_01/chapter_01.tscn")
const Chapter = preload("res://chapters/chapter_01/chapter_01.gd")
const PATH := "user://checks/process-restart.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var chapter: Chapter = Scene.instantiate() as Chapter
	chapter.checkpoint_path = PATH
	root.add_child(chapter)
	root.focus_exited.disconnect(chapter._on_focus_lost)
	var write_phase: bool = OS.get_cmdline_user_args().has("write")
	if write_phase:
		chapter.start_new_game()
		chapter.finish_arrival()
		chapter.interact("power")
		chapter.interact("computer")
		chapter.close_record()
		chapter.sensitivity_slider.value = 0.0035
		if not chapter.save_checkpoint():
			push_error("PROCESS CHECK: write failed")
			quit(1)
			return
		print("PROCESS CHECK: written powered checkpoint with one clue and sensitivity")
	else:
		chapter.continue_game()
		var valid: bool = chapter.mode == Chapter.Mode.WALK and chapter.powered and chapter.evidence == [Chapter.CLUE_ID] and is_equal_approx(chapter.player.mouse_sensitivity, 0.0035)
		if not valid:
			push_error("PROCESS CHECK: fresh process did not restore checkpoint")
			quit(1)
			return
		if not chapter.checkpoint.clear(PATH):
			push_error("PROCESS CHECK: test cleanup failed")
			quit(1)
			return
		print("PROCESS CHECK: fresh process restored power, unique clue, input and sensitivity")
	chapter.queue_free()
	quit(0)
