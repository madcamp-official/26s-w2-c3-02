extends Node3D

const CAMERA_OFFSET := Vector3(0, 16, 14)

var _target: Node3D = null

func _ready() -> void:
	_target = get_tree().get_first_node_in_group("controllable_player")

func _process(_delta: float) -> void:
	if _target:
		$Camera3D.position = _target.position + CAMERA_OFFSET
