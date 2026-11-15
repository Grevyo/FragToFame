class_name FirstPersonController
extends CharacterBody3D
## First-person player: WASD, mouse look, jump, walk, crouch, gravity and collision, plus the
## player's [Health] and [WeaponController] (child nodes "Health" and "Weapons").
##
## The body origin sits at the player's feet; the Head node holds the camera at eye height.
## Human career attributes never feed into anything here (aim, recoil and reaction are the
## player's own).

signal died(info: DamageInfo)
signal respawned

const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.2
const STAND_EYE: float = 1.62
const CROUCH_EYE: float = 1.04

@export var run_speed: float = 5.6
@export var walk_speed: float = 2.9
@export var crouch_move_speed: float = 2.4
@export var ground_acceleration: float = 45.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 4.9
## Crouch transitions per second (1 / seconds to fully crouch).
@export var crouch_rate: float = 7.0
@export var mouse_sensitivity: float = 0.0022
@export var max_pitch_degrees: float = 89.0
## Falling below this height kills the player.
@export var kill_height: float = -30.0

## When false the controller ignores look, movement and weapon input (e.g. while paused).
## Turning it off also releases the trigger, so a paused or dead player never keeps firing.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not value and weapons != null:
			weapons.trigger = false
## Crouch request. Driven by the crouch key while input is enabled; scripts/tests may set it
## directly while input is disabled.
var wants_crouch: bool = false
## 0 = standing, 1 = fully crouched.
var crouch_amount: float = 0.0
## When true the player can look around but not move, jump or fire (freeze time, planting).
var frozen: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn_transform: Transform3D
var _capsule: CapsuleShape3D
## The player's own hitboxes (so bots can hit them); they follow the crouch height.
var hitboxes: Array[Hitbox] = []

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var collision: CollisionShape3D = $Collision
@onready var health: Health = $Health
@onready var weapons: WeaponController = $Weapons


func _ready() -> void:
	_spawn_transform = global_transform
	collision_layer = Hitscan.LAYER_CHARACTERS
	collision_mask = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS
	# Packed-scene sub-resources are shared between instances; crouching resizes ours.
	_capsule = (collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	collision.shape = _capsule
	hitboxes = HumanoidRig.build(self, health, false).hitboxes
	health.owner_id = weapons.shooter_id
	weapons.eye = head
	weapons.punch_target = camera
	var own: Array[RID] = [get_rid()]
	for hitbox: Hitbox in hitboxes:
		own.append(hitbox.get_rid())
	weapons.exclude = own
	health.died.connect(_on_died)


func _unhandled_input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative)
		return
	if event.is_action_pressed(InputActions.RELOAD):
		weapons.request_reload()
	elif event.is_action_pressed(InputActions.WEAPON_1):
		weapons.select_slot(1)
	elif event.is_action_pressed(InputActions.WEAPON_2):
		weapons.select_slot(2)
	elif event.is_action_pressed(InputActions.WEAPON_3):
		weapons.select_slot(3)
	elif event.is_action_pressed(InputActions.WEAPON_NEXT):
		weapons.cycle(1)
	elif event.is_action_pressed(InputActions.WEAPON_PREVIOUS):
		weapons.cycle(-1)


## Applies a mouse-look delta in screen pixels.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	var max_pitch := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - relative.y * mouse_sensitivity, -max_pitch, max_pitch)


## Turns the body and head so the view looks straight at [param world_point].
func face_point(world_point: Vector3) -> void:
	var to_target := world_point - head.global_position
	rotation.y = atan2(-to_target.x, -to_target.z)
	head.rotation.x = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var alive := not health.is_dead
	var input_dir := Vector2.ZERO
	if input_enabled:
		var active := _accepts_input() and alive
		wants_crouch = active and Input.is_action_pressed(InputActions.CROUCH)
		weapons.trigger = active and not frozen and Input.is_action_pressed(InputActions.FIRE)
	if _accepts_input() and alive and not frozen:
		input_dir = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
			InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
		if Input.is_action_just_pressed(InputActions.JUMP) and is_on_floor():
			velocity.y = jump_velocity
	_update_crouch(delta)

	var wish := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var target := Vector2(wish.x, wish.z) * current_max_speed()
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()

	weapons.motion.speed = horizontal_speed()
	weapons.motion.airborne = not is_on_floor()
	weapons.motion.crouched = is_crouched()

	if global_position.y < kill_height and alive:
		health.kill(DamageInfo.world(health.current))


## Sets the team key used for friendly fire and bot targeting.
func set_team(team_key: StringName) -> void:
	health.team = team_key
	weapons.team = team_key


func current_max_speed() -> float:
	if is_crouched():
		return crouch_move_speed
	if Input.is_action_pressed(InputActions.WALK) and _accepts_input():
		return walk_speed
	return run_speed


func is_crouched() -> bool:
	return crouch_amount >= 0.5


func current_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)


## True if there is room above to stand fully upright.
func can_stand() -> bool:
	var rise := STAND_HEIGHT - current_height()
	return rise <= 0.001 or not test_move(global_transform, Vector3(0, rise, 0))


func _update_crouch(delta: float) -> void:
	var target := 1.0 if wants_crouch else 0.0
	if target < crouch_amount and not can_stand():
		target = crouch_amount
	if is_equal_approx(target, crouch_amount):
		return
	crouch_amount = move_toward(crouch_amount, target, crouch_rate * delta)
	_apply_crouch_shape()


func _apply_crouch_shape() -> void:
	var height := current_height()
	_capsule.height = height
	collision.position.y = height / 2.0
	head.position.y = lerpf(STAND_EYE, CROUCH_EYE, crouch_amount)
	HumanoidRig.apply_height_ratio(hitboxes, height / STAND_HEIGHT)


## Moves the player to a spawn point (feet position, facing yaw) and remembers it for respawns.
func set_spawn(feet_position: Vector3, yaw: float) -> void:
	global_position = feet_position + Vector3(0, 0.05, 0)
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_spawn_transform = global_transform


## Returns to the spawn point alive, standing, with full health and ammo.
func respawn() -> void:
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	crouch_amount = 0.0
	wants_crouch = false
	_apply_crouch_shape()
	weapons.refill_all()
	health.revive()
	respawned.emit()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _on_died(info: DamageInfo) -> void:
	weapons.trigger = false
	died.emit(info)


func _accepts_input() -> bool:
	return input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
