extends Node3D

const LERP_SPEED := 10.0
const BOB_HEIGHT := 0.15
const BOB_SPEED := 4.0

var duckling_id: String = ""

var _base_y := 0.0
var _bob_time := randf_range(0.0, TAU)

func _process(delta: float) -> void:
	var entry := _find_entry()
	if entry.is_empty() or entry["state"] == "delivered":
		queue_free()
		return

	var pos: Dictionary = entry["position"]
	_base_y = pos["y"]
	_bob_time += delta * BOB_SPEED
	var target := Vector3(pos["x"], _base_y + sin(_bob_time) * BOB_HEIGHT, pos["z"])
	position = position.lerp(target, clamp(delta * LERP_SPEED, 0.0, 1.0))

func _find_entry() -> Dictionary:
	for d in GameData.ducklings:
		if d["ducklingId"] == duckling_id:
			return d
	return {}
