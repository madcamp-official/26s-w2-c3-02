extends CharacterBody3D

const SPEED := 10.0
const GRAVITY := 20.0
const TURN_SPEED := 6.0
const REMOTE_LERP_SPEED := 10.0
const WATER_SUBMERGE_LERP_SPEED := 6.0 # 물/땅 전환 시 모델이 순간이동하지 않고 부드럽게 오르내리도록
# 물 위에 떠 있을 때의 출렁임(상하) + 롤링(좌우 기울임) 애니메이션
const WATER_BOB_HEIGHT := 0.3
const WATER_BOB_SPEED := 1.6
const WATER_ROLL_DEGREES := 8.0
const WATER_ROLL_SPEED := 2.0
const FOAM_MOVE_SPEED_THRESHOLD := 1.0 # 물 위에서 이 속도 이상으로 움직일 때만 물결 파티클 방출
const WAKE_SPAWN_INTERVAL := 0.12 # 웨이크 자국을 새로 찍는 간격(초)
const WakeScene := preload("res://scenes/effects/WaterWake.tscn")

# 경찰(악어) 전용 대시: 현재 바라보는 방향으로 짧게 돌진해 경로 위의 오리를 잡는다.
const DASH_DISTANCE := 9.8
const DASH_DURATION := 0.25
const DASH_SPEED := DASH_DISTANCE / DASH_DURATION
const DASH_COOLDOWN := 5.0

const DEFAULT_STEALTH_RADIUS := 8.0

# CharacterBody3D는 Unity의 stepOffset 같은 자동 계단 오르기가 없어서, floor_max_angle을
# 넘는 낮은 턱(수직면)에도 그냥 막힌다. 이 정도 높이는 자연스럽게 넘어가야 하므로,
# 진행 방향 앞에 STEP_HEIGHT보다 낮은 턱만 있으면 그만큼 미리 들어올려 넘어가게 한다.
const STEP_HEIGHT := 1.0
const STEP_CHECK_DISTANCE := 2.0
# 실측 결과 섬의 실제 해안선(마른 땅의 마지막 표면)은 y≈0.3, 물 표면은 y=0.0
# (오리 원점 = 발 높이 기준). 그 사이에서 물에 거의 닿았을 때만 반응하도록 0.1로 설정.
const JAIL_WATER_MARGIN_Y := 0.3

const CHARACTER_CONFIG := {
	"duck": {
		"model": "res://assets/duck/duck.glb",
		# 실측 결과 duck.glb는 로컬 원점 기준 발끝이 y=-1.182에 있어, 땅(발 기준 y=0) 위에서
		# 완전히 선 모습을 보이려면 model_pos.y=1.182여야 한다. 기존 값(0.622)은 발이 항상
		# y≈-0.56에 오게 해 물에 뜬 모습만 맞춰둔 값이었으므로, 그 차이(0.56)를
		# water_submerge_depth로 옮겨 물 위에서는 기존과 동일하게 잠기고 땅에서는 다리가 보이게 한다.
		"model_pos": Vector3(0, 1.182, 0),
		"model_scale": 3.0,
		"collision_size": Vector3(1.2, 3.6, 1.5),
		"collision_pos": Vector3(0, 1.8, 0),
		"water_submerge_depth": 0.56,
		"water_effect_scale": 1.0,
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
		# 악어는 오리보다 몸집이 훨씬 크므로(model_scale 2배), 물결/포말 효과도 그만큼 크게 보이도록.
		"water_effect_scale": 1.8,
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

@onready var _foam_particles: GPUParticles3D = $WaterFoamParticles

var _model_node: Node3D = null
var _base_model_pos_y := 0.0
var _water_submerge_depth := 0.0
var _water_base_y := 0.0
var _water_motion_time := randf_range(0.0, TAU) # 캐릭터마다 위상을 다르게 해 동시에 출렁이지 않도록
var _step_probe_half_width := 0.0
var _wake_spawn_timer := 0.0
var _water_effect_scale := 1.0


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
	_water_base_y = _base_model_pos_y
	_water_effect_scale = float(config.get("water_effect_scale", 1.0))
	_foam_particles.scale = Vector3.ONE * _water_effect_scale

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = config["collision_size"]
	$CollisionShape3D.shape = shape
	# 콜리전 박스 절반 폭의 80% 지점을 좌우 스텝업 프로브 위치로 삼는다(모서리 근처에서
	# 턱을 밟는 경우도 감지하되, 박스 바깥으로 나가 벽을 뚫고 감지하지 않도록 안쪽으로 여유를 둔다).
	_step_probe_half_width = float(config["collision_size"].x) * 0.48
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
	_apply_step_up()
	move_and_slide()
	_update_water_submersion(delta)
	_update_local_transform_if_needed()


func _apply_step_up() -> void:
	if not is_on_floor():
		return
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length() < 0.01:
		return

	var direction := horizontal_vel.normalized()
	# 중앙 레이 하나만 쓰면 캐릭터 폭(콜리전 박스)의 모서리가 턱에 걸리는 경우(비스듬한
	# 접근, 회전 중 이동 등)를 놓친다. 진행 방향의 좌/우로도 함께 프로브해서 박스 폭
	# 전체에 걸쳐 턱을 감지한다.
	var perp := Vector3(-direction.z, 0.0, direction.x) * _step_probe_half_width
	var origin := global_position

	var best_step := 0.0
	for offset in [Vector3.ZERO, perp, -perp, perp * 0.5, -perp * 0.5]:
		var step := _probe_step_up(origin + offset, direction)
		if step > best_step:
			best_step = step

	if best_step > 0.01:
		global_position.y += best_step


func _probe_step_up(origin: Vector3, direction: Vector3) -> float:
	var space_state := get_world_3d().direct_space_state

	# 발목 높이에서 진행 방향으로 뭔가 막고 있는지 확인
	var low_from := origin + Vector3(0, 0.1, 0)
	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_from + direction * STEP_CHECK_DISTANCE)
	low_query.exclude = [self]
	if space_state.intersect_ray(low_query).is_empty():
		return 0.0

	# 턱 높이에서는 막혀있지 않은지 확인 (막혀있으면 STEP_HEIGHT보다 높은 벽/바위이므로 그냥 막는다)
	var high_from := origin + Vector3(0, STEP_HEIGHT, 0)
	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_from + direction * STEP_CHECK_DISTANCE)
	high_query.exclude = [self]
	if not space_state.intersect_ray(high_query).is_empty():
		return 0.0

	# 턱 너머의 실제 바닥 높이를 아래로 레이캐스트해서 얼마나 들어올려야 하는지 확인
	var probe_top := high_from + direction * STEP_CHECK_DISTANCE
	var floor_query := PhysicsRayQueryParameters3D.create(probe_top, probe_top + Vector3(0, -STEP_HEIGHT - 0.2, 0))
	floor_query.exclude = [self]
	var floor_hit := space_state.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return 0.0

	var step_up_amount: float = floor_hit["position"].y - origin.y
	if step_up_amount > 0.01 and step_up_amount <= STEP_HEIGHT:
		return step_up_amount
	return 0.0


func _update_water_submersion(delta: float) -> void:
	if _model_node == null:
		return
	var on_water := _is_water_directly_below()

	var target_base_y := _base_model_pos_y
	if _water_submerge_depth > 0.0 and on_water:
		target_base_y -= _water_submerge_depth
	_water_base_y = lerp(_water_base_y, target_base_y, clamp(delta * WATER_SUBMERGE_LERP_SPEED, 0.0, 1.0))

	_water_motion_time += delta
	var bob := 0.0
	var target_roll := 0.0
	if on_water:
		bob = sin(_water_motion_time * WATER_BOB_SPEED) * WATER_BOB_HEIGHT
		target_roll = sin(_water_motion_time * WATER_ROLL_SPEED + PI * 0.25) * deg_to_rad(WATER_ROLL_DEGREES)

	_model_node.position.y = _water_base_y + bob
	_model_node.rotation.z = lerp_angle(_model_node.rotation.z, target_roll, clamp(delta * WATER_SUBMERGE_LERP_SPEED, 0.0, 1.0))

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_wake_active := on_water and horizontal_speed > FOAM_MOVE_SPEED_THRESHOLD
	_foam_particles.emitting = is_wake_active

	if is_wake_active:
		_wake_spawn_timer -= delta
		if _wake_spawn_timer <= 0.0:
			_wake_spawn_timer = WAKE_SPAWN_INTERVAL
			_spawn_wake()
	else:
		_wake_spawn_timer = 0.0


func _spawn_wake() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var wake: Node3D = WakeScene.instantiate()
	wake.set("size_scale", _water_effect_scale)
	scene_root.add_child(wake)
	wake.global_position = Vector3(global_position.x, 0.02, global_position.z)
	var flat_velocity := Vector2(velocity.x, velocity.z)
	if flat_velocity.length() > 0.01:
		wake.rotation.y = atan2(-flat_velocity.x, -flat_velocity.y)


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
	# 이번 프레임의 이동을 계산하기 "전에" 대시 종료 여부를 먼저 확정해야, 이번 프레임의
	# 실제 이동이 dash_active 값과 항상 일치한다(로컬 애니메이션/이동 처리용).
	if dash_active:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			dash_active = false

	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = max(0.0, dash_cooldown_remaining - delta)

	var action_suffix := "_arrow" if control_scheme == "arrows" else ""
	if not dash_active and dash_cooldown_remaining <= 0.0 and Input.is_action_just_pressed("dash" + action_suffix):
		AudioManager.play_sfx("dash")
		dash_active = true
		_dash_time_left = DASH_DURATION
		_dash_direction = -global_transform.basis.z
		# 대시를 누른 순간의 시작/도착 지점을 고정해 로컬 이동에 사용한다.
		dash_start_pos = global_position
		dash_end_pos = dash_start_pos + _dash_direction * DASH_DISTANCE
		dash_cooldown_remaining = DASH_COOLDOWN
		# "player:dash" 격: 입력(시작/도착 지점)만 서버(MockServer)에 보고한다. 그 경로 위에
		# 오리가 겹치는지 판정하는 건 서버 몫이므로 여기서는 판정하지 않는다.
		MockServer.begin_dash(controlled_player_id, dash_start_pos, dash_end_pos, DASH_DURATION)

	GameData.dash_cooldown_duration = DASH_COOLDOWN
	GameData.dash_cooldown_remaining = dash_cooldown_remaining


func _move_inside_jail(delta: float) -> void:
	_apply_free_movement(delta)
	_apply_step_up()
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
