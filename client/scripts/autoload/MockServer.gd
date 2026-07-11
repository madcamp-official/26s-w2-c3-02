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

# 감옥 관련 상수
const JAIL_POSITION := Vector3(-32, 7, 32)       # 감옥 텔레포트 목표 좌표 (섬 위)
const JAIL_RELEASE_POSITION := Vector3(-15, 0, 15) # 석방 후 복귀 좌표
const RESCUE_RADIUS := 10.0                        # 탈옥 시도 가능 거리
const RESCUE_DURATION := 3.0                       # 탈옥에 필요한 시간(초)
const JAIL_SECONDS := 8.0                          # 1인 플레이 시 자동 탈출 시간(초)

var _broadcast_timer := 0.0
var _second_timer := 0.0
var _npc_angle := 0.0

# Internal mock-simulation-only bookkeeping (not part of the api-spec.md Duckling schema).
var _wander_state: Dictionary = {} # ducklingId -> {"dir": Vector2, "timer": float}
var _carry_queues: Dictionary = {} # playerId -> Array[ducklingId]
var _player_motion: Dictionary = {} # playerId -> {"prev_pos": Vector3, "is_moving": bool, "idle_spin": float}
var _delivering_settle: Dictionary = {} # ducklingId -> seconds spent settled at the nest center
var _delivery_batches: Dictionary = {} # batchId -> {playerId, playerName, total, delivered}
var _next_delivery_batch_id := 1

# 감옥/구출 내부 상태
var _jail_timer: float = 0.0        # 1인 자동탈출 카운트다운
var _rescue_timer: float = 0.0      # 현재 구출 진행 시간
var _is_rescuing: bool = false      # 구출 진행 중 여부
var _active_rescuer_id: String = "" # 구출 중인 플레이어 id
var _has_fake_duck: bool = false     # 디버그: 가짜 오리(npc2) 존재 여부

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
	_delivery_batches.clear()
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
	_delivery_batches.clear()
	_next_delivery_batch_id = 1
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
	_update_jail_and_rescue(delta)

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

func release_ducklings(player_id: String, at_position: Vector3) -> void:
	# Called when the duck is caught: drop everything it was carrying back into the
	# pond at the catch spot (state -> spawned so they wander and can be re-collected).
	var queue: Array = _carry_queues.get(player_id, [])
	if queue.is_empty():
		return
	var ducklings_by_id := {}
	for d in GameData.ducklings:
		ducklings_by_id[d["ducklingId"]] = d
	for duckling_id in queue:
		var d = ducklings_by_id.get(duckling_id)
		if d == null:
			continue
		var angle := randf_range(0.0, TAU)
		var radius := randf_range(1.0, 3.0)
		d["position"] = {"x": at_position.x + cos(angle) * radius, "y": 0.0, "z": at_position.z + sin(angle) * radius}
		d["state"] = "spawned"
		d["carrierPlayerId"] = null
		_wander_state.erase(duckling_id)
	_carry_queues[player_id] = []
	GameData.game_state_changed.emit()

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

		var delivering_ducklings: Array = []
		for duckling_id in queue:
			var d = ducklings_by_id.get(duckling_id)
			if d == null:
				continue
			delivering_ducklings.append(d)

		if delivering_ducklings.is_empty():
			_carry_queues[player_id] = []
			continue

		var batch_id: String = "delivery_%d" % _next_delivery_batch_id
		_next_delivery_batch_id += 1
		_delivery_batches[batch_id] = {
			"playerId": player_id,
			"playerName": str(player.get("nickname", player_id)),
			"total": delivering_ducklings.size(),
			"delivered": 0,
		}

		# Hand the carried ducklings off to the "delivering" state instead of
		# scoring them instantly. They then swim into the nest on their own
		# (see _update_delivering), then emit one notification when the whole
		# batch has arrived.
		for d in delivering_ducklings:
			d["state"] = "delivering"
			d["carrierPlayerId"] = null
			d["deliveryBatchId"] = batch_id

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

	var batch_id: String = str(d.get("deliveryBatchId", ""))
	d.erase("deliveryBatchId")

	if batch_id == "" or not _delivery_batches.has(batch_id):
		GameData.game_event.emit("duckling_delivered", {"ducklingId": d["ducklingId"], "count": 1})
		if GameData.score >= GameData.target_score:
			_end_game("duck")
		return

	var batch: Dictionary = _delivery_batches[batch_id]
	batch["delivered"] = int(batch.get("delivered", 0)) + 1
	_delivery_batches[batch_id] = batch

	if int(batch["delivered"]) < int(batch["total"]):
		return

	_delivery_batches.erase(batch_id)
	GameData.game_event.emit("duckling_delivered", {
		"ducklingId": d["ducklingId"],
		"count": int(batch["total"]),
		"playerId": str(batch["playerId"]),
		"playerName": str(batch["playerName"]),
	})
	if GameData.score >= GameData.target_score:
		_end_game("duck")

# ──────────────────────────────────────────────────────────────────────────────
# 감옥 / 구출 로직
# ──────────────────────────────────────────────────────────────────────────────

func jail_player(player_id: String) -> void:
	# 해당 플레이어를 수감 상태로 전환하고 들고 있던 새끼오리를 떨어뜨린다.
	for p in GameData.players:
		if p["playerId"] != player_id:
			continue
		if p["state"] == "jailed":
			return  # 이미 수감 중
		p["state"] = "jailed"
		var catch_pos := _dict_to_vec3(p["position"])
		p["position"] = {"x": JAIL_POSITION.x, "y": JAIL_POSITION.y, "z": JAIL_POSITION.z}
		release_ducklings(player_id, catch_pos)
		break

	# 1인 자동탈출 타이머 초기화
	_jail_timer = JAIL_SECONDS
	# 구출 진행 리셋
	_reset_rescue()
	GameData.game_event.emit("player_jailed", {"playerId": player_id})
	GameData.game_state_changed.emit()

func _release_player(player_id: String, is_rescue: bool) -> void:
	# 플레이어를 석방하고 감옥 밖으로 이동시킨다.
	for p in GameData.players:
		if p["playerId"] != player_id:
			continue
		p["state"] = "idle"
		p["position"] = {
			"x": JAIL_RELEASE_POSITION.x,
			"y": JAIL_RELEASE_POSITION.y,
			"z": JAIL_RELEASE_POSITION.z,
		}
		break

	if is_rescue:
		GameData.game_event.emit("player_rescued", {
			"targetId": player_id,
			"rescuerId": _active_rescuer_id,
		})
	else:
		GameData.game_event.emit("player_released", {"playerId": player_id})
	GameData.game_state_changed.emit()

func _rescue_all_jailed() -> void:
	# 현재 수감 중인 오리 플레이어를 전원 석방한다.
	var jailed_ids: Array = []
	for p in GameData.players:
		if p["team"] == "duck" and p["state"] == "jailed":
			jailed_ids.append(p["playerId"])
	for pid in jailed_ids:
		_release_player(pid, true)

func _reset_rescue() -> void:
	_rescue_timer = 0.0
	_is_rescuing = false
	_active_rescuer_id = ""
	GameData.rescue_progress = 0.0
	GameData.active_rescuer_id = ""

func _count_jailed_ducks() -> int:
	var count := 0
	for p in GameData.players:
		if p["team"] == "duck" and p["state"] == "jailed":
			count += 1
	return count

func _count_duck_players() -> int:
	var count := 0
	for p in GameData.players:
		if p["team"] == "duck":
			count += 1
	return count

func _update_jail_and_rescue(delta: float) -> void:
	var jailed_count := _count_jailed_ducks()
	var total_ducks := _count_duck_players()

	# 수감된 오리가 없으면 리셋 후 종료
	if jailed_count == 0:
		if _is_rescuing:
			_reset_rescue()
		return

	# ── 1인 모드: 자동 탈출 ──────────────────────────────────────────────────
	if total_ducks == 1 or jailed_count == total_ducks:
		# 모든 오리가 수감된 경우: 자동탈출 타이머만 진행
		_jail_timer -= delta
		if _jail_timer <= 0:
			var jailed_ids: Array = []
			for p in GameData.players:
				if p["team"] == "duck" and p["state"] == "jailed":
					jailed_ids.append(p["playerId"])
			for pid in jailed_ids:
				_active_rescuer_id = "" # 자동탈출은 구출자 없음
				_release_player(pid, false)
			_reset_rescue()
		return

	# ── 멀티 모드: 자유 오리가 감옥 근처에 있으면 구출 진행 ─────────────────
	var jail_pos_vec := JAIL_POSITION
	var potential_rescuer_id := ""

	for p in GameData.players:
		if p["team"] != "duck":
			continue
		if p["state"] == "jailed":
			continue
		var ppos := _dict_to_vec3(p["position"])
		if ppos.distance_to(jail_pos_vec) <= RESCUE_RADIUS:
			potential_rescuer_id = p["playerId"]
			break

	if potential_rescuer_id == "":
		# 구출자가 구역을 벗어남 → 진행 리셋
		if _is_rescuing:
			_reset_rescue()
		return

	# 새 구출자가 들어왔을 때 또는 이미 진행 중인 경우
	if not _is_rescuing:
		_is_rescuing = true
		_active_rescuer_id = potential_rescuer_id
		_rescue_timer = 0.0
		GameData.active_rescuer_id = potential_rescuer_id
		GameData.game_event.emit("rescue_started", {"rescuerId": potential_rescuer_id})

	# 같은 구출자가 계속 머무는 경우만 진행 (다른 사람이 오면 리셋)
	if _active_rescuer_id != potential_rescuer_id:
		_reset_rescue()
		return

	_rescue_timer += delta
	GameData.rescue_progress = clamp(_rescue_timer / RESCUE_DURATION, 0.0, 1.0)

	if _rescue_timer >= RESCUE_DURATION:
		var rescuer_id := _active_rescuer_id
		_rescue_all_jailed()
		_reset_rescue()

# ──────────────────────────────────────────────────────────────────────────────
# 디버그 헬퍼
# ──────────────────────────────────────────────────────────────────────────────

func debug_jail_local_player() -> void:
	if GameData.phase != "playing":
		return
	jail_player(GameData.local_player_id)

func debug_toggle_fake_duck() -> void:
	if GameData.phase != "playing":
		return
	if _has_fake_duck:
		# npc2 제거
		var new_players: Array = []
		for p in GameData.players:
			if p["playerId"] != "npc2":
				new_players.append(p)
		GameData.players = new_players
		_carry_queues.erase("npc2")
		_player_motion.erase("npc2")
		_has_fake_duck = false
	else:
		# npc2 추가
		GameData.players.append(_fake_player("npc2", "Mock Duck", "duck", "duck"))
		_has_fake_duck = true
	GameData.game_state_changed.emit()

func debug_jail_fake_duck() -> void:
	if GameData.phase != "playing" or not _has_fake_duck:
		return
	jail_player("npc2")

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
