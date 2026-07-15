extends CanvasLayer

const TOAST_DURATION := 3.0
const OBJECTIVE_TOAST_DURATION := 5.0
const NEST_1_POSITION := Vector3(-58.5, 1.68, 58.5) 
const NEST_2_POSITION := Vector3(58.5, 1.68, -58.5) 
const JAIL_FALLBACK_POSITION := Vector3(0, 0.5, 0)
const INDICATOR_MARGIN := 20.0
const INDICATOR_SIZE := Vector2(180, 180)
const INDICATOR_CENTER := Vector2(90, 90)
const INDICATOR_SAFE_RADIUS := 96.0
const SAFE_AREA_EXTRA_MARGIN := 4.0
const TOP_BAR_BASE_LEFT := 24.0
const TOP_BAR_BASE_TOP := 18.0
const TOP_BAR_BASE_RIGHT := 24.0
const TOP_BAR_HEIGHT := 78.0
const PLAYER_LIST_BASE_LEFT := 24.0
const PLAYER_LIST_WIDTH := 264.0
const SETTINGS_BUTTON_BASE_RIGHT := 28.0
const SETTINGS_BUTTON_BASE_BOTTOM := 28.0
const SETTINGS_BUTTON_SIZE := 56.0
const DUCK_ICON_PATH := "res://assets/ui/icons/duck_icon.png"
const POLICE_ICON_PATH := "res://assets/ui/icons/police_icon.png"
const JAIL_ICON_PATH := "res://assets/ui/icons/jail_icon.png"
const MobileControlsScript := preload("res://scripts/hud/MobileControls.gd")

@onready var top_bar: PanelContainer = $Root/TopBar
@onready var timer_label: Label = %TimerLabel
@onready var score_label: Label = %ScoreLabel
@onready var event_toast: PanelContainer = %EventToast
@onready var event_message_label: Label = %EventMessageLabel
@onready var countdown_overlay: Control = %CountdownOverlay
@onready var countdown_label: Label = %CountdownLabel
@onready var objective_toast: PanelContainer = %ObjectiveToast
@onready var objective_label: Label = %ObjectiveLabel
@onready var player_list_panel: PanelContainer = %PlayerListPanel
@onready var player_list_content: VBoxContainer = %PlayerListContent
@onready var jail_direction_indicator: Control = %JailDirectionIndicator
@onready var nest_direction_indicator: Control = %NestDirectionIndicator
@onready var nest_2_direction_indicator: Control = %Nest2DirectionIndicator
@onready var jail_arrow_label: TextureRect = %JailArrowLabel
@onready var nest_arrow_label: TextureRect = %NestArrowLabel
@onready var nest_2_arrow_label: TextureRect = %Nest2ArrowLabel
@onready var jail_photo: TextureRect = %JailPhoto
@onready var nest_photo: TextureRect = %NestPhoto
@onready var nest_2_photo: TextureRect = %Nest2Photo
@onready var settings_button: TextureButton = %SettingsButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var settings_close_button: Button = %SettingsCloseButton
@onready var hud_bgm_volume_slider: HSlider = %HudBgmVolumeSlider
@onready var hud_sfx_volume_slider: HSlider = %HudSfxVolumeSlider
@onready var hud_bgm_volume_value_label: Label = %HudBgmVolumeValueLabel
@onready var hud_sfx_volume_value_label: Label = %HudSfxVolumeValueLabel

var _toast_remaining := 0.0
var _objective_remaining := 0.0
var _jail_node: Node3D = null
var _icon_mask_shader: Shader = null
var _circle_photo_mask_shader: Shader = null
var _settings_button_rest_position := Vector2.ZERO
var _settings_button_tween: Tween = null
var _mobile_controls: Control = null


func _ready() -> void:
	GameData.game_state_changed.connect(_refresh)
	GameData.game_event.connect(_on_game_event)
	get_viewport().size_changed.connect(_apply_safe_area_margins)
	_init_settings_overlay()
	_init_mobile_controls()
	_apply_direction_photo_masks()
	_apply_direction_arrow_styles()
	_apply_static_text_styles()
	_apply_safe_area_margins()
	_refresh()
	_update_direction_indicators()


func _init_mobile_controls() -> void:
	_mobile_controls = MobileControlsScript.new()
	get_node("Root").add_child(_mobile_controls)


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
	if get_viewport().size_changed.is_connected(_apply_safe_area_margins):
		get_viewport().size_changed.disconnect(_apply_safe_area_margins)
	if GameData.game_state_changed.is_connected(_refresh):
		GameData.game_state_changed.disconnect(_refresh)
	if GameData.game_event.is_connected(_on_game_event):
		GameData.game_event.disconnect(_on_game_event)


func _init_settings_overlay() -> void:
	settings_overlay.visible = false
	_apply_settings_button_style()
	settings_button.pressed.connect(_on_settings_button_pressed)
	settings_button.mouse_entered.connect(_on_settings_button_mouse_entered)
	settings_button.mouse_exited.connect(_on_settings_button_mouse_exited)
	settings_close_button.pressed.connect(_on_settings_close_button_pressed)
	hud_bgm_volume_slider.value_changed.connect(_on_hud_bgm_volume_slider_value_changed)
	hud_sfx_volume_slider.value_changed.connect(_on_hud_sfx_volume_slider_value_changed)
	hud_bgm_volume_slider.set_value_no_signal(AudioManager.get_bgm_volume() * 100.0)
	hud_sfx_volume_slider.set_value_no_signal(AudioManager.get_sfx_volume() * 100.0)
	_refresh_hud_audio_volume_labels()


func _apply_safe_area_margins() -> void:
	var safe_margins := _safe_area_margins()
	var left_margin: float = max(TOP_BAR_BASE_LEFT, safe_margins.x + SAFE_AREA_EXTRA_MARGIN)
	var top_margin: float = max(TOP_BAR_BASE_TOP, safe_margins.y + SAFE_AREA_EXTRA_MARGIN)
	var right_margin: float = max(TOP_BAR_BASE_RIGHT, safe_margins.z + SAFE_AREA_EXTRA_MARGIN)
	var bottom_margin: float = max(SETTINGS_BUTTON_BASE_BOTTOM, safe_margins.w + SAFE_AREA_EXTRA_MARGIN)

	top_bar.offset_left = left_margin
	top_bar.offset_top = top_margin
	top_bar.offset_right = -right_margin
	top_bar.offset_bottom = top_margin + TOP_BAR_HEIGHT

	player_list_panel.offset_left = max(PLAYER_LIST_BASE_LEFT, safe_margins.x + SAFE_AREA_EXTRA_MARGIN)
	player_list_panel.offset_right = player_list_panel.offset_left + PLAYER_LIST_WIDTH

	settings_button.offset_left = -right_margin - SETTINGS_BUTTON_SIZE
	settings_button.offset_top = -bottom_margin - SETTINGS_BUTTON_SIZE
	settings_button.offset_right = -right_margin
	settings_button.offset_bottom = -bottom_margin
	_settings_button_rest_position = settings_button.position


func _safe_area_margins() -> Vector4:
	if not _is_mobile_safe_area_target():
		return Vector4.ZERO

	var viewport_size := get_viewport().get_visible_rect().size
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe_rect := DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return Vector4.ZERO

	var scale := Vector2.ONE
	if screen_size.x > 0.0 and screen_size.y > 0.0:
		scale = Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)

	var left := float(safe_rect.position.x) * scale.x
	var top := float(safe_rect.position.y) * scale.y
	var right: float = max(0.0, screen_size.x - float(safe_rect.position.x + safe_rect.size.x)) * scale.x
	var bottom: float = max(0.0, screen_size.y - float(safe_rect.position.y + safe_rect.size.y)) * scale.y
	return Vector4(left, top, right, bottom)


func _is_mobile_safe_area_target() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()


func _refresh_hud_audio_volume_labels() -> void:
	hud_bgm_volume_value_label.text = "%d%%" % int(round(hud_bgm_volume_slider.value))
	hud_sfx_volume_value_label.text = "%d%%" % int(round(hud_sfx_volume_slider.value))


func _on_settings_button_pressed() -> void:
	settings_overlay.visible = true
	hud_bgm_volume_slider.set_value_no_signal(AudioManager.get_bgm_volume() * 100.0)
	hud_sfx_volume_slider.set_value_no_signal(AudioManager.get_sfx_volume() * 100.0)
	_refresh_hud_audio_volume_labels()


func _on_settings_button_mouse_entered() -> void:
	_tween_settings_button_to(_settings_button_rest_position + Vector2(0, -6))


func _on_settings_button_mouse_exited() -> void:
	_tween_settings_button_to(_settings_button_rest_position)


func _tween_settings_button_to(target_position: Vector2) -> void:
	if _settings_button_tween != null:
		_settings_button_tween.kill()
	_settings_button_tween = create_tween()
	_settings_button_tween.set_trans(Tween.TRANS_QUAD)
	_settings_button_tween.set_ease(Tween.EASE_OUT)
	_settings_button_tween.tween_property(settings_button, "position", target_position, 0.12)


func _on_settings_close_button_pressed() -> void:
	settings_overlay.visible = false


func _on_hud_bgm_volume_slider_value_changed(value: float) -> void:
	AudioManager.set_bgm_volume(value / 100.0)
	_refresh_hud_audio_volume_labels()


func _on_hud_sfx_volume_slider_value_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
	_refresh_hud_audio_volume_labels()


func _refresh() -> void:
	timer_label.text = "남은 시간 %s" % _format_time(GameData.remaining_seconds)
	score_label.text = "모은 새끼오리 %d/%d" % [GameData.score, GameData.target_score]
	_refresh_countdown()
	_refresh_player_list()


func _refresh_countdown() -> void:
	var is_countdown := GameData.phase == "countdown"
	countdown_overlay.visible = is_countdown
	if not is_countdown:
		return

	if GameData.countdown_seconds > 0:
		countdown_label.text = "게임 시작 %d초 전" % GameData.countdown_seconds
	else:
		countdown_label.text = "시작!"


func _format_time(seconds: int) -> String:
	var minutes := int(seconds / 60)
	var remaining := seconds % 60
	return "%02d:%02d" % [minutes, remaining]


func _on_game_event(event: String, data: Dictionary) -> void:
	if event == "game_ended":
		_hide_game_toasts()
		SceneRouter.show_overlay("result")
		return
	if event == "game_started":
		_show_objective_toast()
		return

	var message := _event_message(event, data)
	if message != "":
		_show_event_toast(message)


func _hide_game_toasts() -> void:
	_toast_remaining = 0.0
	_objective_remaining = 0.0
	event_toast.visible = false
	objective_toast.visible = false


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

	var is_jailed := str(player.get("state", "")) == "jailed"
	row.add_child(_make_role_status_icon(_icon_path_for_team(str(player.get("team", ""))), is_jailed))

	var name_label: Label = Label.new()
	name_label.text = str(player.get("nickname", "Player"))
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_game_text_style(name_label, 22, Color.WHITE, 6, 4)
	row.add_child(name_label)

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


func _make_role_status_icon(role_path: String, is_jailed: bool) -> Control:
	var holder := _make_hud_icon(role_path, Vector2(30, 30))
	if not is_jailed or not ResourceLoader.exists(JAIL_ICON_PATH):
		return holder

	var jail_texture: Texture2D = load(JAIL_ICON_PATH) as Texture2D
	if jail_texture == null:
		return holder

	var jail_size := Vector2(44, 50)
	var jail_offset := Vector2(-1, -6)
	_add_raw_icon_layer(holder, jail_texture, jail_offset, jail_size)
	return holder


func _apply_settings_button_style() -> void:
	var texture := settings_button.texture_normal
	if texture == null:
		return

	var icon_size := Vector2(48, 48)
	settings_button.texture_normal = null
	_add_icon_layer(settings_button, texture, Vector2(4, 7), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(settings_button, texture, Vector2(1, 4), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(settings_button, texture, Vector2(7, 4), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(settings_button, texture, Vector2(4, 1), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(settings_button, texture, Vector2(4, 4), icon_size, Color.WHITE)


func _add_raw_icon_layer(parent: Control, texture: Texture2D, offset: Vector2, icon_size: Vector2) -> void:
	var layer: TextureRect = TextureRect.new()
	layer.position = offset
	layer.custom_minimum_size = icon_size
	layer.size = icon_size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(layer)


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


func _apply_direction_photo_masks() -> void:
	var material := _make_circle_photo_mask_material()
	jail_photo.material = material.duplicate()
	nest_photo.material = material.duplicate()
	nest_2_photo.material = material.duplicate()


func _apply_direction_arrow_styles() -> void:
	_apply_direction_arrow_style(jail_arrow_label)
	_apply_direction_arrow_style(nest_arrow_label)
	_apply_direction_arrow_style(nest_2_arrow_label)


func _apply_direction_arrow_style(arrow: TextureRect) -> void:
	if arrow == null or arrow.texture == null:
		return

	var texture := arrow.texture
	var icon_size := arrow.size
	arrow.texture = null
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_icon_layer(arrow, texture, Vector2(0, 5), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(arrow, texture, Vector2(-3, 2), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(arrow, texture, Vector2(3, 2), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(arrow, texture, Vector2(0, -1), icon_size, Color(0.04, 0.05, 0.06, 1.0))
	_add_icon_layer(arrow, texture, Vector2(0, 2), icon_size, Color.WHITE)


func _make_circle_photo_mask_material() -> ShaderMaterial:
	if _circle_photo_mask_shader == null:
		_circle_photo_mask_shader = Shader.new()
		_circle_photo_mask_shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 tex = texture(TEXTURE, UV);\n\tfloat mask = step(length(UV - vec2(0.5)), 0.5);\n\tCOLOR = vec4(tex.rgb, tex.a * mask);\n}"
	var material := ShaderMaterial.new()
	material.shader = _circle_photo_mask_shader
	return material


func _apply_static_text_styles() -> void:
	_apply_game_text_style(timer_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(score_label, 34, Color.WHITE, 8, 5)
	_apply_game_text_style(event_message_label, 30, Color.WHITE, 7, 4)
	_apply_game_text_style(countdown_label, 72, Color.WHITE, 12, 7)
	_apply_game_text_style(objective_label, 34, Color.WHITE, 7, 4)


func _apply_game_text_style(label: Label, font_size: int, color: Color, outline_size: int, shadow_offset_y: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.06, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", shadow_offset_y)


func _event_message(event: String, data: Dictionary) -> String:
	match event:
		"player_jailed":
			return "%s님이 감옥에 갇혔습니다!" % _player_name(data, "playerName", "playerId")
		"player_released":
			return "%s님이 감옥에서 탈출했습니다!" % _player_name(data, "playerName", "playerId")
		"player_rescued":
			var rescuer := _player_name(data, "rescuerName", "rescuerId")
			var target := _player_name(data, "targetName", "targetId")
			return "모든 오리들이 탈옥했습니다!" 
		"rescue_started":
			var rescuer := _player_name(data, "rescuerName", "rescuerId")
			return "%s님이 수감된 오리를 구출하고 있습니다!" % rescuer
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


func _update_direction_indicator(indicator: Control, arrow_label: Control, world_position: Vector3, camera: Camera3D) -> void:
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
	var half_bounds: Vector2 = viewport_size * 0.5 - Vector2.ONE * (INDICATOR_SAFE_RADIUS + INDICATOR_MARGIN)
	var distance_x := INF
	if abs(unit.x) >= 0.001:
		distance_x = half_bounds.x / abs(unit.x)
	var distance_y := INF
	if abs(unit.y) >= 0.001:
		distance_y = half_bounds.y / abs(unit.y)
	var edge_center: Vector2 = center + unit * min(distance_x, distance_y)
	indicator.position = edge_center - INDICATOR_CENTER

	var rotator := indicator.get_node_or_null("Rotator") as Control
	if rotator != null:
		var target_angle := direction.angle()
		rotator.rotation = target_angle
		arrow_label.rotation = 0.0

		var circle := rotator.get_node_or_null("Circle") as Control
		if circle != null:
			circle.rotation = -target_angle


func _is_world_position_visible(screen_pos: Vector2, viewport_size: Vector2, is_behind: bool) -> bool:
	if is_behind:
		return false

	return (
		screen_pos.x >= INDICATOR_MARGIN
		and screen_pos.x <= viewport_size.x - INDICATOR_MARGIN
		and screen_pos.y >= INDICATOR_MARGIN
		and screen_pos.y <= viewport_size.y - INDICATOR_MARGIN
	)
