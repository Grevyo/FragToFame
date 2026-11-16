class_name CoatLibrary
extends RefCounted
## Coats (weapon finishes) known to the game. A Coat is one PNG in its weapon's Coat layout
## (the size and UV mapping the weapon's kit exports) plus a small record:
##   {"id", "name", "weapon_id", "rarity", "texture", "source", "unlock"}
##
## Two places are read:
##   res://data/coats/coats.json         official Coats shipped with the game (none yet)
##   user://coats/<id>.coat.json         Coats the player imported or, later, painted
## Adding a Coat is data only: drop the PNG next to a record. The weapon's factory finish is
## not a Coat; an empty Coat ID means "factory".
##
## This class also holds the kit conversion: [method compose] turns per-zone paint into a full
## Coat texture using the kit's zone masks, and [method import_png] checks and stores a PNG
## exported from a kit.

const OFFICIAL_PATH: String = "res://data/coats/coats.json"
const CUSTOM_DIR: String = "user://coats"
const FORMAT: String = "f2f.coats"
const FORMAT_VERSION: int = 1
const RECORD_EXTENSION: String = ".coat.json"
## Rarity tiers, lowest first.
const RARITIES: Array[String] = ["standard", "refined", "elite", "prestige", "legendary"]
const SOURCE_OFFICIAL: String = "official"
const SOURCE_CUSTOM: String = "custom"

## Folder of the player's own Coats; tests point it at a scratch folder with [method set_custom_dir].
static var custom_dir: String = CUSTOM_DIR
static var _coats: Dictionary[String, Dictionary] = {}
static var _loaded: bool = false
static var _textures: Dictionary[String, Texture2D] = {}


## Points the library at another folder of custom Coats (tests use a scratch folder) and reloads.
static func set_custom_dir(path: String) -> void:
	custom_dir = path
	refresh()


## Forgets everything read so far; the next query reads the records again. (Not called "reload":
## that name belongs to the script object itself and would reset this class.)
static func refresh() -> void:
	_coats.clear()
	_textures.clear()
	_loaded = false


## Every Coat for a weapon (official first, then custom, each by name).
static func coats_for(weapon_id: StringName) -> Array[Dictionary]:
	_ensure_loaded()
	var list: Array[Dictionary] = []
	for coat: Dictionary in _coats.values():
		if coat["weapon_id"] == String(weapon_id):
			list.append(coat)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["source"] != b["source"]:
			return a["source"] == SOURCE_OFFICIAL
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return list


static func all() -> Array[Dictionary]:
	_ensure_loaded()
	var list: Array[Dictionary] = []
	list.assign(_coats.values())
	return list


static func coat(coat_id: String) -> Dictionary:
	_ensure_loaded()
	return _coats.get(coat_id, {})


## True when the Coat exists and was made for this weapon.
static func fits(weapon_id: StringName, coat_id: String) -> bool:
	return coat(coat_id).get("weapon_id", "") == String(weapon_id)


## Whether the player may equip the Coat. Everything registered is available until unlocks exist.
static func is_unlocked(coat_id: String) -> bool:
	return not coat(coat_id).is_empty()


## The Coat's texture for a weapon, or null for "" (factory), an unknown Coat, a Coat made for
## another weapon, or a texture that does not match the weapon's Coat layout.
static func texture(weapon_id: StringName, coat_id: String) -> Texture2D:
	if coat_id.is_empty() or not fits(weapon_id, coat_id):
		return null
	if not _textures.has(coat_id):
		_textures[coat_id] = _load_texture(str(coat(coat_id)["texture"]), WeaponModels.coat_size(weapon_id))
	return _textures[coat_id]


## Checks a record ({} problems = valid). Used for both official and custom records.
static func validate(record: Dictionary) -> String:
	for field: String in ["id", "name", "weapon_id", "texture"]:
		if not record.get(field) is String or str(record[field]).is_empty():
			return "A Coat needs a %s." % field
	if not Ids.is_file_id(str(record["id"])):
		return "The Coat ID is not valid."
	if not WeaponModels.has_model(StringName(str(record["weapon_id"]))):
		return "The Coat names a weapon that has no model."
	if not RARITIES.has(str(record.get("rarity", RARITIES[0]))):
		return "Unknown rarity."
	return ""


## Stores a PNG exported from a weapon's Coat kit as a custom Coat. The image must be the kit's
## size (a same-shape image is resized). Returns {"id", "error"}.
static func import_png(weapon_id: StringName, png_path: String, coat_name: String, rarity: String = "standard") -> Dictionary:
	var image := Image.load_from_file(png_path) if FileAccess.file_exists(png_path) else null
	if image == null:
		return {"id": "", "error": "The image could not be read."}
	return register_image(weapon_id, image, coat_name, rarity)


## Stores an image (already in the weapon's Coat layout) as a custom Coat. Returns {"id", "error"}.
static func register_image(weapon_id: StringName, image: Image, coat_name: String, rarity: String = "standard") -> Dictionary:
	var expected := WeaponModels.coat_size(weapon_id)
	if expected == Vector2i.ZERO:
		return {"id": "", "error": "This weapon cannot take Coats."}
	if image.get_size() != expected:
		if not is_equal_approx(float(image.get_width()) / image.get_height(), float(expected.x) / expected.y):
			return {"id": "", "error": "The image is %d x %d; this weapon's Coats are %d x %d." % [
				image.get_width(), image.get_height(), expected.x, expected.y]}
		image = image.duplicate() as Image
		image.resize(expected.x, expected.y, Image.INTERPOLATE_LANCZOS)
	var record := {"id": Ids.generate("coat"), "name": coat_name.strip_edges(), "weapon_id": String(weapon_id),
		"rarity": rarity, "texture": "", "source": SOURCE_CUSTOM, "unlock": ""}
	record["texture"] = custom_dir.path_join(str(record["id"]) + ".png")
	var problem := validate(record)
	if not problem.is_empty():
		return {"id": "", "error": problem}
	var made := DirAccess.make_dir_recursive_absolute(custom_dir)
	if made != OK and not DirAccess.dir_exists_absolute(custom_dir):
		return {"id": "", "error": "Could not create the Coats folder."}
	if image.save_png(str(record["texture"])) != OK:
		return {"id": "", "error": "Could not save the Coat texture."}
	var file := FileAccess.open(custom_dir.path_join(str(record["id"]) + RECORD_EXTENSION), FileAccess.WRITE)
	if file == null:
		return {"id": "", "error": "Could not save the Coat record."}
	file.store_string(JSON.stringify({"format": FORMAT, "format_version": FORMAT_VERSION, "coats": [record]}, "\t"))
	file.close()
	refresh()
	return {"id": record["id"], "error": ""}


## Removes a custom Coat and its texture. Official Coats cannot be removed.
static func remove_custom(coat_id: String) -> bool:
	var record := coat(coat_id)
	if record.get("source", "") != SOURCE_CUSTOM:
		return false
	DirAccess.remove_absolute(str(record["texture"]))
	DirAccess.remove_absolute(custom_dir.path_join(coat_id + RECORD_EXTENSION))
	refresh()
	return true


## Kit conversion: paints zones of a weapon's base texture and returns the full Coat image.
## [param base] is the weapon's factory texture (or any image in its Coat layout).
## [param paint] maps a zone index (kit order, from 0) to a Color (flat paint) or an Image in
## the Coat layout (artwork). White in a zone's mask takes the paint; black keeps the base, so
## stock details outside the zones are never touched.
static func compose(weapon_id: StringName, base: Image, paint: Dictionary) -> Image:
	var expected := WeaponModels.coat_size(weapon_id)
	var result := base.duplicate() as Image
	if result.is_compressed():
		result.decompress()
	result.convert(Image.FORMAT_RGBA8)
	if result.get_size() != expected:
		result.resize(expected.x, expected.y, Image.INTERPOLATE_BILINEAR)
	var zones := WeaponModels.zone_paths(weapon_id)
	for zone: Variant in paint:
		var index := int(zone)
		if index < 0 or index >= zones.size():
			continue
		var mask := zone_mask(weapon_id, index)
		if mask == null:
			continue
		var source: Image
		if paint[zone] is Image:
			source = (paint[zone] as Image).duplicate() as Image
			source.convert(Image.FORMAT_RGBA8)
			if source.get_size() != expected:
				source.resize(expected.x, expected.y, Image.INTERPOLATE_BILINEAR)
		else:
			source = Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
			source.fill(paint[zone] as Color)
		# The mask's brightness becomes the paint's alpha, then the paint is blended over the base.
		var alpha := mask.duplicate() as Image
		alpha.convert(Image.FORMAT_LA8)
		var data := alpha.get_data()
		var pixels := source.get_data()
		for i: int in expected.x * expected.y:
			pixels[i * 4 + 3] = int(pixels[i * 4 + 3] * data[i * 2] / 255.0)
		var layer := Image.create_from_data(expected.x, expected.y, false, Image.FORMAT_RGBA8, pixels)
		result.blend_rect(layer, Rect2i(Vector2i.ZERO, expected), Vector2i.ZERO)
	return result


## A zone's mask at the weapon's Coat size (white = painted), or null if it cannot be read.
static func zone_mask(weapon_id: StringName, zone_index: int) -> Image:
	var paths := WeaponModels.zone_paths(weapon_id)
	if zone_index < 0 or zone_index >= paths.size():
		return null
	var texture_resource := load(paths[zone_index]) as Texture2D
	if texture_resource == null:
		return null
	var image := texture_resource.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	var expected := WeaponModels.coat_size(weapon_id)
	if image.get_size() != expected:
		image.resize(expected.x, expected.y, Image.INTERPOLATE_BILINEAR)
	return image


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_read_records(OFFICIAL_PATH, SOURCE_OFFICIAL)
	var dir := DirAccess.open(custom_dir)
	if dir != null:
		var names := dir.get_files()
		names.sort()
		for file_name: String in names:
			if file_name.ends_with(RECORD_EXTENSION):
				_read_records(custom_dir.path_join(file_name), SOURCE_CUSTOM)


static func _read_records(path: String, source: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return
	var data := json.data as Dictionary
	if data.get("format") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION or not data.get("coats") is Array:
		return
	for raw: Variant in data["coats"] as Array:
		if not raw is Dictionary or not validate(raw as Dictionary).is_empty():
			continue
		var record := (raw as Dictionary).duplicate()
		record["source"] = source
		record["rarity"] = str(record.get("rarity", RARITIES[0]))
		record["unlock"] = str(record.get("unlock", ""))
		if not _coats.has(str(record["id"])):
			_coats[str(record["id"])] = record


static func _load_texture(path: String, expected: Vector2i) -> Texture2D:
	var made: Texture2D = null
	if path.begins_with("res://"):
		made = load(path) as Texture2D if ResourceLoader.exists(path) else null
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			image.generate_mipmaps()
			made = ImageTexture.create_from_image(image)
	if made == null or Vector2i(made.get_size()) != expected:
		return null
	return made
