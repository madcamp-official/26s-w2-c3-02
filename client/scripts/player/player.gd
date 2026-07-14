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
# 필드 전역에서 "맵 밖으로 빠짐"만 잡는 안전망용 임계값. 저수심 구간을 헤엄칠 때도
# global_position.y가 물 표면(0.0) 근처까지 자연스럽게 내려갈 수 있으므로, JAIL_WATER_MARGIN_Y
# 같은 얕은 값을 재사용하면 정상 수영 중에도 오탐이 난다. 실제 지형 최저 높이보다 확실히
# 낮은 값으로 잡아, 진짜로 바닥을 뚫고 떨어졌을 때만 반응하게 한다.
const FALL_RECOVERY_Y := -1.0

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
	"nupjuk": {
		"model": "res://assets/nupjuk/nupjuk.glb",
		"model_pos": Vector3(0, 1.383, 0),
		"model_scale": 1.8,
		"collision_size": Vector3(1.2, 3.6, 1.5),
		"collision_pos": Vector3(0, 1.8, 0),
		"water_submerge_depth": 0.56,
		"water_effect_scale": 1.0,
	},
	"greenduck": {
		"model": "res://assets/greenduck/greenduck.glb",
		# greenduck.glb는 duck.glb와 달리 로컬 원점이 이미 발 높이에 있고(model_pos.y=0로
		# 충분), 기본 정면 방향도 duck.glb와 반대라서 다른 캐릭터들과 같은 180도 회전을
		# 적용하면 뒤를 보고 서게 된다. 실측(스크린샷 비교) 결과 model_scale=6.2일 때
		# 일반 오리와 비슷한 체구로 보인다.
		"model_pos": Vector3(0, 0.0, 0),
		"model_scale": 6.2,
		"model_rotation_degrees": Vector3(0, 0, 0),
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

# 오리 팀으로 취급되는 캐릭터(스킨) 키 목록. 인벤토리에 오리 스킨이 추가되면 여기에도 더한다.
const DUCK_CHARACTERS := ["duck", "nupjuk", "greenduck"]

@export var character: String = "duck":
	set(value):
		if character == value and _model_node != null:
			return
		character = value
		if is_inside_tree():
			_update_character_model()

@export var controllable: bool = false
@export_enum("wasd", "arrows") var control_scheme: String = "wasd"

@export var controlled_player_id: String = "":
	set(value):
		controlled_player_id = value
		if is_inside_tree():
			_update_character_from_player_id()

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
var _prev_water_check_pos := Vector2.ZERO
var _has_prev_water_check_pos := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(40)
	floor_snap_length = 2.5
	max_slides = 6

	# Game.tscn에 고정 배치된 로컬 테스트용 오리/악어 노드는 controlled_player_id가 비어
	# 있는 채로 시작한다(원격 플레이어는 스폰 시점에 항상 pid가 채워져 있음). 그 경우에만
	# 인벤토리에서 고른 장착 스킨으로 교체해, 로비/메뉴에서 선택한 스킨이 실제 플레이에도
	# 반영되게 한다.
	if controlled_player_id == "":
		if character in DUCK_CHARACTERS:
			character = GameData.local_duck_character
		elif character == "aligator":
			character = GameData.local_tagger_character
		controlled_player_id = GameData.local_player_id
	else:
		_update_character_from_player_id()

	_update_character_model()

	if character in DUCK_CHARACTERS:
		GameData.register_local_player("duck", character)

	if controllable:
		add_to_group("controllable_player")
		if character in DUCK_CHARACTERS:
			if not GameData.game_event.is_connected(_on_game_event):
				GameData.game_event.connect(_on_game_event)


func _update_character_from_player_id() -> void:
	var target_id := controlled_player_id
	if target_id == "":
		target_id = GameData.local_player_id
	for p in GameData.players:
		if p["playerId"] == target_id:
			character = p["character"]
			break


func _update_character_model() -> void:
	if not is_inside_tree():
		return

	if _model_node != null:
		_model_node.queue_free()
		_model_node = null

	var config: Dictionary = CHARACTER_CONFIG.get(character, CHARACTER_CONFIG["duck"])
	var model_scene: PackedScene = load(config["model"])
	if model_scene == null:
		push_error("Player failed to load model for '%s': %s" % [character, config["model"]])
		return

	var model: Node3D = model_scene.instantiate()
	model.position = config["model_pos"]
	model.scale = Vector3.ONE * float(config["model_scale"])
	model.rotation_degrees = config.get("model_rotation_degrees", Vector3(0, 180, 0))
	var model_slot = get_node_or_null("ModelSlot")
	if model_slot != null:
		model_slot.add_child(model)
	_model_node = model
	_base_model_pos_y = float(config["model_pos"].y)
	_water_submerge_depth = float(config.get("water_submerge_depth", 0.0))
	_water_base_y = _base_model_pos_y
	_water_effect_scale = float(config.get("water_effect_scale", 1.0))
	
	var foam = _foam_particles if _foam_particles != null else get_node_or_null("WaterFoamParticles")
	if foam != null:
		foam.scale = Vector3.ONE * _water_effect_scale

	var col_shape = get_node_or_null("CollisionShape3D")
	if col_shape != null:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = config["collision_size"]
		col_shape.shape = shape
		_step_probe_half_width = float(config["collision_size"].x) * 0.48
		col_shape.position = config["collision_pos"]


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
	if not controllable:
		# 원격/동기화 캐릭터는 _physics_process가 아예 실행되지 않으므로(controllable=false면
		# 맨 위에서 return), 물 잠김/출렁임/웨이크 연출을 여기서 대신 갱신해준다. 그렇지 않으면
		# 다른 클라이언트가 조작하는 캐릭터가 항상 뭍 위에 있는 것처럼 보인다.
		_update_water_submersion(delta)
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
	var prev_pos := global_position
	move_and_slide()

	# 대시처럼 빠른 이동이 지형 이음매(연못 바닥 메쉬 조각 사이 틈, 섬 콜리전 경계 등)를
	# 스치면 한두 프레임 is_on_floor()가 false가 되면서 중력이 붙어 맵 밖으로 떨어질 수
	# 있다. 정상 수영 중과 구분하기 위해 실제 지형보다 훨씬 낮은 FALL_RECOVERY_Y를 기준으로
	# 삼는다.
	if global_position.y <= FALL_RECOVERY_Y:
		global_position = prev_pos
		velocity = Vector3.ZERO

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

	var flat_velocity := _flat_motion_velocity(delta)
	var horizontal_speed := flat_velocity.length()
	var is_wake_active := on_water and horizontal_speed > FOAM_MOVE_SPEED_THRESHOLD
	_foam_particles.emitting = is_wake_active

	if is_wake_active:
		_wake_spawn_timer -= delta
		if _wake_spawn_timer <= 0.0:
			_wake_spawn_timer = WAKE_SPAWN_INTERVAL
			_spawn_wake(flat_velocity)
	else:
		_wake_spawn_timer = 0.0


# controllable(로컬 조작) 캐릭터는 CharacterBody3D의 실제 velocity를 그대로 쓰지만,
# 원격/동기화 캐릭터는 move_and_slide를 타지 않아 velocity가 항상 0이므로 프레임 간
# 위치 변화량으로 대신 속도를 추정한다.
func _flat_motion_velocity(delta: float) -> Vector2:
	if controllable:
		return Vector2(velocity.x, velocity.z)
	var current := Vector2(global_position.x, global_position.z)
	var estimated := Vector2.ZERO
	if _has_prev_water_check_pos and delta > 0.0:
		estimated = (current - _prev_water_check_pos) / delta
	_prev_water_check_pos = current
	_has_prev_water_check_pos = true
	return estimated


func _spawn_wake(flat_velocity: Vector2) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var wake: Node3D = WakeScene.instantiate()
	wake.set("size_scale", _water_effect_scale)
	scene_root.add_child(wake)
	wake.global_position = Vector3(global_position.x, 0.02, global_position.z)
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
	var mobile_dash_requested := controlled_player_id == GameData.local_player_id and GameData.consume_mobile_dash_request()
	if not dash_active and dash_cooldown_remaining <= 0.0 and (Input.is_action_just_pressed("dash" + action_suffix) or mobile_dash_requested):
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
	if controlled_player_id == GameData.local_player_id:
		input_dir.x += GameData.mobile_move_input.x
		input_dir.z += GameData.mobile_move_input.y
	return input_dir.normalized()


func _face_input_direction(input_dir: Vector3, delta: float) -> void:
	if input_dir.length() <= 0.01:
		return
	var target_angle := atan2(-input_dir.x, -input_dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))


func _update_local_transform_if_needed() -> void:
	if controlled_player_id == "":
		return
	GameData.update_player_transform(controlled_player_id, global_position, rotation.y)
	if controlled_player_id == GameData.local_player_id:
		# 서버에는 자기 자신(local_player_id)의 위치만 보고한다("player:input" 격).
		# 다른 캐릭터(로컬 2인 핫싯 등)는 이 클라이언트가 곧 서버가 아니므로 보고하지 않는다.
		MockServer.report_local_transform(global_position, rotation.y)
