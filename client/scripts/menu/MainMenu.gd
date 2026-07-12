extends Control

enum ContentView { NONE, PLAY, INVENTORY, SETTINGS, LOGIN }

@onready var play_panel: PanelContainer = %PlayPanel
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var login_panel: PanelContainer = %LoginPanel
@onready var room_list: VBoxContainer = %RoomList
@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton
@onready var lobby_overlay: Control = %LobbyOverlay
@onready var room_code_label: Label = %RoomCodeLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var lobby_status_label: Label = %LobbyStatusLabel
@onready var add_mock_player_button: Button = %AddMockPlayerButton
@onready var start_game_button: Button = %StartGameButton
@onready var alert_overlay: Control = %AlertOverlay
@onready var alert_message_label: Label = %AlertMessageLabel
@onready var bgm_volume_slider: HSlider = %BgmVolumeSlider
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var bgm_volume_value_label: Label = %BgmVolumeValueLabel
@onready var sfx_volume_value_label: Label = %SfxVolumeValueLabel

const NICKNAME_MAX_LENGTH := 8

var _normalizing_room_code := false
var _normalizing_nickname := false
var _current_view: ContentView = ContentView.NONE


func _ready() -> void:
	GameData.room_state_changed.connect(_refresh_lobby)
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	_on_room_code_input_text_changed(room_code_input.text)
	nickname_input.text_changed.connect(_on_nickname_input_text_changed)
	_on_nickname_input_text_changed(nickname_input.text)
	_init_audio_settings()

	_set_content_view(ContentView.NONE)
	lobby_overlay.visible = false

	if GameData.menu_entry_view == "lobby":
		GameData.menu_entry_view = "menu"
		_show_lobby()


func _exit_tree() -> void:
	if GameData.room_state_changed.is_connected(_refresh_lobby):
		GameData.room_state_changed.disconnect(_refresh_lobby)


func _on_create_room_button_pressed() -> void:
	var result: Dictionary = MockServer.create_room(nickname_input.text, room_code_input.text)
	if result.get("ok", false) != true:
		_show_alert(str(result.get("message", "방을 만들 수 없습니다.")))
		return
	_show_lobby()


func _on_join_room_button_pressed() -> void:
	var result: Dictionary = MockServer.join_room(nickname_input.text, room_code_input.text)
	if result.get("ok", false) != true:
		_show_alert(str(result.get("message", "방에 입장할 수 없습니다.")))
		return
	_show_lobby()


func _on_room_code_input_text_changed(new_text: String) -> void:
	if _normalizing_room_code:
		return

	var normalized := _room_code_digits(new_text)
	if normalized != new_text:
		_normalizing_room_code = true
		room_code_input.text = normalized
		room_code_input.caret_column = normalized.length()
		_normalizing_room_code = false

	join_room_button.disabled = normalized.length() != 4


func _on_nickname_input_text_changed(new_text: String) -> void:
	if _normalizing_nickname:
		return
	if new_text.length() <= NICKNAME_MAX_LENGTH:
		return
	var caret := nickname_input.caret_column
	var truncated := new_text.substr(0, NICKNAME_MAX_LENGTH)
	_normalizing_nickname = true
	nickname_input.text = truncated
	nickname_input.caret_column = min(caret, truncated.length())
	_normalizing_nickname = false


func _room_code_digits(value: String) -> String:
	var code := ""
	for i in range(value.length()):
		var c := value.substr(i, 1)
		if c >= "0" and c <= "9":
			code += c
		if code.length() >= 4:
			break
	return code


func _set_content_view(view: ContentView) -> void:
	_current_view = view
	play_panel.visible = view == ContentView.PLAY
	inventory_panel.visible = view == ContentView.INVENTORY
	settings_panel.visible = view == ContentView.SETTINGS
	login_panel.visible = view == ContentView.LOGIN
	if view == ContentView.PLAY:
		_refresh_room_list()


func _init_audio_settings() -> void:
	bgm_volume_slider.value_changed.connect(_on_bgm_volume_slider_value_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_slider_value_changed)
	bgm_volume_slider.set_value_no_signal(AudioManager.get_bgm_volume() * 100.0)
	sfx_volume_slider.set_value_no_signal(AudioManager.get_sfx_volume() * 100.0)
	_refresh_audio_volume_labels()


func _refresh_audio_volume_labels() -> void:
	bgm_volume_value_label.text = "%d%%" % int(round(bgm_volume_slider.value))
	sfx_volume_value_label.text = "%d%%" % int(round(sfx_volume_slider.value))


func _on_bgm_volume_slider_value_changed(value: float) -> void:
	AudioManager.set_bgm_volume(value / 100.0)
	_refresh_audio_volume_labels()


func _on_sfx_volume_slider_value_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
	_refresh_audio_volume_labels()


func _on_play_button_pressed() -> void:
	_set_content_view(ContentView.PLAY)


func _on_inventory_button_pressed() -> void:
	_set_content_view(ContentView.INVENTORY)


func _on_settings_nav_button_pressed() -> void:
	_set_content_view(ContentView.SETTINGS)


func _on_login_button_pressed() -> void:
	_set_content_view(ContentView.LOGIN)


func _refresh_room_list() -> void:
	if not is_instance_valid(room_list):
		return

	for child in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()

	for room in MockServer.list_rooms():
		room_list.add_child(_make_room_row(room))


func _room_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _make_room_row(room: Dictionary) -> Control:
	var room_id: String = str(room.get("room_id", "----"))
	var host_nickname: String = str(room.get("host_nickname", "-"))
	var player_count: int = int(room.get("player_count", 0))
	var is_full: bool = player_count >= MockServer.MVP_PLAYER_LIMIT

	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 54)
	row.text = ""
	row.add_theme_stylebox_override("normal", _room_card_style(Color(0.0117647, 0.054902, 0.101961, 0.75), Color(0.172549, 0.313726, 0.478431, 1)))
	row.add_theme_stylebox_override("hover", _room_card_style(Color(0.0862745, 0.223529, 0.360784, 0.9), Color(0.466667, 0.713726, 0.956863, 1)))
	row.add_theme_stylebox_override("pressed", _room_card_style(Color(0.129412, 0.45098, 0.780392, 1), Color(0.466667, 0.713726, 0.956863, 1)))
	row.pressed.connect(_on_room_row_pressed.bind(room_id))

	var content: HBoxContainer = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	row.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16.0
	content.offset_top = 8.0
	content.offset_right = -16.0
	content.offset_bottom = -8.0

	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	dot_style.corner_radius_top_left = 7
	dot_style.corner_radius_top_right = 7
	dot_style.corner_radius_bottom_right = 7
	dot_style.corner_radius_bottom_left = 7
	dot_style.bg_color = Color(0.85, 0.25, 0.25) if is_full else Color(0.45, 0.8, 0.3)
	dot.add_theme_stylebox_override("panel", dot_style)
	content.add_child(dot)

	var code_label: Label = Label.new()
	code_label.text = room_id
	code_label.custom_minimum_size = Vector2(70, 0)
	code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_label.add_theme_font_size_override("font_size", 24)
	code_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(code_label)

	var host_label: Label = Label.new()
	host_label.text = host_nickname
	host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_label.add_theme_font_size_override("font_size", 22)
	host_label.add_theme_color_override("font_color", Color(0.941176, 0.972549, 1, 1))
	content.add_child(host_label)

	var count_label: Label = Label.new()
	count_label.text = "%d/%d" % [player_count, MockServer.MVP_PLAYER_LIMIT]
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 22)
	count_label.add_theme_color_override("font_color", Color(0.682353, 0.780392, 0.886275, 1))
	content.add_child(count_label)

	return row


func _on_room_row_pressed(room_id: String) -> void:
	room_code_input.text = room_id
	_on_room_code_input_text_changed(room_id)


func _show_lobby() -> void:
	lobby_overlay.visible = true
	alert_overlay.visible = false
	_refresh_lobby()


func _refresh_lobby() -> void:
	if not is_instance_valid(room_code_label) or not is_instance_valid(players_list):
		return

	room_code_label.text = "방 코드: %s" % GameData.room_id
	lobby_status_label.text = MockServer.lobby_status_text()
	start_game_button.disabled = not MockServer.can_start_game()
	add_mock_player_button.visible = MockServer.can_add_mock_player()

	for child in players_list.get_children():
		players_list.remove_child(child)
		child.queue_free()

	for player in GameData.players:
		players_list.add_child(_make_player_row(player))


func _make_player_row(player: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 48)
	row.add_theme_constant_override("separation", 12)

	var player_id: String = str(player.get("playerId", ""))
	var role_label: Label = Label.new()
	role_label.custom_minimum_size = Vector2(68, 0)
	if player_id == GameData.local_player_id:
		role_label.text = "본인"
	else:
		role_label.text = "Mock"
	role_label.add_theme_font_size_override("font_size", 24)
	role_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(role_label)

	var name_input: LineEdit = LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.max_length = NICKNAME_MAX_LENGTH
	name_input.text = str(player.get("nickname", "Player"))
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.text_changed.connect(_on_lobby_name_input_text_changed.bind(name_input, player_id))
	row.add_child(name_input)

	var team_select: OptionButton = OptionButton.new()
	team_select.custom_minimum_size = Vector2(132, 0)
	team_select.add_item("오리", 0)
	team_select.add_item("경찰", 1)
	var team: String = str(player.get("team", "duck"))
	var selected_team_index := 0
	if team == "tagger":
		selected_team_index = 1
	team_select.select(selected_team_index)
	team_select.set_item_disabled(0, not MockServer.can_set_player_team(player_id, "duck"))
	team_select.set_item_disabled(1, not MockServer.can_set_player_team(player_id, "tagger"))
	team_select.add_theme_font_size_override("font_size", 24)
	team_select.item_selected.connect(_on_lobby_player_team_selected.bind(player_id))
	row.add_child(team_select)

	return row


func _on_lobby_name_input_text_changed(new_text: String, input: LineEdit, player_id: String) -> void:
	if input.get_meta("normalizing", false):
		return
	if new_text.length() > NICKNAME_MAX_LENGTH:
		var caret := input.caret_column
		var truncated := new_text.substr(0, NICKNAME_MAX_LENGTH)
		input.set_meta("normalizing", true)
		input.text = truncated
		input.caret_column = min(caret, truncated.length())
		input.set_meta("normalizing", false)
		new_text = truncated
	MockServer.set_player_nickname(player_id, new_text)


func _on_lobby_player_team_selected(index: int, player_id: String) -> void:
	var team := "duck"
	if index == 1:
		team = "tagger"
	if not MockServer.set_player_team(player_id, team):
		_show_alert("역할 구성이 올바르지 않습니다.")
		_refresh_lobby()


func _on_add_mock_player_button_pressed() -> void:
	if not MockServer.add_mock_player():
		_show_alert("더 이상 Mock 플레이어를 추가할 수 없습니다.")


func _on_start_game_button_pressed() -> void:
	if not MockServer.can_start_game():
		_show_alert("경찰 1명, 오리 1~2명이 필요합니다.")
		return
	SceneRouter.go_to("game")


func _on_back_button_pressed() -> void:
	lobby_overlay.visible = false


func _show_alert(message: String) -> void:
	alert_message_label.text = message
	alert_overlay.visible = true


func _on_alert_ok_button_pressed() -> void:
	alert_overlay.visible = false
