extends Node

# Field names mirror Docs/api-spec.md so MockServer can be swapped for a real NetworkClient later.

var local_player_id: String = "local"
var room_id: String = ""
var room_name: String = ""
var room_is_private: bool = false
var join_code: String = ""
var local_nickname: String = "Player"
var phase: String = "lobby" # lobby | countdown | playing | ended
var countdown_seconds: int = 0
var remaining_seconds: int = 0
var score: int = 0
var target_score: int = 5
var winner = null # "duck" | "tagger" | null
var end_reason: String = ""
var menu_entry_view: String = "menu"
var players: Array = [] # [{playerId, nickname, team, character, position:{x,y,z}, rotationY, state, carryingDucklingId, jailedUntil}]
var ducklings: Array = [] # [{ducklingId, position:{x,y,z}, state, carrierPlayerId}]
var debug_mode_enabled: bool = false
var rescue_progress: float = 0.0   # 0.0 ~ 1.0, 구출 진행률
var active_rescuer_id: String = "" # 현재 탈옥 시도 중인 플레이어 id
var dash_cooldown_remaining: float = 0.0 # 경찰(악어) 대시 쿨타임 잔여 시간(초)
var dash_cooldown_duration: float = 5.0  # 경찰(악어) 대시 쿨타임 총 시간(초)
var local_duck_character: String = "duck"       # 인벤토리에서 고른 오리 팀 장착 스킨(character 키)
var local_tagger_character: String = "aligator" # 인벤토리에서 고른 경찰 팀 장착 스킨(character 키)
var is_host: bool = false # 현재 방의 호스트인지 여부 (room:joined 응답의 isHost를 저장)

signal room_state_changed
signal game_state_changed
signal game_event(event: String, data: Dictionary)
signal debug_mode_changed(enabled: bool)
signal action_error(code: String, message: String) # 요청-응답 상관관계가 없는(fire-and-forget) 액션이 서버에서 거부됐을 때

func register_local_player(team: String, character: String, nickname: String = "") -> void:
	for p in players:
		if p["playerId"] == local_player_id:
			if nickname != "":
				p["nickname"] = nickname
			return
	if nickname != "":
		local_nickname = nickname
	players.append({
		"playerId": local_player_id,
		"nickname": local_nickname,
		"team": team,
		"character": character,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"rotationY": 0.0,
		"state": "idle",
		"carryingDucklingId": null,
		"jailedUntil": null,
	})

func update_local_player_transform(pos: Vector3, rotation_y: float) -> void:
	update_player_transform(local_player_id, pos, rotation_y)

func update_player_transform(player_id: String, pos: Vector3, rotation_y: float) -> void:
	for p in players:
		if p["playerId"] == player_id:
			p["position"] = {"x": pos.x, "y": pos.y, "z": pos.z}
			p["rotationY"] = rotation_y
			return

func set_debug_mode(enabled: bool) -> void:
	if debug_mode_enabled == enabled:
		return
	debug_mode_enabled = enabled
	debug_mode_changed.emit(debug_mode_enabled)
