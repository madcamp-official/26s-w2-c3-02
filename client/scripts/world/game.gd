extends Node3D

const CAMERA_OFFSET := Vector3(0, 16, 14)
const PlayerScene := preload("res://scenes/player/Player.tscn")

var _target: Node3D = null
var _remote_players: Dictionary = {}

func _ready() -> void:
	if GameData.phase == "lobby":
		MockServer.start_game()
	_target = get_tree().get_first_node_in_group("controllable_player")
	GameData.game_state_changed.connect(_sync_remote_players)
	_sync_remote_players()

func _process(_delta: float) -> void:
	if _target:
		$Camera3D.position = _target.position + CAMERA_OFFSET

func _sync_remote_players() -> void:
	var seen_ids := {}
	for p in GameData.players:
		var pid: String = p["playerId"]
		if pid == GameData.local_player_id:
			continue
		seen_ids[pid] = true
		if not _remote_players.has(pid):
			var node := PlayerScene.instantiate()
			node.character = p["character"]
			node.controllable = false
			add_child(node)
			node.set_display_name(pid)
			_remote_players[pid] = node
		var pos: Dictionary = p["position"]
		_remote_players[pid].set_remote_state(Vector3(pos["x"], pos["y"], pos["z"]), p["rotationY"])

	for pid in _remote_players.keys():
		if not seen_ids.has(pid):
			_remote_players[pid].queue_free()
			_remote_players.erase(pid)
