class_name DevOptions
extends RefCounted
## Developer switches that are not part of the game's settings yet, saved to
## user://profile/dev_options.json ([constant FORMAT] v1). Everything defaults to off, so a
## missing or unreadable file leaves the game exactly as it plays without developer tools.

const DEFAULT_PATH: String = "user://profile/dev_options.json"
const FORMAT: String = "f2f.dev_options"
const FORMAT_VERSION: int = 1

static var path: String = DEFAULT_PATH
static var _loaded: bool = false
## Bots in the FPS runtime wear character models (random looks in their team colours) instead
## of the box bodies. Hitboxes, movement and aim are unchanged.
static var _bot_character_models: bool = false


static func bot_character_models() -> bool:
	_ensure_loaded()
	return _bot_character_models


static func set_bot_character_models(enabled: bool) -> Error:
	_ensure_loaded()
	_bot_character_models = enabled
	return _save()


## Forgets the loaded values (tests point [member path] elsewhere first).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_bot_character_models = false
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and str((parsed as Dictionary).get("format", "")) == FORMAT:
		_bot_character_models = bool((parsed as Dictionary).get("bot_character_models", false))


static func _save() -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": FORMAT, "format_version": FORMAT_VERSION,
		"bot_character_models": _bot_character_models}, "\t"))
	file.close()
	return OK
