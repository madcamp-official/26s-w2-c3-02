extends Node3D

@export var model_scene: PackedScene
@export var model_position: Vector3 = Vector3.ZERO
@export var model_rotation_degrees: Vector3 = Vector3(0, 180, 0)
@export var model_scale: Vector3 = Vector3.ONE
@export var rotation_speed: float = 0.35 # rad/sec, 천천히 회전

var _model: Node3D
var _time: float = 0.0


func _ready() -> void:
	if model_scene == null:
		return
	_model = model_scene.instantiate()
	add_child(_model)
	_model.position = model_position
	_model.rotation_degrees = model_rotation_degrees
	_model.scale = model_scale


func _process(delta: float) -> void:
	if _model == null:
		return
	_time += delta
	_model.rotation.y = deg_to_rad(model_rotation_degrees.y) + _time * rotation_speed
