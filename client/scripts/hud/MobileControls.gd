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
@onready var _dash_button: Button = $DashButton
@onready var _dash_cooldown_ring: TextureProgressBar = $DashCooldownRing
var _dash_ready_texture: ImageTexture
var _dash_cooldown_texture: ImageTexture


func _ready() -> void:
	visible = _should_show_mobile_controls()
	_configure_dash_button()
	_configure_dash_cooldown_ring()
	get_viewport().size_changed.connect(_position_dash_button)
	call_deferred("_position_dash_button")
	set_process_input(true)
	set_process(true)


func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_position_dash_button):
		get_viewport().size_changed.disconnect(_position_dash_button)
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
	var should_show_dash := visible and _local_player_can_dash()
	_dash_button.visible = should_show_dash
	# 표시는 조이스틱과 동일하게 phase 무관(터치스크린 + 술래 팀이면 항상)이지만, 실제 대시는
	# playing 단계에서만 의미가 있다(player.gd의 _update_dash가 playing에서만 돎). 로비/카운트다운
	# 중에도 클릭 가능하게 두면 GameData.mobile_dash_requested가 소비되지 않고 남아있다가,
	# 게임이 실제로 시작되는 순간 플레이어가 의도치 않은 대시가 터지므로 여기서 막는다.
	_dash_button.disabled = not (should_show_dash and GameData.phase == "playing")
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


func _configure_dash_button() -> void:
	if not _dash_button.pressed.is_connected(_on_dash_button_pressed):
		_dash_button.pressed.connect(_on_dash_button_pressed)
	_dash_button.add_theme_font_size_override("font_size", 28)
	_dash_button.add_theme_color_override("font_color", Color.WHITE)
	_dash_button.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.06, 1.0))
	_dash_button.add_theme_constant_override("outline_size", 6)
	_dash_button.add_theme_stylebox_override("normal", _make_dash_style(Color(0.16, 0.49, 0.82, 0.9), Color(0.05, 0.18, 0.34, 0.95)))
	_dash_button.add_theme_stylebox_override("hover", _make_dash_style(Color(0.25, 0.58, 0.92, 0.95), Color(0.05, 0.18, 0.34, 0.95)))
	_dash_button.add_theme_stylebox_override("pressed", _make_dash_style(Color(0.08, 0.27, 0.48, 0.95), Color(0.03, 0.11, 0.22, 1.0)))
	_dash_button.add_theme_stylebox_override("disabled", _make_dash_style(Color(0.08, 0.16, 0.24, 0.45), Color(0.03, 0.08, 0.14, 0.6)))


func _configure_dash_cooldown_ring() -> void:
	_dash_cooldown_ring.texture_under = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_TRACK_COLOR)
	_dash_ready_texture = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_READY_COLOR)
	_dash_cooldown_texture = RingTexture.generate(DASH_RING_SIZE, DASH_RING_OUTER_RADIUS, DASH_RING_INNER_RADIUS, DASH_COOLDOWN_COLOR)
	_dash_cooldown_ring.texture_progress = _dash_ready_texture


func _position_dash_button() -> void:
	if _dash_button == null:
		return
	var safe_margins := _safe_area_margins()
	var margin_right: float = max(DASH_BASE_MARGIN_RIGHT, safe_margins.z + SAFE_AREA_EXTRA_MARGIN)
	var margin_bottom: float = max(DASH_BASE_MARGIN_BOTTOM, safe_margins.w + SAFE_AREA_EXTRA_MARGIN)
	var viewport_size := get_viewport_rect().size
	margin_right = min(margin_right, max(0.0, viewport_size.x - DASH_BUTTON_SIZE - 16.0))
	margin_bottom = min(margin_bottom, max(0.0, viewport_size.y - DASH_BUTTON_SIZE - 16.0))
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
	var should_show := visible and _dash_button.visible and _local_player_can_dash()
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
		call_deferred("_position_dash_button")


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
