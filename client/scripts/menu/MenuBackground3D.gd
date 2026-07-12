extends Node3D

const DUCK_ROUTE_CENTER := Vector2(30.0, 4.0)
const DUCK_ROUTE_RADIUS := Vector2(12.0, 7.0)
const ALIGATOR_ROUTE_CENTER := Vector2(-20.0, 15.0)
const ALIGATOR_ROUTE_RADIUS := Vector2(38.0, 25.0)
const DUCK_WATER_BASE_Y := 0.622
const ALIGATOR_WATER_BASE_Y := -0.016
const WATER_BOB_SPEED := 1.6
const DUCK_BOB_HEIGHT := 0.3
const ALIGATOR_BOB_HEIGHT := 0.18
const DUCK_ROLL_DEGREES := 8.0
const ALIGATOR_ROLL_DEGREES := 5.0

@onready var duck: Node3D = $Duck
@onready var aligator: Node3D = $Aligator
@onready var duck_model: Node3D = $Duck/Model
@onready var aligator_model: Node3D = $Aligator/Model
@onready var camera: Camera3D = $Camera3D

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta

	var duck_angle: float = _time * 0.45
	var aligator_angle: float = _time * 0.28 + PI

	duck.position = Vector3(
		DUCK_ROUTE_CENTER.x + cos(duck_angle) * DUCK_ROUTE_RADIUS.x,
		0.0,
		DUCK_ROUTE_CENTER.y + sin(duck_angle) * DUCK_ROUTE_RADIUS.y
	)
	_face_path_direction(duck, duck_angle, DUCK_ROUTE_RADIUS)
	_apply_water_motion(duck_model, DUCK_WATER_BASE_Y, DUCK_BOB_HEIGHT, DUCK_ROLL_DEGREES, 0.0)

	aligator.position = Vector3(
		ALIGATOR_ROUTE_CENTER.x + cos(aligator_angle) * ALIGATOR_ROUTE_RADIUS.x,
		0.0,
		ALIGATOR_ROUTE_CENTER.y + sin(aligator_angle) * ALIGATOR_ROUTE_RADIUS.y
	)
	_face_path_direction(aligator, aligator_angle, ALIGATOR_ROUTE_RADIUS)
	_apply_water_motion(aligator_model, ALIGATOR_WATER_BASE_Y, ALIGATOR_BOB_HEIGHT, ALIGATOR_ROLL_DEGREES, PI * 0.35)

	camera.position = Vector3(
		6.0 + sin(_time * 0.18) * 1.2,
		40.0 + sin(_time * 0.25) * 0.45,
		45.0 + cos(_time * 0.2) * 0.75
	)


func _face_path_direction(node: Node3D, angle: float, radius: Vector2) -> void:
	var direction: Vector3 = Vector3(-sin(angle) * radius.x, 0.0, cos(angle) * radius.y).normalized()
	node.rotation.y = atan2(-direction.x, -direction.z)


func _apply_water_motion(model: Node3D, base_y: float, bob_height: float, roll_degrees: float, phase_offset: float) -> void:
	var motion_time := _time * WATER_BOB_SPEED + phase_offset
	model.position.y = base_y + sin(motion_time) * bob_height
	model.rotation.z = sin(motion_time + PI * 0.25) * deg_to_rad(roll_degrees)
