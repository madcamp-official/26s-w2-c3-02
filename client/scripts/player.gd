extends CharacterBody3D

const SPEED := 7.0
const GRAVITY := 20.0
const TURN_SPEED := 6.0

func _ready() -> void:
	GameData.register_local_player("duck", "duck")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var input_dir := Vector3.ZERO
	if Input.is_action_pressed("move_up"):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()
	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED

	if input_dir.length() > 0.01:
		var target_angle := atan2(-input_dir.x, -input_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))

	move_and_slide()
	GameData.update_local_player_transform(global_position, rotation.y)
