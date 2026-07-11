extends CharacterBody3D

const SPEED := 10.0
const GRAVITY := 20.0
const TURN_SPEED := 6.0
const REMOTE_LERP_SPEED := 10.0

const CHARACTER_CONFIG := {
	"duck": {
		"model": "res://assets/duck/duck.glb",
		"model_pos": Vector3(0, 0.622, 0),
		"model_scale": 3.0,
		"collision_size": Vector3(1.2, 3.6, 1.5),
		"collision_pos": Vector3(0, 1.8, 0),
	},
	"aligator": {
		"model": "res://assets/aligator/aligator.glb",
		"model_pos": Vector3(0, 1.684, 0),
		"model_scale": 6.0,
		"collision_size": Vector3(4.0, 3.36, 12.0),
		"collision_pos": Vector3(0, 1.68, 0),
	},
}

@export var character: String = "duck"
@export var controllable: bool = false
@export_enum("wasd", "arrows") var control_scheme: String = "wasd"

var _remote_target_pos: Vector3
var _remote_target_rot: float
var _has_remote_target := false

func _ready() -> void:
	var config: Dictionary = CHARACTER_CONFIG[character]

	var model_scene: PackedScene = load(config["model"])
	if model_scene == null:
		push_error("Player failed to load model for '%s': %s" % [character, config["model"]])
		return
	var model: Node3D = model_scene.instantiate()
	model.position = config["model_pos"]
	model.scale = Vector3.ONE * config["model_scale"]
	model.rotation_degrees = Vector3(0, 180, 0)
	$ModelSlot.add_child(model)

	var shape := BoxShape3D.new()
	shape.size = config["collision_size"]
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = config["collision_pos"]

	# The jail island is a low-poly trimesh with faceted, sloped grass. Allow steeper
	# contact normals to count as floor (and snap down onto them) so the character
	# stays grounded there instead of sliding/jittering.
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 1.5

	if character == "duck":
		GameData.register_local_player("duck", "duck")

	if controllable:
		add_to_group("controllable_player")

func set_remote_state(pos: Vector3, rotation_y: float) -> void:
	_remote_target_pos = pos
	_remote_target_rot = rotation_y
	_has_remote_target = true

func set_display_name(text: String) -> void:
	$IdLabel.text = text
	$IdLabel.visible = true

func _process(delta: float) -> void:
	if not _has_remote_target:
		return
	position = position.lerp(_remote_target_pos, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_target_rot, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	if not controllable:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var action_suffix := "_arrow" if control_scheme == "arrows" else ""

	var input_dir := Vector3.ZERO
	if Input.is_action_pressed("move_up" + action_suffix):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_down" + action_suffix):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left" + action_suffix):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right" + action_suffix):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()
	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED

	if input_dir.length() > 0.01:
		var target_angle := atan2(-input_dir.x, -input_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))

	move_and_slide()

	if character == "duck":
		GameData.update_local_player_transform(global_position, rotation.y)
