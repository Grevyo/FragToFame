class_name WeaponState
extends RefCounted
## Runtime state of one carried weapon: ammo, fire cadence, reload, spread bloom and recoil.
##
## Pure logic with no nodes, so it is unit-testable and reusable by bots and (later) the match
## host. [method update] advances time and returns the aim offsets of the shots fired this step;
## turning offsets into rays and damage is the caller's job.

var definition: WeaponDefinition
var ammo: int = 0
var reserve: int = 0
## Accumulated recoil in degrees (x = yaw right, y = pitch up). Bullets follow it in full.
var recoil_offset: Vector2 = Vector2.ZERO
var bloom: float = 0.0
## Seconds left on the current reload, 0 when not reloading.
var reload_remaining: float = 0.0
## Set by [method update]: true on the step a reload started / finished.
var reload_started_this_step: bool = false
var reload_finished_this_step: bool = false
var shots_fired_total: int = 0

var _cooldown: float = 0.0
var _recoil_index: float = 0.0
var _since_last_shot: float = 1000.0
var _trigger_was_held: bool = false
var _reload_start_pending: bool = false


func _init(weapon: WeaponDefinition) -> void:
	definition = weapon
	refill()


func refill() -> void:
	ammo = definition.magazine_size
	reserve = definition.reserve_ammo
	reload_remaining = 0.0
	reset_recoil()


func reset_recoil() -> void:
	recoil_offset = Vector2.ZERO
	bloom = 0.0
	_recoil_index = 0.0
	_cooldown = 0.0


func is_reloading() -> bool:
	return reload_remaining > 0.0


func can_reload() -> bool:
	return not is_reloading() and ammo < definition.magazine_size and reserve > 0


func start_reload() -> bool:
	if not can_reload():
		return false
	reload_remaining = definition.reload_time
	_reload_start_pending = true
	return true


## Abandons a reload in progress (e.g. when switching weapons); no ammo is transferred.
func cancel_reload() -> void:
	reload_remaining = 0.0


## Reload progress 0..1 (1 when not reloading).
func reload_progress() -> float:
	if not is_reloading():
		return 1.0
	return 1.0 - reload_remaining / definition.reload_time


## Current spread cone half-angle in degrees for the given movement state.
func current_spread(motion: ShooterMotion) -> float:
	var spread := definition.base_spread + bloom + definition.run_spread * motion.movement_factor()
	if motion.airborne:
		spread += definition.air_spread
	elif motion.crouched:
		spread *= definition.crouch_multiplier
	return spread


## Advances [param delta] seconds with the trigger held or not. Returns one aim offset (degrees,
## relative to where the shooter is looking) per shot fired during this step.
func update(delta: float, trigger: bool, motion: ShooterMotion, rng: RandomNumberGenerator) -> Array[Vector2]:
	reload_finished_this_step = false
	# A reload requested between steps is reported on the next step.
	reload_started_this_step = _reload_start_pending
	_reload_start_pending = false
	var shots: Array[Vector2] = []
	_advance_reload(delta)
	_cooldown -= delta
	var pressed_now := trigger and not _trigger_was_held
	if trigger and not is_reloading():
		if ammo <= 0:
			if pressed_now and start_reload():
				_reload_start_pending = false
				reload_started_this_step = true
		elif definition.is_automatic() or pressed_now:
			while _cooldown <= 0.0 and ammo > 0:
				shots.append(_fire_one(motion, rng))
				_cooldown += definition.fire_interval
				if not definition.is_automatic():
					break
	if _cooldown < 0.0 and (not trigger or ammo <= 0 or is_reloading()):
		_cooldown = 0.0
	_trigger_was_held = trigger
	_recover(delta)
	return shots


func _advance_reload(delta: float) -> void:
	if not is_reloading():
		return
	reload_remaining -= delta
	if reload_remaining <= 0.0:
		reload_remaining = 0.0
		var needed := definition.magazine_size - ammo
		var moved := mini(needed, reserve)
		ammo += moved
		reserve -= moved
		reload_finished_this_step = true
		reset_recoil()


func _fire_one(motion: ShooterMotion, rng: RandomNumberGenerator) -> Vector2:
	var spread := current_spread(motion)
	# Uniform radius (not uniform area) concentrates hits near the centre of the cone.
	var radius := spread * rng.randf()
	var angle := rng.randf() * TAU
	var offset := recoil_offset + Vector2(cos(angle), sin(angle)) * radius
	recoil_offset += definition.recoil_kick(int(_recoil_index))
	_recoil_index += 1.0
	bloom = minf(bloom + definition.bloom_per_shot, definition.bloom_max)
	ammo -= 1
	shots_fired_total += 1
	_since_last_shot = 0.0
	return offset


func _recover(delta: float) -> void:
	_since_last_shot += delta
	# Bloom and recoil both hold during sustained fire and recover after a short pause.
	if _since_last_shot < definition.recovery_delay:
		return
	bloom = maxf(bloom - definition.bloom_recovery * delta, 0.0)
	var before := recoil_offset.length()
	if before <= 0.0:
		_recoil_index = 0.0
		return
	recoil_offset = recoil_offset.move_toward(Vector2.ZERO, definition.recovery_rate * delta)
	# Walk back along the pattern in proportion, so a short pause resumes mid-pattern.
	_recoil_index *= recoil_offset.length() / before
