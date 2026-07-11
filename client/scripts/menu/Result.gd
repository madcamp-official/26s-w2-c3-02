extends Control

@onready var winner_label: Label = %WinnerLabel
@onready var reason_label: Label = %ReasonLabel
@onready var summary_label: Label = %SummaryLabel
@onready var players_list: VBoxContainer = %PlayersList


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	winner_label.text = _winner_text()
	reason_label.text = _reason_text()
	summary_label.text = "최종 새끼오리 %d / %d" % [GameData.score, GameData.target_score]
	_refresh_players()


func _refresh_players() -> void:
	for child in players_list.get_children():
		players_list.remove_child(child)
		child.queue_free()

	for player in GameData.players:
		var label: Label = Label.new()
		label.text = "%s / %s" % [
			str(player.get("nickname", "Player")),
			_role_label(str(player.get("team", ""))),
		]
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color.WHITE)
		players_list.add_child(label)


func _winner_text() -> String:
	if GameData.winner == "duck":
		return "오리 팀 승리!"
	if GameData.winner == "tagger":
		return "경찰 팀 승리!"
	return "게임 종료"


func _reason_text() -> String:
	match str(GameData.end_reason):
		"duck_goal":
			return "오리 팀이 목표 수를 달성했습니다."
		"time_up":
			return "시간 종료로 경찰 팀이 승리했습니다."
	return "게임이 종료되었습니다."


func _role_label(team: String) -> String:
	match team:
		"duck":
			return "오리"
		"tagger":
			return "경찰"
	return "미정"


func _on_main_menu_button_pressed() -> void:
	GameData.menu_entry_view = "menu"
	SceneRouter.go_to("main_menu")


func _on_lobby_button_pressed() -> void:
	MockServer.return_to_lobby()
	SceneRouter.go_to("main_menu")
