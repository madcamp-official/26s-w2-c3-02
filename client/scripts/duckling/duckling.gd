extends CharacterBody3D

const LERP_SPEED := 10.0
const BOB_HEIGHT := 0.15
const BOB_SPEED := 4.0
const TURN_SPEED := 6.0
const MIN_MOVE_DIST := 0.01
const WATER_ROLL_DEGREES := 5.0
const WATER_ROLL_SPEED := 0.9
const WATER_CHECK_INTERVAL := 0.15 # 물 위 흔들림 연출용 판정이라 매 프레임 정확할 필요 없음

# 서버는 새끼오리 y좌표를 항상 물 높이(0.0)로만 보낸다(지형 개념이 없는 2D 시뮬레이션이라
# 판정에도 x/z만 쓰임). 그래서 섬처럼 물보다 높은 지형 위로 올라갈 때는 실제로 밟고 선
# 표면 높이를 클라이언트가 직접 레이캐스트로 구해 보정해야 섬 속으로 파묻히지 않는다.
const GROUND_CHECK_TOP := 10.0
const GROUND_CHECK_BOTTOM := -2.0
# jail_island.gd/game.gd가 지형(섬, 바위, 벽, 바닥) 콜리전에 소속시켜두는 전용 레이어.
# 기본 레이어(1)로 검사/충돌하면 근처에 서 있는 플레이어 캐릭터의 콜라이더까지 걸리므로,
# 이 레이어만 보게 해서 실제 지형만 걸러낸다. 지면 높이 레이캐스트뿐 아니라, 이 노드
# 자신의 collision_mask로도 그대로 재사용한다(아래 _ready 참고) — 그래야 오리/악어나
# 서로 다른 새끼오리끼리는 절대 물리적으로 부딪히지 않으면서, 섬처럼 지형에 파묻힌
# 나무 등 실제 콜리전 메쉬에는 자연스럽게 옆으로 밀려나 위로 "올라타는" 일이 없다
# (섬 전체가 지형+나무가 하나로 합쳐진 단일 메쉬라 이름으로는 나무만 골라낼 수 없다 —
# 2026-07-14 실제로 새끼오리가 섬에 포함된 나무 위로 올라가는 문제가 있었다).
const GROUND_QUERY_MASK := 4 # layer 3

# 섬 해안선 같은 낮은 턱을 자연스럽게 올라가기 위한 계단 오르기(player.gd _apply_step_up과
# 같은 방식). CharacterBody3D는 floor_max_angle을 넘는 수직 턱에 그냥 막히기 때문에,
# 오리는 넘어가는 턱을 새끼오리만 못 넘어 섬 아래에 남겨지는 문제가 있었다. 플레이어와
# 같은 STEP_HEIGHT를 쓰되(리더가 갈 수 있는 곳은 따라갈 수 있어야 하므로), 레이는 지형
# 전용 레이어(GROUND_QUERY_MASK)만 검사해 플레이어/다른 새끼오리에 반응하지 않는다.
const STEP_HEIGHT := 1.0
const STEP_CHECK_DISTANCE := 1.0
const STEP_PROBE_HALF_WIDTH := 0.25 # 캡슐 반지름(0.3)보다 살짝 안쪽

# 오리를 따라다니는(state == "carried") 대형 연출 상수. 예전엔 서버가 이 값으로 매 틱
# 좌표를 계산해 브로드캐스트했는데, carried 동안의 좌표는 서버 게임 로직(픽업/배달 판정)에
# 전혀 쓰이지 않는 순수 연출이라 네트워크 브로드캐스트 지터가 그대로 버벅임으로 보였다.
# 그래서 이 값들을 그대로 옮겨와 각 클라이언트가 매 프레임 로컬로 재현한다
# (예전 server/src/constants.js FOLLOW_*/CIRCLE_*/MOVING_SPEED_THRESHOLD와 동일한 값).
const FOLLOW_SPACING := 1.5
const FOLLOW_LEASH := FOLLOW_SPACING * 1.6
const FOLLOW_LERP_SPEED := 4.0
const FOLLOW_LERP_FALLOFF := 0.5
const FOLLOW_LERP_MIN := 1.5
const MOVING_SPEED_THRESHOLD := 1.0
const CIRCLE_RADIUS := 2.2
const CIRCLE_LERP_SPEED := 4.0
const CIRCLE_SPIN_SPEED := 0.4

# 둥지로 걸어가는(state == "delivering") 연출도 carried와 같은 이유로 로컬 계산한다 —
# 이 좌표 자체는 더 이상 서버 판정에 쓰이지 않는다(서버는 이 클라이언트가 직접 보내는
# 'duckling:deliver' 메시지로만 도착을 판단한다). carried에서 넘어온 그 자리(position)에서
# 그대로 이어서 걷기 시작하므로 상태 전환 경계에서 순간이동이 생길 수 없다(예전
# server/src/gameLoop.js updateDelivering()과 동일한 등속 이동 + 정착 시간 수식).
const DELIVER_MOVE_SPEED := 30.0 # player.gd SPEED(오리 기본 이동속도)와 동일하게 맞춤
const NEST_ARRIVE_DISTANCE := 0.35
const NEST_SETTLE_TIME := 0.35
const NEST_1_POS := Vector2(-58.5, 58.5)
const NEST_2_POS := Vector2(58.5, -58.5)

var duckling_id: String = ""

@onready var _model: Node3D = $Model

var _base_y := 0.0
var _bob_time := randf_range(0.0, TAU)
var _roll_time := randf_range(0.0, TAU)
var _on_water_cached := false
var _ground_height_cached := 0.0
var _water_check_timer := randf_range(0.0, WATER_CHECK_INTERVAL) # 새끼오리마다 검사 시점을 분산시켜 한 프레임에 몰리지 않게 함

var _idle_spin := randf_range(0.0, TAU)
var _prev_player_pos := Vector2.ZERO
var _has_prev_player_pos := false
var _carried_base_y_set := false
var _carried_base_y := 0.0
var _delivering_nest_set := false
var _delivering_nest: Vector2 = Vector2.ZERO
var _delivering_settle_timer := 0.0
var _delivering_notified := false

func _physics_process(delta: float) -> void:
	var entry := _find_entry()
	if entry.is_empty() or entry["state"] == "delivered":
		queue_free()
		return

	# 항상 최대 10마리가 맵에 유지되면서 매 프레임 레이캐스트 10회가 겹쳐 버벅임을
	# 유발했다. 흔들림 연출은 즉각 반응할 필요가 없으므로 판정 자체를 스로틀링한다.
	_water_check_timer += delta
	if _water_check_timer >= WATER_CHECK_INTERVAL:
		_water_check_timer = 0.0
		_on_water_cached = _is_water_directly_below()
		_ground_height_cached = _ground_height_at(position.x, position.z)
	var on_water := _on_water_cached

	# 흔들림(bob)은 물리 바디(position.y)가 아니라 모델 자식 노드의 로컬 오프셋으로만
	# 적용한다. move_and_slide()가 매 프레임 미세하게 오르내리는 사인파를 따라가려 하면
	# 지형 콜리전과 계속 미세 충돌하며 떨리므로, 실제 콜리전에 관여하는 몸통 높이(_base_y)와
	# 순수 연출용 높이를 분리했다(player.gd의 _update_water_submersion과 같은 패턴).
	_bob_time += delta * BOB_SPEED
	var bob := sin(_bob_time) * BOB_HEIGHT if on_water else 0.0
	_model.position.y = bob

	var target: Vector3
	if entry["state"] == "carried":
		_reset_delivering_state()
		target = _compute_carried_target(entry, delta)
	elif entry["state"] == "delivering":
		_carried_base_y_set = false
		target = _compute_delivering_target(delta)
	else:
		_has_prev_player_pos = false
		_carried_base_y_set = false # 다음에 다시 잡힐 때 pickup 시점 y로 재초기화되도록
		_reset_delivering_state()
		var pos: Dictionary = entry["position"]
		_base_y = max(float(pos["y"]), _ground_height_cached)
		target = Vector3(pos["x"], _base_y, pos["z"])

	var dx := target.x - position.x
	var dz := target.z - position.z
	if Vector2(dx, dz).length() > MIN_MOVE_DIST:
		# The duckling model (Duckling.tscn) has no 180° yaw correction like the
		# player model does, so it faces +Z natively. atan2(dx, dz) points its nose
		# toward the movement direction; atan2(-dx, -dz) would face it backward.
		var target_angle := atan2(dx, dz)
		rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))

	# 예전엔 position.lerp() 결과를 그대로 대입해서 나무/바위 등 지형 메쉬를 그냥 뚫고
	# 지나갔다(오리를 따라다니는 대형 계산에는 장애물 회피가 아예 없었음). CharacterBody3D로
	# 바꾸고 move_and_slide()를 쓰면, 오리/악어가 이미 쓰는 것과 같은 실제 물리 콜리전으로
	# 지형에 옆으로 밀려나게 되어(위로 올라타지 않음) 같은 lerp 이동감은 그대로 유지된다.
	if delta > 0.0:
		var desired := position.lerp(target, clamp(delta * LERP_SPEED, 0.0, 1.0))
		velocity = (desired - position) / delta
		# 직전 프레임 이동에서 지형(벽/턱)에 막혔을 때만 계단 오르기 프로브를 돌린다 —
		# 새끼오리 10마리가 평시(開水面)에도 매 물리 프레임 레이캐스트를 쏘면 예전에
		# 잡았던 버벅임이 그대로 돌아오므로, 막히지 않은 동안엔 레이캐스트 0회다.
		if is_on_wall():
			_apply_step_up()
		move_and_slide()

	_roll_time += delta
	var target_roll := sin(_roll_time * WATER_ROLL_SPEED) * deg_to_rad(WATER_ROLL_DEGREES) if on_water else 0.0
	rotation.z = lerp_angle(rotation.z, target_roll, clamp(delta * TURN_SPEED, 0.0, 1.0))

# 오리(또는 앞 순번 새끼오리)를 리더 삼아 대형을 이루는 목표 위치를 로컬에서 계산한다.
# 옛 서버 updateDucklingFollow()와 동일한 수식이며, 오직 계산 위치와 주기(네트워크
# 브로드캐스트 -> 매 렌더 프레임)만 다르다.
func _compute_carried_target(entry: Dictionary, delta: float) -> Vector3:
	if not _carried_base_y_set:
		var pos: Dictionary = entry.get("position", {})
		_carried_base_y = float(pos.get("y", position.y))
		_carried_base_y_set = true
	_base_y = max(_carried_base_y, _ground_height_cached)

	var carrier_id := str(entry.get("carrierPlayerId", ""))
	var queue_index := int(entry.get("queueIndex", 0))
	# SceneRouter.go_to()는 change_scene_to_*가 아니라 screen_root 아래에 씬을 직접 붙이는
	# 방식이라, get_tree().current_scene은 항상 Boot 씬이라 game.gd에 도달하지 못한다.
	var scene := SceneRouter.find_current_child_with_method("get_player_node")
	if carrier_id == "" or scene == null:
		return Vector3(position.x, _base_y, position.z)

	var player_node: Node3D = scene.call("get_player_node", carrier_id)
	var is_moving := _update_is_moving(player_node, delta)

	var leader_node: Node3D = player_node
	if queue_index > 0 and scene.has_method("get_duckling_node"):
		var leader_duckling_id := _find_leader_duckling_id(carrier_id, queue_index - 1)
		if leader_duckling_id != "":
			leader_node = scene.call("get_duckling_node", leader_duckling_id)

	if leader_node == null:
		return Vector3(position.x, _base_y, position.z)

	var current2 := Vector2(position.x, position.z)
	var next2: Vector2
	if is_moving:
		var leader_pos2 := Vector2(leader_node.global_position.x, leader_node.global_position.z)
		var to_leader := current2 - leader_pos2
		var dist := to_leader.length()
		var dir := Vector2(0.0, 1.0)
		if dist > 0.01:
			dir = to_leader / dist
		if dist > FOLLOW_LEASH:
			next2 = leader_pos2 + dir * FOLLOW_LEASH
		else:
			var target2 := leader_pos2 + dir * FOLLOW_SPACING
			var lerp_speed: float = max(FOLLOW_LERP_MIN, FOLLOW_LERP_SPEED - queue_index * FOLLOW_LERP_FALLOFF)
			next2 = current2.lerp(target2, clamp(delta * lerp_speed, 0.0, 1.0))
	else:
		if player_node == null:
			return Vector3(position.x, _base_y, position.z)
		_idle_spin += delta * CIRCLE_SPIN_SPEED
		var count := _count_queue(carrier_id)
		var player_pos2 := Vector2(player_node.global_position.x, player_node.global_position.z)
		var angle: float = _idle_spin + (TAU / max(count, 1)) * queue_index
		var target2 := player_pos2 + Vector2(cos(angle), sin(angle)) * CIRCLE_RADIUS
		next2 = current2.lerp(target2, clamp(delta * CIRCLE_LERP_SPEED, 0.0, 1.0))

	return Vector3(next2.x, _base_y, next2.y)

# 둥지까지 걸어가는 목표 위치를 로컬에서 계산한다. 도착해서 NEST_SETTLE_TIME만큼
# 머무르면 서버에 'duckling:deliver'로 알려 점수/삭제를 확정한다(한 번만 보내도록 가드).
func _compute_delivering_target(delta: float) -> Vector3:
	var current2 := Vector2(position.x, position.z)
	if not _delivering_nest_set:
		_delivering_nest = NEST_1_POS if current2.distance_to(NEST_1_POS) <= current2.distance_to(NEST_2_POS) else NEST_2_POS
		_delivering_nest_set = true

	var to_nest := _delivering_nest - current2
	var dist := to_nest.length()
	if dist <= NEST_ARRIVE_DISTANCE:
		_base_y = 1.68 # 둥지 좌표의 y (server NEST_POSITIONS와 동일)
		_delivering_settle_timer += delta
		if _delivering_settle_timer >= NEST_SETTLE_TIME and not _delivering_notified:
			_delivering_notified = true
			MockServer.notify_duckling_delivered(duckling_id)
		return Vector3(_delivering_nest.x, _base_y, _delivering_nest.y)

	_base_y = max(0.0, _ground_height_cached)
	var step: float = min(DELIVER_MOVE_SPEED * delta, dist)
	var next2 := current2 + to_nest / dist * step
	return Vector3(next2.x, _base_y, next2.y)

# player.gd _apply_step_up()/_probe_step_up()과 동일한 3-레이 방식(전방 하단 막힘 확인 →
# 턱 높이 통과 확인 → 턱 너머 바닥 높이 측정). 캡슐이 좁아 좌우 프로브는 1쌍이면 충분하다.
func _apply_step_up() -> void:
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length() < 0.01:
		return

	var direction := horizontal_vel.normalized()
	var perp := Vector3(-direction.z, 0.0, direction.x) * STEP_PROBE_HALF_WIDTH
	var origin := global_position

	var best_step := 0.0
	for offset in [Vector3.ZERO, perp, -perp]:
		var step := _probe_step_up(origin + offset, direction)
		if step > best_step:
			best_step = step

	if best_step > 0.01:
		global_position.y += best_step

func _probe_step_up(origin: Vector3, direction: Vector3) -> float:
	var space_state := get_world_3d().direct_space_state

	# 발목 높이에서 진행 방향으로 지형이 막고 있는지 확인
	var low_from := origin + Vector3(0, 0.1, 0)
	var low_query := PhysicsRayQueryParameters3D.create(
		low_from, low_from + direction * STEP_CHECK_DISTANCE, GROUND_QUERY_MASK)
	if space_state.intersect_ray(low_query).is_empty():
		return 0.0

	# 턱 높이에서는 막혀있지 않은지 확인 (막혀있으면 STEP_HEIGHT보다 높은 벽이므로 그냥 막는다)
	var high_from := origin + Vector3(0, STEP_HEIGHT, 0)
	var high_query := PhysicsRayQueryParameters3D.create(
		high_from, high_from + direction * STEP_CHECK_DISTANCE, GROUND_QUERY_MASK)
	if not space_state.intersect_ray(high_query).is_empty():
		return 0.0

	# 턱 너머의 실제 바닥 높이를 아래로 레이캐스트해서 얼마나 들어올려야 하는지 확인
	var probe_top := high_from + direction * STEP_CHECK_DISTANCE
	var floor_query := PhysicsRayQueryParameters3D.create(
		probe_top, probe_top + Vector3(0, -STEP_HEIGHT - 0.2, 0), GROUND_QUERY_MASK)
	var floor_hit := space_state.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return 0.0

	var step_up_amount: float = floor_hit["position"].y - origin.y
	if step_up_amount > 0.01 and step_up_amount <= STEP_HEIGHT:
		return step_up_amount
	return 0.0

func _reset_delivering_state() -> void:
	_delivering_nest_set = false
	_delivering_settle_timer = 0.0
	_delivering_notified = false

func _update_is_moving(player_node: Node3D, delta: float) -> bool:
	if player_node == null:
		_has_prev_player_pos = false
		return false
	var pos2 := Vector2(player_node.global_position.x, player_node.global_position.z)
	var moving := false
	if _has_prev_player_pos and delta > 0.0:
		moving = (pos2 - _prev_player_pos).length() / delta > MOVING_SPEED_THRESHOLD
	_prev_player_pos = pos2
	_has_prev_player_pos = true
	return moving

func _find_leader_duckling_id(carrier_id: String, leader_queue_index: int) -> String:
	for d in GameData.ducklings:
		if str(d.get("carrierPlayerId", "")) == carrier_id and int(d.get("queueIndex", -1)) == leader_queue_index:
			return str(d.get("ducklingId", ""))
	return ""

func _count_queue(carrier_id: String) -> int:
	var count := 0
	for d in GameData.ducklings:
		if str(d.get("carrierPlayerId", "")) == carrier_id:
			count += 1
	return count

func _ground_height_at(x: float, z: float) -> float:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, GROUND_CHECK_TOP, z),
		Vector3(x, GROUND_CHECK_BOTTOM, z),
		GROUND_QUERY_MASK
	)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result["position"].y

func _is_water_directly_below() -> bool:
	var space_state := get_world_3d().direct_space_state
	var origin := Vector3(position.x, _base_y, position.z)
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.3, origin + Vector3.DOWN * 0.5)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider = result.get("collider")
	return collider is Node and (collider as Node).is_in_group("water_surface")

func _find_entry() -> Dictionary:
	for d in GameData.ducklings:
		if d["ducklingId"] == duckling_id:
			return d
	return {}
