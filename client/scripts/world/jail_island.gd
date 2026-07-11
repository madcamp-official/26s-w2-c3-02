extends Node3D

# The jail island is a single irregular glb mesh. A box collider doesn't match its
# rounded shoreline, so ducks appear to float or hit invisible walls near the edge.
# Instead we bake a trimesh (concave) collider straight from the mesh geometry, so
# collision follows the actual island surface and shoreline.

func _ready() -> void:
	# Single source of truth for the jail location: the HUD direction indicator finds
	# this node via the "jail" group instead of hardcoding a position.
	add_to_group("jail")
	for mesh in _find_meshes(self):
		mesh.create_trimesh_collision()

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out += _find_meshes(child)
	return out
