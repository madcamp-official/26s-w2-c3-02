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
var _arrow_control_player_id := ""

func _ready() -> void:
	if GameData.phase == "lobby":
		MockServer.start_game()
	_duck = get_node_or_null("Duck")
	_aligator = get_node_or_null("Aligator")
	_jail_point = get_node_or_null("JailIsland/TeleportPoint")
	_configure_controlled_players()
	_register_pond_obstacles()
	GameData.game_state_changed.connect(_sync_remote_players)
	GameData.game_event.connect(_on_game_event)
	_apply_phase_positions()
	_sync_remote_players()

# 새끼오리가 바위/덤불/나무 안으로 들어가지 않도록, Pond의 소품들을 원형 장애물
# 목록(월드 좌표 + 반지름)으로 변환해 MockServer의 이동 계산에 넘겨준다.
func _register_pond_obstacles() -> void:
	var pond := get_node_or_null("Pond")
	if pond == null:
		return
	var obstacles: Array = []
	for child in pond.get_children():
		if child.name.begins_with("Rock"):
			var model := child.get_node_or_null("Model")
			if model:
				var obs := _obstacle_from_node(model)
				if not obs.is_empty():
					obstacles.append(obs)
		elif child.name.begins_with("Bush") or child.name.begins_with("Tree"):
			var obs := _obstacle_from_node(child)
			if not obs.is_empty():
				obstacles.append(obs)
	MockServer.register_obstacles(obstacles)

func _obstacle_from_node(node: Node3D) -> Dictionary:
	var aabb: AABB
	var first := true
	for mesh in _find_mesh_instances(node):
		var world_aabb: AABB = mesh.global_transform * mesh.get_aabb()
		aabb = world_aabb if first else aabb.merge(world_aabb)
		first = false
	if first:
		return {}
	var center := aabb.position + aabb.size * 0.5
	var radius: float = max(aabb.size.x, aabb.size.z) * 0.5
	return {"pos": Vector2(center.x, center.z), "radius": radius}

func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _find_mesh_instances(c)
	return out

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
		_configure_controlled_players()
		_apply_phase_positions()

func _configure_controlled_players() -> void:
	_arrow_control_player_id = MockServer.arrow_control_player_id()
	var local_team := MockServer.local_player_team()

	if local_team == "tagger":
		_configure_controlled_node(_aligator, GameData.local_player_id, "wasd", true)
		_configure_controlled_node(_duck, _arrow_control_player_id, "arrows", _arrow_control_player_id != "")
		_target = _aligator
	else:
		_configure_controlled_node(_duck, GameData.local_player_id, "wasd", true)
		_configure_controlled_node(_aligator, _arrow_control_player_id, "arrows", _arrow_control_player_id != "")
		_target = _duck

func _configure_controlled_node(node: Node3D, player_id: String, scheme: String, enabled: bool) -> void:
	if node == null:
		return
	node.set("controllable", enabled)
	node.set("control_scheme", scheme)
	node.set("controlled_player_id", player_id)
	if player_id != "":
		var player := _player_by_id(player_id)
		if not player.is_empty():
			node.call("set_display_name", str(player.get("nickname", player_id)))

func _apply_phase_positions() -> void:
	var duck_player_id := ""
	if _duck != null:
		duck_player_id = str(_duck.get("controlled_player_id"))
	var aligator_player_id := ""
	if _aligator != null:
		aligator_player_id = str(_aligator.get("controlled_player_id"))
	_snap_node_to_player_id(_duck, duck_player_id)
	_snap_node_to_player_id(_aligator, aligator_player_id)

func _snap_node_to_player_id(node: Node3D, player_id: String) -> void:
	if node == null:
		return

	var player: Dictionary = _player_by_id(player_id)
	if player.is_empty():
		return

	var pos: Vector3 = _dict_to_vec3(player["position"])
	node.global_position = pos
	node.rotation.y = float(player.get("rotationY", 0.0))

func _player_by_id(player_id: String) -> Dictionary:
	for player in GameData.players:
		if str(player.get("playerId", "")) == player_id:
			return player
	return {}

func _check_jail() -> void:
	if GameData.phase != "playing":
		return
	if _aligator == null or _jail_point == null:
		return
	var forward := -_aligator.global_transform.basis.z
	var mouth := _aligator.global_position + forward * MOUTH_OFFSET
	for duck_node in _duck_jail_candidates():
		if duck_node.global_position.distance_to(mouth) > MOUTH_CATCH_RADIUS:
			continue
		# 모든 수감/텔레포트 처리는 MockServer.jail_player()에 위임
		var duck_player_id := str(duck_node.get("controlled_player_id"))
		if duck_player_id != "" and not _is_player_jailed(duck_player_id):
			MockServer.jail_player(duck_player_id)


func _duck_jail_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if _is_duck_player_node(_duck):
		candidates.append(_duck)
	for value in _remote_players.values():
		var node := value as Node3D
		if _is_duck_player_node(node):
			candidates.append(node)
	return candidates


func _is_duck_player_node(node: Node) -> bool:
	if node == null:
		return false
	var player_id := str(node.get("controlled_player_id"))
	if player_id == "":
		return false
	var player := _player_by_id(player_id)
	if player.is_empty():
		return false
	return str(player.get("team", "")) == "duck"


func _is_player_jailed(player_id: String) -> bool:
	var player := _player_by_id(player_id)
	return not player.is_empty() and str(player.get("state", "")) == "jailed"


func _sync_remote_players() -> void:
	var seen_ids := {}
	for p in GameData.players:
		var pid: String = p["playerId"]
		if pid == GameData.local_player_id:
			continue
		if pid == _arrow_control_player_id:
			continue
		seen_ids[pid] = true
		var was_created := false
		if not _remote_players.has(pid):
			var node := PlayerScene.instantiate()
			node.character = p["character"]
			node.controllable = false
			node.controlled_player_id = pid
			add_child(node)
			node.set_display_name(str(p.get("nickname", pid)))
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
