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
# - JAIL_BOUND_RADIUS: 섬에서 멀리 이탈하는 것을 방지하기 위한 최대 안전 반경 버퍼 (15.0으로 넉넉하게 설정).
# - JAIL_MIN_Y: 섬의 해안선(지형과 호수 물이 만나는 높이) 기준 최소 Y값.
#   (Y=0.45 미만으로 내려가 물을 밟기 직전에 이동을 차단하여 해안선을 물리적 경계로 작동하게 함)
const JAIL_BOUND_RADIUS := 15.0
const JAIL_MIN_Y        := 0.45

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

	# \ub85c\uc6b0\ud3f4\ub9ac \ud2b8\ub9ac\uba54\uc2dc \uc12c\uc5d0\uc11c \ud134(ledge)\uc5d0 \uac78\ub9ac\uc9c0 \uc54a\ub3c4\ub85d \ud310\uc815\uc744 \ud6c4\ud558\uac8c \uc124\uc815\ud55c\ub2e4.
	#
	# floor_max_angle: \uc774 \uac01\ub3c4 \uc774\ub0b4\uc758 \uba74\uc740 "\ubc14\ub2e5"\uc73c\ub85c \uc778\uc2dd\ud55c\ub2e4.
	#   \ub85c\uc6b0\ud3f4\ub9ac \uba54\uc2dc\ub294 \ud3f4\ub9ac\uacf5 \uacbd\uacc4\uc5d0 \uadfc\uc218\uc9c1 \uba74\uc774 \uc0dd\uae30\ubbc0\ub85c, 60\u00b0\uba74 \uc774\ub97c "\ubcbd"\uc73c\ub85c \ud310\ub2e8\ud574 \uc774\ub3d9\uc744 \ub9c9\ub294\ub2e4.
	#   80\u00b0\ub85c \uc62c\ub9ac\uba74 \uac70\uc758 \uc218\uc9c1\uc5d0 \uac00\uae4c\uc6b4 \uba74\ub3c4 \ubc14\ub2e5\uc73c\ub85c \uc778\uc2dd\ub3fc \uadf8 \uc704\ub97c \uac78\uc5b4\uc62c\ub77c\uac08 \uc218 \uc788\ub2e4.
	# floor_snap_length: \ub0b4\ub9ac\ub9c9 \ub54c \ubc14\ub2e5\uc5d0 \uc2a4\ub0c5\ud558\ub294 \uac70\ub9ac.
	# max_slides: \ucda9\ub3cc \ud574\uc18c \ubc18\ubcf5 \ud69f\uc218. \ubcf5\uc7a1\ud55c \uc9c0\ud615\uc5d0\uc11c \ub354 \ub9ce\uc740 \ud328\uc2a4\ub85c \ucda9\ub3cc\uc744 \ud480\uc5b4\ub09c\ub2e4.
	floor_max_angle  = deg_to_rad(80)  # 60\u00b0 \u2192 80\u00b0: \ub85c\uc6b0\ud3f4\ub9ac \ud134 \ud310\uc815 \ud6c4\ud558\uac8c
	floor_snap_length = 2.5            # 1.5 \u2192 2.5: \ub0b4\ub9ac\ub9c9 \uc2a4\ub0c5 \uac15\ud654
	max_slides        = 6              # 4(default) \u2192 6: \ubcf5\uc7a1\ud55c \ucda9\ub3cc \ud574\uc18c \ub2a5\ub825 \ud5a5\uc0c1


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
				# MockServer가 이벤트 payload에 석방 위치를 담아 보낸다.
				# 서버 권한 원칙: 위치 결정은 서버(MockServer)가 하고, 클라이언트는 따른다.
				var rp: Dictionary = data.get("releasePosition", {})
				if not rp.is_empty():
					global_position = Vector3(float(rp["x"]), float(rp["y"]), float(rp["z"]))
				else:
					# 폴백: 데이터가 없을 경우 감옥 남쪽 기본 위치로
					global_position = Vector3(-32, 0, 16)
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
