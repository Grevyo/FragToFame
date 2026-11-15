class_name PlayerMovement
extends RefCounted
## Shared movement model: ground friction and directional acceleration, air control,
## jump and the short "stamina" slowdown after jumping and landing. Pure maths (no Nodes);
## [CombatantMovementBody] applies it for both human and AI combatants.
##
## Reference: measured from a stock install of the reference game (offline local server,
## competitive mode, 64 tick, default movement cvars) with the tick logger in
## tools/movement_reference/. Reference figures are in game units (u); this project converts
## them with one factor, [constant METRES_PER_UNIT] (1 u = 1 inch), which maps the reference
## 72 u player / 64 u eye height onto our 1.8 m / 1.62 m player.
##
## Each value is tagged [measured] (fitted to the logs, reproduces them to < 0.01 u/s per tick
## at 64 Hz) or [estimate] (not measured; see the comment).

## The single conversion between reference units and Godot metres.
const METRES_PER_UNIT: float = 0.0254

## [measured] Unencumbered run speed: 250 u/s (reference with the melee weapon out). The weapon in
## hand scales it through [member WeaponDefinition.mobility] (rifle 0.86 = the measured 215 u/s);
## acceleration scales with the result, as recorded for both 250 and 215 u/s.
var run_speed: float = 250.0 * METRES_PER_UNIT
## [measured] Shift-walk speed as a fraction of the run speed (130 / 250).
var walk_factor: float = 0.52
## [measured] Fully crouched speed as a fraction of the run speed (85 / 250).
var crouch_factor: float = 0.34
## [measured] Ground acceleration rate (1/s): each second adds this many times the current
## maximum speed along the wish direction, never past that maximum.
var ground_accelerate: float = 5.5
## [measured] Ground friction rate (1/s): speed lost per second as a fraction of speed.
var friction: float = 5.2
## [measured] Below this speed (80 u/s) friction acts as if moving at it, giving the linear
## final stop instead of an endless exponential tail.
var stop_speed: float = 80.0 * METRES_PER_UNIT
## [measured] Air acceleration rate (1/s), same form as the ground rate.
var air_accelerate: float = 12.0
## [measured] In the air the wish speed is capped to this (30 u/s): air input can only add
## velocity along the wish direction until the projection reaches the cap, which is what keeps
## take-off momentum and makes air strafing depend on turning.
var air_wish_speed: float = 30.0 * METRES_PER_UNIT
## [measured] Gravity while airborne: 800 u/s^2 (the project default gravity is not used).
var gravity: float = 800.0 * METRES_PER_UNIT
## [measured] Peak height of a standing jump: 54.65 u, giving 0.739 s of hang time.
var jump_height: float = 54.65 * METRES_PER_UNIT

## [measured] Stamina added per m/s of jump velocity (0.08 per u/s; 23.66 for a fresh jump).
var stamina_jump_cost: float = 0.08 / METRES_PER_UNIT
## [measured up to 300 u/s impacts; extrapolated above] Stamina added per m/s of landing speed
## (0.05 per u/s; 13.96 landing from a standing-height jump).
var stamina_land_cost: float = 0.05 / METRES_PER_UNIT
## [measured] Stamina recovered per second.
var stamina_recovery: float = 60.0
## [estimate] Upper bound on stamina (stock setting; never reached in the measured runs).
var stamina_max: float = 80.0

## [measured] Seconds to crouch fully on the ground (13 ticks at 64 Hz); the eye follows a
## smoothstep of this progress and the speed limit falls linearly with it.
var crouch_time: float = 13.0 / 64.0
## [measured] Seconds to stand back up (10 ticks at 64 Hz); speed stays at crouch speed until
## fully upright.
var stand_time: float = 10.0 / 64.0
## [measured: 9 of 18 u] Share of the height lost by crouching in the air that is taken from
## the feet (legs tuck up), which is what lets a crouch-jump clear taller ledges. Crouching in
## the air is immediate [measured]; standing up in the air uses [member stand_time] [estimate].
var air_crouch_feet_share: float = 0.5

## 0 = fresh. While above zero it lowers the ground speed cap, air acceleration and the next
## jump (see [method speed_scale] and [method jump]).
var stamina: float = 0.0


## Converts reference units (or u/s, u/s^2) to metres.
static func from_units(units: float) -> float:
	return units * METRES_PER_UNIT


## Converts metres (or m/s) to reference units, for HUD/debug read-outs.
static func to_units(metres: float) -> float:
	return metres / METRES_PER_UNIT


## Clears transient state (respawn).
func reset() -> void:
	stamina = 0.0


## Maximum ground speed for the stance. [param crouch_speed_blend] is 0 standing .. 1 at full
## crouch speed, [param mobility] the held weapon's share of the run speed.
## [estimate] crouch + walk uses the slower of the two.
func max_speed(walking: bool, crouch_speed_blend: float, mobility: float = 1.0) -> float:
	var factor := lerpf(1.0, crouch_factor, clampf(crouch_speed_blend, 0.0, 1.0))
	if walking:
		factor = minf(factor, walk_factor)
	return run_speed * mobility * factor


## [measured] Fraction of the maximum speed available at the current stamina: (1 - s/100)^2.
func speed_scale() -> float:
	var remaining := 1.0 - stamina / 100.0
	return remaining * remaining


## Take-off speed of a fresh jump (m/s).
func jump_speed() -> float:
	return sqrt(2.0 * gravity * jump_height)


## Recovers stamina; call once per physics tick before stepping.
func recover(delta: float) -> void:
	stamina = maxf(stamina - stamina_recovery * delta, 0.0)


## One grounded tick: friction, then acceleration along [param wish_dir] (unit length or zero)
## limited by the velocity already projected onto it, then the stamina speed cap.
func ground_step(velocity: Vector2, wish_dir: Vector2, speed_limit: float, delta: float) -> Vector2:
	var result := apply_friction(velocity, delta)
	result = accelerate(result, wish_dir, speed_limit, ground_accelerate * speed_limit * delta)
	return cap_ground_speed(result, speed_limit)


## One airborne tick: no friction; acceleration only towards the small air wish speed.
func air_step(velocity: Vector2, wish_dir: Vector2, speed_limit: float, delta: float) -> Vector2:
	var scaled := speed_limit * speed_scale()
	return accelerate(velocity, wish_dir, minf(scaled, air_wish_speed), air_accelerate * scaled * delta)


func apply_friction(velocity: Vector2, delta: float) -> Vector2:
	var speed := velocity.length()
	if speed < 0.0001:
		return Vector2.ZERO
	var drop := maxf(speed, stop_speed) * friction * delta
	return velocity * (maxf(speed - drop, 0.0) / speed)


## Adds up to [param amount] of speed along [param wish_dir], but only until the velocity
## projected onto that direction reaches [param wish_speed]. Opposing input therefore brakes at
## the full rate (the counter-strafe) and diagonal input gains nothing over a single key.
func accelerate(velocity: Vector2, wish_dir: Vector2, wish_speed: float, amount: float) -> Vector2:
	if wish_dir == Vector2.ZERO:
		return velocity
	var room := wish_speed - velocity.dot(wish_dir)
	if room <= 0.0:
		return velocity
	return velocity + wish_dir * minf(amount, room)


## [measured for landings; estimate for walk/crouch changes] Hard cap on grounded speed.
func cap_ground_speed(velocity: Vector2, speed_limit: float) -> Vector2:
	return velocity.limit_length(speed_limit * speed_scale())


## Starts a jump: returns the vertical take-off speed (lower while stamina is spent, which is
## why chained jumps are lower) and charges the jump's stamina cost.
func jump() -> float:
	var speed := jump_speed() * (1.0 - stamina / 100.0)
	stamina = minf(stamina + stamina_jump_cost * speed, stamina_max)
	return speed


## Charges the landing stamina cost for hitting the ground at [param impact_speed] (m/s, >= 0).
func land(impact_speed: float) -> void:
	stamina = minf(stamina + stamina_land_cost * impact_speed, stamina_max)
