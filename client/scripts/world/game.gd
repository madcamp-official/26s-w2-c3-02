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
	GameData.game_event.connect(_on_game_event)
	_apply_phase_positions()
	_sync_remote_players()

func _exit_tree() -> void:
	if GameData.game_state_changed.is_connected(_sync_remote_players):
		GameData.game_state_changed.disconnect(_sync_remote_players)
	if GameData.game_event.is_connected(_on_game_event):
		GameData.game_event.disconnect(_on_game_event)

func _process(_delta: float) -> void:
	if _target:
		$Camera3D.position = _target.position + CAMERA_OFFSET

func _physics_process(_delta: float) -> void:
	_check_jail()

func _on_game_event(event: String, _data: Dictionary) -> void:
	if event == "game_started":
		_apply_phase_positions()

func _apply_phase_positions() -> void:
	_snap_local_node_to_team(_duck, "duck")
	_snap_local_node_to_team(_aligator, "tagger")

func _snap_local_node_to_team(node: Node3D, team: String) -> void:
	if node == null:
		return

	var player: Dictionary = _first_player_for_team(team)
	if player.is_empty():
		return

	var pos: Vector3 = _dict_to_vec3(player["position"])
	node.global_position = pos
	node.rotation.y = float(player.get("rotationY", 0.0))

func _first_player_for_team(team: String) -> Dictionary:
	for player in GameData.players:
		if str(player.get("team", "")) == team:
			return player
	return {}

func _check_jail() -> void:
	if GameData.phase != "playing":
		return
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
		var was_created := false
		if not _remote_players.has(pid):
			var node := PlayerScene.instantiate()
			node.character = p["character"]
			node.controllable = false
			add_child(node)
			node.set_display_name(pid)
			_remote_players[pid] = node
			was_created = true
		var pos: Dictionary = p["position"]
		var target_pos: Vector3 = _dict_to_vec3(pos)
		var target_rot: float = float(p["rotationY"])
		if was_created or GameData.phase == "countdown":
			_remote_players[pid].snap_to_state(target_pos, target_rot)
		else:
			_remote_players[pid].set_remote_state(target_pos, target_rot)

	for pid in _remote_players.keys():
		if not seen_ids.has(pid):
			_remote_players[pid].queue_free()
			_remote_players.erase(pid)

func _dict_to_vec3(pos: Dictionary) -> Vector3:
	return Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"]))
