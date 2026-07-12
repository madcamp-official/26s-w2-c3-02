extends CharacterBody3D

const SPEED := 10.0
const GRAVITY := 20.0
const TURN_SPEED := 6.0
const REMOTE_LERP_SPEED := 10.0
const WATER_SUBMERGE_LERP_SPEED := 6.0 # 물/땅 전환 시 모델이 순간이동하지 않고 부드럽게 오르내리도록

# 경찰(악어) 전용 대시: 현재 바라보는 방향으로 짧게 돌진해 경로 위의 오리를 잡는다.
const DASH_DISTANCE := 9.8
const DASH_DURATION := 0.25
const DASH_SPEED := DASH_DISTANCE / DASH_DURATION
const DASH_COOLDOWN := 5.0

const DEFAULT_STEALTH_RADIUS := 8.0
# 실측 결과 섬의 실제 해안선(마른 땅의 마지막 표면)은 y≈0.3, 물 표면은 y=0.0
# (오리 원점 = 발 높이 기준). 그 사이에서 물에 거의 닿았을 때만 반응하도록 0.1로 설정.
const JAIL_WATER_MARGIN_Y := 0.3

const CHARACTER_CONFIG := {
	"duck": {
		"model": "res://assets/duck/duck.glb",
		"model_pos": Vector3(0, 0.622, 0),
		"model_scale": 3.0,
		"collision_size": Vector3(1.2, 3.6, 1.5),
		"collision_pos": Vector3(0, 1.8, 0),
		"water_submerge_depth": 0.0,
	},
	"aligator": {
		"model": "res://assets/aligator/aligator.glb",
		"model_pos": Vector3(0, 1.684, 0),
		"model_scale": 6.0,
		"collision_size": Vector3(4.0, 3.36, 12.0),
		"collision_pos": Vector3(0, 1.68, 0),
		# 실측 결과 model_pos.y=1.684는 모델 바닥이 정확히 수면(y=0)에 딱 맞아 전혀 잠기지
		# 않았음(전신 높이 약 3.37). 물(연못 바닥)을 밟고 있을 때만 이만큼 모델을 내려서
		# 다리와 몸통 아랫부분이 잠기게 하고, 섬(땅) 위에서는 원래 높이(발 기준)를 유지한다.
		# (0.5는 발끝만 잠겨서 1.1로 높여 몸통 아랫부분까지 잠기게 조정.)
		"water_submerge_depth": 1.7,
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

var dash_active := false
var dash_cooldown_remaining := 0.0
var dash_start_pos := Vector3.ZERO
var dash_end_pos := Vector3.ZERO
var _dash_time_left := 0.0
var _dash_direction := Vector3.ZERO

var _model_node: Node3D = null
var _base_model_pos_y := 0.0
var _water_submerge_depth := 0.0


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
	_model_node = model
	_base_model_pos_y = float(config["model_pos"].y)
	_water_submerge_depth = float(config.get("water_submerge_depth", 0.0))

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = config["collision_size"]
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = config["collision_pos"]

	floor_max_angle = deg_to_rad(40)
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

	if character == "aligator":
		_update_dash(delta)

	_apply_free_movement(delta)
	move_and_slide()
	_update_water_submersion(delta)
	_update_local_transform_if_needed()


func _update_water_submersion(delta: float) -> void:
	if _model_node == null or _water_submerge_depth <= 0.0:
		return
	var on_water := _is_water_directly_below()
	var target_y: float = _base_model_pos_y - _water_submerge_depth if on_water else _base_model_pos_y
	_model_node.position.y = lerp(_model_node.position.y, target_y, clamp(delta * WATER_SUBMERGE_LERP_SPEED, 0.0, 1.0))


func _is_water_directly_below() -> bool:
	# 발밑을 직접 레이캐스트로 확인한다 — 이번 프레임에 오리/바위 등 옆에서 스친
	# 충돌이 있어도(get_slide_collision은 그런 것도 섞여 들어옴) 전혀 영향받지 않고,
	# 매 프레임 "지금 이 자리 밑에 뭐가 있는가"만 새로 판정하므로 이전에 섬을 밟았던
	# 기록에 발목 잡혀 계속 안 잠기는 현상도 생기지 않는다.
	var space_state := get_world_3d().direct_space_state
	var origin := global_position
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.3, origin + Vector3.DOWN * 0.5)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider = result.get("collider")
	return collider is Node and (collider as Node).is_in_group("water_surface")


func _apply_free_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if dash_active:
		velocity.x = _dash_direction.x * DASH_SPEED
		velocity.z = _dash_direction.z * DASH_SPEED
		return

	var input_dir := _input_direction()
	velocity.x = input_dir.x * SPEED
	velocity.z = input_dir.z * SPEED
	_face_input_direction(input_dir, delta)


func _update_dash(delta: float) -> void:
	# 이번 프레임의 이동을 계산하기 "전에" 대시 종료 여부를 먼저 확정해야, game.gd가
	# 같은 프레임에 읽는 dash_active 값과 실제 이번 프레임 이동이 항상 일치한다
	# (이동 계산 이후에 끄면 "대시가 끝난 마지막 이동 프레임"이 dash_active=false로
	# 보고돼 game.gd의 대시 경로 판정에서 그 구간이 누락된다).
	if dash_active:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			dash_active = false

	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = max(0.0, dash_cooldown_remaining - delta)

	var action_suffix := "_arrow" if control_scheme == "arrows" else ""
	if not dash_active and dash_cooldown_remaining <= 0.0 and Input.is_action_just_pressed("dash" + action_suffix):
		dash_active = true
		_dash_time_left = DASH_DURATION
		_dash_direction = -global_transform.basis.z
		# 대시를 누른 순간의 시작/도착 지점을 고정해 두면, game.gd가 매 프레임 위치를
		# 다시 계산할 필요 없이 항상 같은 전체 경로 사각형으로 판정할 수 있다.
		dash_start_pos = global_position
		dash_end_pos = dash_start_pos + _dash_direction * DASH_DISTANCE
		dash_cooldown_remaining = DASH_COOLDOWN

	GameData.dash_cooldown_duration = DASH_COOLDOWN
	GameData.dash_cooldown_remaining = dash_cooldown_remaining


func _move_inside_jail(delta: float) -> void:
	_apply_free_movement(delta)
	var prev_pos := global_position
	move_and_slide()

	# 섬의 실제 트라이메시 콜리전 위를 그대로 걸어다니게 하되(다리가 지형 높이를
	# 따라 자연스럽게 보임), 발이 물 표면(y=0)에 닿을 만큼 내려가면 그 스텝을 되돌린다.
	if global_position.y <= JAIL_WATER_MARGIN_Y:
		global_position = prev_pos
		velocity = Vector3.ZERO

	_update_water_submersion(delta)
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
