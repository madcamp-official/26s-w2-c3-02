extends Node3D

const CHASE_ROUTE_CENTER := Vector2(30.0, 4.0)
const CHASE_ROUTE_SIZE := Vector2(18.0, 10.0)
const CHASE_FOLLOW_DELAY := 0.9
const CHASE_SPEED := 0.30
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

	var duck_angle: float = _time * CHASE_SPEED
	var aligator_angle: float = duck_angle - CHASE_FOLLOW_DELAY

	duck.position = _nest_orbit_position(duck_angle)
	_face_path_direction_from_velocity(duck, duck_angle)
	_apply_water_motion(duck_model, DUCK_WATER_BASE_Y, DUCK_BOB_HEIGHT, DUCK_ROLL_DEGREES, 0.0)

	aligator.position = _nest_orbit_position(aligator_angle)
	_face_path_direction_from_velocity(aligator, aligator_angle)
	_apply_water_motion(aligator_model, ALIGATOR_WATER_BASE_Y, ALIGATOR_BOB_HEIGHT, ALIGATOR_ROLL_DEGREES, PI * 0.35)

	camera.position = Vector3(
		6.0 + sin(_time * 0.18) * 1.2,
		40.0 + sin(_time * 0.25) * 0.45,
		45.0 + cos(_time * 0.2) * 0.75
	)


func _nest_orbit_position(angle: float) -> Vector3:
	return Vector3(
		CHASE_ROUTE_CENTER.x + cos(angle) * CHASE_ROUTE_SIZE.x,
		0.0,
		CHASE_ROUTE_CENTER.y + sin(angle) * CHASE_ROUTE_SIZE.y
	)


func _face_path_direction_from_velocity(node: Node3D, angle: float) -> void:
	var direction := Vector3(
		-sin(angle) * CHASE_ROUTE_SIZE.x,
		0.0,
		cos(angle) * CHASE_ROUTE_SIZE.y
	).normalized()
	node.rotation.y = atan2(-direction.x, -direction.z)


func _apply_water_motion(model: Node3D, base_y: float, bob_height: float, roll_degrees: float, phase_offset: float) -> void:
	var motion_time := _time * WATER_BOB_SPEED + phase_offset
	model.position.y = base_y + sin(motion_time) * bob_height
	model.rotation.z = sin(motion_time + PI * 0.25) * deg_to_rad(roll_degrees)
