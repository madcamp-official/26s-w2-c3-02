extends Control

@onready var menu_panel: PanelContainer = $"MarginContainer/CenterContainer/Panel"
@onready var lobby_panel: PanelContainer = %LobbyPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var settings_button: Button = %SettingsButton
@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton
@onready var room_code_label: Label = %RoomCodeLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var lobby_status_label: Label = %LobbyStatusLabel
@onready var add_mock_player_button: Button = %AddMockPlayerButton
@onready var start_game_button: Button = %StartGameButton
@onready var alert_overlay: Control = %AlertOverlay
@onready var alert_message_label: Label = %AlertMessageLabel

var _normalizing_room_code := false
var _settings_return_view := "menu"
var _settings_button_base_position: Vector2
var _settings_hover_tween: Tween = null


func _ready() -> void:
	GameData.room_state_changed.connect(_refresh_lobby)
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	settings_button.mouse_entered.connect(_on_settings_button_mouse_entered)
	settings_button.mouse_exited.connect(_on_settings_button_mouse_exited)
	_settings_button_base_position = settings_button.position
	_on_room_code_input_text_changed(room_code_input.text)

	if GameData.menu_entry_view == "lobby":
		GameData.menu_entry_view = "menu"
		_show_lobby()
	else:
		_show_menu()


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


func _room_code_digits(value: String) -> String:
	var code := ""
	for i in range(value.length()):
		var c := value.substr(i, 1)
		if c >= "0" and c <= "9":
			code += c
		if code.length() >= 4:
			break
	return code


func _show_menu() -> void:
	menu_panel.visible = true
	lobby_panel.visible = false
	settings_panel.visible = false
	alert_overlay.visible = false


func _show_lobby() -> void:
	menu_panel.visible = false
	lobby_panel.visible = true
	settings_panel.visible = false
	alert_overlay.visible = false
	_refresh_lobby()


func _show_settings() -> void:
	if lobby_panel.visible:
		_settings_return_view = "lobby"
	else:
		_settings_return_view = "menu"

	menu_panel.visible = false
	lobby_panel.visible = false
	settings_panel.visible = true
	alert_overlay.visible = false


func _restore_from_settings() -> void:
	if _settings_return_view == "lobby":
		_show_lobby()
	else:
		_show_menu()


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
	name_input.text = str(player.get("nickname", "Player"))
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.text_changed.connect(_on_lobby_player_name_changed.bind(player_id))
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


func _on_lobby_player_name_changed(new_text: String, player_id: String) -> void:
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
		_show_alert("경찰 1명, 오리 2명이 필요합니다.")
		return
	SceneRouter.go_to("game")


func _on_back_button_pressed() -> void:
	_show_menu()


func _show_alert(message: String) -> void:
	alert_message_label.text = message
	alert_overlay.visible = true


func _on_alert_ok_button_pressed() -> void:
	alert_overlay.visible = false


func _on_settings_button_pressed() -> void:
	if settings_panel.visible:
		_restore_from_settings()
	else:
		_show_settings()


func _on_settings_button_mouse_entered() -> void:
	_animate_settings_button(_settings_button_base_position + Vector2(0.0, -6.0))


func _on_settings_button_mouse_exited() -> void:
	_animate_settings_button(_settings_button_base_position)


func _animate_settings_button(target_position: Vector2) -> void:
	if _settings_hover_tween != null and _settings_hover_tween.is_running():
		_settings_hover_tween.kill()

	_settings_hover_tween = create_tween()
	_settings_hover_tween.set_trans(Tween.TRANS_SINE)
	_settings_hover_tween.set_ease(Tween.EASE_OUT)
	_settings_hover_tween.tween_property(settings_button, "position", target_position, 0.12)
