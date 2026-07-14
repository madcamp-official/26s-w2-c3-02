extends Node3D

# The jail island is a single irregular glb mesh. A box collider doesn't match its
# rounded shoreline, so ducks appear to float or hit invisible walls near the edge.
# Instead we bake a trimesh (concave) collider straight from the mesh geometry, so
# collision follows the actual island surface and shoreline.

# 새끼오리(duckling.gd)의 "밟고 선 지면 높이" 레이캐스트가 이 비트만 감지하도록, 기본
# 충돌 레이어(플레이어도 포함됨)와 별개로 3번 레이어에도 이 콜리전을 소속시킨다.
# 이게 없으면 레이가 지형과 플레이어 캐릭터를 구분 못 해서, 새끼오리가 옆에 있는
# 오리를 "땅"으로 오인해 그 위로 올라타는 문제가 생긴다.
const GROUND_QUERY_LAYER_BIT := 4 # layer 3 (1 << (3 - 1))

func _ready() -> void:
	# Single source of truth for the jail location: the HUD direction indicator finds
	# this node via the "jail" group instead of hardcoding a position.
	add_to_group("jail")
	for mesh in _find_meshes(self):
		mesh.create_trimesh_collision()
		for child in mesh.get_children():
			if child is StaticBody3D:
				child.collision_layer |= GROUND_QUERY_LAYER_BIT

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out += _find_meshes(child)
	return out
