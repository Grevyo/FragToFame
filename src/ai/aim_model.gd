class_name AimModel
extends RefCounted
## Human-like aiming as pure maths: a bot's view (yaw/pitch in degrees) chases the target
## direction with a capped turn speed and proportional lag, plus an acquisition error that decays
## while it stays on target. No nodes, so it is unit-testable and deterministic.

var skill: BotSkill
## Current aim error offset in degrees (x = yaw, y = pitch).
var error: Vector2 = Vector2.ZERO


func _init(bot_skill: BotSkill) -> void:
	skill = bot_skill


## Starts tracking a new target: rolls an error that grows with how far off the view was.
func acquire(angle_off_degrees: float, rng: RandomNumberGenerator) -> void:
	var magnitude := skill.initial_error * (1.0 + clampf(angle_off_degrees, 0.0, 180.0) / 45.0)
	var angle := rng.randf() * TAU
	error = Vector2(cos(angle), sin(angle)) * magnitude * rng.randf_range(0.6, 1.0)


## Returns the new view angles (Vector2 yaw, pitch in degrees) after [param delta] seconds,
## turning from [param current] toward [param desired] (+ the decaying error).
func step(current: Vector2, desired: Vector2, delta: float) -> Vector2:
	error *= exp(-skill.error_decay * delta)
	var target := desired + error
	var diff := Vector2(wrapf(target.x - current.x, -180.0, 180.0), target.y - current.y)
	var wanted := diff * minf(skill.aim_gain * delta, 1.0)
	var max_step := skill.turn_speed * delta
	if wanted.length() > max_step:
		wanted = wanted.normalized() * max_step
	return current + wanted


## Yaw/pitch (degrees) that look from [param from] toward [param to] (forward = -Z).
static func angles_to(from: Vector3, to: Vector3) -> Vector2:
	var d := to - from
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return Vector2(yaw, pitch)


## Angular distance in degrees between two yaw/pitch pairs.
static func angle_between(a: Vector2, b: Vector2) -> float:
	return Vector2(wrapf(a.x - b.x, -180.0, 180.0), a.y - b.y).length()
