extends Node

# Field names mirror Docs/api-spec.md so MockServer can be swapped for a real NetworkClient later.

var local_player_id: String = "local"
var room_id: String = ""
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

signal room_state_changed
signal game_state_changed
signal game_event(event: String, data: Dictionary)
signal debug_mode_changed(enabled: bool)

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
	for p in players:
		if p["playerId"] == local_player_id:
			p["position"] = {"x": pos.x, "y": pos.y, "z": pos.z}
			p["rotationY"] = rotation_y
			return

func set_debug_mode(enabled: bool) -> void:
	if debug_mode_enabled == enabled:
		return
	debug_mode_enabled = enabled
	debug_mode_changed.emit(debug_mode_enabled)
