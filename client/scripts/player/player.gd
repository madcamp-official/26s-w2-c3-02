extends CharacterBody3D

const SPEED := 10.0
const GRAVITY := 20.0
const TURN_SPEED := 6.0
const REMOTE_LERP_SPEED := 10.0

const JAIL_BOUND_RADIUS := 15.0
const JAIL_MIN_Y := 0.45
const DEFAULT_STEALTH_RADIUS := 8.0

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
@export var controlled_player_id: String = ""

var _remote_target_pos: Vector3
var _remote_target_rot: float
var _has_remote_target := false
var _is_jailed := false
var _display_name_text := ""


func _ready() -> void:
	if controlled_player_id == "":
		controlled_player_id = GameData.local_player_id

	var config: Dictionary = CHARACTER_CONFIG[character]
	var model_scene: PackedScene = load(config["model"])
	if model_scene == null:
		push_error("Player failed to load model for '%s': %s" % [character, config["model"]])
		return

	var model: Node3D = model_scene.instantiate()
	model.position = config["model_pos"]
	model.scale = Vector3.ONE * float(config["model_scale"])
	model.rotation_degrees = Vector3(0, 180, 0)
	$ModelSlot.add_child(model)

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = config["collision_size"]
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = config["collision_pos"]

	floor_max_angle = deg_to_rad(80)
	floor_snap_length = 2.5
	max_slides = 6

	if character == "duck":
		GameData.register_local_player("duck", "duck")

	if controllable:
		add_to_group("controllable_player")
		if character == "duck":
			GameData.game_event.connect(_on_game_event)


func set_remote_state(pos: Vector3, rotation_y: float) -> void:
	_remote_target_pos = pos
	_remote_target_rot = rotation_y
	_has_remote_target = true


func snap_to_state(pos: Vector3, rotation_y: float) -> void:
	global_position = pos
	rotation.y = rotation_y
	_remote_target_pos = pos
	_remote_target_rot = rotation_y
	_has_remote_target = true


func set_display_name(text: String) -> void:
	_display_name_text = text
	$IdLabel.text = text
	_update_name_visibility()


func _on_game_event(event: String, data: Dictionary) -> void:
	var my_id := controlled_player_id
	match event:
		"player_jailed":
			if str(data.get("playerId", "")) == my_id:
				_is_jailed = true
				global_position = MockServer.JAIL_POSITION
				velocity = Vector3.ZERO
		"player_released", "player_rescued":
			if str(data.get("playerId", "")) == my_id or str(data.get("targetId", "")) == my_id:
				_is_jailed = false
				var release_position: Dictionary = data.get("releasePosition", {})
				if not release_position.is_empty():
					global_position = Vector3(
						float(release_position["x"]),
						float(release_position["y"]),
						float(release_position["z"])
					)
				else:
					global_position = Vector3(0, 0, 16)
				velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_update_name_visibility()
	if not _has_remote_target:
		return
	position = position.lerp(_remote_target_pos, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_target_rot, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))


func _update_name_visibility() -> void:
	$IdLabel.visible = _display_name_text != "" and not _is_inside_stealth_cover()


func _is_inside_stealth_cover() -> bool:
	var player_flat := Vector2(global_position.x, global_position.z)
	for cover in get_tree().get_nodes_in_group("stealth_cover"):
		if not cover is Node3D:
			continue
		var cover_node := cover as Node3D
		var cover_flat := Vector2(cover_node.global_position.x, cover_node.global_position.z)
		var radius := DEFAULT_STEALTH_RADIUS
		if cover_node.get("stealth_radius") != null:
			radius = float(cover_node.get("stealth_radius"))
		if player_flat.distance_to(cover_flat) <= radius:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not controllable:
		return

	if GameData.phase == "countdown":
		_move_inside_jail(delta)
		return

	if GameData.phase != "playing":
		velocity = Vector3.ZERO
		return

	if _is_jailed:
		_move_inside_jail(delta)
		return

	_apply_free_movement(delta)
	move_and_slide()
	_update_local_transform_if_needed()


func _apply_free_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var input_dir := _input_direction()
	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED
	_face_input_direction(input_dir, delta)


func _move_inside_jail(delta: float) -> void:
	_apply_free_movement(delta)
	var prev_pos := global_position
	move_and_slide()

	var flat_pos := Vector2(global_position.x, global_position.z)
	var jail_center := Vector2(MockServer.JAIL_POSITION.x, MockServer.JAIL_POSITION.z)
	var fell_to_water := global_position.y < JAIL_MIN_Y
	var left_boundary := flat_pos.distance_to(jail_center) > JAIL_BOUND_RADIUS
	if fell_to_water or left_boundary:
		global_position = prev_pos
		velocity.x = 0.0
		velocity.z = 0.0
		if fell_to_water:
			velocity.y = 0.0

	_update_local_transform_if_needed()


func _input_direction() -> Vector3:
	var action_suffix := ""
	if control_scheme == "arrows":
		action_suffix = "_arrow"
	var input_dir := Vector3.ZERO
	if Input.is_action_pressed("move_up" + action_suffix):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_down" + action_suffix):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left" + action_suffix):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right" + action_suffix):
		input_dir.x += 1.0
	return input_dir.normalized()


func _face_input_direction(input_dir: Vector3, delta: float) -> void:
	if input_dir.length() <= 0.01:
		return
	var target_angle := atan2(-input_dir.x, -input_dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))


func _update_local_transform_if_needed() -> void:
	if controlled_player_id != "":
		GameData.update_player_transform(controlled_player_id, global_position, rotation.y)
