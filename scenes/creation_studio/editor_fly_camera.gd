class_name EditorFlyCamera
extends Camera3D
## Free-flying editor camera with an overhead orthographic mode.
##
## Hold right mouse to look (mouse is captured while held). While looking: WASD fly, E/Q up/down,
## Shift faster, mouse wheel changes fly speed. Without right mouse, the wheel dollies forward/back.
## F resets the view. In overhead mode the camera looks straight down: right-drag or WASD pans
## and the wheel zooms.

const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 80.0
const DEFAULT_POSITION: Vector3 = Vector3(12, 14, 18)
const DEFAULT_TARGET: Vector3 = Vector3.ZERO
const OVERHEAD_HEIGHT: float = 150.0
const MIN_ORTHO_SIZE: float = 8.0
const MAX_ORTHO_SIZE: float = 320.0

@export var fly_speed: float = 10.0
@export var fast_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.0025
@export var dolly_step: float = 2.0

var is_looking: bool = false
var overhead: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _perspective_view: Transform3D


func _ready() -> void:
	reset_view()


func reset_view() -> void:
	if overhead:
		position = Vector3(DEFAULT_TARGET.x, OVERHEAD_HEIGHT, DEFAULT_TARGET.z)
		size = 80.0
		return
	position = DEFAULT_POSITION
	look_at(DEFAULT_TARGET, Vector3.UP)
	_yaw = rotation.y
	_pitch = rotation.x


## Restores a saved camera transform (e.g. after returning from a playtest).
func set_view(view_transform: Transform3D) -> void:
	global_transform = view_transform
	_yaw = rotation.y
	_pitch = rotation.x


## Switches between the fly camera and a straight-down orthographic view centred on [param focus].
func set_overhead(enabled: bool, focus: Vector3 = Vector3.ZERO) -> void:
	if enabled == overhead:
		return
	overhead = enabled
	if enabled:
		_perspective_view = global_transform
		projection = Camera3D.PROJECTION_ORTHOGONAL
		size = 80.0
		far = OVERHEAD_HEIGHT * 3.0
		rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		position = Vector3(focus.x, OVERHEAD_HEIGHT, focus.z)
	else:
		projection = Camera3D.PROJECTION_PERSPECTIVE
		set_view(_perspective_view)


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
		if overhead:
			var metres_per_pixel := size / maxf(1.0, get_viewport().get_visible_rect().size.y)
			position += Vector3(-motion.relative.x, 0.0, -motion.relative.y) * metres_per_pixel
			return
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
		if overhead:
			size = clampf(size * (1.0 / 1.15 if direction > 0.0 else 1.15), MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
		elif is_looking:
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
	var speed := fly_speed * (fast_multiplier if Input.is_action_pressed(InputActions.EDITOR_FAST) else 1.0)
	if overhead:
		position += Vector3(input.x, 0.0, input.z) * speed * delta
		return
	var vertical := Input.get_axis(InputActions.EDITOR_DOWN, InputActions.EDITOR_UP)
	var move := global_transform.basis * input
	move.y += vertical
	if move.length_squared() > 1.0:
		move = move.normalized()
	position += move * speed * delta


func _set_looking(looking: bool) -> void:
	is_looking = looking
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
