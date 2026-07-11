extends Node

func _ready() -> void:
	SceneRouter.screen_root = $ScreenRoot
	SceneRouter.go_to("game")
	for i in range(6):
		await get_tree().process_frame
	var island: Node3D = $ScreenRoot.get_node("Game/JailIsland")
	var aabb := AABB()
	var has := false
	for mi in _all_mesh(island):
		var b: AABB = mi.global_transform * mi.get_aabb()
		if not has:
			aabb = b; has = true
		else:
			aabb = aabb.merge(b)
	print("ISLAND world AABB: bottom_y=", aabb.position.y, " top_y=", aabb.position.y + aabb.size.y, " size=", aabb.size)
	get_tree().quit()

func _all_mesh(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _all_mesh(c)
	return out
