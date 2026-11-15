class_name FirstPersonController
extends CharacterBody3D
## Basic first-person movement: WASD, mouse look, jump, walk modifier, gravity and collision.
##
## The body origin sits at the player's feet; the Head node holds the camera at eye height.
## Movement values are placeholders to be tuned in Milestone 4.

@export var run_speed: float = 5.6
@export var walk_speed: float = 2.9
@export var ground_acceleration: float = 45.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 4.9
@export var mouse_sensitivity: float = 0.0022
@export var max_pitch_degrees: float = 89.0
## Falling below this height respawns the player.
@export var kill_height: float = -30.0

## When false the controller ignores look and movement input (e.g. while paused).
var input_enabled: bool = true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn_transform: Transform3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera


func _ready() -> void:
	_spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative)


## Applies a mouse-look delta in screen pixels.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	var max_pitch := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - relative.y * mouse_sensitivity, -max_pitch, max_pitch)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO
	if _accepts_input():
		input_dir = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
			InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
		if Input.is_action_just_pressed(InputActions.JUMP) and is_on_floor():
			velocity.y = jump_velocity

	var wish := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var speed := walk_speed if Input.is_action_pressed(InputActions.WALK) else run_speed
	var target := Vector2(wish.x, wish.z) * speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()

	if global_position.y < kill_height:
		respawn()


## Moves the player to a spawn point (feet position, facing yaw) and remembers it for respawns.
func set_spawn(feet_position: Vector3, yaw: float) -> void:
	global_position = feet_position + Vector3(0, 0.05, 0)
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_spawn_transform = global_transform


func respawn() -> void:
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _accepts_input() -> bool:
	return input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
