class_name InputActions
extends RefCounted
## Input action names, how they are shown on the Controls screen, and their default bindings.
##
## Actions are registered at startup only if missing; saved user bindings (InputBindings) are
## then applied on top. Keys use physical keycodes so WASD is layout-independent.
## A binding is a string: "key:<physical keycode>" or "mouse:<button index>".

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
## Knife stab and grenade lob.
const SECONDARY_FIRE: StringName = &"secondary_fire"
const RELOAD: StringName = &"reload"
const CROUCH: StringName = &"crouch"
const WEAPON_1: StringName = &"weapon_1"
const WEAPON_2: StringName = &"weapon_2"
const WEAPON_3: StringName = &"weapon_3"
const WEAPON_4: StringName = &"weapon_4"
const WEAPON_NEXT: StringName = &"weapon_next"
const WEAPON_PREVIOUS: StringName = &"weapon_previous"
const INTERACT: StringName = &"interact"
const BUY_MENU: StringName = &"buy_menu"
const TEAM_CALL: StringName = &"team_call"
const NOCLIP: StringName = &"noclip"
const INSPECT: StringName = &"inspect_weapon"

const GROUP_ORDER: Array[String] = ["Movement", "Combat", "Match", "Sandbox", "Editor camera", "System"]

## One entry per action. "context" decides which actions may not share a binding ("game" and
## "editor" are never active together, so E can be both Interact and editor Up). "locked"
## actions are shown but cannot be rebound (Esc must always reach the pause menu).
const DEFINITIONS: Array[Dictionary] = [
	{"id": MOVE_FORWARD, "label": "Move forward", "group": "Movement", "context": "game", "defaults": ["key:87"]},
	{"id": MOVE_BACK, "label": "Move back", "group": "Movement", "context": "game", "defaults": ["key:83"]},
	{"id": MOVE_LEFT, "label": "Strafe left", "group": "Movement", "context": "game", "defaults": ["key:65"]},
	{"id": MOVE_RIGHT, "label": "Strafe right", "group": "Movement", "context": "game", "defaults": ["key:68"]},
	{"id": JUMP, "label": "Jump", "group": "Movement", "context": "game", "defaults": ["key:32"]},
	{"id": WALK, "label": "Walk (hold)", "group": "Movement", "context": "game", "defaults": ["key:4194325"]},
	{"id": CROUCH, "label": "Crouch (hold)", "group": "Movement", "context": "game", "defaults": ["key:4194326", "key:67"]},
	{"id": FIRE, "label": "Fire", "group": "Combat", "context": "game", "defaults": ["mouse:1"]},
	{"id": SECONDARY_FIRE, "label": "Stab / lob grenade", "group": "Combat", "context": "game", "defaults": ["mouse:2"]},
	{"id": RELOAD, "label": "Reload", "group": "Combat", "context": "game", "defaults": ["key:82"]},
	{"id": WEAPON_1, "label": "Primary weapon", "group": "Combat", "context": "game", "defaults": ["key:49"]},
	{"id": WEAPON_2, "label": "Secondary weapon", "group": "Combat", "context": "game", "defaults": ["key:50"]},
	{"id": WEAPON_3, "label": "Knife", "group": "Combat", "context": "game", "defaults": ["key:51"]},
	{"id": WEAPON_4, "label": "Utility (press again for the next)", "group": "Combat", "context": "game", "defaults": ["key:52"]},
	{"id": WEAPON_NEXT, "label": "Next weapon", "group": "Combat", "context": "game", "defaults": ["mouse:5"]},
	{"id": WEAPON_PREVIOUS, "label": "Previous weapon", "group": "Combat", "context": "game", "defaults": ["mouse:4"]},
	{"id": INSPECT, "label": "Inspect weapon", "group": "Combat", "context": "game", "defaults": ["key:70"]},
	{"id": INTERACT, "label": "Plant / defuse / use", "group": "Match", "context": "game", "defaults": ["key:69"]},
	{"id": BUY_MENU, "label": "Buy menu", "group": "Match", "context": "game", "defaults": ["key:66"]},
	{"id": TEAM_CALL, "label": "Team calls (IGL)", "group": "Match", "context": "game", "defaults": ["key:90"]},
	{"id": NOCLIP, "label": "Noclip (sandbox only)", "group": "Sandbox", "context": "game", "defaults": ["key:86"]},
	{"id": EDITOR_LOOK, "label": "Look / fly (hold)", "group": "Editor camera", "context": "editor", "defaults": ["mouse:2"]},
	{"id": EDITOR_UP, "label": "Fly up", "group": "Editor camera", "context": "editor", "defaults": ["key:69"]},
	{"id": EDITOR_DOWN, "label": "Fly down", "group": "Editor camera", "context": "editor", "defaults": ["key:81"]},
	{"id": EDITOR_FAST, "label": "Fly faster (hold)", "group": "Editor camera", "context": "editor", "defaults": ["key:4194325"]},
	{"id": EDITOR_RESET_VIEW, "label": "Reset view", "group": "Editor camera", "context": "editor", "defaults": ["key:70"]},
	{"id": PAUSE_MENU, "label": "Pause menu / back", "group": "System", "context": "system", "defaults": ["key:4194305"], "locked": true},
]


## Adds every missing action; an action that has no events yet gets its defaults.
static func register_defaults() -> void:
	for definition: Dictionary in DEFINITIONS:
		var action: StringName = definition["id"]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			for binding: String in definition["defaults"]:
				InputMap.action_add_event(action, binding_to_event(binding))


static func all_actions() -> Array[StringName]:
	var list: Array[StringName] = []
	for definition: Dictionary in DEFINITIONS:
		list.append(definition["id"])
	return list


static func definition(action: StringName) -> Dictionary:
	for entry: Dictionary in DEFINITIONS:
		if entry["id"] == action:
			return entry
	return {}


static func defaults(action: StringName) -> Array[String]:
	var list: Array[String] = []
	list.assign(definition(action).get("defaults", []))
	return list


static func is_locked(action: StringName) -> bool:
	return bool(definition(action).get("locked", false))


static func actions_in_group(group: String) -> Array[StringName]:
	var list: Array[StringName] = []
	for entry: Dictionary in DEFINITIONS:
		if entry["group"] == group:
			list.append(entry["id"])
	return list


## The input event for a binding string, or null when the string is not a valid binding.
static func binding_to_event(binding: String) -> InputEvent:
	var parts := binding.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or int(parts[1]) <= 0:
		return null
	if parts[0] == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(parts[1]) as Key
		return key
	if parts[0] == "mouse" and int(parts[1]) <= MOUSE_BUTTON_XBUTTON2:
		var button := InputEventMouseButton.new()
		button.button_index = int(parts[1]) as MouseButton
		return button
	return null


## The binding string for a key or mouse-button event ("" for anything else).
static func event_to_binding(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	var button := event as InputEventMouseButton
	if button != null and button.button_index != MOUSE_BUTTON_NONE:
		return "mouse:%d" % button.button_index
	return ""
