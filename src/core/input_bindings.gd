class_name InputBindings
extends RefCounted
## The player's key and mouse bindings: up to four per action, applied to Godot's InputMap and
## saved to user://input_bindings.json. Everything that reads input keeps using action names,
## so rebinding needs no changes elsewhere.

const MAX_BINDINGS: int = 4
const DEFAULT_PATH: String = "user://input_bindings.json"
const FORMAT: String = "f2f.input_bindings"
const FORMAT_VERSION: int = 1
const MOUSE_NAMES: Dictionary[int, String] = {1: "Left mouse", 2: "Right mouse", 3: "Middle mouse",
	4: "Wheel up", 5: "Wheel down", 6: "Wheel left", 7: "Wheel right", 8: "Mouse 4", 9: "Mouse 5"}


## Current bindings of an action, in slot order.
static func bindings(action: StringName) -> Array[String]:
	var list: Array[String] = []
	if not InputMap.has_action(action):
		return list
	for event: InputEvent in InputMap.action_get_events(action):
		var binding := InputActions.event_to_binding(event)
		if not binding.is_empty() and not list.has(binding):
			list.append(binding)
	return list


## Replaces an action's bindings (invalid and repeated entries dropped, at most four kept).
static func set_bindings(action: StringName, list: Array[String]) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var kept: Array[String] = []
	for binding: String in list:
		var event := InputActions.binding_to_event(binding)
		if event != null and not kept.has(binding) and kept.size() < MAX_BINDINGS:
			kept.append(binding)
			InputMap.action_add_event(action, event)


## Why a binding cannot be given to an action ("" when it can).
static func refusal(action: StringName, binding: String) -> String:
	if InputActions.definition(action).is_empty():
		return "Unknown action."
	if InputActions.is_locked(action):
		return "This control cannot be changed."
	if InputActions.binding_to_event(binding) == null:
		return "That input cannot be bound."
	for locked: StringName in InputActions.all_actions():
		if InputActions.is_locked(locked) and bindings(locked).has(binding):
			return "%s is reserved for %s." % [label(binding), str(InputActions.definition(locked)["label"]).to_lower()]
	return ""


## Puts [param binding] in slot [param slot] (0–3) of an action; a slot past the end appends.
## The same input is removed from every other action of the same context, and those actions are
## returned so the screen can say what was unbound. Returns null when the binding is refused.
static func assign(action: StringName, slot: int, binding: String) -> Variant:
	if not refusal(action, binding).is_empty() or slot < 0 or slot >= MAX_BINDINGS:
		return null
	var unbound: Array[StringName] = []
	var context := str(InputActions.definition(action)["context"])
	for other: StringName in InputActions.all_actions():
		if other == action or InputActions.definition(other)["context"] != context:
			continue
		var theirs := bindings(other)
		if theirs.has(binding):
			theirs.erase(binding)
			set_bindings(other, theirs)
			unbound.append(other)
	var mine := bindings(action)
	mine.erase(binding)
	if slot < mine.size():
		mine[slot] = binding
	else:
		mine.append(binding)
	set_bindings(action, mine)
	return unbound


static func clear_slot(action: StringName, slot: int) -> bool:
	var mine := bindings(action)
	if InputActions.is_locked(action) or slot < 0 or slot >= mine.size():
		return false
	mine.remove_at(slot)
	set_bindings(action, mine)
	return true


static func reset_action(action: StringName) -> void:
	set_bindings(action, InputActions.defaults(action))


static func reset_all() -> void:
	for action: StringName in InputActions.all_actions():
		reset_action(action)


## Readable name of a binding, e.g. "W", "Left mouse", "Shift".
static func label(binding: String) -> String:
	var event := InputActions.binding_to_event(binding)
	if event is InputEventMouseButton:
		return MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "Mouse %d" % (event as InputEventMouseButton).button_index)
	if event is InputEventKey:
		var text := OS.get_keycode_string((event as InputEventKey).physical_keycode)
		return text if not text.is_empty() else binding
	return "?"


static func to_dict() -> Dictionary:
	var actions: Dictionary = {}
	for action: StringName in InputActions.all_actions():
		if not InputActions.is_locked(action):
			actions[String(action)] = bindings(action)
	return {"format": FORMAT, "format_version": FORMAT_VERSION, "actions": actions}


static func save(path: String = DEFAULT_PATH) -> Error:
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	if not written:
		DirAccess.remove_absolute(staged)
		return ERR_FILE_CANT_WRITE
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(staged, path)


## Applies saved bindings. Unknown actions, locked actions and invalid entries are ignored;
## actions missing from the file keep what they have. Returns false if the file is unusable.
static func load_file(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return false
	var data := json.data as Dictionary
	if data.get("format") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION \
			or not data.get("actions") is Dictionary:
		return false
	var actions := data["actions"] as Dictionary
	for key: Variant in actions:
		var action := StringName(str(key))
		if InputActions.definition(action).is_empty() or InputActions.is_locked(action) or not actions[key] is Array:
			continue
		var list: Array[String] = []
		for entry: Variant in actions[key] as Array:
			if entry is String and refusal(action, entry as String).is_empty():
				list.append(entry as String)
		set_bindings(action, list)
	return true
