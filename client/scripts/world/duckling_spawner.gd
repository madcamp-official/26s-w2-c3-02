extends Node

const DucklingScene := preload("res://scenes/duckling/Duckling.tscn")

var _spawned: Dictionary = {} # ducklingId -> Node

func _ready() -> void:
	GameData.game_state_changed.connect(_sync)
	_sync()

func _sync() -> void:
	for id in _spawned.keys():
		if not is_instance_valid(_spawned[id]):
			_spawned.erase(id)

	for d in GameData.ducklings:
		var id: String = d["ducklingId"]
		if d["state"] == "delivered":
			continue
		if _spawned.has(id):
			continue
		var node := DucklingScene.instantiate()
		node.duckling_id = id
		# 스폰 위치를 즉시 서버 좌표로 맞춘다. 예전처럼 원점(0,0,0)에서 목표로 lerp해
		# 가게 두면, 맵 정중앙에 있는 감옥섬(JailIsland) 트라이메쉬 콜리전 "안"에서
		# 태어나는 셈이라 — 새끼오리가 CharacterBody3D가 된 뒤로는 — 사방이 지형에
		# 막혀 섬 밖으로 영영 못 나오고 섬 속에 갇혀 안 보이게 된다.
		var pos: Dictionary = d["position"]
		node.position = Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"]))
		add_child(node)
		_spawned[id] = node

# 대열에서 자기 앞(queueIndex - 1)에 있는 새끼오리의 실시간 위치를 참조해야 체인으로
# 따라가는 연출이 가능하므로, ducklingId로 그 노드를 찾을 수 있게 공개한다.
func get_node_for_duckling(id: String) -> Node3D:
	return _spawned.get(id)
