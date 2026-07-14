extends Control

@onready var title_label: Label = $MarginContainer/CenterContainer/Panel/Content/TitleLabel
@onready var winner_label: Label = %WinnerLabel
@onready var reason_label: Label = %ReasonLabel
@onready var summary_label: Label = %SummaryLabel
@onready var players_title_label: Label = $MarginContainer/CenterContainer/Panel/Content/PlayersTitleLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var main_menu_button: Button = $MarginContainer/CenterContainer/Panel/Content/Buttons/MainMenuButton
@onready var lobby_button: Button = $MarginContainer/CenterContainer/Panel/Content/Buttons/LobbyButton


func _ready() -> void:
	_apply_static_text()
	_apply_button_styles()
	_refresh()


func _apply_static_text() -> void:
	title_label.text = "결과"
	players_title_label.text = "플레이어"
	main_menu_button.text = "메인으로"
	lobby_button.text = "대기실로"


func _refresh() -> void:
	winner_label.text = _winner_text()
	reason_label.text = _reason_text()
	summary_label.text = "최종 새끼오리 %d / %d" % [GameData.score, GameData.target_score]
	_refresh_players()


func _refresh_players() -> void:
	for child in players_list.get_children():
		players_list.remove_child(child)
		child.queue_free()

	for player in GameData.players:
		players_list.add_child(_make_player_row(player))


func _make_player_row(player: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 18)

	var role_label := _make_row_label(_role_label(str(player.get("team", ""))), 76, HORIZONTAL_ALIGNMENT_LEFT)
	var name_label := _make_row_label(str(player.get("nickname", "Player")), 0, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count_label := _make_row_label(_duckling_count_text(player), 230, HORIZONTAL_ALIGNMENT_RIGHT)

	row.add_child(role_label)
	row.add_child(name_label)
	row.add_child(count_label)
	return row


func _make_row_label(text: String, min_width: float, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


func _winner_text() -> String:
	if GameData.winner == "duck":
		return "오리 팀 승리!"
	if GameData.winner == "tagger":
		return "경찰 팀 승리!"
	return "게임 종료"


func _reason_text() -> String:
	match str(GameData.end_reason):
		"duck_goal":
			return "오리 팀이 새끼오리를 목표 수만큼 모았습니다."
		"time_up":
			return "제한 시간이 끝났습니다."
		"all_ducks_jailed":
			return "모든 오리가 감옥에 갇혔습니다."
		"debug_force_end":
			return "테스트 종료 버튼으로 게임을 종료했습니다."
	return "게임이 종료되었습니다."


func _role_label(team: String) -> String:
	match team:
		"duck":
			return "오리"
		"tagger":
			return "경찰"
	return "미정"


func _duckling_count_text(player: Dictionary) -> String:
	if str(player.get("team", "")) != "duck":
		return "-"
	return "모은 새끼오리 수: %d마리" % int(player.get("deliveredDucklings", 0))


func _apply_button_styles() -> void:
	_apply_button_style(main_menu_button, Color(0.45098, 0.670588, 0.164706), Color(0.537255, 0.760784, 0.223529), Color(0.129412, 0.207843, 0.0784314))
	_apply_button_style(lobby_button, Color(0.129412, 0.45098, 0.780392), Color(0.192157, 0.54902, 0.894118), Color(0.0196078, 0.0862745, 0.188235))


func _apply_button_style(button: Button, normal_color: Color, hover_color: Color, outline_color: Color) -> void:
	button.add_theme_stylebox_override("normal", _make_button_box(normal_color, outline_color))
	button.add_theme_stylebox_override("hover", _make_button_box(hover_color, outline_color))
	button.add_theme_stylebox_override("pressed", _make_button_box(Color(0.0862745, 0.223529, 0.360784), outline_color))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0.0156863, 0.0392157, 0.0784314))
	button.add_theme_color_override("font_shadow_color", Color(0.0156863, 0.0392157, 0.0784314, 0.75))
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_constant_override("shadow_offset_x", 0)
	button.add_theme_constant_override("shadow_offset_y", 2)


func _make_button_box(color: Color, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_width_left = 3
	box.border_width_top = 3
	box.border_width_right = 3
	box.border_width_bottom = 6
	box.border_color = border_color
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_right = 8
	box.corner_radius_bottom_left = 8
	return box


func _on_main_menu_button_pressed() -> void:
	MockServer.leave_room()
	GameData.menu_entry_view = "menu"
	SceneRouter.go_to("main_menu")


func _on_lobby_button_pressed() -> void:
	MockServer.return_to_lobby()
	SceneRouter.go_to("main_menu")
