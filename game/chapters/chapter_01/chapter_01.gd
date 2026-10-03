extends Node3D

const PlayerController = preload("res://player/player.gd")
const START := Vector3(0, 0.05, 10)
const CLUE_ID := "shop_service_note"
const CLUE_TEXT := "SAVED SERVICE NOTE / draft clue\n\nRadios charged at the shop. The collection point changed; see the address list upstairs.\n\nObserved: a saved local note describes repair work and an address list.\nInterpretation: a lead to investigate. Author and chronology are unconfirmed."

enum Mode { ARRIVAL, WALK, COMPUTER, PAUSE }
var mode: Mode = Mode.ARRIVAL
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_input()
	_build_world()
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	_build_ui()
	player.position = START + Vector3(0, 0, 1.5)
	_set_mode(Mode.ARRIVAL)
	get_window().focus_exited.connect(_on_focus_lost)

func _configure_input() -> void:
	var bindings: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E}
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
			Mode.COMPUTER, Mode.PAUSE: _set_mode(Mode.WALK)
			Mode.WALK: _set_mode(Mode.PAUSE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if mode == Mode.ARRIVAL:
			finish_arrival()
		elif mode == Mode.WALK:
			interact(player.interaction_target())
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if mode == Mode.ARRIVAL:
		arrival_time += delta
		player.position = START + Vector3(0, 0, 1.5 * (1.0 - clampf(arrival_time / 3.0, 0, 1)))
		if arrival_time >= 3.0:
			finish_arrival()
	if mode == Mode.WALK:
		var target: String = player.interaction_target()
		match target:
			"computer": prompt.text = "E  ·  Inspect workbench computer"
			"power": prompt.text = "E  ·  Connect portable supply" if not powered else "E  ·  Supply connected"
			_: prompt.text = ""
	hud.text = "LAST KNOWN  /  FOUNDATION\n" + ("Foundation complete · service note recovered" if not evidence.is_empty() else ("Read the saved workbench file" if powered else "Find the repair shop · restore workbench power")) + "\nEvidence: %d / 1  ·  %s" % [evidence.size(), "Service note collected" if not evidence.is_empty() else "No records yet"]

func finish_arrival() -> void:
	player.position = START
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	_set_mode(Mode.WALK)

func _set_mode(next_mode: Mode) -> void:
	mode = next_mode
	get_tree().paused = mode == Mode.PAUSE
	player.movement_enabled = mode == Mode.WALK
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mode == Mode.WALK else Input.MOUSE_MODE_VISIBLE
	screen.visible = mode == Mode.COMPUTER
	pause_panel.visible = mode == Mode.PAUSE
	crosshair.visible = mode == Mode.WALK
	prompt.visible = mode == Mode.WALK or mode == Mode.ARRIVAL
	if mode == Mode.ARRIVAL:
		prompt.text = "Arrival  ·  E or Escape to skip"
	elif mode == Mode.PAUSE:
		resume_button.grab_focus()
	elif mode == Mode.COMPUTER:
		close_button.grab_focus()
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
		"computer":
			if not powered:
				feedback.text = "No power. Connect the portable supply beside the shop entrance."
				return
			if not evidence.has(CLUE_ID):
				evidence.append(CLUE_ID)
			feedback.text = "Service note recorded. Foundation complete; upstairs investigation comes next."
			_set_mode(Mode.COMPUTER)

func _on_focus_lost() -> void:
	if mode == Mode.ARRIVAL:
		finish_arrival()
	if mode == Mode.WALK:
		_set_mode(Mode.PAUSE)

func _box(label: String, at: Vector3, dimensions: Vector3, color: Color, interaction: String = "") -> StaticBody3D:
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
	body.add_child(shape)
	if not interaction.is_empty():
		body.set_meta("interaction", interaction)
	return body

func _sign(text: String, at: Vector3, font_size: int = 32) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
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
		_box("Curb", Vector3(side * 5, 0.05, 3), Vector3(0.25, 0.1, 24), Color(0.48, 0.49, 0.42))
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
	for x: float in [-2.7, 2.7]:
		_box("Shelf", Vector3(x, 1.1, -9), Vector3(1, 2.2, 0.6), Color(0.32, 0.3, 0.24))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, -6)
	lamp.light_color = Color(0.75, 0.8, 0.65)
	lamp.light_energy = 1.2
	lamp.omni_range = 8.0
	add_child(lamp)

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
	feedback = _label("WASD walk · Mouse look · E interact · Escape pause", root, 20)
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
	_label("WORKBENCH / LOCAL ARCHIVE", content, 28)
	var clue := _label(CLUE_TEXT, content)
	clue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.text = "Leave computer · Escape"
	content.add_child(close_button)
	close_button.pressed.connect(func() -> void: _set_mode(Mode.WALK))
	pause_panel = _panel(root)
	var menu := VBoxContainer.new()
	pause_panel.add_child(menu)
	_label("PAUSED", menu, 30)
	_label("Mouse sensitivity (session setting)", menu)
	var slider := HSlider.new()
	slider.min_value = 0.0005
	slider.max_value = 0.008
	slider.step = 0.0001
	slider.value = player.mouse_sensitivity
	menu.add_child(slider)
	slider.value_changed.connect(func(value: float) -> void: player.mouse_sensitivity = value)
	_label("Evidence: saved service note appears once in the HUD.\nProgress resets when you quit this foundation.", menu, 20)
	resume_button = Button.new()
	resume_button.text = "Resume · Escape"
	menu.add_child(resume_button)
	resume_button.pressed.connect(func() -> void: _set_mode(Mode.WALK))
	var quit_button := Button.new()
	quit_button.text = "Quit"
	menu.add_child(quit_button)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
