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
var _is_jailed: bool = false  # 현재 수감 상태 여부

# 감옥 섬 경계 상수
# - JAIL_BOUND_RADIUS: 섬 중심(JAIL_POSITION XZ)에서 벗어날 수 있는 최대 수평 거리.
# - JAIL_MIN_Y: 이 Y값 아래로 내려가면 연못 수면에 닿은 것으로 간주해 이동을 차단.
#   연못 수면 ≈ Y 0, 섬 노드 원점 ≈ Y 2.5이므로 0.5로 설정.
#   (3.0으로 설정하면 섬 표면(Y≈2.5~4)에서도 롤백이 발동해 이동이 불가능해짐)
const JAIL_BOUND_RADIUS := 11.0
const JAIL_MIN_Y        := 0.5

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
		# 오리만 감옥/구출 이벤트를 처리한다.
		# 악어(tagger)는 수감 대상이 아니므로 연결하지 않는다.
		if character == "duck":
			GameData.game_event.connect(_on_game_event)

func set_remote_state(pos: Vector3, rotation_y: float) -> void:
	_remote_target_pos = pos
	_remote_target_rot = rotation_y
	_has_remote_target = true

func set_display_name(text: String) -> void:
	$IdLabel.text = text
	$IdLabel.visible = true

func _on_game_event(event: String, data: Dictionary) -> void:
	var my_id := GameData.local_player_id
	match event:
		"player_jailed":
			if str(data.get("playerId", "")) == my_id:
				_is_jailed = true
				# MockServer가 이미 GameData.players 좌표를 jail 위치로 업데이트했으므로
				# 비주얼 노드도 즉시 텔레포트한다.
				global_position = MockServer.JAIL_POSITION
				velocity = Vector3.ZERO
		"player_released", "player_rescued":
			if str(data.get("playerId", "")) == my_id or str(data.get("targetId", "")) == my_id:
				_is_jailed = false
				global_position = MockServer.JAIL_RELEASE_POSITION
				velocity = Vector3.ZERO

func _process(delta: float) -> void:
	if not _has_remote_target:
		return
	position = position.lerp(_remote_target_pos, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_target_rot, clamp(delta * REMOTE_LERP_SPEED, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	if not controllable:
		return

	# 수감 상태: 섬 위에서는 자유롭게 이동하되, 섬을 벗어나면(물로 내려가거나
	# 수평 경계를 넘으면) 이전 위치로 롤백하여 물에 발을 디딜 수 없게 한다.
	if _is_jailed:
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

		# move_and_slide 전 위치를 저장한다.
		# 이동 후 섬을 벗어난 경우 이 위치로 되돌린다.
		var prev_pos := global_position
		move_and_slide()

		# 섬 이탈 판정:
		#   1) Y가 JAIL_MIN_Y(0.5) 미만 → 연못 수면(Y≈0)에 내려간 것
		#   2) XZ 거리가 JAIL_BOUND_RADIUS 초과 → 수평 경계 이탈
		var jail_center := MockServer.JAIL_POSITION
		var flat_pos    := Vector2(global_position.x, global_position.z)
		var flat_center := Vector2(jail_center.x, jail_center.z)
		var fell_to_water := global_position.y < JAIL_MIN_Y
		var left_boundary := flat_pos.distance_to(flat_center) > JAIL_BOUND_RADIUS
		if fell_to_water or left_boundary:
			global_position = prev_pos
			velocity.x = 0.0
			velocity.z = 0.0
			# 물에 빠진 경우 수직 속도도 0으로 리셋해 모서리에서 튀는 현상을 방지
			if fell_to_water:
				velocity.y = 0.0
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
