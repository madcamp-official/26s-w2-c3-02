extends Control

@onready var room_code_label: Label = %RoomCodeLabel
@onready var players_list: VBoxContainer = %PlayersList

func _ready() -> void:
	GameData.room_state_changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if GameData.room_state_changed.is_connected(_refresh):
		GameData.room_state_changed.disconnect(_refresh)

func _refresh() -> void:
	room_code_label.text = "참가코드: %s" % ("-" if GameData.join_code.strip_edges() == "" else GameData.join_code)

	for child in players_list.get_children():
		child.queue_free()

	for player in GameData.players:
		var label := Label.new()
		var nickname := str(player.get("nickname", player.get("playerId", "Unknown")))
		var team := _team_label(str(player.get("team", "")))
		label.text = "%s        %s" % [nickname, team]
		players_list.add_child(label)

func _team_label(team: String) -> String:
	if team == "duck":
		return "오리 팀"
	if team == "tagger":
		return "술래 팀"
	return "팀 미정"

func _on_start_game_button_pressed() -> void:
	SceneRouter.go_to("game")

func _on_back_button_pressed() -> void:
	SceneRouter.go_to("main_menu")
