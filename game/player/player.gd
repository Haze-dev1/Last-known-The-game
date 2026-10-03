extends CharacterBody3D

@export_range(0.0005, 0.008, 0.0001) var mouse_sensitivity: float = 0.002
var movement_enabled: bool = false
var camera: Camera3D
var ray: RayCast3D

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 75.0
	add_child(camera)
	camera.current = true
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.8)
	camera.add_child(ray)
	ray.add_exception(self)

func _unhandled_input(event: InputEvent) -> void:
	if movement_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * mouse_sensitivity, -1.35, 1.35)

func _physics_process(delta: float) -> void:
	if not movement_enabled:
		velocity = Vector3.ZERO
		return
	var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(axes.x, 0, axes.y)
	velocity.x = direction.x * 3.0
	velocity.z = direction.z * 3.0
	velocity.y -= 18.0 * delta
	move_and_slide()

func interaction_target() -> String:
	ray.force_raycast_update()
	if ray.is_colliding():
		var collider := ray.get_collider() as Node
		if collider != null:
			return str(collider.get_meta("interaction", ""))
	return ""
