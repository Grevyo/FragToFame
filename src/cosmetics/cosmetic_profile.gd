class_name CosmeticProfile
extends RefCounted
## The player's weapon customisation: for each weapon, the equipped Coat ("" = factory finish)
## and the Magnet in each of its five slots ("" = empty). Saved to user://profile/cosmetics.json
## and used by every mode (sandbox, practice and careers), so a look follows the player.
##
## The career database is not involved: cosmetics belong to the player, not to one career.

const DEFAULT_PATH: String = "user://profile/cosmetics.json"
const FORMAT: String = "f2f.cosmetics"
const FORMAT_VERSION: int = 1

static var _current: CosmeticProfile = null

var path: String = DEFAULT_PATH
## weapon_id -> {"coat": String, "magnets": Array of five Strings}
var weapons: Dictionary[String, Dictionary] = {}


## The profile in use (loaded from disk the first time it is asked for).
static func current() -> CosmeticProfile:
	if _current == null:
		_current = CosmeticProfile.new()
		_current.load_file()
	return _current


## Replaces the profile in use (tests point it at a scratch file).
static func use(profile: CosmeticProfile) -> void:
	_current = profile


## A weapon's customisation; always complete, defaulting to factory finish and empty slots.
func loadout(weapon_id: StringName) -> Dictionary:
	var entry: Dictionary = weapons.get(String(weapon_id), {})
	var magnets: Array[String] = []
	var stored: Array = entry.get("magnets", [])
	for slot: int in WeaponModels.SLOT_COUNT:
		magnets.append(str(stored[slot]) if slot < stored.size() else "")
	return {"coat": str(entry.get("coat", "")), "magnets": magnets}


## Equips a Coat ("" = factory finish). Returns "" or why it was refused.
func set_coat(weapon_id: StringName, coat_id: String) -> String:
	if not WeaponModels.has_model(weapon_id):
		return "This weapon cannot be customised."
	if not coat_id.is_empty():
		if not CoatLibrary.fits(weapon_id, coat_id):
			return "That Coat does not fit this weapon."
		if not CoatLibrary.is_unlocked(coat_id):
			return "That Coat is not unlocked."
	var entry := loadout(weapon_id)
	entry["coat"] = coat_id
	weapons[String(weapon_id)] = entry
	return ""


## Puts a Magnet in a slot (0–4), or clears the slot with "". Returns "" or why it was refused.
func set_magnet(weapon_id: StringName, slot: int, magnet_id: String) -> String:
	if not WeaponModels.has_model(weapon_id):
		return "This weapon cannot be customised."
	if slot < 0 or slot >= WeaponModels.SLOT_COUNT:
		return "A weapon has five Magnet slots."
	if not magnet_id.is_empty() and not MagnetCatalog.is_unlocked(magnet_id):
		return "That Magnet is not available."
	var entry := loadout(weapon_id)
	(entry["magnets"] as Array)[slot] = magnet_id
	weapons[String(weapon_id)] = entry
	return ""


func to_dict() -> Dictionary:
	var stored: Dictionary = {}
	for weapon_id: String in weapons:
		stored[weapon_id] = loadout(StringName(weapon_id))
	return {"format": FORMAT, "format_version": FORMAT_VERSION, "weapons": stored}


## Saves the profile, keeping the previous file as ".bak". Returns OK or an error.
func save() -> Error:
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK and not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return made
	var staged := path + "." + Ids.generate("stage")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	if not written:
		DirAccess.remove_absolute(staged)
		return ERR_FILE_CANT_WRITE
	var installed := FileReplacement.install(staged, path, path + ".bak")
	if installed != OK:
		DirAccess.remove_absolute(staged)
	return installed


## Loads the profile. Entries that no longer make sense (unknown weapon, a Coat that is gone or
## fits another weapon, an unknown Magnet) fall back to factory finish / an empty slot, so a
## stale file can never break a weapon. Returns false when there is no usable file.
func load_file() -> bool:
	weapons.clear()
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return false
	var data := json.data as Dictionary
	if data.get("format") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION or not data.get("weapons") is Dictionary:
		return false
	var stored := data["weapons"] as Dictionary
	for key: Variant in stored:
		var weapon_id := StringName(str(key))
		if not WeaponModels.has_model(weapon_id) or not stored[key] is Dictionary:
			continue
		var entry := stored[key] as Dictionary
		set_coat(weapon_id, str(entry.get("coat", "")))
		var magnets: Variant = entry.get("magnets", [])
		if magnets is Array:
			for slot: int in mini(WeaponModels.SLOT_COUNT, (magnets as Array).size()):
				set_magnet(weapon_id, slot, str((magnets as Array)[slot]))
	return true
