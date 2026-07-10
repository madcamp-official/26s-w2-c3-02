extends Node

const TICK_HZ := 10.0 # api-spec.md STATE_TICK_RATE
const GAME_DURATION := 180 # api-spec.md GAME_DURATION_SECONDS
const TARGET_SCORE := 5

var _broadcast_timer := 0.0
var _second_timer := 0.0
var _npc_angle := 0.0

func _ready() -> void:
	GameData.target_score = TARGET_SCORE
	_seed_lobby()

func _seed_lobby() -> void:
	GameData.players = [_fake_player("npc1", "tagger", "aligator")]
	GameData.room_state_changed.emit()

func start_game() -> void:
	GameData.phase = "playing"
	GameData.remaining_seconds = GAME_DURATION
	GameData.score = 0
	GameData.winner = null
	GameData.ducklings = [_fake_duckling("d1"), _fake_duckling("d2"), _fake_duckling("d3")]
	GameData.game_event.emit("game_started", {})
	GameData.game_state_changed.emit()

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

	_broadcast_timer += delta
	if _broadcast_timer >= 1.0 / TICK_HZ:
		_broadcast_timer = 0.0
		GameData.game_state_changed.emit()

func _end_game(winner: String) -> void:
	GameData.phase = "ended"
	GameData.winner = winner
	GameData.game_event.emit("game_ended", {"winner": winner})
	GameData.game_state_changed.emit()

func _fake_player(id: String, team: String, character: String) -> Dictionary:
	return {
		"playerId": id,
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
