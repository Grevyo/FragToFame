class_name Hitscan
extends RefCounted
## Instant-hit ray tracing for bullets, plus the physics layer conventions it relies on.
##
## Layers (also named in project.godot): 1 world geometry, 2 character bodies (movement only),
## 3 hitboxes (shots only). Shots query world + hitboxes; bodies are ignored so the hitboxes,
## not the movement capsule, decide what was hit.

const LAYER_WORLD: int = 1
const LAYER_CHARACTERS: int = 2
const LAYER_HITBOXES: int = 4
const SHOT_MASK: int = LAYER_WORLD | LAYER_HITBOXES


class Result extends RefCounted:
	var hit: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var distance: float = 0.0
	var collider: Object = null
	## The hitbox struck, or null if the ray hit world geometry / nothing.
	var hitbox: Hitbox = null


## Rotates the forward (-Z) direction of [param basis] by an aim offset in degrees
## (x = yaw right, y = pitch up).
static func offset_direction(basis: Basis, offset_degrees: Vector2) -> Vector3:
	var local := Basis(Vector3.UP, -deg_to_rad(offset_degrees.x)) * Basis(Vector3.RIGHT, deg_to_rad(offset_degrees.y))
	return (basis.orthonormalized() * local * Vector3.FORWARD).normalized()


static func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3,
		max_range: float, exclude: Array[RID] = []) -> Result:
	var result := Result.new()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * max_range, SHOT_MASK, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		result.position = origin + direction.normalized() * max_range
		result.distance = max_range
		return result
	result.hit = true
	result.position = hit["position"]
	result.normal = hit["normal"]
	result.distance = origin.distance_to(result.position)
	result.collider = hit["collider"]
	result.hitbox = result.collider as Hitbox
	return result
