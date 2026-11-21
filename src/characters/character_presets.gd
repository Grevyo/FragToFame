class_name CharacterPresets
extends RefCounted
## Saved character presets: one JSON file per preset in user://characters/presets
## ([constant FORMAT] v1: id, name, saved_at, appearance). Presets belong to the player, not to a
## career, like the rest of the cosmetic profile.

const DEFAULT_DIR: String = "user://characters/presets"
const FORMAT: String = "f2f.character_preset"
const FORMAT_VERSION: int = 1
const EXTENSION: String = ".preset.json"

static var directory: String = DEFAULT_DIR


## Saved presets, newest first: [{id, name, saved_at}].
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var data := _read(directory.path_join(file_name))
		if not data.is_empty():
			found.append({"id": str(data["id"]), "name": str(data.get("name", "")), "saved_at": int(data.get("saved_at", 0))})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return found


## Saves [param appearance] as a preset. An empty [param preset_id] makes a new one; an existing
## ID overwrites that preset. Returns {"id": String, "error": String}.
static func save(preset_name: String, appearance: CharacterAppearance, preset_id: String = "") -> Dictionary:
	var clean_name := preset_name.strip_edges()
	if clean_name.is_empty():
		return {"id": "", "error": "Give the preset a name."}
	var id := preset_id if _valid_id(preset_id) else Ids.generate("chp")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return {"id": "", "error": "Could not create the presets folder (%s)." % error_string(error)}
	var data := {"format": FORMAT, "format_version": FORMAT_VERSION, "id": id, "name": clean_name,
		"saved_at": int(Time.get_unix_time_from_system()), "appearance": appearance.to_dict()}
	var file := FileAccess.open(_path(id), FileAccess.WRITE)
	if file == null:
		return {"id": "", "error": "Could not write the preset (%s)." % error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return {"id": id, "error": ""}


## The appearance stored in a preset, or null.
static func load_preset(preset_id: String) -> CharacterAppearance:
	if not _valid_id(preset_id):
		return null
	var data := _read(_path(preset_id))
	if data.is_empty() or not data.get("appearance") is Dictionary:
		return null
	return CharacterAppearance.from_dict(data["appearance"] as Dictionary)


static func preset_name(preset_id: String) -> String:
	return str(_read(_path(preset_id)).get("name", "")) if _valid_id(preset_id) else ""


static func delete(preset_id: String) -> Error:
	if not _valid_id(preset_id) or not FileAccess.file_exists(_path(preset_id)):
		return ERR_DOES_NOT_EXIST
	return DirAccess.remove_absolute(_path(preset_id))


static func _path(preset_id: String) -> String:
	return directory.path_join(preset_id + EXTENSION)


## IDs become file names, so only simple ones are accepted.
static func _valid_id(preset_id: String) -> bool:
	return Ids.is_file_id(preset_id)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var data := parsed as Dictionary
	if str(data.get("format", "")) != FORMAT or int(data.get("format_version", 0)) > FORMAT_VERSION or str(data.get("id", "")).is_empty():
		return {}
	return data
