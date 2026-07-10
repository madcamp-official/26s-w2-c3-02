extends Node

func _ready() -> void:
	SceneRouter.screen_root = $ScreenRoot
	SceneRouter.go_to("main_menu")
