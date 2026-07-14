extends Node

const SCENES := {
	"main_menu": ["res://scenes/menu/MainMenu.tscn"],
	"lobby": ["res://scenes/menu/Lobby.tscn"],
	"game": ["res://scenes/world/Game.tscn", "res://scenes/hud/GameHUD.tscn"],
	"result": ["res://scenes/menu/Result.tscn"],
}

var screen_root: Node = null
var _current_children: Array = []
var _overlay_children: Array = []

func go_to(screen: String) -> void:
	if screen == "game":
		AudioManager.play_game_bgm()
	else:
		AudioManager.play_lobby_bgm()

	_clear_overlays()

	for child in _current_children:
		child.queue_free()
	_current_children.clear()

	for path in SCENES.get(screen, []):
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("SceneRouter failed to load scene: %s" % path)
			continue
		var instance := packed.instantiate()
		screen_root.add_child(instance)
		_current_children.append(instance)

func show_overlay(screen: String) -> void:
	_clear_overlays()

	for path in SCENES.get(screen, []):
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("SceneRouter failed to load overlay scene: %s" % path)
			continue
		var instance := packed.instantiate()
		screen_root.add_child(instance)
		_overlay_children.append(instance)

func _clear_overlays() -> void:
	for child in _overlay_children:
		child.queue_free()
	_overlay_children.clear()

# go_to()가 change_scene_to_*를 쓰지 않고 screen_root 아래에 씬을 직접 붙였다 뗐다 하는
# 방식이라, get_tree().current_scene은 항상 Boot 씬을 가리키고 실제 활성 화면(Game.tscn
# 등)에는 절대 도달하지 않는다. 다른 노드가 "지금 떠 있는 화면 중 특정 메서드를 가진
# 노드"를 찾아야 할 때(예: 새끼오리가 game.gd의 get_player_node를 호출해야 함) 이 함수를
# 쓴다.
func find_current_child_with_method(method_name: String) -> Node:
	for child in _current_children:
		if is_instance_valid(child) and child.has_method(method_name):
			return child
	return null
