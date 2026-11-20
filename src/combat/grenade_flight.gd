class_name GrenadeFlight
extends RefCounted
## Flight of a thrown grenade: gravity, bounces off walls, floors and bodies, sliding to rest.
##
## Deterministic: it always advances in fixed [constant STEP] increments whatever the frame rate,
## so the same throw from the same spot always lands in the same place. Lineups, the trajectory
## preview and (later) bots and the Tactical Play Creator rely on that.

const STEP: float = 1.0 / 64.0
const GRAVITY: float = 11.0
const RADIUS: float = 0.06
## Share of the speed into a surface that survives a bounce, and of the speed along it.
const RESTITUTION: float = 0.42
const FRICTION: float = 0.72
## Contacts slower than this (m/s into the surface) roll rather than bounce, losing
## [constant ROLL_FRICTION] of their speed per fixed step.
const ROLL_INTO_SPEED: float = 1.2
const ROLL_FRICTION: float = 0.9
## Below this speed on a floor the grenade stops.
const REST_SPEED: float = 0.6
## Surfaces whose normal points at least this far up count as floor.
const FLOOR_NORMAL_Y: float = 0.7
const MASK: int = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS

var position: Vector3
var velocity: Vector3
## Seconds since the throw.
var time: float = 0.0
var resting: bool = false
var bounces: int = 0
## Set on a step in which the grenade touched a floor; [member floor_touches] counts them all
## (impact detonation checks it after each advance).
var touched_floor: bool = false
var floor_touches: int = 0
var last_normal: Vector3 = Vector3.ZERO
var exclude: Array[RID] = []

var _accumulator: float = 0.0


func _init(start: Vector3, start_velocity: Vector3, excluded: Array[RID] = []) -> void:
	position = start
	velocity = start_velocity
	exclude = excluded


## Initial velocity of a throw along [param aim] (unit vector) at [param speed], lifted a little
## above the crosshair, plus the share of the thrower's own [param carrier_velocity].
static func throw_velocity(aim: Vector3, speed: float, carrier_velocity: Vector3) -> Vector3:
	var flat := Vector3(aim.x, 0.0, aim.z)
	var axis := flat.cross(Vector3.UP).normalized() if flat.length_squared() > 0.0001 else Vector3.RIGHT
	var lifted := aim.rotated(axis, deg_to_rad(EquipmentCatalog.THROW_LIFT_DEGREES))
	return lifted.normalized() * speed + carrier_velocity * EquipmentCatalog.THROW_INHERIT


## Advances by [param delta] seconds of real time (whole fixed steps only). Returns the number
## of fixed steps taken.
func advance(space: PhysicsDirectSpaceState3D, delta: float) -> int:
	_accumulator += delta
	var steps := 0
	while _accumulator >= STEP:
		_accumulator -= STEP
		step(space)
		steps += 1
	return steps


## One fixed step.
func step(space: PhysicsDirectSpaceState3D) -> void:
	time += STEP
	touched_floor = false
	if resting:
		return
	velocity.y -= GRAVITY * STEP
	var motion := velocity * STEP
	var length := motion.length()
	if length <= 0.000001:
		return
	var direction := motion / length
	var query := PhysicsRayQueryParameters3D.create(position, position + direction * (length + RADIUS), MASK, exclude)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		position += motion
		return
	var normal: Vector3 = hit["normal"]
	position = (hit["position"] as Vector3) + normal * RADIUS
	_bounce(normal)


func _bounce(normal: Vector3) -> void:
	bounces += 1
	last_normal = normal
	var into := velocity.dot(normal)
	var along := velocity - normal * into
	if absf(into) < ROLL_INTO_SPEED:
		# Resting contact: roll along the surface instead of bouncing in place.
		velocity = along * ROLL_FRICTION
	else:
		velocity = along * FRICTION - normal * into * RESTITUTION
	if normal.y >= FLOOR_NORMAL_Y:
		touched_floor = true
		floor_touches += 1
		if velocity.length() < REST_SPEED:
			velocity = Vector3.ZERO
			resting = true


## The path a throw would take for up to [param seconds] (one point per fixed step), for the
## trajectory preview and lineup tools. Stops early once the grenade rests.
static func predict(space: PhysicsDirectSpaceState3D, start: Vector3, start_velocity: Vector3,
		seconds: float, excluded: Array[RID] = []) -> PackedVector3Array:
	var flight := GrenadeFlight.new(start, start_velocity, excluded)
	var points := PackedVector3Array([start])
	while flight.time < seconds and not flight.resting:
		flight.step(space)
		points.append(flight.position)
	return points
