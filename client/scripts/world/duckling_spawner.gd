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
		add_child(node)
		_spawned[id] = node

# 대열에서 자기 앞(queueIndex - 1)에 있는 새끼오리의 실시간 위치를 참조해야 체인으로
# 따라가는 연출이 가능하므로, ducklingId로 그 노드를 찾을 수 있게 공개한다.
func get_node_for_duckling(id: String) -> Node3D:
	return _spawned.get(id)
