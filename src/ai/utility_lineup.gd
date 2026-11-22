class_name UtilityLineup
extends RefCounted
## A grenade throw solved against the real map: the view angles and throw speed that make a
## grenade thrown from an eye position go off where it is wanted. Solving runs the same
## deterministic flight ([GrenadeFlight]) and detonation rule ([method ThrownGrenade.goes_off]) as
## a live grenade, from the same origin [WeaponController] throws from, so a solved line-up lands
## where it says, and one the geometry blocks is never found (no throwing through walls).

## Pitches tried on the coarse pass (degrees, up is positive), and the yaw offsets around the
## straight line to the target (bank throws round a corner).
const COARSE_PITCH: Vector3 = Vector3(-15.0, 70.0, 5.0)
const YAW_OFFSETS: Array[float] = [0.0, -6.0, 6.0]
const SPEEDS: Array[float] = [EquipmentCatalog.THROW_SPEED_FULL, EquipmentCatalog.THROW_SPEED_MEDIUM,
	EquipmentCatalog.THROW_SPEED_LOB]
## The fine pass searches this far (degrees) around the best coarse throw in these steps.
const FINE_SPAN: float = 4.0
const FINE_STEP: float = 1.0

var utility_id: StringName = &""
## View angles (degrees, as [method BotController.view_angles]) and throw speed (m/s).
var yaw: float = 0.0
var pitch: float = 0.0
var speed: float = 0.0
## Where the grenade goes off, how far that is from the target (metres) and after how long.
var burst: Vector3 = Vector3.ZERO
var error: float = INF
var seconds: float = 0.0


## The view direction for yaw/pitch in degrees (forward is −Z, as [method AimModel.angles_to]).
static func aim_direction(yaw_degrees: float, pitch_degrees: float) -> Vector3:
	var yaw_rad := deg_to_rad(yaw_degrees)
	var pitch_rad := deg_to_rad(pitch_degrees)
	return Vector3(-sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), -cos(yaw_rad) * cos(pitch_rad))


## Where and when a grenade of [param id] thrown from [param eye] along the angles at
## [param throw_speed] goes off: {position, time}.
static func simulate(space: PhysicsDirectSpaceState3D, id: StringName, eye: Vector3, yaw_degrees: float,
		pitch_degrees: float, throw_speed: float, exclude: Array[RID] = []) -> Dictionary:
	var aim := aim_direction(yaw_degrees, pitch_degrees)
	var origin := eye + aim * 0.25 + Vector3(0, -0.05, 0)
	var flight := GrenadeFlight.new(origin, GrenadeFlight.throw_velocity(aim, throw_speed, Vector3.ZERO), exclude)
	var params := EquipmentCatalog.params(id)
	var limit := maxf(float(params.get("max_fuse", 0.0)), float(params.get("fuse", 2.0))) + 0.1
	while not ThrownGrenade.goes_off(params, flight) and flight.time < limit:
		flight.step(space)
	return {"position": flight.position, "time": flight.time}


## How far a burst at [param at] is from [param target] for this kind of utility: smokes and
## fire must land on the right floor (height counts double); a flash only needs to be over the
## spot and not more than a metre below it (popping higher clears the wall it is thrown over).
static func miss_distance(id: StringName, at: Vector3, target: Vector3) -> float:
	var flat := Vector2(at.x - target.x, at.z - target.z).length()
	if EquipmentCatalog.utility_kind(id) == EquipmentCatalog.KIND_FLASH:
		return flat + maxf(target.y - at.y - 1.0, 0.0)
	return flat + absf(at.y - target.y) * 2.0


## The best throw of [param id] from [param eye] to go off within [param tolerance] metres of
## [param target], or null when the map allows none (a coarse search over speeds, pitches and
## small yaw offsets, then a finer one around the best).
static func solve(space: PhysicsDirectSpaceState3D, id: StringName, eye: Vector3, target: Vector3,
		tolerance: float, exclude: Array[RID] = []) -> UtilityLineup:
	var straight := AimModel.angles_to(eye, target).x
	var best := UtilityLineup.new()
	best.utility_id = id
	# Straight throws first; a bank or another speed is only searched while nothing is close yet
	# (each throw tried is a whole flight, so a good early answer saves most of the work).
	for offset: float in YAW_OFFSETS:
		for throw_speed: float in SPEEDS:
			var pitch_degrees := COARSE_PITCH.x
			while pitch_degrees <= COARSE_PITCH.y:
				_try(best, space, eye, target, straight + offset, pitch_degrees, throw_speed, exclude)
				pitch_degrees += COARSE_PITCH.z
			if best.error <= tolerance * 0.5:
				break
		if best.error <= tolerance * 0.5:
			break
	if best.error == INF:
		return null
	var centre := Vector2(best.yaw, best.pitch)
	var yaw_step := -FINE_SPAN
	while yaw_step <= FINE_SPAN:
		var pitch_step := -FINE_SPAN
		while pitch_step <= FINE_SPAN:
			_try(best, space, eye, target, centre.x + yaw_step, centre.y + pitch_step, best.speed, exclude)
			pitch_step += FINE_STEP
		yaw_step += FINE_STEP * 2.0
	return best if best.error <= tolerance else null


static func _try(best: UtilityLineup, space: PhysicsDirectSpaceState3D, eye: Vector3, target: Vector3,
		yaw_degrees: float, pitch_degrees: float, throw_speed: float, exclude: Array[RID]) -> void:
	var clamped := clampf(pitch_degrees, -80.0, 80.0)
	var result := simulate(space, best.utility_id, eye, yaw_degrees, clamped, throw_speed, exclude)
	var at := result["position"] as Vector3
	var miss := miss_distance(best.utility_id, at, target)
	if miss < best.error:
		best.error = miss
		best.yaw = wrapf(yaw_degrees, -180.0, 180.0)
		best.pitch = clamped
		best.speed = throw_speed
		best.burst = at
		best.seconds = float(result["time"])
