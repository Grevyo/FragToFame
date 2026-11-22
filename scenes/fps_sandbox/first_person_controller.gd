class_name FirstPersonController
extends CombatantMovementBody
## First-person player: WASD, mouse look, jump, walk, crouch, gravity and collision, plus the
## player's [Health] and [WeaponController] (child nodes "Health" and "Weapons").
##
## The body origin sits at the player's feet; the Head node holds the camera at eye height.
## How the player accelerates, stops, jumps and air-strafes is decided by [PlayerMovement]
## ([member movement]), which is also where every movement tuning value lives.
## Human career attributes never feed into anything here (aim, recoil and reaction are the
## player's own).

signal died(info: DamageInfo)
signal respawned

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
			weapons.secondary_trigger = false
## Scripted movement, used instead of the keyboard while [member input_enabled] is false
## (tests, cutscenes): x = strafe right, y = backwards, as [method Input.get_vector] returns.
var scripted_move: Vector2 = Vector2.ZERO
## Scripted walk (Shift) state, see [member scripted_move].
var scripted_walk: bool = false
## Scripted jump press; consumed by the next physics tick, see [member scripted_move].
var scripted_jump: bool = false
## When true the player can look around but not move, jump or fire (freeze time, planting).
var frozen: bool = false
## Noclip may only be toggled where the runtime allows it (sandbox and playtest, never matches).
var noclip_allowed: bool = false
## Flying through geometry: no gravity, no collision. Changed with [method set_noclip].
var noclip: bool = false
## Scripted climb while noclipping (-1 down … 1 up), see [member scripted_move].
var scripted_climb: float = 0.0

const NOCLIP_SPEED: float = 10.0
const NOCLIP_FAST_MULTIPLIER: float = 3.0

var _spawn_transform: Transform3D

@onready var camera: Camera3D = $Head/Camera
@onready var health: Health = $Health


func _ready() -> void:
	_spawn_transform = global_transform
	collision_layer = Hitscan.LAYER_CHARACTERS
	collision_mask = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS
	collision = $Collision
	head = $Head
	weapons = $Weapons
	_initialize_movement()
	hitboxes = HumanoidRig.build(self, health, false).hitboxes
	health.owner_id = weapons.shooter_id
	weapons.eye = head
	weapons.punch_target = camera
	var own: Array[RID] = [get_rid()]
	for hitbox: Hitbox in hitboxes:
		own.append(hitbox.get_rid())
	weapons.exclude = own
	health.died.connect(_on_died)
	CombatantSounds.attach(self, health, true)


func _unhandled_input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative)
		return
	if event.is_action_pressed(InputActions.NOCLIP):
		set_noclip(not noclip)
	elif event.is_action_pressed(InputActions.RELOAD):
		weapons.request_reload()
	elif event.is_action_pressed(InputActions.WEAPON_1):
		weapons.select_slot(1)
	elif event.is_action_pressed(InputActions.WEAPON_2):
		weapons.select_slot(2)
	elif event.is_action_pressed(InputActions.WEAPON_3):
		weapons.select_slot(3)
	elif event.is_action_pressed(InputActions.WEAPON_4):
		weapons.select_slot(EquipmentCatalog.UTILITY_SLOT)
	elif event.is_action_pressed(InputActions.WEAPON_NEXT):
		weapons.cycle(1)
	elif event.is_action_pressed(InputActions.WEAPON_PREVIOUS):
		weapons.cycle(-1)


## Applies a mouse-look delta in screen pixels.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	var max_pitch := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - relative.y * mouse_sensitivity, -max_pitch, max_pitch)


## Turns noclip on or off. Ignored (returns false) where it is not allowed or while dead.
func set_noclip(enabled: bool) -> bool:
	if enabled == noclip:
		return true
	if enabled and (not noclip_allowed or health.is_dead):
		return false
	noclip = enabled
	collision.disabled = enabled
	velocity = Vector3.ZERO
	_airborne = false
	_fall_speed = 0.0
	_clear_jump_chain()
	return true


## One tick of noclip flight: along the view direction, plus straight up and down.
func _fly(input_dir: Vector2, climb: float, fast: bool, delta: float) -> void:
	var direction := head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y) + Vector3.UP * climb
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	velocity = direction * NOCLIP_SPEED * (NOCLIP_FAST_MULTIPLIER if fast else 1.0)
	global_position += velocity * delta
	weapons.motion.speed = 0.0
	weapons.motion.airborne = false
	weapons.motion.crouched = false


## Turns the body and head so the view looks straight at [param world_point].
func face_point(world_point: Vector3) -> void:
	var to_target := world_point - head.global_position
	rotation.y = atan2(-to_target.x, -to_target.z)
	head.rotation.x = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())


func _physics_process(delta: float) -> void:
	var alive := not health.is_dead
	var input_dir := Vector2.ZERO
	var jump_pressed := false
	var walking := false
	var can_jump := alive and not frozen and (not input_enabled or _accepts_input())
	if noclip and (not alive or not noclip_allowed):
		set_noclip(false)
	if noclip:
		# Jump climbs, crouch descends and the walk key flies faster.
		var climb := scripted_climb
		if input_enabled:
			var flying := _accepts_input()
			weapons.trigger = flying and Input.is_action_pressed(InputActions.FIRE)
			if flying:
				input_dir = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
					InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
				climb = Input.get_axis(InputActions.CROUCH, InputActions.JUMP)
				walking = Input.is_action_pressed(InputActions.WALK)
			else:
				climb = 0.0
		else:
			input_dir = scripted_move
			walking = scripted_walk
		_fly(input_dir, climb, walking, delta)
		return
	if input_enabled:
		var active := _accepts_input() and alive
		wants_crouch = active and Input.is_action_pressed(InputActions.CROUCH)
		weapons.trigger = active and not frozen and Input.is_action_pressed(InputActions.FIRE)
		weapons.secondary_trigger = active and not frozen and Input.is_action_pressed(InputActions.SECONDARY_FIRE)
		if active and not frozen:
			input_dir = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
				InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
			jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
			walking = Input.is_action_pressed(InputActions.WALK)
	elif alive and not frozen:
		input_dir = scripted_move
		jump_pressed = scripted_jump
		walking = scripted_walk
	scripted_jump = false
	var wish := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	_step_movement(Vector2(wish.x, wish.z), walking, jump_pressed, delta, can_jump)
	weapons.carrier_velocity = velocity

	if global_position.y < kill_height and alive:
		health.kill(DamageInfo.world(health.current))


## Sets the team key used for friendly fire and bot targeting.
func set_team(team_key: StringName) -> void:
	health.team = team_key
	weapons.team = team_key


## Moves the player to a spawn point (feet position, facing yaw) and remembers it for respawns.
func set_spawn(feet_position: Vector3, yaw: float) -> void:
	global_position = feet_position + Vector3(0, 0.05, 0)
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_clear_jump_chain()
	_spawn_transform = global_transform


## Returns to the spawn point alive, standing, with full health and ammo.
func respawn() -> void:
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
	set_noclip(false)
	_reset_movement()
	weapons.refill_all()
	health.revive()
	respawned.emit()


func _on_died(info: DamageInfo) -> void:
	weapons.trigger = false
	weapons.secondary_trigger = false
	died.emit(info)


func _accepts_input() -> bool:
	return input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
