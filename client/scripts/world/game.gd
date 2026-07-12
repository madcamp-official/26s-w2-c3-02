extends Node3D

const CAMERA_OFFSET := Vector3(0, 16, 14)
const PlayerScene := preload("res://scenes/player/Player.tscn")

# Jail mechanic: the alligator dashes (Player.gd handles the movement/cooldown) and,
# for the whole duration of the dash, any duck inside the dash's path rectangle gets
# caught. Player.gd fixes dash_start_pos/dash_end_pos the instant the dash begins, so
# the rectangle doesn't depend on per-frame position sampling (no risk of missing the
# first/last movement chunk). DASH_CATCH_HALF_WIDTH is double
# CHARACTER_CONFIG["aligator"]["collision_size"].x (4.0) in player.gd, i.e. the
# corridor is a full body-width wider than the alligator on each side.
const DASH_CATCH_HALF_WIDTH := 4.0

var _target: Node3D = null
var _remote_players: Dictionary = {}
var _duck: Node3D = null
var _aligator: Node3D = null
var _jail_point: Marker3D = null
var _arrow_control_player_id := ""

func _ready() -> void:
	_duck = get_node_or_null("Duck")
	_aligator = get_node_or_null("Aligator")
	_jail_point = get_node_or_null("JailIsland/TeleportPoint")
	# Obstacles must be registered before MockServer spawns ducklings, otherwise
	# the very first spawn positions are computed against an empty obstacle list.
	_register_pond_obstacles()
	if GameData.phase == "lobby":
		MockServer.start_game()
	_configure_controlled_players()
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
	var jail_island := get_node_or_null("JailIsland")
	if jail_island:
		var jail_obs := _obstacle_from_node(jail_island)
		if not jail_obs.is_empty():
			obstacles.append(jail_obs)
	MockServer.register_obstacles(obstacles)

	# 연못 바닥(물)과 섬(땅)을 구분해서 밟은 표면에 따라 캐릭터의 물 잠김 표현을
	# 다르게 적용할 수 있도록 표식을 남긴다 (player.gd _update_water_submersion 참고).
	var ground := pond.get_node_or_null("Ground")
	if ground:
		ground.add_to_group("water_surface")

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

	var dash_active: bool = bool(_aligator.get("dash_active"))
	if not dash_active:
		return

	# player.gd가 대시 시작 순간에 고정해 둔 시작/도착 지점을 그대로 사용한다.
	# 프레임마다 위치를 다시 샘플링하지 않으므로 대시 도중 어느 프레임에 검사하든
	# 항상 전체 경로 사각형 기준으로 판정되고, 처리 순서에 따른 빈틈이 생기지 않는다.
	var seg_start: Vector3 = _aligator.get("dash_start_pos")
	var seg_end: Vector3 = _aligator.get("dash_end_pos")
	_check_dash_catch(seg_start, seg_end)


func _check_dash_catch(seg_start: Vector3, seg_end: Vector3) -> void:
	var a := Vector2(seg_start.x, seg_start.z)
	var b := Vector2(seg_end.x, seg_end.z)
	for duck_node in _duck_jail_candidates():
		var duck_player_id := str(duck_node.get("controlled_player_id"))
		if duck_player_id == "" or _is_player_jailed(duck_player_id):
			continue
		var p := Vector2(duck_node.global_position.x, duck_node.global_position.z)
		if _distance_point_to_segment(p, a, b) <= DASH_CATCH_HALF_WIDTH:
			# 경로와 겹치는 그 프레임에 바로 수감 처리해 "부딪힌 순간 = 잡힘"이 명확하게 보이도록 한다.
			# 모든 수감/텔레포트 처리는 MockServer.jail_player()에 위임
			MockServer.jail_player(duck_player_id)


func _distance_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


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
