extends CanvasLayer

const TOAST_DURATION := 3.0
const OBJECTIVE_TOAST_DURATION := 5.0
const NEST_1_POSITION := Vector3(-58.5, 1.68, 58.5) 
const NEST_2_POSITION := Vector3(58.5, 1.68, -58.5) 
const JAIL_FALLBACK_POSITION := Vector3(0, 0.5, 0)
const INDICATOR_MARGIN := 32.0
const INDICATOR_SIZE := Vector2(116, 60)
const DUCK_ICON_PATH := "res://assets/ui/icons/duck_icon.png"
const POLICE_ICON_PATH := "res://assets/ui/icons/police_icon.png"
const LOCK_ICON_PATH := "res://assets/ui/icons/lock_icon.png"

@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var jailed_label: Label = %JailedLabel
@onready var event_toast: PanelContainer = %EventToast
@onready var event_message_label: Label = %EventMessageLabel
@onready var countdown_overlay: Control = %CountdownOverlay
@onready var countdown_label: Label = %CountdownLabel
@onready var objective_toast: PanelContainer = %ObjectiveToast
@onready var objective_label: Label = %ObjectiveLabel
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
var _objective_remaining := 0.0
var _jail_node: Node3D = null
var _icon_mask_shader: Shader = null


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

	if _objective_remaining > 0.0:
		_objective_remaining -= delta
		if _objective_remaining <= 0.0:
			objective_toast.visible = false

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
	_refresh_countdown()
	_refresh_player_list()
	_refresh_debug_summary()


func _refresh_countdown() -> void:
	var is_countdown := GameData.phase == "countdown"
	countdown_overlay.visible = is_countdown
	if not is_countdown:
		return

	if GameData.countdown_seconds > 0:
		countdown_label.text = str(GameData.countdown_seconds)
	else:
		countdown_label.text = "시작!"


func _format_time(seconds: int) -> String:
	var minutes := int(seconds / 60)
	var remaining := seconds % 60
	return "%02d:%02d" % [minutes, remaining]


func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "game_ended":
		SceneRouter.show_overlay("result")
		return
	if event == "game_started":
		_show_objective_toast()
		return

	var message := _event_message(event, data)
	if message != "":
		_show_event_toast(message)


func _show_objective_toast() -> void:
	var team := _local_team()
	if team == "tagger":
		objective_label.text = "오리를 잡아 감옥에 보내세요."
	else:
		objective_label.text = "새끼오리를 둥지로 데려가세요."
	objective_toast.visible = true
	_objective_remaining = OBJECTIVE_TOAST_DURATION


func _local_team() -> String:
	for player in GameData.players:
		if str(player.get("playerId", "")) == GameData.local_player_id:
			return str(player.get("team", "duck"))
	return "duck"


func _on_end_test_button_pressed() -> void:
	var winner := "tagger"
	if GameData.score >= GameData.target_score:
		winner = "duck"
	MockServer.finish_game_for_test(winner)


func _on_debug_mode_button_pressed() -> void:
	GameData.set_debug_mode(not GameData.debug_mode_enabled)


func _on_debug_mode_changed(enabled: bool) -> void:
	debug_panel.visible = enabled
	if enabled:
		debug_mode_button.text = "디버그 ON"
	else:
		debug_mode_button.text = "디버그 OFF"
	_refresh_debug_summary()


func _refresh_player_list() -> void:
	for child in player_list_content.get_children():
		player_list_content.remove_child(child)
		child.queue_free()

	_add_player_rows_for_team("duck")
	_add_player_rows_for_team("tagger")


func _add_player_rows_for_team(team: String) -> void:
	var group_players: Array = []
	for player in GameData.players:
		if str(player.get("team", "")) == team:
			group_players.append(player)

	for player in group_players:
		player_list_content.add_child(_make_player_row(player))


func _make_player_row(player: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.add_theme_constant_override("separation", 8)

	row.add_child(_make_hud_icon(_icon_path_for_team(str(player.get("team", ""))), Vector2(30, 30)))

	var name_label: Label = Label.new()
	name_label.text = str(player.get("nickname", "Player"))
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_game_text_style(name_label, 22, Color.WHITE, 6, 4)
	row.add_child(name_label)

	if str(player.get("state", "")) == "jailed":
		row.add_child(_make_hud_icon(LOCK_ICON_PATH, Vector2(26, 26)))

	return row


func _icon_path_for_team(team: String) -> String:
	if team == "tagger":
		return POLICE_ICON_PATH
	return DUCK_ICON_PATH


func _make_hud_icon(path: String, icon_size: Vector2) -> Control:
	var holder: Control = Control.new()
	holder.custom_minimum_size = icon_size + Vector2(8, 8)

	if not ResourceLoader.exists(path):
		return holder

	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return holder

	_add_icon_layer(holder, texture, Vector2(4, 7), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(holder, texture, Vector2(1, 4), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(holder, texture, Vector2(7, 4), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(holder, texture, Vector2(4, 1), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(holder, texture, Vector2(4, 4), icon_size, Color.WHITE)
	return holder


func _add_icon_layer(parent: Control, texture: Texture2D, offset: Vector2, icon_size: Vector2, color: Color) -> void:
	var layer: TextureRect = TextureRect.new()
	layer.position = offset
	layer.custom_minimum_size = icon_size
	layer.size = icon_size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = texture
	layer.material = _make_icon_mask_material(color)
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(layer)


func _make_icon_mask_material(color: Color) -> ShaderMaterial:
	if _icon_mask_shader == null:
		_icon_mask_shader = Shader.new()
		_icon_mask_shader.code = "shader_type canvas_item;\nuniform vec4 fill_color : source_color = vec4(1.0);\nvoid fragment() {\n\tvec4 tex = texture(TEXTURE, UV);\n\tCOLOR = vec4(fill_color.rgb, tex.a * fill_color.a);\n}"

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _icon_mask_shader
	material.set_shader_parameter("fill_color", color)
	return material


func _apply_static_text_styles() -> void:
	_apply_game_text_style(timer_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(score_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(jailed_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(event_message_label, 30, Color.WHITE, 7, 4)
	_apply_game_text_style(jail_arrow_label, 42, Color.WHITE, 7, 4)
	_apply_game_text_style(nest_arrow_label, 42, Color.WHITE, 7, 4)
	_apply_game_text_style(nest_2_arrow_label, 42, Color.WHITE, 7, 4)
	_apply_game_text_style(countdown_label, 96, Color.WHITE, 12, 7)
	_apply_game_text_style(objective_label, 34, Color.WHITE, 7, 4)


func _apply_game_text_style(label: Label, font_size: int, color: Color, outline_size: int, shadow_offset_y: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.06, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", shadow_offset_y)


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
	var distance_x := INF
	if abs(unit.x) >= 0.001:
		distance_x = half_bounds.x / abs(unit.x)
	var distance_y := INF
	if abs(unit.y) >= 0.001:
		distance_y = half_bounds.y / abs(unit.y)
	var edge_center: Vector2 = center + unit * min(distance_x, distance_y)
	indicator.position = edge_center - INDICATOR_SIZE * 0.5

	var rotator := indicator.get_node_or_null("Rotator") as Control
	if rotator != null:
		var target_angle := direction.angle()
		rotator.rotation = target_angle
		arrow_label.rotation = 0.0

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


func _on_debug_jail_me_pressed() -> void:
	MockServer.debug_jail_local_player()


func _on_debug_toggle_duck_pressed() -> void:
	MockServer.debug_toggle_fake_duck()


func _on_debug_jail_duck_pressed() -> void:
	MockServer.debug_jail_fake_duck()
