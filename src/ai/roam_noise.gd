class_name RoamNoise
extends RefCounted
## A gunshot a roaming bot heard ([RoamPlanner]): where, how long ago and who fired.

var position: Vector3
var age: float = 0.0
var source_id: String = ""


func _init(at: Vector3 = Vector3.ZERO, source: String = "") -> void:
	position = at
	source_id = source
