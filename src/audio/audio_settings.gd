class_name AudioSettings
extends RefCounted
## The player's volume settings and the game's audio buses (Milestone 22), saved to
## user://profile/audio_settings.json ([constant FORMAT] v1). A missing or unreadable file gives
## the defaults. Buses: Master, and under it Effects (the world), UI and Voice.

const DEFAULT_PATH: String = "user://profile/audio_settings.json"
const FORMAT: String = "f2f.audio_settings"
const FORMAT_VERSION: int = 1
const BUSES: Array[StringName] = [&"Master", &"Effects", &"UI", &"Voice"]
const DEFAULT_VOLUME: Dictionary[StringName, float] = {&"Master": 0.8, &"Effects": 1.0, &"UI": 0.7, &"Voice": 1.0}

static var file_path: String = DEFAULT_PATH
static var _loaded: bool = false
static var _volumes: Dictionary[StringName, float] = {}


## Creates any missing bus and applies the saved volumes.
static func apply() -> void:
	_ensure_loaded()
	for bus: StringName in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
		var volume := _volumes[bus]
		AudioServer.set_bus_mute(index, volume <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


## The volume (0..1) of [param bus].
static func volume(bus: StringName) -> float:
	_ensure_loaded()
	return _volumes.get(bus, 1.0)


## Sets, applies and saves the volume (0..1) of [param bus].
static func set_volume(bus: StringName, value: float) -> Error:
	_ensure_loaded()
	if not BUSES.has(bus):
		return ERR_INVALID_PARAMETER
	_volumes[bus] = clampf(value, 0.0, 1.0)
	apply()
	return _save()


## Forgets the loaded values and reads the file again (tests point [member file_path] elsewhere).
static func reread() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_volumes.assign(DEFAULT_VOLUME)
	if not FileAccess.file_exists(file_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not parsed is Dictionary or str((parsed as Dictionary).get("format", "")) != FORMAT:
		return
	var saved: Dictionary = (parsed as Dictionary).get("volumes", {})
	for bus: StringName in BUSES:
		if saved.has(String(bus)):
			_volumes[bus] = clampf(float(saved[String(bus)]), 0.0, 1.0)


static func _save() -> Error:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var volumes: Dictionary[String, float] = {}
	for bus: StringName in BUSES:
		volumes[String(bus)] = _volumes[bus]
	file.store_string(JSON.stringify({"format": FORMAT, "format_version": FORMAT_VERSION, "volumes": volumes}, "\t"))
	file.close()
	return OK
