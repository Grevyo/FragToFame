class_name CombatantMovementBody
extends CharacterBody3D
## Applies the same [PlayerMovement] physics, stance and weapon mobility to humans and bots.
## Controllers supply world-space intent and own their input, health and decisions.

const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.2
const STAND_EYE: float = 1.62
const CROUCH_EYE: float = 1.04

## Distance the body is pulled back onto the floor when walking down ramps and stairs, so
## slopes never make the player briefly "airborne" (which would cost accuracy and control).
const FLOOR_SNAP: float = 0.3

const BODY_RADIUS: float = 0.35

## 0 = standing, 1 = fully crouched (linear progress; the eye height eases along it).
var crouch_amount: float = 0.0
var wants_crouch: bool = false
## Each body owns its stamina and uses the same movement defaults.
var movement: PlayerMovement = PlayerMovement.new()

var collision: CollisionShape3D
var head: Node3D
var weapons: WeaponController
var hitboxes: Array[Hitbox] = []

var _walking: bool = false
var _airborne: bool = false
## Vertical speed at the end of the last airborne tick (the landing impact speed).
var _fall_speed: float = 0.0
var _capsule: CapsuleShape3D


func _initialize_movement() -> void:
	floor_snap_length = FLOOR_SNAP
	# A packed-scene capsule can be shared by multiple instances before crouching resizes it.
	_capsule = (collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	collision.shape = _capsule


func _reset_movement() -> void:
	velocity = Vector3.ZERO
	crouch_amount = 0.0
	wants_crouch = false
	movement.reset()
	_airborne = false
	_fall_speed = 0.0
	_apply_crouch_shape()


## Intent is horizontal in world space. The movement model owns speed and acceleration.
func _step_movement(direction: Vector2, walking: bool, jump_pressed: bool, delta: float) -> void:
	_walking = walking
	_update_crouch(delta)
	_move(direction.normalized(), jump_pressed, delta)
	weapons.motion.speed = accuracy_speed()
	weapons.motion.airborne = not is_on_floor()
	weapons.motion.crouched = is_crouched()


## One tick of body movement. A jump needs a fresh press while grounded (holding the key does
## not chain jumps) and the take-off tick already counts as airborne, so it keeps its momentum.
func _move(wish_dir: Vector2, jump_pressed: bool, delta: float) -> void:
	movement.recover(delta)
	var jumping := jump_pressed and is_on_floor()
	var grounded := is_on_floor() and not jumping

	var limit := current_max_speed()
	var horizontal := Vector2(velocity.x, velocity.z)
	if grounded:
		horizontal = movement.ground_step(horizontal, wish_dir, limit, delta)
		velocity.y = 0.0
	else:
		horizontal = movement.air_step(horizontal, wish_dir, limit, delta)
		if jumping:
			velocity.y = movement.jump()
		# Gravity is applied half before and half after the move, so the jump arc (height and
		# hang time) does not depend on the physics tick rate.
		velocity.y -= movement.gravity * delta * 0.5
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	# No snapping on the way up, or the floor would swallow the jump.
	floor_snap_length = FLOOR_SNAP if grounded else 0.0

	move_and_slide()

	if is_on_floor():
		if _airborne:
			_land()
		_airborne = false
	else:
		velocity.y -= movement.gravity * delta * 0.5
		_fall_speed = maxf(-velocity.y, 0.0)
		_airborne = true


## Landing costs stamina in proportion to the impact speed and caps the speed at once.
func _land() -> void:
	movement.land(_fall_speed)
	var capped := movement.cap_ground_speed(Vector2(velocity.x, velocity.z), current_max_speed())
	velocity.x = capped.x
	velocity.z = capped.y
	_fall_speed = 0.0


## Ground speed limit for the current stance (before any stamina slowdown). Crouching lowers
## it linearly as the player goes down; standing back up keeps crouch speed until upright.
func current_max_speed() -> float:
	var crouch_blend := crouch_amount if wants_crouch else ceilf(crouch_amount)
	return movement.max_speed(_walking, crouch_blend, weapon_mobility())


## Run-speed share of the weapon in hand (1.0 with nothing equipped).
func weapon_mobility() -> float:
	var state := weapons.current() if weapons != null else null
	return state.definition.mobility if state != null else 1.0


## Horizontal speed as weapon accuracy sees it: rescaled so that a full run with the weapon in
## hand always equals [constant ShooterMotion.REFERENCE_SPEED]. Weapon spread values were
## balanced against that reference, so retuning run speeds leaves weapon balance untouched.
func accuracy_speed() -> float:
	return horizontal_speed() * ShooterMotion.REFERENCE_SPEED / (movement.run_speed * weapon_mobility())


func is_crouched() -> bool:
	return crouch_amount >= 0.5


func current_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)


## True if there is room to stand fully upright. In the air the legs come back down first
## (see [method _air_stand_drop]), so less headroom is needed there.
func can_stand() -> bool:
	var rise := STAND_HEIGHT - current_height()
	if rise <= 0.001:
		return true
	var drop := _air_stand_drop(rise)
	return not test_move(global_transform.translated(Vector3(0, -drop, 0)), Vector3(0, rise - drop, 0))


func _update_crouch(delta: float) -> void:
	var target := 1.0 if wants_crouch else 0.0
	if target < crouch_amount and not can_stand():
		target = crouch_amount
	if is_equal_approx(target, crouch_amount):
		return
	var before := current_height()
	if is_on_floor():
		var seconds := movement.crouch_time if target > crouch_amount else movement.stand_time
		crouch_amount = move_toward(crouch_amount, target, delta / seconds)
	elif target > crouch_amount:
		# Airborne: the legs tuck up at once, lifting the feet (crouch-jump).
		crouch_amount = target
		global_position.y += (before - current_height()) * movement.air_crouch_feet_share
	else:
		crouch_amount = move_toward(crouch_amount, target, delta / movement.stand_time)
		global_position.y -= _air_stand_drop(current_height() - before)
	_apply_crouch_shape()


## How far the feet can come back down when growing by [param rise] in the air: the tucked
## share if there is room below, otherwise nothing (the body then grows upwards only).
func _air_stand_drop(rise: float) -> float:
	if is_on_floor():
		return 0.0
	var drop := rise * movement.air_crouch_feet_share
	return 0.0 if test_move(global_transform, Vector3(0, -drop, 0)) else drop


func _apply_crouch_shape() -> void:
	var height := current_height()
	_capsule.height = height
	collision.position.y = height / 2.0
	head.position.y = lerpf(STAND_EYE, CROUCH_EYE, smoothstep(0.0, 1.0, crouch_amount))
	HumanoidRig.apply_height_ratio(hitboxes, height / STAND_HEIGHT)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
