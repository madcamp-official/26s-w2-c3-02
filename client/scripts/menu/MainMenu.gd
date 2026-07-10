extends Control

@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput

func _on_create_room_button_pressed() -> void:
	MockServer.create_room(nickname_input.text)
	SceneRouter.go_to("lobby")

func _on_join_room_button_pressed() -> void:
	MockServer.join_room(nickname_input.text, room_code_input.text)
	SceneRouter.go_to("lobby")
