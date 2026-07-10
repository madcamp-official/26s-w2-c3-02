extends Control

@onready var winner_label: Label = %WinnerLabel
@onready var summary_label: Label = %SummaryLabel

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	winner_label.text = _winner_text()
	summary_label.text = "구출한 새끼오리 %d / %d" % [GameData.score, GameData.target_score]

func _winner_text() -> String:
	if GameData.winner == "duck":
		return "오리 팀 승리!"
	if GameData.winner == "tagger":
		return "술래 팀 승리!"
	return "게임 종료"

func _on_main_menu_button_pressed() -> void:
	SceneRouter.go_to("main_menu")
