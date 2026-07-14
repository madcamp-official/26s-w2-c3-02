extends Control

const ACTIVE_WIDTH_RATIO := 0.5
const JOYSTICK_RADIUS := 80.0
const STICK_RADIUS := 32.0
const DASH_BUTTON_SIZE := 110.0
const DASH_RING_SIZE := 110
const DASH_RING_OUTER_RADIUS := 52.0
const DASH_RING_INNER_RADIUS := 42.0
const DASH_TRACK_COLOR := Color(0.05, 0.05, 0.05, 0.55)
const DASH_READY_COLOR := Color(0.35, 0.85, 0.45, 0.95)
const DASH_COOLDOWN_COLOR := Color(0.95, 0.72, 0.24, 0.95)
const SAFE_AREA_EXTRA_MARGIN := 4.0
const DASH_BASE_MARGIN_RIGHT := 116.0
const DASH_BASE_MARGIN_BOTTOM := 116.0

var _touch_index := -1
var _joystick_active := false
var _base_position := Vector2.ZERO
var _stick_position := Vector2.ZERO
var _dash_button: Button
var _dash_cooldown_ring: TextureProgressBar
var _dash_ready_texture: ImageTexture
var _dash_cooldown_texture: ImageTexture


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = _should_show_mobile_controls()
	_create_dash_button()
	set_process_input(true)
	set_process(true)


func _exit_tree() -> void:
	GameData.mobile_move_input = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _process(_delta: float) -> void:
	if _dash_button == null:
		return
	var should_show_dash := GameData.phase == "playing"
	_dash_button.visible = should_show_dash
	_dash_button.disabled = not should_show_dash or not _local_player_can_dash()
	_update_dash_cooldown_ring()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index != -1 or not _is_joystick_start_position(event.position):
			return
		_touch_index = event.index
		_joystick_active = true
		_base_position = event.position
		_stick_position = event.position
		GameData.mobile_move_input = Vector2.ZERO
		queue_redraw()
		return

	if event.index == _touch_index:
		_reset_joystick()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return

	var offset := event.position - _base_position
	if offset.length() > JOYSTICK_RADIUS:
		offset = offset.normalized() * JOYSTICK_RADIUS
	_stick_position = _base_position + offset

	var direction := offset / JOYSTICK_RADIUS
	GameData.mobile_move_input = direction if direction.length() >= 0.08 else Vector2.ZERO
	queue_redraw()


func _reset_joystick() -> void:
	_touch_index = -1
	_joystick_active = false
	GameData.mobile_move_input = Vector2.ZERO
	queue_redraw()


func _is_joystick_start_position(position: Vector2) -> bool:
	var viewport_size := get_viewport_rect().size
	if position.x > viewport_size.x * ACTIVE_WIDTH_RATIO:
		return false
	return position.y > viewport_size.y * 0.18


func _create_dash_button() -> void:
	_dash_button = Button.new()
	_dash_button.text = "대시"
	_dash_button.custom_minimum_size = Vector2(DASH_BUTTON_SIZE, DASH_BUTTON_SIZE)
	_dash_button.focus_mode = Control.FOCUS_NONE
	_dash_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_dash_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dash_button.pressed.connect(_on_dash_button_pressed)
	_dash_button.add_theme_font_size_override("font_size", 28)
	_dash_button.add_theme_color_override("font_color", Color.WHITE)
	_dash_button.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0))
	_dash_button.add_theme_constant_override("outline_size", 6)
	_dash_button.add_theme_stylebox_override("normal", _make_dash_style(Color(0.16, 0.49, 0.82, 0.9), Color(0.05, 0.18, 0.34, 0.95)))
	_dash_button.add_theme_stylebox_override("hover", _make_dash_style(Color(0.25, 0.58, 0.92, 0.95), Color(0.05, 0.18, 0.34, 0.95)))
	_dash_button.add_theme_stylebox_override("pressed", _make_dash_style(Color(0.08, 0.27, 0.48, 0.95), Color(0.03, 0.11, 0.22, 1.0)))
	_dash_button.add_theme_stylebox_override("disabled", _make_dash_style(Color(0.08, 0.16, 0.24, 0.45), Color(0.03, 0.08, 0.14, 0.6)))
	add_child(_dash_button)
	_create_dash_cooldown_ring()
	_position_dash_button()


func _create_dash_cooldown_ring() -> void:
	_dash_cooldown_ring = TextureProgressBar.new()
	_dash_cooldown_ring.custom_minimum_size = Vector2(DASH_RING_SIZE, DASH_RING_SIZE)
	_dash_cooldown_ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_dash_cooldown_ring.radial_initial_angle = 0.0
	_dash_cooldown_ring.radial_fill_degrees = 360.0
	_dash_cooldown_ring.min_value = 0.0
	_dash_cooldown_ring.max_value = 1.0
	_dash_cooldown_ring.step = 0.0
	_dash_cooldown_ring.value = 1.0
	_dash_cooldown_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash_cooldown_ring.texture_under = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_TRACK_COLOR)
	_dash_ready_texture = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_READY_COLOR)
	_dash_cooldown_texture = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_COOLDOWN_COLOR)
	_dash_cooldown_ring.texture_progress = _dash_ready_texture
	add_child(_dash_cooldown_ring)
	move_child(_dash_cooldown_ring, _dash_button.get_index() + 1)


func _position_dash_button() -> void:
	if _dash_button == null:
		return
	var safe_margins := _safe_area_margins()
	var margin_right: float = max(DASH_BASE_MARGIN_RIGHT, safe_margins.z + SAFE_AREA_EXTRA_MARGIN)
	var margin_bottom: float = max(DASH_BASE_MARGIN_BOTTOM, safe_margins.w + SAFE_AREA_EXTRA_MARGIN)
	_dash_button.anchor_left = 1.0
	_dash_button.anchor_top = 1.0
	_dash_button.anchor_right = 1.0
	_dash_button.anchor_bottom = 1.0
	_dash_button.offset_left = -margin_right - DASH_BUTTON_SIZE
	_dash_button.offset_top = -margin_bottom - DASH_BUTTON_SIZE
	_dash_button.offset_right = -margin_right
	_dash_button.offset_bottom = -margin_bottom

	if _dash_cooldown_ring != null:
		_dash_cooldown_ring.anchor_left = _dash_button.anchor_left
		_dash_cooldown_ring.anchor_top = _dash_button.anchor_top
		_dash_cooldown_ring.anchor_right = _dash_button.anchor_right
		_dash_cooldown_ring.anchor_bottom = _dash_button.anchor_bottom
		_dash_cooldown_ring.offset_left = _dash_button.offset_left
		_dash_cooldown_ring.offset_top = _dash_button.offset_top
		_dash_cooldown_ring.offset_right = _dash_button.offset_right
		_dash_cooldown_ring.offset_bottom = _dash_button.offset_bottom


func _update_dash_cooldown_ring() -> void:
	if _dash_cooldown_ring == null:
		return
	var should_show := visible and _dash_button.visible and GameData.phase == "playing" and _local_player_can_dash()
	_dash_cooldown_ring.visible = should_show
	if not should_show:
		return

	var duration: float = max(GameData.dash_cooldown_duration, 0.001)
	var remaining: float = GameData.dash_cooldown_remaining
	var ready_fraction: float = clamp(1.0 - remaining / duration, 0.0, 1.0)
	_dash_cooldown_ring.value = ready_fraction
	_dash_cooldown_ring.texture_progress = _dash_ready_texture if ready_fraction >= 1.0 else _dash_cooldown_texture


func _make_dash_style(color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 8
	var radius := int(DASH_BUTTON_SIZE * 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	return style


func _on_dash_button_pressed() -> void:
	if _dash_button.disabled:
		return
	GameData.request_mobile_dash()


func _local_player_can_dash() -> bool:
	var team := MockServer.local_player_team()
	return team == "tagger" or team == "police"


func _draw() -> void:
	if not _joystick_active:
		return
	draw_circle(_base_position, JOYSTICK_RADIUS, Color(0.05, 0.12, 0.18, 0.42))
	draw_arc(_base_position, JOYSTICK_RADIUS, 0.0, TAU, 96, Color(0.92, 0.98, 1.0, 0.55), 4.0)
	draw_circle(_stick_position, STICK_RADIUS, Color(0.35, 0.67, 1.0, 0.72))
	draw_arc(_stick_position, STICK_RADIUS, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.7), 3.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_position_dash_button()


func _should_show_mobile_controls() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()


func _safe_area_margins() -> Vector4:
	if not _should_show_mobile_controls():
		return Vector4.ZERO

	var viewport_size := get_viewport_rect().size
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
