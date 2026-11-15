class_name InputActions
extends RefCounted
## Input action names and their default bindings.
##
## Actions are registered at startup only if missing, so user rebinds (future feature, loaded
## before this runs) take precedence. Keys use physical keycodes so WASD is layout-independent.

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const JUMP: StringName = &"jump"
const WALK: StringName = &"walk"
const PAUSE_MENU: StringName = &"pause_menu"
const EDITOR_LOOK: StringName = &"editor_look"
const EDITOR_UP: StringName = &"editor_up"
const EDITOR_DOWN: StringName = &"editor_down"
const EDITOR_FAST: StringName = &"editor_fast"
const EDITOR_RESET_VIEW: StringName = &"editor_reset_view"
const FIRE: StringName = &"fire"
const RELOAD: StringName = &"reload"
const CROUCH: StringName = &"crouch"
const WEAPON_1: StringName = &"weapon_1"
const WEAPON_2: StringName = &"weapon_2"
const WEAPON_3: StringName = &"weapon_3"
const WEAPON_NEXT: StringName = &"weapon_next"
const WEAPON_PREVIOUS: StringName = &"weapon_previous"
const INTERACT: StringName = &"interact"
const BUY_MENU: StringName = &"buy_menu"


static func register_defaults() -> void:
	_add_key(MOVE_FORWARD, KEY_W)
	_add_key(MOVE_BACK, KEY_S)
	_add_key(MOVE_LEFT, KEY_A)
	_add_key(MOVE_RIGHT, KEY_D)
	_add_key(JUMP, KEY_SPACE)
	_add_key(WALK, KEY_SHIFT)
	_add_key(PAUSE_MENU, KEY_ESCAPE)
	_add_mouse_button(EDITOR_LOOK, MOUSE_BUTTON_RIGHT)
	_add_key(EDITOR_UP, KEY_E)
	_add_key(EDITOR_DOWN, KEY_Q)
	_add_key(EDITOR_FAST, KEY_SHIFT)
	_add_key(EDITOR_RESET_VIEW, KEY_F)
	_add_mouse_button(FIRE, MOUSE_BUTTON_LEFT)
	_add_key(RELOAD, KEY_R)
	_add_keys(CROUCH, [KEY_CTRL, KEY_C])
	_add_key(WEAPON_1, KEY_1)
	_add_key(WEAPON_2, KEY_2)
	_add_key(WEAPON_3, KEY_3)
	_add_mouse_button(WEAPON_NEXT, MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse_button(WEAPON_PREVIOUS, MOUSE_BUTTON_WHEEL_UP)
	_add_key(INTERACT, KEY_E)
	_add_key(BUY_MENU, KEY_B)


static func all_actions() -> Array[StringName]:
	return [MOVE_FORWARD, MOVE_BACK, MOVE_LEFT, MOVE_RIGHT, JUMP, WALK, PAUSE_MENU,
		EDITOR_LOOK, EDITOR_UP, EDITOR_DOWN, EDITOR_FAST, EDITOR_RESET_VIEW,
		FIRE, RELOAD, CROUCH, WEAPON_1, WEAPON_2, WEAPON_3, WEAPON_NEXT, WEAPON_PREVIOUS,
		INTERACT, BUY_MENU]


static func _ensure_action(action: StringName) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	return InputMap.action_get_events(action).is_empty()


static func _add_key(action: StringName, keycode: Key) -> void:
	if not _ensure_action(action):
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


static func _add_keys(action: StringName, keycodes: Array[Key]) -> void:
	if not _ensure_action(action):
		return
	for keycode: Key in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


static func _add_mouse_button(action: StringName, button: MouseButton) -> void:
	if not _ensure_action(action):
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
