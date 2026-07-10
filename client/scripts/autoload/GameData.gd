extends Node

# Field names mirror Docs/api-spec.md so MockServer can be swapped for a real NetworkClient later.

var local_player_id: String = "local"
var phase: String = "lobby" # lobby | countdown | playing | ended
var remaining_seconds: int = 0
var score: int = 0
var target_score: int = 5
var winner = null # "duck" | "tagger" | null
var players: Array = [] # [{playerId, team, character, position:{x,y,z}, rotationY, state, carryingDucklingId, jailedUntil}]
var ducklings: Array = [] # [{ducklingId, position:{x,y,z}, state, carrierPlayerId}]

signal room_state_changed
signal game_state_changed
signal game_event(event: String, data: Dictionary)

func register_local_player(team: String, character: String) -> void:
	for p in players:
		if p["playerId"] == local_player_id:
			return
	players.append({
		"playerId": local_player_id,
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
