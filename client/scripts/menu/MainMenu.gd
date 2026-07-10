extends Control

@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_room_button: Button = %JoinRoomButton

var _normalizing_room_code := false

func _ready() -> void:
	room_code_input.text_changed.connect(_on_room_code_input_text_changed)
	_on_room_code_input_text_changed(room_code_input.text)

func _on_create_room_button_pressed() -> void:
	MockServer.create_room(nickname_input.text)
	SceneRouter.go_to("lobby")

func _on_join_room_button_pressed() -> void:
	MockServer.join_room(nickname_input.text, room_code_input.text)
	SceneRouter.go_to("lobby")

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
