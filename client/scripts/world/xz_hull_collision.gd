extends StaticBody3D

# 바위처럼 "위에 올라갈 수만 없으면 되는" 오브젝트용 콜리전 자동 생성기.
# Model 자식의 실제 메시를 XZ 평면에 투영한 컨벡스 헐을 밑면으로 하는, 위아래로
# 아주 긴 기둥 콜리전을 런타임에 만든다. Model을 나중에 옮기거나 새 바위를
# 추가해도 다시 실행하면 자동으로 맞는 콜리전이 생성된다.
const COLUMN_MARGIN := 50.0

func _ready() -> void:
	var model := get_node_or_null("Model")
	var collision := get_node_or_null("CollisionShape3D")
	if model == null or collision == null:
		return

	var points_2d := PackedVector2Array()
	var min_y := INF
	var max_y := -INF
	for mesh_inst in _find_mesh_instances(model):
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		var xform: Transform3D = model.transform * mesh_inst.transform
		for surf in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var world_v: Vector3 = xform * v
				points_2d.append(Vector2(world_v.x, world_v.z))
				min_y = min(min_y, world_v.y)
				max_y = max(max_y, world_v.y)

	if points_2d.is_empty():
		return

	var hull := Geometry2D.convex_hull(points_2d)
	var col_points := PackedVector3Array()
	var bottom := min_y - COLUMN_MARGIN
	var top := max_y + COLUMN_MARGIN
	for p in hull:
		col_points.append(Vector3(p.x, bottom, p.y))
		col_points.append(Vector3(p.x, top, p.y))

	var shape := ConvexPolygonShape3D.new()
	shape.points = col_points
	collision.shape = shape
	collision.transform = Transform3D.IDENTITY

func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _find_mesh_instances(c)
	return out
