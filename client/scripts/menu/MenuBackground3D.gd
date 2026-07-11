extends Node3D

const DUCK_RADIUS := Vector2(22.0, 13.0)
const ALIGATOR_RADIUS := Vector2(28.0, 15.0)

@onready var duck: Node3D = $Duck
@onready var aligator: Node3D = $Aligator
@onready var camera: Camera3D = $Camera3D

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta

	var duck_angle: float = _time * 0.45
	var aligator_angle: float = _time * 0.28 + PI

	duck.position = Vector3(
		cos(duck_angle) * DUCK_RADIUS.x - 8.0,
		0.0,
		sin(duck_angle) * DUCK_RADIUS.y + 4.0
	)
	_face_path_direction(duck, duck_angle)

	aligator.position = Vector3(
		cos(aligator_angle) * ALIGATOR_RADIUS.x + 8.0,
		0.0,
		sin(aligator_angle) * ALIGATOR_RADIUS.y - 3.0
	)
	_face_path_direction(aligator, aligator_angle)

	camera.position = Vector3(
		sin(_time * 0.18) * 1.4,
		42.0 + sin(_time * 0.25) * 0.5,
		48.0 + cos(_time * 0.2) * 0.8
	)


func _face_path_direction(node: Node3D, angle: float) -> void:
	var direction: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)).normalized()
	node.rotation.y = atan2(-direction.x, -direction.z)
