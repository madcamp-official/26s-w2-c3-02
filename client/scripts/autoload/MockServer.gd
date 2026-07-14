extends Node

## 실제 Node.js + ws 서버(server/)에 접속하는 네트워크 클라이언트 구현.
## 예전 MockServer(로컬 시뮬레이션)를 대체한다. 오토로드 이름(MockServer)과 공개
## 함수 시그니처는 최대한 유지해 메뉴/HUD/월드/플레이어 쪽 호출부를 거의 건드리지
## 않고 교체할 수 있게 했다. 메시지 계약은 Docs/api-spec.md를 기준으로 한다.

const SERVER_URL := "wss://cops-and-ducks.madcamp-kaist.org/ws" # 배포 시 이 상수만 바꾸면 된다.
## const SERVER_URL := "ws://127.0.0.1:8080/ws" # 로컬 서버 테스트용
## const SERVER_URL := "wss://54.180.118.137:8080/ws"

const MVP_PLAYER_LIMIT := 5
const MVP_TAGGER_COUNT := 1
const JAIL_POSITION := Vector3(0, 6.7, 0) # 감옥 텔레포트 목표 좌표 (서버 상수와 동일해야 함)

const INPUT_SEND_INTERVAL := 1.0 / 30.0 # player:input 전송 주기(초)
const RECONNECT_INTERVAL := 2.0
const REQUEST_TIMEOUT_SECONDS := 8.0 # 연결이 끊긴 채로 요청이 걸려 있을 때 무한 대기하지 않도록

signal _response_received(request_id: String, result: Dictionary)

var _peer := WebSocketPeer.new()
var _reconnect_timer := 0.0
var _awaited_request_ids: Dictionary = {} # request_id -> true, _send_and_await로 응답을 기다리는 중인 요청들

var _pending_position := Vector3.ZERO
var _pending_rotation_y := 0.0
var _has_pending_input := false
var _input_send_timer := 0.0

func _ready() -> void:
	_peer.connect_to_url(SERVER_URL)

func _process(delta: float) -> void:
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			_handle_packet(_peer.get_packet())
		_flush_pending_input(delta)
	elif state == WebSocketPeer.STATE_CLOSED:
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_INTERVAL:
			_reconnect_timer = 0.0
			_peer = WebSocketPeer.new()
			_peer.connect_to_url(SERVER_URL)

# ──────────────────────────────────────────────────────────────────────────────
# 저수준 송수신
# ──────────────────────────────────────────────────────────────────────────────

func _next_request_id() -> String:
	return "%d_%d" % [Time.get_ticks_usec(), randi()]

# 항상 requestId를 붙여서 보낸다. create_room처럼 응답을 기다리는 요청뿐 아니라,
# set_player_team/start_game처럼 "보내고 잊어버리는(fire-and-forget)" 요청도
# 서버가 error로 거부했을 때 그 requestId를 그대로 돌려주므로, 어느 쪽이든
# _handle_packet에서 거부 사유를 놓치지 않고 처리할 수 있다.
func _send(type: String, payload: Dictionary, room_id: String = "") -> String:
	var request_id := _next_request_id()
	var msg := {"type": type, "requestId": request_id, "payload": payload}
	if room_id != "":
		msg["roomId"] = room_id
	_peer.send_text(JSON.stringify(msg))
	return request_id

func _send_and_await(type: String, payload: Dictionary, room_id: String = "") -> Dictionary:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return {"ok": false, "message": "서버에 연결할 수 없습니다."}
	var request_id := _send(type, payload, room_id)
	_awaited_request_ids[request_id] = true
	_start_request_timeout(request_id)

	var result: Dictionary = {}
	var resolved := false
	while not resolved:
		var args = await _response_received
		if args[0] == request_id:
			result = args[1]
			resolved = true
	_awaited_request_ids.erase(request_id)
	return result

# 응답을 기다리는 도중 연결이 끊기면(_peer가 새 객체로 교체되며 예전 요청은 영영
# 응답받을 수 없게 된다) 호출자가 영원히 멈추지 않도록, 타임아웃 시 같은 신호로
# 실패 응답을 대신 흘려보내 _send_and_await의 대기 루프를 풀어준다.
func _start_request_timeout(request_id: String) -> void:
	await get_tree().create_timer(REQUEST_TIMEOUT_SECONDS).timeout
	if _awaited_request_ids.has(request_id):
		_awaited_request_ids.erase(request_id)
		_response_received.emit(request_id, {"ok": false, "message": "서버 응답이 없습니다. 다시 시도해주세요."})

func _handle_packet(packet: PackedByteArray) -> void:
	var parsed = JSON.parse_string(packet.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	var type := str(msg.get("type", ""))
	var payload: Dictionary = msg.get("payload", {})

	match type:
		"room:joined":
			GameData.local_player_id = str(payload.get("playerId", GameData.local_player_id))
			GameData.room_id = str(msg.get("roomId", GameData.room_id))
			GameData.is_host = bool(payload.get("isHost", false))
			_apply_room_state(payload.get("state", {}))
			_resolve_request(msg, {"ok": true, "isHost": GameData.is_host})
		"room:list":
			_resolve_request(msg, {"ok": true, "rooms": payload.get("rooms", [])})
		"room:state":
			_apply_room_state(payload)
			GameData.room_state_changed.emit()
		"game:state":
			_apply_game_state(payload)
			GameData.game_state_changed.emit()
		"game:event":
			GameData.game_event.emit(str(payload.get("event", "")), payload)
		"error":
			_handle_error_message(msg, payload)

# _send_and_await로 응답을 기다리는 중인 요청의 오류면 그 호출자에게 상관관계로
# 돌려주고, 그렇지 않으면(set_player_team/start_game 같은 fire-and-forget 요청)
# GameData.action_error로 브로드캐스트해 UI가 알림을 띄울 수 있게 한다.
func _handle_error_message(msg: Dictionary, payload: Dictionary) -> void:
	var request_id := str(msg.get("requestId", ""))
	var code := str(payload.get("code", ""))
	var message := str(payload.get("message", ""))
	if request_id != "" and _awaited_request_ids.has(request_id):
		_resolve_request(msg, {"ok": false, "code": code, "message": message})
	else:
		GameData.action_error.emit(code, message)

func _resolve_request(msg: Dictionary, result: Dictionary) -> void:
	var request_id := str(msg.get("requestId", ""))
	if request_id != "":
		_response_received.emit(request_id, result)

func _apply_room_state(state: Dictionary) -> void:
	if state.has("roomName"):
		GameData.room_name = str(state.get("roomName", ""))
	if state.has("isPrivate"):
		GameData.room_is_private = bool(state.get("isPrivate", false))
	if state.has("joinCode"):
		var join_code_value = state.get("joinCode")
		GameData.join_code = "" if join_code_value == null else str(join_code_value)
	if state.has("players"):
		GameData.players = state["players"]
	if state.has("hostPlayerId"):
		GameData.is_host = str(state["hostPlayerId"]) == GameData.local_player_id

func _apply_game_state(payload: Dictionary) -> void:
	GameData.phase = str(payload.get("phase", GameData.phase))
	GameData.countdown_seconds = int(payload.get("countdownSeconds", GameData.countdown_seconds))
	GameData.remaining_seconds = int(payload.get("remainingSeconds", GameData.remaining_seconds))
	GameData.score = int(payload.get("score", GameData.score))
	GameData.target_score = int(payload.get("targetScore", GameData.target_score))
	if payload.has("players"):
		GameData.players = payload["players"]
	if payload.has("ducklings"):
		GameData.ducklings = payload["ducklings"]
	GameData.winner = payload.get("winner", GameData.winner)
	var end_reason_value = payload.get("endReason")
	GameData.end_reason = str(end_reason_value) if end_reason_value != null else ""
	GameData.rescue_progress = float(payload.get("rescueProgress", GameData.rescue_progress))
	GameData.active_rescuer_id = str(payload.get("activeRescuerId", GameData.active_rescuer_id))

func _flush_pending_input(delta: float) -> void:
	_input_send_timer += delta
	if not _has_pending_input or _input_send_timer < INPUT_SEND_INTERVAL:
		return
	_input_send_timer = 0.0
	_has_pending_input = false
	_send("player:input", {
		"position": {"x": _pending_position.x, "y": _pending_position.y, "z": _pending_position.z},
		"rotationY": _pending_rotation_y,
	}, GameData.room_id)

# ──────────────────────────────────────────────────────────────────────────────
# 방/로비
# ──────────────────────────────────────────────────────────────────────────────

func create_room(nickname: String, room_name: String = "", character_skin: String = "duck", is_private: bool = false, tagger_skin: String = "aligator") -> Dictionary:
	var result: Dictionary = await _send_and_await("room:create", {
		"nickname": nickname,
		"roomName": room_name,
		"isPrivate": is_private,
		"characterSkin": character_skin,
		"taggerSkin": tagger_skin,
	})
	if not result.get("ok", false):
		return {"ok": false, "message": result.get("message", "방을 만들 수 없습니다.")}
	GameData.room_is_private = is_private
	GameData.menu_entry_view = "lobby"
	return {"ok": true}

func join_room(nickname: String, room_id: String, join_code: String = "", character_skin: String = "duck", tagger_skin: String = "aligator") -> Dictionary:
	var result: Dictionary = await _send_and_await("room:join", {
		"nickname": nickname,
		"joinCode": join_code,
		"characterSkin": character_skin,
		"taggerSkin": tagger_skin,
	}, room_id)
	if not result.get("ok", false):
		return {"ok": false, "message": result.get("message", "방에 입장할 수 없습니다.")}
	GameData.menu_entry_view = "lobby"
	return {"ok": true}

func list_rooms() -> Array:
	var result: Dictionary = await _send_and_await("room:list", {})
	if not result.get("ok", false):
		return []
	var out: Array = []
	for r in result.get("rooms", []):
		out.append({
			"room_id": str(r.get("roomId", "")),
			"room_name": str(r.get("roomName", "")),
			"host_nickname": str(r.get("hostNickname", "")),
			"player_count": int(r.get("playerCount", 0)),
			"is_private": bool(r.get("isPrivate", false)),
		})
	return out

func set_player_nickname(player_id: String, nickname: String) -> void:
	if player_id != GameData.local_player_id:
		return # 실제 서버에서는 자기 자신의 닉네임만 바꿀 수 있다.
	_send("player:setNickname", {"nickname": nickname}, GameData.room_id)

func can_start_game() -> bool:
	# 임시 테스트 모드: UI/게임 로직 확인을 쉽게 하려고 1명이어도 시작을 허용한다.
	var player_count := GameData.players.size()
	return player_count >= 1 and player_count <= MVP_PLAYER_LIMIT

func lobby_status_text() -> String:
	var player_count := GameData.players.size()
	if player_count <= 1:
		return "테스트로 시작 가능"
	return "경찰 1명 / 오리 %d명" % (player_count - 1)

func local_player_team() -> String:
	for player in GameData.players:
		if str(player.get("playerId", "")) == GameData.local_player_id:
			return str(player.get("team", "duck"))
	return "duck"

func arrow_control_player_id() -> String:
	# 한 기기에서 방향키로 두 번째 캐릭터를 조작하는 로컬 시연(핫싯) 기능. 순수 로컬
	# 읽기라 네트워크 여부와 무관하게 동작한다. 다만 실제 서버에는 자기 자신
	# (local_player_id)의 위치/대시만 보고되므로, 이렇게 조작하는 두 번째 캐릭터의
	# 움직임은 다른 클라이언트 화면에는 반영되지 않는다(같은 화면을 보는 로컬 시연용).
	var target_team := "duck"
	if local_player_team() == "duck":
		target_team = "tagger"

	for player in GameData.players:
		if str(player.get("playerId", "")) == GameData.local_player_id:
			continue
		if str(player.get("team", "")) == target_team:
			return str(player.get("playerId", ""))
	return ""

func start_game() -> bool:
	if not can_start_game():
		return false
	_send("game:start", {}, GameData.room_id)
	return true

func return_to_lobby() -> void:
	GameData.menu_entry_view = "lobby"
	_send("game:returnToLobby", {}, GameData.room_id)

func force_end_game() -> void:
	_send("game:forceEnd", {}, GameData.room_id)

func leave_room() -> void:
	_send("room:leave", {}, GameData.room_id)
	GameData.room_id = ""
	GameData.room_name = ""
	GameData.room_is_private = false
	GameData.join_code = ""
	GameData.is_host = false
	GameData.players = []

# ──────────────────────────────────────────────────────────────────────────────
# 인게임
# ──────────────────────────────────────────────────────────────────────────────

func register_obstacles(_list: Array) -> void:
	pass # 서버가 정적 장애물 좌표(Pond.tscn에서 추출해 하드코딩)를 자체적으로 알고 있어 필요 없다.

func begin_dash(player_id: String, start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	if player_id != GameData.local_player_id:
		return
	_send("player:dash", {
		"startPosition": {"x": start_pos.x, "y": start_pos.y, "z": start_pos.z},
		"endPosition": {"x": end_pos.x, "y": end_pos.y, "z": end_pos.z},
		"duration": duration,
	}, GameData.room_id)

func notify_duckling_delivered(duckling_id: String) -> void:
	# 둥지까지 걷는 연출과 도착 판정을 클라이언트(duckling.gd)가 로컬로 하고, 실제로
	# 도착했다고 판단한 순간 이 메시지로 서버에 알려야 점수/새끼오리 삭제가 반영된다.
	_send("duckling:deliver", {"ducklingId": duckling_id}, GameData.room_id)

func report_local_transform(pos: Vector3, rotation_y: float) -> void:
	# player.gd가 자기 자신(local_player_id)의 위치를 매 프레임 알려주면, 여기서
	# INPUT_SEND_INTERVAL 주기로 스로틀링해 player:input으로 서버에 보고한다.
	_pending_position = pos
	_pending_rotation_y = rotation_y
	_has_pending_input = true
