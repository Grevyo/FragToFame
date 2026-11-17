class_name RoamPoint
extends RefCounted
## A place worth visiting while roaming ([RoamPlanner]); [member kind] sets its interest.

var position: Vector3
var kind: StringName


func _init(at: Vector3 = Vector3.ZERO, point_kind: StringName = &"wander") -> void:
	position = at
	kind = point_kind
