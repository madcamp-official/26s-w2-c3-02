extends Control

enum ContentView { NONE, PLAY, INVENTORY, RULES, SETTINGS, LOGIN }

@onready var play_panel: PanelContainer = %PlayPanel
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var rules_panel: PanelContainer = %RulesPanel
@onready var rules_card_index_label: Label = %RulesCardIndexLabel
@onready var rules_prev_button: Button = %RulesPrevButton
@onready var rules_next_button: Button = %RulesNextButton
@onready var rules_card_title_label: Label = %RulesCardTitleLabel
@onready var rules_card_text_label: RichTextLabel = %RulesCardTextLabel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var login_panel: PanelContainer = %LoginPanel
@onready var room_list: VBoxContainer = %RoomList
@onready var join_details: VBoxContainer = %JoinDetails
@onready var selected_room_label: Label = %SelectedRoomLabel
@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton
@onready var create_room_overlay: Control = %CreateRoomOverlay
@onready var create_room_name_input: LineEdit = %CreateRoomNameInput
@onready var create_room_code_input: LineEdit = %CreateRoomCodeInput
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
const LOCK_ICON_PATH := "res://assets/ui/icons/lock_icon.png"

const RULES_CARDS: Array[Dictionary] = [
	{
		"title": "게임 개요",
		"color": Color(0.466667, 0.713726, 0.956863, 1),
		"body": "\n[b]오리 팀: [/b]  시간 안에 목표한 수만큼 새끼오리를 둥지에 배달하면 승리한다\n\n[b]경찰 팀: [/b]  시간 종료까지 오리들의 배달을 저지하거나, 오리를 전원 감옥에 가두면 승리한다\n\n",
	},
	{
		"title": "오리 팀",
		"color": Color(1, 0.85, 0.35, 1),
		"body": "[b]조작[/b]\n이동: WASD 또는 조이스틱을 사용한다\n\n[b]목표[/b]\n흩어진 새끼오리를 주워 둥지로 데려간다\n\n[b]감옥 탈출[/b]\n경찰의 돌진에 맞으면 감옥에 갇힌다. 동료가 감옥 근처에 일정 시간 머무르면 갇힌 오리들이 한꺼번에 풀려난다. 오리가 혼자인 경우 시간이 지나면 자동으로 탈출한다.",
	},
	{
		"title": "경찰 팀",
		"color": Color(1, 0.55, 0.5, 1),
		"body": "[b]조작[/b]\n이동: WASD 또는 조이스틱을 사용한다\n대시: Space 키로 바라보는 방향으로 돌진한다\n\n[b]목표[/b]\n돌진으로 오리를 잡아 감옥으로 보낸다\n\n[b]승리 조건[/b]\n시간이 끝날 때까지 오리 팀의 목표 달성을 막거나, 오리를 전부 감옥에 가두면 승리한다.",
	},
]

var _normalizing_room_code := false
var _normalizing_create_room_code := false
var _normalizing_nickname := false
var _current_view: ContentView = ContentView.NONE
var _rooms_by_id: Dictionary = {}
var _selected_room: Dictionary = {}
var _rules_card_index := 0


func _ready() -> void:
	GameData.room_state_changed.connect(_refresh_lobby)
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	_on_room_code_input_text_changed(room_code_input.text)
	nickname_input.text_changed.connect(_on_nickname_input_text_changed)
	_on_nickname_input_text_changed(nickname_input.text)
	create_room_code_input.text_changed.connect(_on_create_room_code_input_text_changed)
	rules_prev_button.pressed.connect(_on_rules_prev_button_pressed)
	rules_next_button.pressed.connect(_on_rules_next_button_pressed)
	_refresh_rules_card()
	_init_audio_settings()

	_set_content_view(ContentView.NONE)
	lobby_overlay.visible = false
	create_room_overlay.visible = false
	_clear_selected_room()

	if GameData.menu_entry_view == "lobby":
		GameData.menu_entry_view = "menu"
		_show_lobby()


func _exit_tree() -> void:
	if GameData.room_state_changed.is_connected(_refresh_lobby):
		GameData.room_state_changed.disconnect(_refresh_lobby)


func _on_create_room_button_pressed() -> void:
	create_room_name_input.text = ""
	create_room_code_input.text = ""
	create_room_overlay.visible = true
	alert_overlay.visible = false
	create_room_name_input.grab_focus()


func _on_create_room_confirm_button_pressed() -> void:
	var room_code := create_room_code_input.text.strip_edges()
	if room_code != "" and room_code.length() != 4:
		_show_alert("방 코드는 네 자리 숫자로 입력해주세요.")
		return
	var result: Dictionary = MockServer.create_room("Player", room_code, create_room_name_input.text)
	if result.get("ok", false) != true:
		_show_alert(str(result.get("message", "방을 만들 수 없습니다.")))
		return
	create_room_overlay.visible = false
	_show_lobby()


func _on_create_room_close_button_pressed() -> void:
	create_room_overlay.visible = false


func _on_join_room_button_pressed() -> void:
	if _selected_room.is_empty():
		_show_alert("참가할 방을 먼저 선택해주세요.")
		return
	var result: Dictionary = MockServer.join_room(nickname_input.text, str(_selected_room.get("room_id", "")), room_code_input.text)
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

	if _selected_room.is_empty():
		join_room_button.disabled = true
		return
	if bool(_selected_room.get("is_private", false)):
		join_room_button.disabled = normalized.length() != 4
	else:
		join_room_button.disabled = false


func _on_create_room_code_input_text_changed(new_text: String) -> void:
	if _normalizing_create_room_code:
		return

	var normalized := _room_code_digits(new_text)
	if normalized == new_text:
		return
	_normalizing_create_room_code = true
	create_room_code_input.text = normalized
	create_room_code_input.caret_column = normalized.length()
	_normalizing_create_room_code = false


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
	rules_panel.visible = view == ContentView.RULES
	settings_panel.visible = view == ContentView.SETTINGS
	login_panel.visible = view == ContentView.LOGIN
	if view == ContentView.PLAY:
		_clear_selected_room()
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


func _on_rules_button_pressed() -> void:
	_rules_card_index = 0
	_refresh_rules_card()
	_set_content_view(ContentView.RULES)


func _on_rules_prev_button_pressed() -> void:
	_rules_card_index = (_rules_card_index - 1 + RULES_CARDS.size()) % RULES_CARDS.size()
	_refresh_rules_card()


func _on_rules_next_button_pressed() -> void:
	_rules_card_index = (_rules_card_index + 1) % RULES_CARDS.size()
	_refresh_rules_card()


func _refresh_rules_card() -> void:
	if not is_instance_valid(rules_card_title_label):
		return

	var card: Dictionary = RULES_CARDS[_rules_card_index]
	rules_card_title_label.text = str(card["title"])
	rules_card_title_label.add_theme_color_override("font_color", card["color"])
	rules_card_text_label.text = str(card["body"])
	rules_card_index_label.text = "%d / %d" % [_rules_card_index + 1, RULES_CARDS.size()]


func _on_settings_nav_button_pressed() -> void:
	_set_content_view(ContentView.SETTINGS)


func _on_login_button_pressed() -> void:
	_set_content_view(ContentView.LOGIN)


func _refresh_room_list() -> void:
	if not is_instance_valid(room_list):
		return

	_rooms_by_id.clear()
	for child in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()

	for room in MockServer.list_rooms():
		_rooms_by_id[str(room.get("room_id", ""))] = room
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
	var room_name: String = str(room.get("room_name", room.get("host_nickname", "-")))
	var player_count: int = int(room.get("player_count", 0))
	var is_full: bool = player_count >= MockServer.MVP_PLAYER_LIMIT
	var is_private := bool(room.get("is_private", false))

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

	var room_name_row: HBoxContainer = HBoxContainer.new()
	room_name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_name_row.add_theme_constant_override("separation", 6)
	content.add_child(room_name_row)

	var room_name_label: Label = Label.new()
	room_name_label.text = room_name
	room_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_name_label.add_theme_font_size_override("font_size", 22)
	room_name_label.add_theme_color_override("font_color", Color(0.941176, 0.972549, 1, 1))
	room_name_row.add_child(room_name_label)

	if is_private:
		var lock_icon := TextureRect.new()
		lock_icon.custom_minimum_size = Vector2(22, 22)
		lock_icon.texture = load(LOCK_ICON_PATH)
		lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		room_name_row.add_child(lock_icon)

	var count_label: Label = Label.new()
	count_label.text = "%d/%d" % [player_count, MockServer.MVP_PLAYER_LIMIT]
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 22)
	count_label.add_theme_color_override("font_color", Color(0.682353, 0.780392, 0.886275, 1))
	content.add_child(count_label)

	return row


func _on_room_row_pressed(room_id: String) -> void:
	_selected_room = _rooms_by_id.get(room_id, {})
	if _selected_room.is_empty():
		_clear_selected_room()
		return

	var room_name := str(_selected_room.get("room_name", _selected_room.get("host_nickname", "-")))
	var is_private := bool(_selected_room.get("is_private", false))
	selected_room_label.text = "%s 선택됨" % room_name
	join_details.visible = true
	nickname_input.text = ""
	room_code_input.text = ""
	room_code_input.editable = is_private
	room_code_input.placeholder_text = "4자리 숫자" if is_private else "공개 방"
	_on_room_code_input_text_changed(room_code_input.text)


func _clear_selected_room() -> void:
	_selected_room.clear()
	if not is_instance_valid(join_details):
		return
	join_details.visible = false
	selected_room_label.text = "방을 선택하세요"
	nickname_input.text = ""
	room_code_input.text = ""
	room_code_input.editable = true
	join_room_button.disabled = true


func _show_lobby() -> void:
	lobby_overlay.visible = true
	alert_overlay.visible = false
	_refresh_lobby()


func _refresh_lobby() -> void:
	if not is_instance_valid(room_code_label) or not is_instance_valid(players_list):
		return

	var display_room_id := GameData.room_id.strip_edges()
	room_code_label.text = "방 코드: %s" % ("-" if display_room_id == "" else display_room_id)
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
