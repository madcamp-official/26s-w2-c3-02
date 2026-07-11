extends CanvasLayer

const TOAST_DURATION := 3.0
const NEST_POSITION := Vector3(0, 1.68, 65)
const JAIL_POSITION := Vector3(-55, 1.0, -45) # TODO: replace with B track's actual jail position.
const INDICATOR_MARGIN := 32.0
const INDICATOR_SIZE := Vector2(144, 60)

@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var jailed_label: Label = %JailedLabel
@onready var event_toast: PanelContainer = %EventToast
@onready var event_message_label: Label = %EventMessageLabel
@onready var jail_direction_indicator: PanelContainer = %JailDirectionIndicator
@onready var nest_direction_indicator: PanelContainer = %NestDirectionIndicator
@onready var jail_arrow_label: Label = %JailArrowLabel
@onready var nest_arrow_label: Label = %NestArrowLabel
@onready var debug_mode_button: Button = %DebugModeButton
@onready var debug_panel: PanelContainer = %DebugPanel
@onready var debug_summary_label: Label = %DebugSummaryLabel

var _toast_remaining := 0.0

func _ready() -> void:
	GameData.game_state_changed.connect(_refresh)
	GameData.game_event.connect(_on_game_event)
	GameData.debug_mode_changed.connect(_on_debug_mode_changed)
	_on_debug_mode_changed(GameData.debug_mode_enabled)
	_refresh()
	_update_direction_indicators()

func _process(delta: float) -> void:
	if _toast_remaining > 0.0:
		_toast_remaining -= delta
		if _toast_remaining <= 0.0:
			event_toast.visible = false
	_update_direction_indicators()

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
	jailed_label.text = "수감 오리 %d명" % _jailed_duck_count()
	_refresh_debug_summary()

func _format_time(seconds: int) -> String:
	var minutes := int(seconds / 60)
	var remaining := seconds % 60
	return "%02d:%02d" % [minutes, remaining]

func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "game_ended":
		SceneRouter.go_to("result")
		return

	var message := _event_message(event, data)
	if message != "":
		_show_event_toast(message)

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
	debug_summary_label.text = "phase: %s\nroom: %s\nscore: %d / %d\ntime: %d\nplayers: %d\nducklings: %d\njailed: %d" % [
		GameData.phase,
		GameData.room_id,
		GameData.score,
		GameData.target_score,
		GameData.remaining_seconds,
		GameData.players.size(),
		GameData.ducklings.size(),
		_jailed_duck_count(),
	]

func _jailed_duck_count() -> int:
	var count := 0
	for player in GameData.players:
		if str(player.get("team", "")) == "duck" and str(player.get("state", "")) == "jailed":
			count += 1
	return count

func _event_message(event: String, data: Dictionary) -> String:
	match event:
		"player_jailed":
			return "%s가 감옥에 갇혔습니다!" % _player_name(data, "playerName", "playerId")
		"player_released":
			return "%s가 감옥에서 탈출했습니다!" % _player_name(data, "playerName", "playerId")
		"player_rescued":
			var rescuer := _player_name(data, "rescuerName", "rescuerId")
			var target := _player_name(data, "targetName", "targetId")
			return "%s이 %s를 구출했습니다!" % [rescuer, target]
		"duckling_delivered":
			var player_name := _player_name(data, "playerName", "playerId")
			var count := int(data.get("count", 1))
			return "%s이 새끼오리 %d마리를 둥지에 데려왔습니다!" % [player_name, count]
	return ""

func _player_name(data: Dictionary, name_key: String, id_key: String) -> String:
	if data.has(name_key):
		return str(data[name_key])
	if data.has(id_key):
		return _name_for_player_id(str(data[id_key]))
	return GameData.local_nickname

func _name_for_player_id(player_id: String) -> String:
	for player in GameData.players:
		if str(player.get("playerId", "")) == player_id:
			return str(player.get("nickname", player_id))
	return player_id

func _show_event_toast(message: String) -> void:
	event_message_label.text = message
	event_toast.visible = true
	_toast_remaining = TOAST_DURATION

func _update_direction_indicators() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_update_direction_indicator(nest_direction_indicator, nest_arrow_label, NEST_POSITION, camera)
	_update_direction_indicator(jail_direction_indicator, jail_arrow_label, JAIL_POSITION, camera)

func _update_direction_indicator(indicator: Control, arrow_label: Label, world_position: Vector3, camera: Camera3D) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var screen_pos := camera.unproject_position(world_position)
	if camera.is_position_behind(world_position):
		screen_pos = center - (screen_pos - center)

	var direction := screen_pos - center
	if direction.length() < 1.0:
		direction = Vector2.RIGHT

	var unit := direction.normalized()
	var half_bounds := viewport_size * 0.5 - INDICATOR_SIZE * 0.5 - Vector2.ONE * INDICATOR_MARGIN
	var distance_x: float = INF if abs(unit.x) < 0.001 else half_bounds.x / abs(unit.x)
	var distance_y: float = INF if abs(unit.y) < 0.001 else half_bounds.y / abs(unit.y)
	var edge_center := center + unit * min(distance_x, distance_y)
	indicator.position = edge_center - INDICATOR_SIZE * 0.5

	if direction.length() < 1.0:
		arrow_label.text = "•"
		return
	arrow_label.text = _arrow_for_angle(direction.angle())

func _arrow_for_angle(angle: float) -> String:
	var step := int(round(angle / (PI / 4.0))) % 8
	if step < 0:
		step += 8
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return arrows[step]
