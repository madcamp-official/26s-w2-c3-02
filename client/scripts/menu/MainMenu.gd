extends Control

enum ContentView { NONE, PLAY, INVENTORY, RULES, SETTINGS, LOGIN }

const ICON_SYMBOL_FONT := preload("res://themes/IconSymbolFont.tres")

# Submit handlers apply pending IME composition before reading LineEdit.text.
@onready var play_panel: PanelContainer = %PlayPanel
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var inventory_duck_tab_button: Button = %InventoryDuckTabButton
@onready var inventory_tagger_tab_button: Button = %InventoryTaggerTabButton
@onready var inventory_skin_grid: HFlowContainer = %InventorySkinGrid
@onready var rules_panel: PanelContainer = %RulesPanel
@onready var rules_card_index_label: Label = %RulesCardIndexLabel
@onready var rules_prev_button: Button = %RulesPrevButton
@onready var rules_next_button: Button = %RulesNextButton
@onready var rules_card_title_label: Label = %RulesCardTitleLabel
@onready var rules_card_text_label: RichTextLabel = %RulesCardTextLabel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var login_panel: PanelContainer = %LoginPanel
@onready var room_list: GridContainer = %RoomList
@onready var join_details: VBoxContainer = %JoinDetails
@onready var selected_room_label: Label = %SelectedRoomLabel
@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton
@onready var create_room_overlay: Control = %CreateRoomOverlay
@onready var create_room_nickname_input: LineEdit = %CreateRoomNicknameInput
@onready var create_room_name_input: LineEdit = %CreateRoomNameInput
@onready var create_room_public_button: Button = %CreateRoomPublicButton
@onready var create_room_private_button: Button = %CreateRoomPrivateButton
@onready var refresh_room_list_button: Button = %RefreshRoomListButton
@onready var lobby_overlay: Control = %LobbyOverlay
@onready var room_code_label: Label = %RoomCodeLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var lobby_status_label: Label = %LobbyStatusLabel
@onready var start_game_button: Button = %StartGameButton
@onready var alert_overlay: Control = %AlertOverlay
@onready var alert_message_label: Label = %AlertMessageLabel
@onready var bgm_volume_slider: HSlider = %BgmVolumeSlider
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var bgm_volume_value_label: Label = %BgmVolumeValueLabel
@onready var sfx_volume_value_label: Label = %SfxVolumeValueLabel

const NICKNAME_MAX_LENGTH := 10
const ROOM_NAME_MAX_LENGTH := 10
const LOCK_ICON_PATH := "res://assets/ui/icons/lock_icon.png"

const RULES_CARDS: Array[Dictionary] = [
	{
		"title": "오리 팀\n",
		"color": Color(1, 0.85, 0.35, 1),
		"body": "<조작>\n이동: WASD 또는 조이스틱을 사용한다\n\n<목표>\n흩어진 새끼오리를 주워 둥지로 데려간다\n\n<감옥 탈출>\n경찰의 돌진에 맞으면 감옥에 갇힌다. 동료가 감옥 근처에 일정 시간 머무르면 갇힌 오리들이 모두 풀려난다. 오리가 혼자인 경우 시간이 지나면 자동으로 탈출한다.",
	},
	{
		"title": "경찰 팀\n",
		"color": Color(1, 0.55, 0.5, 1),
		"body": "<조작>\n이동: WASD 또는 조이스틱을 사용한다\n<대시>: Space 키로 바라보는 방향으로 돌진한다\n\n목표\n대시로 오리를 잡아 감옥으로 보낸다\n\n승리 조건\n시간이 끝날 때까지 오리 팀의 목표 달성을 막거나, 오리를 전부 감옥에 가두면 승리한다.",
	},
]

enum InventoryRole { DUCK, TAGGER }

const SKIN_PREVIEW_SCENE := preload("res://scenes/menu/SkinPreview3D.tscn")

const SKINS_BY_ROLE: Dictionary = {
	InventoryRole.DUCK: [
		{
			"id": "duck_default",
			"name": "기본",
			"character": "duck",
			"model": preload("res://assets/duck/duck.glb"),
			"model_position": Vector3(0, 0.622, 0),
			"model_rotation_degrees": Vector3(0, 180, 0),
			"model_scale": Vector3(2.0, 2.0, 2.0),
		},
		{
			"id": "nupjuk",
			"name": "넙죽이",
			"character": "nupjuk",
			"model": preload("res://assets/nupjuk/nupjuk.glb"),
			"model_position": Vector3(0, 0.922, 0),
			"model_rotation_degrees": Vector3(0, 180, 0),
			"model_scale": Vector3(1.2, 1.2, 1.2),
		},
		{
			"id": "greenduck",
			"name": "청둥오리",
			"character": "greenduck",
			"model": preload("res://assets/greenduck/greenduck.glb"),
			"model_position": Vector3(0, 0, 0),
			"model_rotation_degrees": Vector3(0, 0, 0),
			"model_scale": Vector3(3.1, 3.1, 3.1),
		},
		{
			"id": "mecha_duck",
			"name": "메카오리",
			"character": "mecha_duck",
			"model": preload("res://assets/mecha_duck/mecha_duck.glb"),
			"model_position": Vector3(0, 0, 0),
			"model_rotation_degrees": Vector3(0, 180, 0),
			"model_scale": Vector3(1.5, 1.5, 1.5),
		},
	],
	InventoryRole.TAGGER: [
		{
			"id": "tagger_default",
			"name": "기본",
			"character": "aligator",
			"model": preload("res://assets/aligator/aligator.glb"),
			"model_position": Vector3(0, 0.684, 0),
			"model_rotation_degrees": Vector3(0, 180, 0),
			"model_scale": Vector3(1.4, 1.4, 1.4),
		},
	],
}

var _normalizing_room_code := false
var _normalizing_create_room_nickname := false
var _normalizing_nickname := false
var _normalizing_room_name := false
var _current_view: ContentView = ContentView.NONE
var _rooms_by_id: Dictionary = {}
var _selected_room: Dictionary = {}
var _rules_card_index := 0
var _default_nickname_value := ""
var _default_create_room_nickname_value := ""
var _inventory_role: InventoryRole = InventoryRole.DUCK
var _selected_skin_by_role: Dictionary = {} # InventoryRole -> skin id
var _skin_check_badges: Dictionary = {} # InventoryRole -> {skin id -> Control}


func _ready() -> void:
	GameData.room_state_changed.connect(_refresh_lobby)
	GameData.game_state_changed.connect(_on_game_state_changed_for_lobby)
	GameData.action_error.connect(_on_action_error)
	nickname_input.max_length = NICKNAME_MAX_LENGTH
	create_room_name_input.max_length = ROOM_NAME_MAX_LENGTH
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	_on_room_code_input_text_changed(room_code_input.text)
	nickname_input.text_changed.connect(_on_nickname_input_text_changed)
	nickname_input.focus_entered.connect(_on_nickname_input_focus_entered)
	_default_nickname_value = _random_default_nickname()
	nickname_input.text = _default_nickname_value
	_on_nickname_input_text_changed(nickname_input.text)
	create_room_name_input.text_changed.connect(_on_create_room_name_input_text_changed)
	create_room_nickname_input.text_changed.connect(_on_create_room_nickname_input_text_changed)
	create_room_nickname_input.focus_entered.connect(_on_create_room_nickname_input_focus_entered)
	refresh_room_list_button.pressed.connect(_on_refresh_room_list_button_pressed)
	rules_prev_button.pressed.connect(_on_rules_prev_button_pressed)
	rules_next_button.pressed.connect(_on_rules_next_button_pressed)
	_refresh_rules_card()
	inventory_duck_tab_button.pressed.connect(_on_inventory_duck_tab_button_pressed)
	inventory_tagger_tab_button.pressed.connect(_on_inventory_tagger_tab_button_pressed)
	_init_inventory_selection()
	_refresh_inventory_grid()
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
	if GameData.game_state_changed.is_connected(_on_game_state_changed_for_lobby):
		GameData.game_state_changed.disconnect(_on_game_state_changed_for_lobby)
	if GameData.action_error.is_connected(_on_action_error):
		GameData.action_error.disconnect(_on_action_error)


func _on_action_error(_code: String, message: String) -> void:
	# game:start처럼 응답을 기다리지 않고 보내는(fire-and-forget)
	# 요청이 서버에서 거부됐을 때 여기로 도착한다. 버튼을 눌러도 조용히 아무 일도
	# 일어나지 않는 대신, 거부 사유를 알림으로 보여준다.
	if message != "":
		_show_alert(message)


func _on_game_state_changed_for_lobby() -> void:
	# 서버가 game:start를 승인해 phase가 countdown으로 바뀌면(호스트/참가자 모두 동일하게
	# 브로드캐스트로 통보받음), 로비에 있는 모든 클라이언트가 이 시점에 인게임으로 이동한다.
	# 호스트가 버튼을 누른 즉시 이동하지 않는 이유: 서버 승인 전에 미리 이동하면 시작 조건이
	# 거부됐을 때 되돌아와야 하고, 참가자는 애초에 스스로 트리거할 방법이 없기 때문이다.
	if lobby_overlay.visible and GameData.phase == "countdown":
		SceneRouter.go_to("game")


func _on_create_room_button_pressed() -> void:
	await _commit_text_input(nickname_input)
	create_room_nickname_input.text = nickname_input.text
	# 바깥 닉네임 필드가 아직 기본값(미편집) 상태일 때만 이 필드도 "기본값" 취급해서
	# 처음 클릭했을 때 지워지게 한다. 이미 사용자가 직접 입력한 닉네임이면 그대로 둔다.
	_default_create_room_nickname_value = nickname_input.text if nickname_input.text == _default_nickname_value else ""
	create_room_name_input.text = ""
	create_room_public_button.button_pressed = true
	create_room_overlay.visible = true
	alert_overlay.visible = false
	create_room_name_input.grab_focus()


func _on_create_room_confirm_button_pressed() -> void:
	await _commit_text_inputs([create_room_name_input, create_room_nickname_input])
	var nickname := create_room_nickname_input.text.strip_edges()
	if nickname == "":
		_show_alert("닉네임을 입력해주세요.")
		return
	if nickname.length() > NICKNAME_MAX_LENGTH:
		_show_alert("닉네임은 10자 이내로 입력해주세요.")
		return
	var room_name := create_room_name_input.text.strip_edges()
	if room_name.length() > ROOM_NAME_MAX_LENGTH:
		_show_alert("방 이름은 10자 이내로 입력해주세요.")
		return
	var duck_skin := get_selected_duck_skin()
	var is_private := create_room_private_button.button_pressed
	var result: Dictionary = await MockServer.create_room(nickname, room_name, duck_skin, is_private)
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
	await _commit_text_inputs([nickname_input, room_code_input])
	var nickname := nickname_input.text.strip_edges()
	if nickname.length() > NICKNAME_MAX_LENGTH:
		_show_alert("닉네임은 10자 이내로 입력해주세요.")
		return
	var duck_skin := get_selected_duck_skin()
	var result: Dictionary = await MockServer.join_room(nickname, str(_selected_room.get("room_id", "")), room_code_input.text, duck_skin)
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
		_refresh_join_room_button_state()
		return
	_refresh_join_room_button_state()


func _on_refresh_room_list_button_pressed() -> void:
	_refresh_room_list()


func _on_create_room_name_input_text_changed(new_text: String) -> void:
	if _normalizing_room_name:
		return


func _on_create_room_nickname_input_text_changed(new_text: String) -> void:
	if _normalizing_create_room_nickname:
		return
	if new_text.length() <= NICKNAME_MAX_LENGTH:
		return
	var caret := create_room_nickname_input.caret_column
	var truncated := new_text.substr(0, NICKNAME_MAX_LENGTH)
	_normalizing_create_room_nickname = true
	create_room_nickname_input.text = truncated
	create_room_nickname_input.caret_column = min(caret, truncated.length())
	_normalizing_create_room_nickname = false


func _on_nickname_input_text_changed(new_text: String) -> void:
	if _normalizing_nickname:
		return
	_refresh_join_room_button_state()


func _random_default_nickname() -> String:
	return "Player%03d" % randi_range(0, 999)


func _on_nickname_input_focus_entered() -> void:
	if nickname_input.text == _default_nickname_value:
		nickname_input.text = ""
		_refresh_join_room_button_state()


func _on_create_room_nickname_input_focus_entered() -> void:
	if _default_create_room_nickname_value != "" and create_room_nickname_input.text == _default_create_room_nickname_value:
		create_room_nickname_input.text = ""


func _room_code_digits(value: String) -> String:
	var code := ""
	for i in range(value.length()):
		var c := value.substr(i, 1)
		if c >= "0" and c <= "9":
			code += c
		if code.length() >= 4:
			break
	return code


func _commit_text_input(input: LineEdit) -> void:
	if not is_instance_valid(input):
		return
	if input.has_ime_text():
		input.apply_ime()
	await get_tree().process_frame
	if not is_instance_valid(input):
		return
	input.unedit()
	input.release_focus()
	await get_tree().process_frame


func _commit_text_inputs(inputs: Array) -> void:
	for input in inputs:
		if input is LineEdit:
			await _commit_text_input(input as LineEdit)


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


func _init_inventory_selection() -> void:
	for role in SKINS_BY_ROLE.keys():
		var skins: Array = SKINS_BY_ROLE[role]
		if not skins.is_empty():
			_selected_skin_by_role[role] = skins[0]["id"]
			_apply_equipped_character(role, str(skins[0]["character"]))


func _on_inventory_duck_tab_button_pressed() -> void:
	_inventory_role = InventoryRole.DUCK
	_refresh_inventory_grid()


func _on_inventory_tagger_tab_button_pressed() -> void:
	_inventory_role = InventoryRole.TAGGER
	_refresh_inventory_grid()


func _refresh_inventory_grid() -> void:
	if not is_instance_valid(inventory_skin_grid):
		return

	inventory_duck_tab_button.button_pressed = _inventory_role == InventoryRole.DUCK
	inventory_tagger_tab_button.button_pressed = _inventory_role == InventoryRole.TAGGER

	for child in inventory_skin_grid.get_children():
		inventory_skin_grid.remove_child(child)
		child.queue_free()

	_skin_check_badges[_inventory_role] = {}
	var selected_id: String = str(_selected_skin_by_role.get(_inventory_role, ""))
	for skin in SKINS_BY_ROLE.get(_inventory_role, []):
		var result := _make_skin_box(skin, _inventory_role, str(skin["id"]) == selected_id)
		inventory_skin_grid.add_child(result["box"])
		_skin_check_badges[_inventory_role][skin["id"]] = result["check_badge"]


func _make_skin_box(skin: Dictionary, role: InventoryRole, is_selected: bool) -> Dictionary:
	var box: Button = Button.new()
	box.flat = true
	box.text = ""
	box.focus_mode = Control.FOCUS_NONE
	box.custom_minimum_size = Vector2(110, 134)
	box.pressed.connect(_on_skin_box_pressed.bind(role, str(skin["id"]), str(skin["character"])))

	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	box.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var preview_stack: PanelContainer = PanelContainer.new()
	preview_stack.custom_minimum_size = Vector2(110, 110)
	preview_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_stack.add_theme_stylebox_override("panel", _skin_preview_box_style())
	content.add_child(preview_stack)

	var viewport_container: SubViewportContainer = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_stack.add_child(viewport_container)

	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(110, 110)
	viewport_container.add_child(viewport)

	var preview: Node3D = SKIN_PREVIEW_SCENE.instantiate()
	preview.model_scene = skin.get("model")
	preview.model_position = skin.get("model_position", Vector3.ZERO)
	preview.model_rotation_degrees = skin.get("model_rotation_degrees", Vector3(0, 180, 0))
	preview.model_scale = skin.get("model_scale", Vector3.ONE)
	viewport.add_child(preview)

	var check_badge := _make_check_badge(is_selected)
	preview_stack.add_child(check_badge)

	var name_label: Label = Label.new()
	name_label.text = str(skin.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.941176, 0.972549, 1, 1))
	content.add_child(name_label)

	return {"box": box, "check_badge": check_badge}


func _make_check_badge(is_selected: bool) -> Control:
	var anchor: Control = Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.visible = is_selected

	var badge: Panel = Panel.new()
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -20.0
	badge.offset_right = -4.0
	badge.offset_top = 4.0
	badge.offset_bottom = 20.0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.45098, 0.670588, 0.164706, 1)
	badge_style.corner_radius_top_left = 8
	badge_style.corner_radius_top_right = 8
	badge_style.corner_radius_bottom_right = 8
	badge_style.corner_radius_bottom_left = 8
	badge.add_theme_stylebox_override("panel", badge_style)
	anchor.add_child(badge)

	var check_label: Label = Label.new()
	check_label.text = "✓"
	check_label.add_theme_font_override("font", ICON_SYMBOL_FONT)
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check_label.add_theme_font_size_override("font_size", 11)
	check_label.add_theme_color_override("font_color", Color.WHITE)
	check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.add_child(check_label)

	return anchor


func _skin_preview_box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0117647, 0.054902, 0.101961, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.247059, 0.352941, 0.470588, 1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	return style


func _on_skin_box_pressed(role: InventoryRole, skin_id: String, character: String) -> void:
	if str(_selected_skin_by_role.get(role, "")) == skin_id:
		return
	_selected_skin_by_role[role] = skin_id
	_apply_equipped_character(role, character)
	var badges: Dictionary = _skin_check_badges.get(role, {})
	for id in badges:
		badges[id].visible = str(id) == skin_id


func _apply_equipped_character(role: InventoryRole, character: String) -> void:
	if role == InventoryRole.DUCK:
		GameData.local_duck_character = character
	else:
		GameData.local_tagger_character = character


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

	var room_count := 0
	for room in await MockServer.list_rooms():
		_rooms_by_id[str(room.get("room_id", ""))] = room
		room_list.add_child(_make_room_row(room))
		room_count += 1
	if room_count % 2 == 1:
		room_list.add_child(_make_room_grid_spacer())


func _make_room_grid_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, 54)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


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
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		lock_icon.custom_minimum_size = Vector2(18, 18)
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
	_set_join_form_visible(true)
	room_code_input.editable = is_private
	if is_private:
		room_code_input.text = ""
		room_code_input.placeholder_text = "4자리 숫자"
	else:
		# 공개 방은 참가코드가 곧 방 목록의 room_id이므로 사용자가 따로 입력할 필요 없이
		# 자동으로 채워서 보여준다(요구되지는 않지만 코드가 존재한다는 걸 알 수 있게).
		room_code_input.text = room_id
		room_code_input.placeholder_text = ""
	_refresh_join_room_button_state()


func _clear_selected_room() -> void:
	_selected_room.clear()
	if not is_instance_valid(join_details):
		return
	join_details.visible = true
	selected_room_label.text = "방을 선택하세요"
	_set_join_form_visible(false)
	room_code_input.text = ""
	room_code_input.editable = false
	room_code_input.placeholder_text = "4자리 숫자"
	_refresh_join_room_button_state()


func _set_join_form_visible(is_visible: bool) -> void:
	if is_instance_valid(nickname_input):
		var nickname_row := nickname_input.get_parent()
		if is_instance_valid(nickname_row):
			nickname_row.visible = is_visible
	if is_instance_valid(room_code_input):
		var room_code_row := room_code_input.get_parent()
		if is_instance_valid(room_code_row):
			room_code_row.visible = is_visible
	if is_instance_valid(join_room_button):
		join_room_button.visible = is_visible


func _refresh_join_room_button_state() -> void:
	if not is_instance_valid(join_room_button):
		return
	var has_selected_room := not _selected_room.is_empty()
	var has_nickname := false
	if is_instance_valid(nickname_input):
		has_nickname = nickname_input.text.strip_edges() != ""
	var has_join_code := false
	if is_instance_valid(room_code_input):
		has_join_code = room_code_input.text.strip_edges().length() == 4
	var needs_join_code := false
	if has_selected_room:
		needs_join_code = bool(_selected_room.get("is_private", false))
	join_room_button.disabled = not has_selected_room or not has_nickname or (needs_join_code and not has_join_code)


func _show_lobby() -> void:
	lobby_overlay.visible = true
	alert_overlay.visible = false
	_refresh_lobby()


func _refresh_lobby() -> void:
	if not is_instance_valid(room_code_label) or not is_instance_valid(players_list):
		return

	var display_join_code := GameData.join_code.strip_edges()
	room_code_label.text = "참가코드: %s" % ("-" if display_join_code == "" else display_join_code)
	# 시작 버튼은 호스트에게만 보여준다 — 참가자가 눌러도 서버가 NOT_HOST로 거부할 뿐이라,
	# 애초에 호스트가 아니면 버튼 자체를 숨겨서 왜 안 되는지 헷갈리지 않게 한다.
	start_game_button.visible = GameData.is_host
	if GameData.is_host:
		lobby_status_label.text = MockServer.lobby_status_text()
		start_game_button.disabled = not MockServer.can_start_game()
	else:
		lobby_status_label.text = "호스트가 게임을 시작하기를 기다리는 중... (역할은 시작 시 무작위 배정)"

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
	var is_local := player_id == GameData.local_player_id
	var role_label: Label = Label.new()
	role_label.custom_minimum_size = Vector2(68, 0)
	role_label.text = "본인" if is_local else "상대"
	role_label.add_theme_font_size_override("font_size", 24)
	role_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(role_label)

	var name_input: LineEdit = LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.max_length = NICKNAME_MAX_LENGTH
	name_input.text = str(player.get("nickname", "Player"))
	name_input.editable = is_local # 자기 자신의 닉네임만 바꿀 수 있다.
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.text_changed.connect(_on_lobby_name_input_text_changed.bind(name_input, player_id))
	row.add_child(name_input)

	return row


func _on_lobby_name_input_text_changed(new_text: String, input: LineEdit, player_id: String) -> void:
	if input.get_meta("normalizing", false):
		return
	MockServer.set_player_nickname(player_id, new_text)


func _commit_lobby_name_inputs() -> void:
	if not is_instance_valid(players_list):
		return
	for input in _find_line_edits(players_list):
		await _commit_text_input(input)


func _find_line_edits(node: Node) -> Array[LineEdit]:
	var inputs: Array[LineEdit] = []
	if node is LineEdit:
		inputs.append(node as LineEdit)
	for child in node.get_children():
		inputs.append_array(_find_line_edits(child))
	return inputs


func _on_start_game_button_pressed() -> void:
	await _commit_lobby_name_inputs()

	if not MockServer.can_start_game():
		_show_alert("1~%d명이면 테스트 게임을 시작할 수 있습니다." % MockServer.MVP_PLAYER_LIMIT)
		return
	# 실제 인게임 이동은 서버가 game:start를 승인해 phase가 countdown으로 바뀐 뒤
	# _on_game_state_changed_for_lobby()에서 반응적으로 일어난다(호스트/참가자 공통).
	MockServer.start_game()


func _on_leave_button_pressed() -> void:
	MockServer.leave_room()
	lobby_overlay.visible = false


func _show_alert(message: String) -> void:
	alert_message_label.text = message
	alert_overlay.visible = true


func _on_alert_ok_button_pressed() -> void:
	alert_overlay.visible = false

func get_selected_duck_skin() -> String:
	var skin_id: String = str(_selected_skin_by_role.get(InventoryRole.DUCK, "duck_default"))
	if skin_id == "duck_default":
		return "duck"
	return skin_id
