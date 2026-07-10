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
