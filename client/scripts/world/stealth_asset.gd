extends Node3D

@export var custom_material: Material
@export var stealth_radius: float = 8.0

func _ready() -> void:
	add_to_group("stealth_cover")
	if custom_material != null:
		_apply_material(self)

func _apply_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = custom_material
	for child in node.get_children():
		_apply_material(child)
