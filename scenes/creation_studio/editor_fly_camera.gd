class_name EditorFlyCamera
extends Camera3D
## Free-flying editor camera.
##
## Hold right mouse to look (mouse is captured while held). While looking: WASD fly, E/Q up/down,
## Shift faster, mouse wheel changes fly speed. Without right mouse, the wheel dollies forward/back.
## F resets the view.

const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 80.0
const DEFAULT_POSITION: Vector3 = Vector3(12, 14, 18)
const DEFAULT_TARGET: Vector3 = Vector3.ZERO

@export var fly_speed: float = 10.0
@export var fast_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.0025
@export var dolly_step: float = 2.0

var is_looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	reset_view()


func reset_view() -> void:
	position = DEFAULT_POSITION
	look_at(DEFAULT_TARGET, Vector3.UP)
	_yaw = rotation.y
	_pitch = rotation.x


## Restores a saved camera transform (e.g. after returning from a playtest).
func set_view(view_transform: Transform3D) -> void:
	global_transform = view_transform
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.EDITOR_LOOK):
		_set_looking(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(InputActions.EDITOR_LOOK):
		_set_looking(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.EDITOR_RESET_VIEW) and not is_looking:
		reset_view()
	elif event is InputEventMouseMotion and is_looking:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		var direction := 0.0
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			direction = 1.0
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			direction = -1.0
		if direction == 0.0:
			return
		if is_looking:
			fly_speed = clampf(fly_speed * (1.2 if direction > 0.0 else 1.0 / 1.2), MIN_SPEED, MAX_SPEED)
		else:
			position += -global_transform.basis.z * dolly_step * direction
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Safety: if the button was released while the event went elsewhere, stop looking.
	if is_looking and not Input.is_action_pressed(InputActions.EDITOR_LOOK):
		_set_looking(false)
	if not is_looking:
		return
	var input := Vector3.ZERO
	input.x = Input.get_axis(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT)
	input.z = Input.get_axis(InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
	var vertical := Input.get_axis(InputActions.EDITOR_DOWN, InputActions.EDITOR_UP)
	var move := global_transform.basis * input
	move.y += vertical
	if move.length_squared() > 1.0:
		move = move.normalized()
	var speed := fly_speed * (fast_multiplier if Input.is_action_pressed(InputActions.EDITOR_FAST) else 1.0)
	position += move * speed * delta


func _set_looking(looking: bool) -> void:
	is_looking = looking
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
