class_name DevOptions
extends RefCounted
## Developer switches that are not part of the game's settings yet, saved to
## user://profile/dev_options.json ([constant FORMAT] v2). A missing or unreadable file gives the
## defaults. v2: character models became the default for bots, so v1's saved "off" is ignored.

const DEFAULT_PATH: String = "user://profile/dev_options.json"
const FORMAT: String = "f2f.dev_options"
const FORMAT_VERSION: int = 2

static var file_path: String = DEFAULT_PATH
static var _loaded: bool = false
## Bots in the FPS runtime wear character models (saved presets, else random looks, in their
## team colours) instead of the box bodies. On by default. Hitboxes, movement and aim are unchanged.
static var _bot_character_models: bool = true


static func bot_character_models() -> bool:
	_ensure_loaded()
	return _bot_character_models


static func set_bot_character_models(enabled: bool) -> Error:
	_ensure_loaded()
	_bot_character_models = enabled
	return _save()


## Forgets the loaded values and reads the file again (tests point [member file_path] elsewhere
## first). Not "reload": that name is Script.reload, which would reset every static variable.
static func reread() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_bot_character_models = true
	if not FileAccess.file_exists(file_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if parsed is Dictionary and str((parsed as Dictionary).get("format", "")) == FORMAT 			and int((parsed as Dictionary).get("format_version", 0)) >= FORMAT_VERSION:
		_bot_character_models = bool((parsed as Dictionary).get("bot_character_models", true))


static func _save() -> Error:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": FORMAT, "format_version": FORMAT_VERSION,
		"bot_character_models": _bot_character_models}, "\t"))
	file.close()
	return OK
