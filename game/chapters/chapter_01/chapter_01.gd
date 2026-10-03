extends Node3D

const PlayerController = preload("res://player/player.gd")
const Checkpoint = preload("res://chapters/chapter_01/checkpoint.gd")
const START := Vector3(0, 0.05, 10)
const CLUE_ID := "shop_service_note"
const CLUE_TEXT := "SAVED SERVICE NOTE / draft clue\n\nRadios charged at the shop. The collection point changed; see the address list upstairs.\n\nObserved: a saved local note describes repair work and an address list.\nInterpretation: a lead to investigate. Author and chronology are unconfirmed."

const RECORDS: Dictionary = {
	"shop_service_note": ["Saved service note", CLUE_TEXT],
	"closure_notice": ["Utility closure notice / draft", "Observed: a printed station closure notice bears the code N-04. A separate utility handover records the shop receiving the revised notice after the final station departure.\n\nInterpretation: N-04 markings belong to the period after closure. The notice alone says nothing about who was at the shop."],
	"return_photo": ["Shop photograph / text placeholder", "Observed: this protected print shows the missing person reflected in the shop window while repairing a radio. The revised N-04 closure placard is visible behind them.\n\nInterpretation: compare that placard with the utility notice. A face in a photograph and corroborated markings can establish presence; an account timestamp alone cannot.\n\nPlaceholder: the photograph is described here until an approved image is authored."],
	"address_list": ["Apartment address list / draft", "Observed: an upstairs address list redirects station overflow evacuees to a school shelter. A margin note reads: Registry copies travelled with the volunteers. Start at the northern station handover desk.\n\nOnward lead: northern station, then the overflow school shelter. Addresses and evacuation chronology remain provisional."],
	"acceptance_letter": ["Acceptance letter / draft", "Observed: an acceptance letter and a half-packed case suggest plans to study elsewhere before the emergency. A pencilled reminder says: Tell them this is my choice.\n\nInterpretation: the missing person had plans beyond the shop. This letter does not establish their later fate."]
}
const SPAWNS: Dictionary = {"street": START, "shop": Vector3(0, 0.05, -5), "utility": Vector3(-2.7, 0.05, -5), "apartment": Vector3(2.5, 3.5, -8), "departure": Vector3(0, 0.05, 10)}

enum Mode { START_MENU, ARRIVAL, WALK, COMPUTER, PAUSE, JOURNAL, DISCOVERY, ENDING }
var mode: Mode = Mode.START_MENU
var powered: bool = false
var evidence: Array[String] = []
var player: CharacterBody3D
var arrival_time: float = 0.0
var hud: Label
var prompt: Label
var feedback: Label
var screen: PanelContainer
var pause_panel: PanelContainer
var resume_button: Button
var close_button: Button
var crosshair: Label
var monitor_material: StandardMaterial3D
var checkpoint_path: String = "user://chapter_01.json"
var checkpoint := Checkpoint.new()
var loaded_state: Dictionary = {}
var arrival_seen: bool = false
var discovery_seen: bool = false
var chapter_complete: bool = false
var location: String = "street"
var start_panel: PanelContainer
var journal_panel: PanelContainer
var ending_panel: PanelContainer
var record_title: Label
var record_body: Label
var journal_body: Label
var save_status: Label
var start_status: Label
var continue_button: Button
var new_button: Button
var sensitivity_slider: HSlider
var confirming_new: bool = false
var quit_button: Button
var confirming_quit: bool = false
var journal_close_button: Button
var ending_explore_button: Button
var discovery_time: float = 0.0
var discovery_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_input()
	_build_world()
	_build_investigation_rooms()
	player = PlayerController.new()
	player.floor_snap_length = 0.3
	player.name = "Player"
	add_child(player)
	_build_ui()
	player.position = START
	loaded_state = checkpoint.read(checkpoint_path)
	continue_button.disabled = loaded_state.is_empty()
	start_status.text = checkpoint.message
	_set_mode(Mode.START_MENU)
	get_window().focus_exited.connect(_on_focus_lost)

func _configure_input() -> void:
	var bindings: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E, "journal": KEY_J}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match mode:
			Mode.ARRIVAL: finish_arrival()
			Mode.COMPUTER: close_record()
			Mode.PAUSE, Mode.JOURNAL, Mode.ENDING: _set_mode(Mode.WALK)
			Mode.DISCOVERY: finish_discovery()
			Mode.WALK: _set_mode(Mode.PAUSE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if mode == Mode.ARRIVAL:
			finish_arrival()
		elif mode == Mode.DISCOVERY:
			finish_discovery()
		elif mode == Mode.WALK:
			interact(player.interaction_target())
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("journal"):
		if mode == Mode.WALK:
			journal_body.text = journal_text()
			_set_mode(Mode.JOURNAL)
		elif mode == Mode.JOURNAL:
			_set_mode(Mode.WALK)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if mode == Mode.ARRIVAL:
		arrival_time += delta
		player.position = START + Vector3(0, 0, 1.5 * (1.0 - clampf(arrival_time / 3.0, 0, 1)))
		if arrival_time >= 3.0:
			finish_arrival()
	if mode == Mode.DISCOVERY:
		discovery_time += delta
		player.camera.rotation.x = discovery_rotation.x - sin(minf(discovery_time / 1.6, 1.0) * PI) * 0.22
		if discovery_time >= 1.6:
			finish_discovery()
	if mode == Mode.WALK:
		if player.position.y < -3.0:
			player.position = SPAWNS[location]
			player.velocity = Vector3.ZERO
			feedback.text = "Returned to the last safe checkpoint location."
		var target: String = player.interaction_target()
		match target:
			"computer": prompt.text = "E  ·  Inspect workbench computer"
			"power": prompt.text = "E  ·  Connect portable supply" if not powered else "E  ·  Supply connected"
			"closure_notice", "return_photo", "address_list", "acceptance_letter": prompt.text = "E  ·  Inspect " + str(RECORDS[target][0]).split(" /")[0]
			"departure": prompt.text = "E  ·  Leave for the northern station" if can_depart() else "E  ·  Examine onward route"
			_: prompt.text = ""
	hud.text = "LAST KNOWN  /  CHAPTER 1\n" + objective() + "\nEvidence: %d / 4 essential · J journal" % essential_count()


func finish_arrival() -> void:
	player.position = START
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	arrival_seen = true
	_set_mode(Mode.WALK)
	save_checkpoint()

func _set_mode(next_mode: Mode) -> void:
	mode = next_mode
	confirming_quit = false
	quit_button.text = "Quit"
	get_tree().paused = mode in [Mode.START_MENU, Mode.PAUSE, Mode.JOURNAL, Mode.ENDING]
	player.movement_enabled = mode == Mode.WALK
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mode == Mode.WALK else Input.MOUSE_MODE_VISIBLE
	screen.visible = mode == Mode.COMPUTER
	start_panel.visible = mode == Mode.START_MENU
	journal_panel.visible = mode == Mode.JOURNAL
	ending_panel.visible = mode == Mode.ENDING
	pause_panel.visible = mode == Mode.PAUSE
	crosshair.visible = mode == Mode.WALK
	prompt.visible = mode in [Mode.WALK, Mode.ARRIVAL, Mode.DISCOVERY]
	if mode == Mode.ARRIVAL:
		prompt.text = "Arrival  ·  E or Escape to skip"
	elif mode == Mode.DISCOVERY:
		prompt.text = "The records agree · E or Escape to skip"
	elif mode == Mode.START_MENU:
		if continue_button.disabled:
			new_button.grab_focus()
		else:
			continue_button.grab_focus()
	elif mode == Mode.PAUSE:
		resume_button.grab_focus()
	elif mode == Mode.COMPUTER:
		close_button.grab_focus()
	elif mode == Mode.JOURNAL:
		journal_close_button.grab_focus()
	elif mode == Mode.ENDING:
		ending_explore_button.grab_focus()
	else:
		get_viewport().gui_release_focus()

func interact(target: String) -> void:
	if mode != Mode.WALK:
		return
	match target:
		"power":
			powered = true
			monitor_material.emission_enabled = true
			monitor_material.emission = Color(0.15, 0.5, 0.4)
			feedback.text = "Portable supply connected to workbench. Return to the computer."
			save_checkpoint()
		"computer":
			if not powered:
				feedback.text = "No power. Connect the portable supply beside the shop entrance."
				return
			read_record(CLUE_ID)
		"closure_notice", "return_photo", "address_list", "acceptance_letter":
			read_record(target)
		"departure":
			if not can_depart():
				feedback.text = "Before leaving: compare the service note, closure notice and photograph; find the upstairs address list. J opens evidence."
				return
			chapter_complete = true
			location = "departure"
			save_checkpoint(false)
			_set_mode(Mode.ENDING)

func _on_focus_lost() -> void:
	if mode == Mode.ARRIVAL:
		finish_arrival()
	elif mode == Mode.DISCOVERY:
		finish_discovery()
	if mode == Mode.WALK:
		_set_mode(Mode.PAUSE)

func start_new_game() -> void:
	if not checkpoint.clear(checkpoint_path):
		start_status.text = checkpoint.message
		return
	powered = false
	evidence.clear()
	arrival_seen = false
	discovery_seen = false
	chapter_complete = false
	location = "street"
	arrival_time = 0.0
	player.position = START + Vector3(0, 0, 1.5)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	monitor_material.emission_enabled = false
	feedback.text = "WASD walk · Mouse look · E inspect · J journal · Escape pause"
	confirming_new = false
	new_button.text = "New expedition"
	_set_mode(Mode.ARRIVAL)
	save_checkpoint(false)

func _request_new_game() -> void:
	if FileAccess.file_exists(checkpoint_path) or FileAccess.file_exists(checkpoint_path + ".bak"):
		if not confirming_new:
			confirming_new = true
			new_button.text = "Confirm new expedition · replace checkpoint"
			start_status.text = "Your existing chapter checkpoint will be replaced. Continue keeps it."
			return
	start_new_game()

func continue_game() -> void:
	loaded_state = checkpoint.read(checkpoint_path)
	if loaded_state.is_empty():
		start_status.text = checkpoint.message
		continue_button.disabled = true
		return
	powered = loaded_state.powered
	evidence.assign(loaded_state.evidence)
	arrival_seen = loaded_state.arrival_seen
	discovery_seen = loaded_state.discovery_seen
	chapter_complete = loaded_state.chapter_complete
	location = loaded_state.location
	player.mouse_sensitivity = float(loaded_state.sensitivity)
	sensitivity_slider.set_value_no_signal(player.mouse_sensitivity)
	player.position = SPAWNS[location]
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	monitor_material.emission_enabled = powered
	monitor_material.emission = Color(0.15, 0.5, 0.4)
	feedback.text = checkpoint.message if not checkpoint.message.is_empty() else "Checkpoint restored. J opens collected evidence."
	if chapter_complete:
		_set_mode(Mode.ENDING)
	elif arrival_seen:
		_set_mode(Mode.WALK)
	else:
		arrival_time = 0.0
		player.position = START + Vector3(0, 0, 1.5)
		_set_mode(Mode.ARRIVAL)

func save_checkpoint(update_location: bool = true) -> bool:
	if update_location:
		if player.position.y > 3.0:
			location = "apartment"
		elif player.position.z < -2:
			location = "utility" if player.position.x < -1.5 else "shop"
		else:
			location = "street"
	var state: Dictionary = {"version": 1, "chapter": 1, "powered": powered, "evidence": evidence.duplicate(), "arrival_seen": arrival_seen, "discovery_seen": discovery_seen, "chapter_complete": chapter_complete, "location": location, "sensitivity": player.mouse_sensitivity}
	var success: bool = checkpoint.write(checkpoint_path, state)
	save_status.text = checkpoint.message
	if not success:
		feedback.text = checkpoint.message
	return success

func corroborated() -> bool:
	return evidence.has(CLUE_ID) and evidence.has("closure_notice") and evidence.has("return_photo")

func can_depart() -> bool:
	return corroborated() and evidence.has("address_list")

func essential_count() -> int:
	var count: int = 0
	for id: String in [CLUE_ID, "closure_notice", "return_photo", "address_list"]:
		if evidence.has(id):
			count += 1
	return count

func objective() -> String:
	if chapter_complete:
		return "Chapter complete · next lead: northern station"
	if can_depart():
		return "Return to the street departure marker · follow the station lead"
	if corroborated():
		return "Return after closure corroborated · find the upstairs address list"
	if not powered:
		return "Restore workbench power · investigate the shop and rooms"
	return "Compare shop archive, utility notice and upstairs photograph"

func read_record(id: String) -> void:
	if not evidence.has(id):
		evidence.append(id)
	record_title.text = str(RECORDS[id][0])
	record_body.text = str(RECORDS[id][1])
	feedback.text = "Evidence recorded. J opens your journal."
	save_checkpoint()
	_set_mode(Mode.COMPUTER)

func close_record() -> void:
	if corroborated() and not discovery_seen:
		discovery_seen = true
		discovery_time = 0.0
		discovery_rotation = player.camera.rotation
		_set_mode(Mode.DISCOVERY)
		save_checkpoint()
	else:
		_set_mode(Mode.WALK)

func finish_discovery() -> void:
	player.camera.rotation = discovery_rotation
	player.velocity = Vector3.ZERO
	_set_mode(Mode.WALK)

func journal_text() -> String:
	var text: String = "COLLECTED RECORDS\n\n"
	for id: String in evidence:
		text += "• " + str(RECORDS[id][0]) + "\n"
	if evidence.is_empty():
		text += "No records yet.\n"
	text += "\nRECONSTRUCTION\n"
	if corroborated():
		text += "The photograph identifies the missing person at the shop. Its N-04 placard matches the independently documented post-closure notice. Together with the service note, the records support a return after the final station evacuation. Their later fate remains unknown."
	else:
		text += "Authorship and chronology are unconfirmed. Compare the shop note, utility closure notice and upstairs photograph."
	if evidence.has("address_list"):
		text += "\n\nONWARD LEAD: northern station handover desk → overflow school shelter."
	return text

func _sensitivity_changed(value: float) -> void:
	player.mouse_sensitivity = value
	if arrival_seen:
		save_checkpoint()

func _request_quit() -> void:
	if confirming_quit or save_checkpoint():
		get_tree().quit()
	else:
		confirming_quit = true
		quit_button.text = "Quit without saving · checkpoint failed"

func _return_to_menu() -> void:
	if not save_checkpoint():
		return
	loaded_state = checkpoint.read(checkpoint_path)
	continue_button.disabled = loaded_state.is_empty()
	start_status.text = checkpoint.message
	confirming_new = false
	new_button.text = "New expedition"
	_set_mode(Mode.START_MENU)

func _box(label: String, at: Vector3, dimensions: Vector3, color: Color, interaction: String = "", solid: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	add_child(body)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = dimensions
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	if solid:
		body.add_child(shape)
	else:
		shape.free()
	if not interaction.is_empty():
		body.set_meta("interaction", interaction)
	return body

func _sign(text: String, at: Vector3, font_size: int = 32) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.pixel_size = 0.008
	label.modulate = Color(0.8, 0.88, 0.75)
	add_child(label)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.18, 0.24, 0.24)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.73, 0.7)
	environment.ambient_light_energy = 0.65
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color(0.85, 0.88, 0.75)
	sun.shadow_enabled = true
	add_child(sun)
	_box("Street", Vector3(0, -0.15, 7), Vector3(12, 0.3, 18), Color(0.22, 0.27, 0.27))
	_box("ShopFloor", Vector3(0, -0.15, -6), Vector3(12, 0.3, 8), Color(0.37, 0.38, 0.32))
	_box("RearWall", Vector3(0, 1.6, -10), Vector3(12, 3.2, 0.3), Color(0.34, 0.4, 0.36))
	for side: float in [-1.0, 1.0]:
		_box("ShopSide", Vector3(side * 4, 1.6, -6), Vector3(0.3, 3.2, 8), Color(0.34, 0.4, 0.36))
		_box("ShopFront", Vector3(side * 2.7, 1.6, -2), Vector3(2.6, 3.2, 0.3), Color(0.36, 0.43, 0.38))
		_box("StreetFacade", Vector3(side * 7, 4, 2), Vector3(2, 8, 28), Color(0.29, 0.35, 0.34))
		_box("Curb", Vector3(side * 5, 0.05, 3), Vector3(0.25, 0.1, 24), Color(0.48, 0.49, 0.42), "", false)
	_box("Lintel", Vector3(0, 2.9, -2), Vector3(2.8, 0.6, 0.3), Color(0.36, 0.43, 0.38))
	_box("Ceiling", Vector3(0, 3.3, -6), Vector3(8, 0.2, 8), Color(0.3, 0.35, 0.32))
	_box("StreetEnd", Vector3(0, 1.5, 16), Vector3(12, 3, 0.3), Color(0.3, 0.36, 0.33))
	_box("Workbench", Vector3(0, 0.5, -8.4), Vector3(3, 1, 1), Color(0.34, 0.27, 0.2))
	var monitor := _box("Computer", Vector3(0, 1.45, -8.35), Vector3(1.1, 0.8, 0.25), Color(0.09, 0.14, 0.14), "computer")
	monitor_material = (monitor.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	_box("PortableSupply", Vector3(2.8, 0.65, -0.8), Vector3(0.8, 1.3, 0.6), Color(0.63, 0.48, 0.22), "power")
	_sign("REPAIR SHOP", Vector3(0, 2.95, -1.8))
	_sign("PORTABLE SUPPLY\nWorkbench only", Vector3(2.8, 1.8, -0.4), 22)
	_sign("SAVED ARCHIVE", Vector3(0, 2.3, -9.7), 24)
	_sign("Kowloon-inspired placeholder\nNo geographic data imported", Vector3(-2.7, 1.5, -1.8), 16)
	for i: int in range(7):
		_box("Planter", Vector3(-4.5, 0.18, 11 - i * 2.8), Vector3(0.8, 0.36, 0.65), Color(0.27, 0.32, 0.23))
		_box("Growth", Vector3(-4.5, 0.65, 11 - i * 2.8), Vector3(0.55, 0.75, 0.4), Color(0.22, 0.37, 0.25))
	for x: float in [2.7]:
		_box("Shelf", Vector3(x, 1.1, -9), Vector3(1, 2.2, 0.6), Color(0.32, 0.3, 0.24))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, -6)
	lamp.light_color = Color(0.75, 0.8, 0.65)
	lamp.light_energy = 1.2
	lamp.omni_range = 8.0
	add_child(lamp)

func _build_investigation_rooms() -> void:
	_box("UtilityPartition", Vector3(-1.6, 1.35, -8), Vector3(0.2, 2.7, 3.5), Color(0.35, 0.37, 0.32))
	_box("UtilityNotice", Vector3(-2.7, 1.5, -9.65), Vector3(0.8, 0.7, 0.1), Color(0.76, 0.72, 0.52), "closure_notice")
	_sign("UTILITY ROOM · CLOSURE NOTICE", Vector3(-2.7, 2.55, -9.6), 16)
	_sign("APARTMENT ↑\nService stair to right", Vector3(3, 2.3, -1.7), 18)
	# ponytail: smooth convex collision under visual steps; no custom step controller.
	var ramp := StaticBody3D.new()
	ramp.name = "ServiceStairRamp"
	ramp.position = Vector3(5, 0, -5)
	add_child(ramp)
	var collision := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([Vector3(-0.85, 0, 4), Vector3(0.85, 0, 4), Vector3(-0.85, 0, -4), Vector3(0.85, 0, -4), Vector3(-0.85, 3.4, -4), Vector3(0.85, 3.4, -4)])
	collision.shape = wedge
	ramp.add_child(collision)
	for i: int in range(20):
		var height: float = (i + 1) * 0.17
		_box("ServiceStep", Vector3(5, height / 2, -1.2 - i * 0.4), Vector3(1.7, height, 0.4), Color(0.42, 0.44, 0.38), "", false)
	_box("StairOuterRail", Vector3(5.9, 2.6, -5), Vector3(0.12, 5.2, 8), Color(0.29, 0.34, 0.31))
	_box("ApartmentLanding", Vector3(4.95, 3.25, -9.35), Vector3(2.1, 0.3, 0.7), Color(0.42, 0.44, 0.38))
	_box("ApartmentBack", Vector3(0, 4.95, -10), Vector3(12, 3.1, 0.3), Color(0.41, 0.44, 0.38))
	_box("ApartmentFront", Vector3(0, 4.95, -2), Vector3(8, 3.1, 0.25), Color(0.41, 0.44, 0.38))
	_box("ApartmentLeft", Vector3(-4, 4.95, -6), Vector3(0.25, 3.1, 8), Color(0.41, 0.44, 0.38))
	_box("ApartmentRight", Vector3(4, 4.95, -5), Vector3(0.25, 3.1, 6), Color(0.41, 0.44, 0.38))
	_box("ApartmentLintel", Vector3(4, 6.1, -9), Vector3(0.25, 0.8, 2), Color(0.41, 0.44, 0.38))
	_box("ApartmentRoof", Vector3(0, 6.6, -6), Vector3(8, 0.2, 8), Color(0.33, 0.38, 0.33))
	_box("PhotoDesk", Vector3(-2.5, 3.95, -8.5), Vector3(2, 0.9, 0.8), Color(0.37, 0.29, 0.21))
	_box("ReturnPhoto", Vector3(-2.5, 4.9, -8.5), Vector3(0.85, 0.7, 0.12), Color(0.55, 0.66, 0.55), "return_photo")
	_sign("PROTECTED SHOP PHOTOGRAPH", Vector3(-2.5, 5.65, -8.4), 17)
	_box("AddressDesk", Vector3(1.8, 3.95, -4), Vector3(2, 0.9, 0.8), Color(0.37, 0.29, 0.21))
	_box("AddressList", Vector3(1.8, 4.85, -4), Vector3(0.7, 0.65, 0.12), Color(0.8, 0.76, 0.56), "address_list")
	_sign("REVISED ADDRESSES", Vector3(1.8, 5.6, -3.9), 18)
	_box("Letter", Vector3(-2.4, 4.5, -3.9), Vector3(0.65, 0.6, 0.12), Color(0.72, 0.72, 0.64), "acceptance_letter")
	_sign("ACCEPTANCE LETTER", Vector3(-2.4, 5.2, -3.8), 18)
	_box("PackedCase", Vector3(-2.7, 3.7, -4.8), Vector3(0.9, 0.4, 0.6), Color(0.33, 0.28, 0.2))
	_box("DepartureMarker", Vector3(0, 1.3, 13.5), Vector3(1.1, 1.2, 0.2), Color(0.42, 0.52, 0.42), "departure")
	_sign("ONWARD ROUTE\nNorthern station", Vector3(0, 2.4, 13.35), 24)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 6, -6)
	light.omni_range = 8
	light.light_energy = 1.4
	add_child(light)

func _label(text: String, parent: Node, size: int = 22) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -240
	panel.offset_bottom = 240
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.1, 0.98)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud = _label("", root, 20)
	hud.position = Vector2(28, 22)
	hud.size = Vector2(650, 110)
	feedback = _label("WASD walk · Mouse look · E inspect · J journal · Escape pause", root, 20)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback.offset_left = 28
	feedback.offset_right = -28
	feedback.offset_top = -82
	feedback.offset_bottom = -18
	prompt = _label("", root, 24)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 45
	prompt.offset_bottom = 100
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair = _label("·", root, 32)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -8
	crosshair.offset_top = -22
	screen = _panel(root)
	var content := VBoxContainer.new()
	screen.add_child(content)
	record_title = _label("WORKBENCH / LOCAL ARCHIVE", content, 26)
	record_body = _label(CLUE_TEXT, content, 20)
	record_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.text = "Close record · Escape"
	content.add_child(close_button)
	close_button.pressed.connect(close_record)
	pause_panel = _panel(root)
	var menu := VBoxContainer.new()
	pause_panel.add_child(menu)
	_label("PAUSED", menu, 30)
	_label("Mouse sensitivity (saved with checkpoint)", menu)
	sensitivity_slider = HSlider.new()
	var slider: HSlider = sensitivity_slider
	slider.min_value = 0.0005
	slider.max_value = 0.008
	slider.step = 0.0001
	slider.value = player.mouse_sensitivity
	menu.add_child(slider)
	slider.value_changed.connect(_sensitivity_changed)
	save_status = _label("Evidence and power autosave on discovery. Continue restores a safe room anchor.", menu, 18)
	var save_button := Button.new()
	save_button.text = "Save checkpoint"
	menu.add_child(save_button)
	save_button.pressed.connect(func() -> void: save_checkpoint())
	var menu_button := Button.new()
	menu_button.text = "Return to title"
	menu.add_child(menu_button)
	menu_button.pressed.connect(_return_to_menu)
	resume_button = Button.new()
	resume_button.text = "Resume · Escape"
	menu.add_child(resume_button)
	resume_button.pressed.connect(func() -> void: _set_mode(Mode.WALK))
	quit_button = Button.new()
	quit_button.text = "Quit"
	menu.add_child(quit_button)
	quit_button.pressed.connect(_request_quit)
	start_panel = _panel(root)
	var start_content := VBoxContainer.new()
	start_panel.add_child(start_content)
	_label("LAST KNOWN / CHAPTER 1", start_content, 28)
	_label("The shop\nA placeholder investigation · proposed narrative", start_content, 22)
	start_status = _label("", start_content, 18)
	start_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	continue_button = Button.new()
	continue_button.text = "Continue checkpoint"
	start_content.add_child(continue_button)
	continue_button.pressed.connect(continue_game)
	new_button = Button.new()
	new_button.text = "New expedition"
	start_content.add_child(new_button)
	new_button.pressed.connect(_request_new_game)
	var title_quit := Button.new()
	title_quit.text = "Quit"
	start_content.add_child(title_quit)
	title_quit.pressed.connect(func() -> void: get_tree().quit())
	journal_panel = _panel(root)
	var journal_content := VBoxContainer.new()
	journal_panel.add_child(journal_content)
	journal_body = _label("", journal_content, 19)
	journal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal_close_button = Button.new()
	var journal_close: Button = journal_close_button
	journal_close.text = "Close journal · J or Escape"
	journal_content.add_child(journal_close)
	journal_close.pressed.connect(func() -> void: _set_mode(Mode.WALK))
	ending_panel = _panel(root)
	var ending_content := VBoxContainer.new()
	ending_panel.add_child(ending_content)
	_label("CHAPTER 1 / THE SHOP", ending_content, 28)
	var ending := _label("The records support a return after the station's final evacuation. The missing person's later fate remains unknown.\n\nThe apartment address list points to the northern station handover desk and the overflow school shelter.\n\nNext: follow the registry trail.\n\nChapter complete in placeholder form. The next chapter is not built. You can continue exploring this block.", ending_content, 21)
	ending.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ending_explore_button = Button.new()
	var explore: Button = ending_explore_button
	explore.text = "Keep exploring · Escape"
	ending_content.add_child(explore)
	explore.pressed.connect(func() -> void: _set_mode(Mode.WALK))
	var ending_menu := Button.new()
	ending_menu.text = "Return to title"
	ending_content.add_child(ending_menu)
	ending_menu.pressed.connect(_return_to_menu)
