extends Node

const TICK_HZ := 10.0 # api-spec.md STATE_TICK_RATE
const GAME_DURATION := 180 # api-spec.md GAME_DURATION_SECONDS
const TARGET_SCORE := 5
const PICKUP_DISTANCE := 1.2 # api-spec.md PICKUP_DISTANCE
const DELIVER_DISTANCE := 6.0 # covers the scale-4 Nest footprint (~4.6u radius) so
# standing anywhere on/next to the visible nest triggers delivery
const NEST_POSITION := Vector3(0, 1.68, 65) # matches Pond.tscn Nest node
const DELIVER_MOVE_SPEED := 5.0 # units/sec each duckling swims into the nest once dropped off
const NEST_ARRIVE_DISTANCE := 0.35 # how close counts as "reached the nest center"
const NEST_SETTLE_TIME := 0.35 # linger inside the nest so the visual node catches up before vanishing
const INITIAL_DUCKLING_COUNT := TARGET_SCORE + 2
const WANDER_SPEED := 1.2
const WANDER_TURN_INTERVAL := 2.0
const POND_BOUND := 70.0
const FOLLOW_SPACING := 1.5
const FOLLOW_LEASH := FOLLOW_SPACING * 1.6 # hard cap on gap so it can't balloon at high speed
const FOLLOW_LERP_SPEED := 4.0
const FOLLOW_LERP_FALLOFF := 0.5 # each link back in the chain lags a bit more
const FOLLOW_LERP_MIN := 1.5
const MOVING_SPEED_THRESHOLD := 1.0 # player speed (units/sec) above which it's considered "moving"
const CIRCLE_RADIUS := 2.2
const CIRCLE_LERP_SPEED := 4.0
const CIRCLE_SPIN_SPEED := 0.4 # rad/sec, gentle idle rotation around the player
const ROOM_CODE_CHARS := "0123456789"
const ROOM_CODE_LENGTH := 4

var _broadcast_timer := 0.0
var _second_timer := 0.0
var _npc_angle := 0.0

# Internal mock-simulation-only bookkeeping (not part of the api-spec.md Duckling schema).
var _wander_state: Dictionary = {} # ducklingId -> {"dir": Vector2, "timer": float}
var _carry_queues: Dictionary = {} # playerId -> Array[ducklingId]
var _player_motion: Dictionary = {} # playerId -> {"prev_pos": Vector3, "is_moving": bool, "idle_spin": float}
var _delivering_settle: Dictionary = {} # ducklingId -> seconds spent settled at the nest center

func _ready() -> void:
	GameData.target_score = TARGET_SCORE
	_seed_lobby()

func _seed_lobby() -> void:
	GameData.room_id = _generate_room_code()
	GameData.phase = "lobby"
	GameData.players = [_fake_player("npc1", "Mock Police", "tagger", "aligator")]
	GameData.room_state_changed.emit()

func create_room(nickname: String, room_id: String = "") -> void:
	var normalized_room_id := _normalize_room_code(room_id)
	if normalized_room_id.length() != ROOM_CODE_LENGTH:
		normalized_room_id = _generate_room_code()
	_prepare_lobby(nickname, normalized_room_id)

func join_room(nickname: String, room_id: String) -> void:
	var normalized_room_id := _normalize_room_code(room_id)
	if normalized_room_id.length() != ROOM_CODE_LENGTH:
		normalized_room_id = _generate_room_code()
	_prepare_lobby(nickname, normalized_room_id)

func _generate_room_code() -> String:
	var code := ""
	for i in range(ROOM_CODE_LENGTH):
		var index := randi() % ROOM_CODE_CHARS.length()
		code += ROOM_CODE_CHARS.substr(index, 1)
	return code

func _normalize_room_code(room_id: String) -> String:
	var code := ""
	for i in range(room_id.length()):
		var c := room_id.substr(i, 1)
		if c >= "0" and c <= "9":
			code += c
		if code.length() >= ROOM_CODE_LENGTH:
			break
	return code

func _prepare_lobby(nickname: String, room_id: String) -> void:
	var normalized_nickname := nickname.strip_edges()
	if normalized_nickname == "":
		normalized_nickname = "Player"

	GameData.room_id = room_id
	GameData.local_nickname = normalized_nickname
	GameData.phase = "lobby"
	GameData.remaining_seconds = 0
	GameData.score = 0
	GameData.winner = null
	GameData.ducklings = []
	GameData.players = [
		_fake_player(GameData.local_player_id, normalized_nickname, "duck", "duck"),
		_fake_player("npc1", "Mock Police", "tagger", "aligator"),
	]
	GameData.room_state_changed.emit()

func start_game() -> void:
	_broadcast_timer = 0.0
	_second_timer = 0.0
	GameData.phase = "playing"
	GameData.remaining_seconds = GAME_DURATION
	GameData.score = 0
	GameData.winner = null
	_wander_state.clear()
	_carry_queues.clear()
	_player_motion.clear()
	_delivering_settle.clear()
	var ducklings: Array = []
	for i in range(INITIAL_DUCKLING_COUNT):
		ducklings.append(_fake_duckling("d%d" % (i + 1)))
	GameData.ducklings = ducklings
	GameData.game_event.emit("game_started", {})
	GameData.game_state_changed.emit()

func finish_game_for_test(winner: String = "duck") -> void:
	if winner != "duck" and winner != "tagger":
		winner = "duck"
	_end_game(winner)

func _process(delta: float) -> void:
	if GameData.phase != "playing":
		return

	_npc_angle += delta * 0.5
	for p in GameData.players:
		if p["playerId"] == "npc1":
			p["position"] = {"x": cos(_npc_angle) * 5.0, "y": 0.0, "z": sin(_npc_angle) * 5.0}

	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer -= 1.0
		GameData.remaining_seconds = max(0, GameData.remaining_seconds - 1)
		if GameData.remaining_seconds <= 0:
			_end_game("tagger")
			return

	_update_duckling_wander(delta)
	_check_pickup()
	_update_player_motion(delta)
	_update_duckling_follow(delta)
	_check_deliver()
	_update_delivering(delta)

	_broadcast_timer += delta
	if _broadcast_timer >= 1.0 / TICK_HZ:
		_broadcast_timer = 0.0
		GameData.game_state_changed.emit()

func _update_duckling_wander(delta: float) -> void:
	for d in GameData.ducklings:
		if d["state"] != "spawned":
			continue
		var id: String = d["ducklingId"]
		var w: Dictionary = _wander_state.get(id, {"dir": Vector2.ZERO, "timer": 0.0})
		w["timer"] -= delta
		if w["timer"] <= 0.0 or w["dir"] == Vector2.ZERO:
			var angle := randf_range(0.0, TAU)
			w["dir"] = Vector2(cos(angle), sin(angle))
			w["timer"] = randf_range(WANDER_TURN_INTERVAL * 0.5, WANDER_TURN_INTERVAL * 1.5)
		_wander_state[id] = w

		var pos: Dictionary = d["position"]
		var next_x: float = clamp(pos["x"] + w["dir"].x * WANDER_SPEED * delta, -POND_BOUND, POND_BOUND)
		var next_z: float = clamp(pos["z"] + w["dir"].y * WANDER_SPEED * delta, -POND_BOUND, POND_BOUND)
		d["position"] = {"x": next_x, "y": pos["y"], "z": next_z}

func _check_pickup() -> void:
	for player in GameData.players:
		if player["team"] != "duck":
			continue
		var player_id: String = player["playerId"]
		var player_pos := _dict_to_vec3(player["position"])
		for d in GameData.ducklings:
			if d["state"] != "spawned":
				continue
			var duckling_pos := _dict_to_vec3(d["position"])
			if player_pos.distance_to(duckling_pos) <= PICKUP_DISTANCE:
				d["state"] = "carried"
				d["carrierPlayerId"] = player_id
				_wander_state.erase(d["ducklingId"])
				var queue: Array = _carry_queues.get(player_id, [])
				queue.append(d["ducklingId"])
				_carry_queues[player_id] = queue

func _update_player_motion(delta: float) -> void:
	for player in GameData.players:
		if player["team"] != "duck":
			continue
		var player_id: String = player["playerId"]
		var pos := _dict_to_vec3(player["position"])
		var m: Dictionary = _player_motion.get(player_id, {"prev_pos": pos, "is_moving": false, "idle_spin": 0.0})
		var speed := 0.0
		if delta > 0.0:
			speed = pos.distance_to(m["prev_pos"]) / delta
		m["is_moving"] = speed > MOVING_SPEED_THRESHOLD
		m["prev_pos"] = pos
		if not m["is_moving"]:
			m["idle_spin"] += delta * CIRCLE_SPIN_SPEED
		_player_motion[player_id] = m

func _update_duckling_follow(delta: float) -> void:
	var players_by_id := {}
	for player in GameData.players:
		players_by_id[player["playerId"]] = player

	var ducklings_by_id := {}
	for d in GameData.ducklings:
		ducklings_by_id[d["ducklingId"]] = d

	for player_id in _carry_queues.keys():
		var player = players_by_id.get(player_id)
		if player == null:
			continue
		var queue: Array = _carry_queues[player_id]
		if queue.is_empty():
			continue
		var player_pos := _dict_to_vec3(player["position"])
		var motion: Dictionary = _player_motion.get(player_id, {"is_moving": false, "idle_spin": 0.0})

		if motion["is_moving"]:
			# Leader-follows-leader chain: each duckling keeps roughly FOLLOW_SPACING
			# distance from the node in front of it, but lags behind with its own
			# lerp speed so the line goes loose/slack through turns instead of
			# rotating as a rigid rod.
			var leader_pos := player_pos
			for i in range(queue.size()):
				var d = ducklings_by_id.get(queue[i])
				if d == null:
					continue
				var current := _dict_to_vec3(d["position"])
				var to_leader := current - leader_pos
				var dist := to_leader.length()
				var dir := to_leader.normalized() if dist > 0.01 else Vector3.BACK
				var next_pos: Vector3
				if dist > FOLLOW_LEASH:
					# Rope pulled taut: hard-clamp the gap so it can never keep growing
					# while the leader is moving faster than the lerp can catch up.
					next_pos = leader_pos + dir * FOLLOW_LEASH
				else:
					var target := leader_pos + dir * FOLLOW_SPACING
					var lerp_speed: float = max(FOLLOW_LERP_MIN, FOLLOW_LERP_SPEED - i * FOLLOW_LERP_FALLOFF)
					next_pos = current.lerp(target, clamp(delta * lerp_speed, 0.0, 1.0))
				d["position"] = {"x": next_pos.x, "y": next_pos.y, "z": next_pos.z}
				leader_pos = next_pos
		else:
			# Idle: gather loosely in a slowly-rotating circle beside the player.
			var count := queue.size()
			for i in range(count):
				var d = ducklings_by_id.get(queue[i])
				if d == null:
					continue
				var angle: float = motion["idle_spin"] + (TAU / count) * i
				var target := player_pos + Vector3(cos(angle), 0, sin(angle)) * CIRCLE_RADIUS
				var current := _dict_to_vec3(d["position"])
				var next_pos := current.lerp(target, clamp(delta * CIRCLE_LERP_SPEED, 0.0, 1.0))
				d["position"] = {"x": next_pos.x, "y": next_pos.y, "z": next_pos.z}

func _check_deliver() -> void:
	for player in GameData.players:
		if player["team"] != "duck":
			continue
		var player_id: String = player["playerId"]
		var queue: Array = _carry_queues.get(player_id, [])
		if queue.is_empty():
			continue
		var player_pos := _dict_to_vec3(player["position"])
		if player_pos.distance_to(NEST_POSITION) > DELIVER_DISTANCE:
			continue

		var ducklings_by_id := {}
		for d in GameData.ducklings:
			ducklings_by_id[d["ducklingId"]] = d

		# Hand the carried ducklings off to the "delivering" state instead of
		# scoring them instantly. They then swim into the nest on their own
		# (see _update_delivering) and are scored the moment each one arrives.
		for duckling_id in queue:
			var d = ducklings_by_id.get(duckling_id)
			if d == null:
				continue
			d["state"] = "delivering"
			d["carrierPlayerId"] = null

		_carry_queues[player_id] = []

func _update_delivering(delta: float) -> void:
	for d in GameData.ducklings:
		if d["state"] != "delivering":
			continue
		var id: String = d["ducklingId"]
		var current := _dict_to_vec3(d["position"])
		var to_nest := NEST_POSITION - current
		var dist := to_nest.length()
		if dist > NEST_ARRIVE_DISTANCE:
			var step: float = min(DELIVER_MOVE_SPEED * delta, dist)
			var next_pos := current + to_nest.normalized() * step
			d["position"] = {"x": next_pos.x, "y": next_pos.y, "z": next_pos.z}
			continue

		# Reached the nest: pin it there and let it settle briefly so the visual
		# duckling can catch up, then mark delivered (which despawns the node).
		d["position"] = {"x": NEST_POSITION.x, "y": NEST_POSITION.y, "z": NEST_POSITION.z}
		var settled: float = _delivering_settle.get(id, 0.0) + delta
		_delivering_settle[id] = settled
		if settled >= NEST_SETTLE_TIME:
			_delivering_settle.erase(id)
			_rescue_duckling(d)

func _rescue_duckling(d: Dictionary) -> void:
	d["state"] = "delivered"
	GameData.score += 1
	GameData.game_event.emit("duckling_delivered", {"ducklingId": d["ducklingId"], "count": 1})
	if GameData.score >= GameData.target_score:
		_end_game("duck")

func _dict_to_vec3(pos: Dictionary) -> Vector3:
	return Vector3(pos["x"], pos["y"], pos["z"])

func _end_game(winner: String) -> void:
	GameData.phase = "ended"
	GameData.winner = winner
	GameData.game_event.emit("game_ended", {"winner": winner})
	GameData.game_state_changed.emit()

func _fake_player(id: String, nickname: String, team: String, character: String) -> Dictionary:
	return {
		"playerId": id,
		"nickname": nickname,
		"team": team,
		"character": character,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"rotationY": 0.0,
		"state": "idle",
		"carryingDucklingId": null,
		"jailedUntil": null,
	}

func _fake_duckling(id: String) -> Dictionary:
	return {
		"ducklingId": id,
		"position": {"x": randf_range(-15.0, 15.0), "y": 0.0, "z": randf_range(-15.0, 15.0)},
		"state": "spawned",
		"carrierPlayerId": null,
	}
