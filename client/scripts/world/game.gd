extends Node3D

const CAMERA_OFFSET := Vector3(0, 16, 14)
const PlayerScene := preload("res://scenes/player/Player.tscn")

# Jail mechanic: if the duck touches the zone in front of the alligator's mouth,
# it is instantly teleported onto the jail island. The mouth sits ~5u ahead of
# the alligator body along its forward (-Z) axis (verified against the model).
const MOUTH_OFFSET := 5.0
const MOUTH_CATCH_RADIUS := 3.5

var _target: Node3D = null
var _remote_players: Dictionary = {}
var _duck: Node3D = null
var _aligator: Node3D = null
var _jail_point: Marker3D = null

func _ready() -> void:
	if GameData.phase == "lobby":
		MockServer.start_game()
	_target = get_tree().get_first_node_in_group("controllable_player")
	_duck = get_node_or_null("Duck")
	_aligator = get_node_or_null("Aligator")
	_jail_point = get_node_or_null("JailIsland/TeleportPoint")
	GameData.game_state_changed.connect(_sync_remote_players)
	_sync_remote_players()

func _process(_delta: float) -> void:
	if _target:
		$Camera3D.position = _target.position + CAMERA_OFFSET

func _physics_process(_delta: float) -> void:
	_check_jail()

func _check_jail() -> void:
	if _duck == null or _aligator == null or _jail_point == null:
		return
	var forward := -_aligator.global_transform.basis.z
	var mouth := _aligator.global_position + forward * MOUTH_OFFSET
	if _duck.global_position.distance_to(mouth) <= MOUTH_CATCH_RADIUS:
		# 모든 수감/텔레포트 처리는 MockServer.jail_player()에 위임
		MockServer.jail_player(GameData.local_player_id)


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
