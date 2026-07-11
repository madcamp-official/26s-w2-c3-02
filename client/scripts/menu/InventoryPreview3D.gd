extends Node3D

@onready var duck: Node3D = $Duck
@onready var aligator: Node3D = $Aligator

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	duck.rotation.y = _time * 0.6
	aligator.rotation.y = _time * 0.4 + PI
