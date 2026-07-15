extends Node3D

# 재측정: model_pos=(0,0,0)으로 인스턴스해서 shark.glb의 "로컬 원점 기준" AABB를 구한다.
# 다른 모든 캐릭터(duck/nupjuk/greenduck/aligator)는 전부 collision_pos.y - collision_size.y/2
# == 0 이 되도록(콜리전 박스 바닥이 캐릭터 원점 y=0, 즉 "서 있는 발 높이"에 정확히 닿도록)
# 맞춰져 있는데, 지난번 측정은 이 불변식을 어겼다(바닥이 원점보다 0.2265 위에 떠 있었음) —
# is_on_floor()가 제대로 안 잡혀서 중력에 계속 끌리다 지형에 끼는 것처럼 보였을 가능성이 높다.
func _ready() -> void:
	var model_scene: PackedScene = load("res://assets/shark/shark.glb")
	var model: Node3D = model_scene.instantiate()
	model.position = Vector3.ZERO
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

	print("local-origin AABB position=", aabb.position, " size=", aabb.size)
	var bottom_y: float = aabb.position.y
	var center_x: float = aabb.position.x + aabb.size.x * 0.5
	var center_z: float = aabb.position.z + aabb.size.z * 0.5

	# 모델을 위로 -bottom_y만큼 옮기면(=model_pos.y = -bottom_y) 발이 정확히 y=0에 닿는다.
	var suggested_model_pos_y := -bottom_y
	var collision_center_y := aabb.size.y * 0.5 # 바닥이 0이 되므로 중심은 높이의 절반
	print("suggested model_pos.y = %.3f" % suggested_model_pos_y)
	print("suggested collision_size = Vector3(%.3f, %.3f, %.3f)" % [aabb.size.x, aabb.size.y, aabb.size.z])
	print("suggested collision_pos  = Vector3(%.3f, %.3f, %.3f)" % [center_x, collision_center_y, center_z])
	print("check: collision bottom = %.4f (should be ~0)" % (collision_center_y - aabb.size.y * 0.5))

	get_tree().quit(0)

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _find_meshes(c)
	return out
