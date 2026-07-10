extends Node

const SCENES := {
	"main_menu": ["res://scenes/menu/MainMenu.tscn"],
	"lobby": ["res://scenes/menu/Lobby.tscn"],
	"game": ["res://scenes/world/Game.tscn", "res://scenes/hud/GameHUD.tscn"],
	"result": ["res://scenes/menu/Result.tscn"],
}

var screen_root: Node = null
var _current_children: Array = []

func go_to(screen: String) -> void:
	for child in _current_children:
		child.queue_free()
	_current_children.clear()

	if screen == "game":
		MockServer.start_game()

	for path in SCENES.get(screen, []):
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("SceneRouter failed to load scene: %s" % path)
			continue
		var instance := packed.instantiate()
		screen_root.add_child(instance)
		_current_children.append(instance)
