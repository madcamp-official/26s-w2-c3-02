extends Node3D

const LERP_SPEED := 10.0
const BOB_HEIGHT := 0.15
const BOB_SPEED := 4.0
const TURN_SPEED := 6.0
const MIN_MOVE_DIST := 0.01
const WATER_ROLL_DEGREES := 5.0
const WATER_ROLL_SPEED := 0.9
const WATER_CHECK_INTERVAL := 0.15 # 물 위 흔들림 연출용 판정이라 매 프레임 정확할 필요 없음

var duckling_id: String = ""

var _base_y := 0.0
var _bob_time := randf_range(0.0, TAU)
var _roll_time := randf_range(0.0, TAU)
var _on_water_cached := false
var _water_check_timer := randf_range(0.0, WATER_CHECK_INTERVAL) # 새끼오리마다 검사 시점을 분산시켜 한 프레임에 몰리지 않게 함

func _process(delta: float) -> void:
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
	var on_water := _on_water_cached

	var pos: Dictionary = entry["position"]
	_base_y = pos["y"]
	_bob_time += delta * BOB_SPEED
	var bob := sin(_bob_time) * BOB_HEIGHT if on_water else 0.0
	var target := Vector3(pos["x"], _base_y + bob, pos["z"])

	var dx := target.x - position.x
	var dz := target.z - position.z
	if Vector2(dx, dz).length() > MIN_MOVE_DIST:
		# The duckling model (Duckling.tscn) has no 180° yaw correction like the
		# player model does, so it faces +Z natively. atan2(dx, dz) points its nose
		# toward the movement direction; atan2(-dx, -dz) would face it backward.
		var target_angle := atan2(dx, dz)
		rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * TURN_SPEED, 0.0, 1.0))

	position = position.lerp(target, clamp(delta * LERP_SPEED, 0.0, 1.0))

	_roll_time += delta
	var target_roll := sin(_roll_time * WATER_ROLL_SPEED) * deg_to_rad(WATER_ROLL_DEGREES) if on_water else 0.0
	rotation.z = lerp_angle(rotation.z, target_roll, clamp(delta * TURN_SPEED, 0.0, 1.0))

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
