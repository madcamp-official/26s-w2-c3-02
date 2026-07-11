extends Control

@onready var menu_panel: PanelContainer = $"MarginContainer/CenterContainer/Panel"
@onready var lobby_panel: PanelContainer = %LobbyPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton
@onready var room_code_label: Label = %RoomCodeLabel
@onready var players_list: VBoxContainer = %PlayersList

var _normalizing_room_code := false
var _settings_return_view := "menu"

func _ready() -> void:
	GameData.room_state_changed.connect(_refresh_lobby)
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	_on_room_code_input_text_changed(room_code_input.text)
	_show_menu()

func _exit_tree() -> void:
	if GameData.room_state_changed.is_connected(_refresh_lobby):
		GameData.room_state_changed.disconnect(_refresh_lobby)

func _on_create_room_button_pressed() -> void:
	MockServer.create_room(nickname_input.text, room_code_input.text)
	_show_lobby()

func _on_join_room_button_pressed() -> void:
	MockServer.join_room(nickname_input.text, room_code_input.text)
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

func _show_lobby() -> void:
	menu_panel.visible = false
	lobby_panel.visible = true
	settings_panel.visible = false
	_refresh_lobby()

func _show_settings() -> void:
	if lobby_panel.visible:
		_settings_return_view = "lobby"
	else:
		_settings_return_view = "menu"

	menu_panel.visible = false
	lobby_panel.visible = false
	settings_panel.visible = true

func _restore_from_settings() -> void:
	if _settings_return_view == "lobby":
		_show_lobby()
	else:
		_show_menu()

func _refresh_lobby() -> void:
	if not is_instance_valid(room_code_label) or not is_instance_valid(players_list):
		return

	room_code_label.text = "방 코드: %s" % GameData.room_id

	for child in players_list.get_children():
		players_list.remove_child(child)
		child.queue_free()

	for player in GameData.players:
		var label: Label = Label.new()
		var nickname := str(player.get("nickname", player.get("playerId", "Unknown")))
		var team := _team_label(str(player.get("team", "")))
		label.text = "%s        %s" % [nickname, team]
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color.WHITE)
		players_list.add_child(label)

func _team_label(team: String) -> String:
	if team == "duck":
		return "오리 팀"
	if team == "tagger":
		return "술래 팀"
	return "팀 미정"

func _on_start_game_button_pressed() -> void:
	SceneRouter.go_to("game")

func _on_back_button_pressed() -> void:
	_show_menu()

func _on_settings_button_pressed() -> void:
	if settings_panel.visible:
		_restore_from_settings()
	else:
		_show_settings()
