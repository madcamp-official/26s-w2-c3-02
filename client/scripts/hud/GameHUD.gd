extends CanvasLayer

@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var phase_label: Label = %PhaseLabel
@onready var debug_mode_button: Button = %DebugModeButton
@onready var debug_panel: PanelContainer = %DebugPanel
@onready var debug_summary_label: Label = %DebugSummaryLabel

func _ready() -> void:
	GameData.game_state_changed.connect(_refresh)
	GameData.game_event.connect(_on_game_event)
	GameData.debug_mode_changed.connect(_on_debug_mode_changed)
	_on_debug_mode_changed(GameData.debug_mode_enabled)
	_refresh()

func _exit_tree() -> void:
	if GameData.game_state_changed.is_connected(_refresh):
		GameData.game_state_changed.disconnect(_refresh)
	if GameData.game_event.is_connected(_on_game_event):
		GameData.game_event.disconnect(_on_game_event)
	if GameData.debug_mode_changed.is_connected(_on_debug_mode_changed):
		GameData.debug_mode_changed.disconnect(_on_debug_mode_changed)

func _refresh() -> void:
	timer_label.text = "남은 시간 %s" % _format_time(GameData.remaining_seconds)
	score_label.text = "새끼오리 %d / %d" % [GameData.score, GameData.target_score]
	phase_label.text = "상태 %s" % GameData.phase
	_refresh_debug_summary()

func _format_time(seconds: int) -> String:
	var minutes := int(seconds / 60)
	var remaining := seconds % 60
	return "%02d:%02d" % [minutes, remaining]

func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "game_ended":
		SceneRouter.go_to("result")

func _on_end_test_button_pressed() -> void:
	MockServer.finish_game_for_test("duck")

func _on_debug_mode_button_pressed() -> void:
	GameData.set_debug_mode(not GameData.debug_mode_enabled)

func _on_debug_mode_changed(enabled: bool) -> void:
	debug_panel.visible = enabled
	debug_mode_button.text = "디버그 ON" if enabled else "디버그 OFF"
	_refresh_debug_summary()

func _refresh_debug_summary() -> void:
	if not is_instance_valid(debug_summary_label):
		return
	debug_summary_label.text = "phase: %s\nroom: %s\nscore: %d / %d\ntime: %d\nplayers: %d\nducklings: %d" % [
		GameData.phase,
		GameData.room_id,
		GameData.score,
		GameData.target_score,
		GameData.remaining_seconds,
		GameData.players.size(),
		GameData.ducklings.size(),
	]
