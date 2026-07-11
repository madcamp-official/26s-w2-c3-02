extends CanvasLayer

const TOAST_DURATION := 3.0
const NEST_1_POSITION := Vector3(-58.5, 1.68, 58.5) # 남서쪽 둥지 (1.3배 멀어짐)
const NEST_2_POSITION := Vector3(58.5, 1.68, -58.5) # 북동쪽 둥지 (1.3배 멀어짐)
const JAIL_FALLBACK_POSITION := Vector3(0, 0.5, 0) # 감옥 중앙 이동 반영 폴백
const INDICATOR_MARGIN := 32.0
const INDICATOR_SIZE := Vector2(116, 60)

@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var jailed_label: Label = %JailedLabel
@onready var event_toast: PanelContainer = %EventToast
@onready var event_message_label: Label = %EventMessageLabel
@onready var player_list_content: VBoxContainer = %PlayerListContent
@onready var jail_direction_indicator: Control = %JailDirectionIndicator
@onready var nest_direction_indicator: Control = %NestDirectionIndicator
@onready var nest_2_direction_indicator: Control = %Nest2DirectionIndicator
@onready var jail_arrow_label: Label = %JailArrowLabel
@onready var nest_arrow_label: Label = %NestArrowLabel
@onready var nest_2_arrow_label: Label = %Nest2ArrowLabel
@onready var debug_mode_button: Button = %DebugModeButton
@onready var debug_panel: PanelContainer = %DebugPanel
@onready var debug_summary_label: Label = %DebugSummaryLabel

var _toast_remaining := 0.0
var _jail_node: Node3D = null


func _ready() -> void:
	GameData.game_state_changed.connect(_refresh)
	GameData.game_event.connect(_on_game_event)
	GameData.debug_mode_changed.connect(_on_debug_mode_changed)
	_apply_static_text_styles()
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
	_refresh_player_list()
	_refresh_debug_summary()


func _format_time(seconds: int) -> String:
	var minutes := int(seconds / 60)
	var remaining := seconds % 60
	return "%02d:%02d" % [minutes, remaining]


func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "game_ended":
		SceneRouter.show_overlay("result")
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


func _refresh_player_list() -> void:
	for child in player_list_content.get_children():
		player_list_content.remove_child(child)
		child.queue_free()

	_add_player_group("오리 팀", "duck")
	_add_player_group("술래 팀", "tagger")


func _add_player_group(title: String, team: String) -> void:
	var group_players: Array = []
	for player in GameData.players:
		if str(player.get("team", "")) == team:
			group_players.append(player)

	if group_players.is_empty():
		return

	var title_label: Label = _make_player_list_label(title)
	_apply_game_text_style(title_label, 18, Color(0.78, 0.9, 1.0, 1.0), 5, 3)
	player_list_content.add_child(title_label)

	for player in group_players:
		var row: Label = _make_player_list_label("%s / %s / %s" % [
			_role_label(str(player.get("team", ""))),
			str(player.get("nickname", "Player")),
			_status_label(str(player.get("state", ""))),
		])
		player_list_content.add_child(row)


func _make_player_list_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	_apply_game_text_style(label, 22, Color.WHITE, 6, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _apply_static_text_styles() -> void:
	_apply_game_text_style(timer_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(score_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(jailed_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(event_message_label, 30, Color.WHITE, 7, 4)
	_apply_game_text_style(jail_arrow_label, 42, Color.WHITE, 7, 4)
	_apply_game_text_style(nest_arrow_label, 42, Color.WHITE, 7, 4)


func _apply_game_text_style(label: Label, font_size: int, color: Color, outline_size: int, shadow_offset_y: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.06, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", shadow_offset_y)


func _role_label(team: String) -> String:
	match team:
		"duck":
			return "오리"
		"tagger":
			return "술래"
	return "미정"


func _status_label(state: String) -> String:
	match state:
		"jailed":
			return "수감 중"
	return "정상"


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
			return "%s가 감옥에 갇혔습니다! 🔒" % _player_name(data, "playerName", "playerId")
		"player_released":
			return "%s가 감옥에서 탈출했습니다! 🕊️" % _player_name(data, "playerName", "playerId")
		"player_rescued":
			var rescuer := _player_name(data, "rescuerName", "rescuerId")
			var target := _player_name(data, "targetName", "targetId")
			return "%s이 %s를 구출했습니다! 🦸" % [rescuer, target]
		"rescue_started":
			var rescuer := _player_name(data, "rescuerName", "rescuerId")
			return "%s이 탈옥을 시도하고 있습니다! ⏳" % rescuer
		"duckling_delivered":
			var player_name := _player_name(data, "playerName", "playerId")
			var count := int(data.get("count", 1))
			return "%s님이 새끼오리 %d마리를 둥지에 데려왔습니다!" % [player_name, count]
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
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	_update_direction_indicator(nest_direction_indicator, nest_arrow_label, NEST_1_POSITION, camera)
	_update_direction_indicator(nest_2_direction_indicator, nest_2_arrow_label, NEST_2_POSITION, camera)
	_update_direction_indicator(jail_direction_indicator, jail_arrow_label, _jail_world_position(), camera)

func _jail_world_position() -> Vector3:
	if not is_instance_valid(_jail_node):
		_jail_node = get_tree().get_first_node_in_group("jail") as Node3D
	if is_instance_valid(_jail_node):
		return _jail_node.global_position
	return JAIL_FALLBACK_POSITION


func _update_direction_indicator(indicator: Control, arrow_label: Label, world_position: Vector3, camera: Camera3D) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = viewport_size * 0.5
	var screen_pos: Vector2 = camera.unproject_position(world_position)
	var is_behind: bool = camera.is_position_behind(world_position)

	if _is_world_position_visible(screen_pos, viewport_size, is_behind):
		indicator.visible = false
		return

	indicator.visible = true
	if is_behind:
		screen_pos = center - (screen_pos - center)

	var direction: Vector2 = screen_pos - center
	if direction.length() < 1.0:
		direction = Vector2.RIGHT

	var unit: Vector2 = direction.normalized()
	var half_bounds: Vector2 = viewport_size * 0.5 - INDICATOR_SIZE * 0.5 - Vector2.ONE * INDICATOR_MARGIN
	var distance_x: float = INF if abs(unit.x) < 0.001 else half_bounds.x / abs(unit.x)
	var distance_y: float = INF if abs(unit.y) < 0.001 else half_bounds.y / abs(unit.y)
	var edge_center: Vector2 = center + unit * min(distance_x, distance_y)
	indicator.position = edge_center - INDICATOR_SIZE * 0.5

	# Rotator 노드를 찾아 방향 각도로 회전시킴
	var rotator := indicator.get_node_or_null("Rotator") as Control
	if rotator != null:
		var target_angle := direction.angle()
		rotator.rotation = target_angle
		
		# 화살표(Label)는 0도로 고정 (부모인 Rotator가 통째로 돌기 때문)
		arrow_label.rotation = 0.0
		
		# Circle 자식의 첫 번째 노드인 Photo를 역회전하여 사진이 뒤집어지지 않고 항상 똑바로 유지되도록 함
		var circle := rotator.get_node_or_null("Circle") as Control
		if circle != null and circle.get_child_count() > 0:
			var photo := circle.get_child(0) as Control
			if photo != null:
				photo.rotation = -target_angle



func _is_world_position_visible(screen_pos: Vector2, viewport_size: Vector2, is_behind: bool) -> bool:
	if is_behind:
		return false

	return (
		screen_pos.x >= INDICATOR_MARGIN
		and screen_pos.x <= viewport_size.x - INDICATOR_MARGIN
		and screen_pos.y >= INDICATOR_MARGIN
		and screen_pos.y <= viewport_size.y - INDICATOR_MARGIN
	)


# ── 디버그 버튼 핸들러 ──────────────────────────────────────────────────────

func _on_debug_jail_me_pressed() -> void:
	MockServer.debug_jail_local_player()

func _on_debug_toggle_duck_pressed() -> void:
	MockServer.debug_toggle_fake_duck()

func _on_debug_jail_duck_pressed() -> void:
	MockServer.debug_jail_fake_duck()
