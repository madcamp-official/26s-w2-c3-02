extends Node3D

# 임시 진단용: player.gd가 shark 캐릭터를 구성할 때와 동일한 방식(model_pos/model_scale/
# model_rotation_degrees)으로 shark.glb를 인스턴스해서, 실제 메쉬의 월드 AABB를 측정한다.
# 이 AABB를 CHARACTER_CONFIG["shark"]의 collision_size/collision_pos 계산에 그대로 쓴다.

func _ready() -> void:
	var model_scene: PackedScene = load("res://assets/shark/shark.glb")
	var model: Node3D = model_scene.instantiate()
	model.position = Vector3(0, 1.684, 0)
	model.scale = Vector3.ONE * 1.8
	model.rotation_degrees = Vector3(0, 180, 0)
	add_child(model)

	await get_tree().process_frame

	var aabb: AABB
	var first := true
	for mesh in _find_meshes(model):
		var world_aabb: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			aabb = world_aabb
			first = false
		else:
			aabb = aabb.merge(world_aabb)

	print("combined world AABB position=", aabb.position, " size=", aabb.size)
	var center := aabb.position + aabb.size * 0.5
	print("suggested collision_size = Vector3(%.3f, %.3f, %.3f)" % [aabb.size.x, aabb.size.y, aabb.size.z])
	print("suggested collision_pos  = Vector3(%.3f, %.3f, %.3f)" % [center.x, center.y, center.z])

	get_tree().quit(0)

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _find_meshes(c)
	return out
