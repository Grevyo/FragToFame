class_name ThrownGrenade
extends Node3D
## A grenade in flight. [UtilityField] advances it and decides when it goes off; this node only
## carries the flight state, who threw it and its model.

var utility_id: StringName = &""
var thrower_id: String = ""
var team: StringName = &""
var flight: GrenadeFlight
var params: Dictionary = {}
var model: Node3D = null

var _spin_axis: Vector3 = Vector3.RIGHT


func setup(id: StringName, start: Vector3, start_velocity: Vector3, thrower: String, team_key: StringName,
		exclude: Array[RID], model_node: Node3D) -> void:
	utility_id = id
	thrower_id = thrower
	team = team_key
	params = EquipmentCatalog.params(id)
	flight = GrenadeFlight.new(start, start_velocity, exclude)
	name = "Grenade_%s" % String(id)
	if model_node != null:
		model = model_node
		add_child(model)
		model.position = Vector3(0, -0.05, 0)
	var flat := Vector3(start_velocity.x, 0.0, start_velocity.z)
	if flat.length_squared() > 0.01:
		_spin_axis = flat.normalized().cross(Vector3.UP).normalized()


## Moves the node to the flight position and tumbles the model while it flies.
func sync(delta: float) -> void:
	global_position = flight.position
	if model != null and not flight.resting:
		model.rotate(_spin_axis, -delta * minf(flight.velocity.length(), 14.0) * 1.4)


## True once the grenade should go off (see "detonate" in [EquipmentCatalog]).
func should_detonate() -> bool:
	var fuse := float(params.get("fuse", 2.0))
	match str(params.get("detonate", "fuse")):
		"rest":
			return (flight.resting and flight.time >= fuse) or flight.time >= float(params.get("max_fuse", 6.0))
		"impact":
			return flight.floor_touches > 0 or flight.time >= fuse
		_:
			return flight.time >= fuse
