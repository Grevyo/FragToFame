class_name MapSkies
extends RefCounted
## The sky panoramas a map can use (lighting key "sky"). Each is an original painted panorama in
## res://assets/skies (made by tools/generate_skies.py); the sun or moon is drawn on top by
## map_sky.gdshader where the map's lighting puts it. An empty or unknown ID keeps the plain sky
## tinted from the sun and ambient colours.

const DIRECTORY: String = "res://assets/skies"
const SHADER_PATH: String = "res://src/maps/map_sky.gdshader"
## id -> label, file and shader settings. Order is the order shown in the Creation Studio.
const SKIES: Dictionary[String, Dictionary] = {
	"hazy_noon": {"label": "Hazy noon, dry hills", "file": "hazy_noon.webp",
		"energy": 1.0, "disc_energy": 10.0, "disc_size": 0.9, "glow": 0.7, "horizon_glow": 0.0},
	"harbour_fair": {"label": "Fair weather over the sea", "file": "harbour_fair.webp",
		"energy": 1.0, "disc_energy": 10.0, "disc_size": 0.9, "glow": 0.6, "horizon_glow": 0.0},
	"overcast_works": {"label": "Overcast, industrial plain", "file": "overcast_works.webp",
		"energy": 1.0, "disc_energy": 1.2, "disc_size": 1.6, "glow": 0.25, "horizon_glow": 0.0},
	"highland_afternoon": {"label": "Highland afternoon, mountains", "file": "highland_afternoon.webp",
		"energy": 1.0, "disc_energy": 9.0, "disc_size": 0.9, "glow": 0.8, "horizon_glow": 0.1},
	"english_grey": {"label": "Soft grey, open fields", "file": "english_grey.webp",
		"energy": 1.0, "disc_energy": 2.0, "disc_size": 1.4, "glow": 0.35, "horizon_glow": 0.0},
	"fen_summer": {"label": "Late summer over the fens", "file": "fen_summer.webp",
		"energy": 1.0, "disc_energy": 10.0, "disc_size": 0.9, "glow": 0.7, "horizon_glow": 0.0},
	"city_dusk": {"label": "Dusk over a city, from a tower", "file": "city_dusk.webp",
		"energy": 1.0, "disc_energy": 7.0, "disc_size": 1.1, "glow": 1.0, "horizon_glow": 0.6},
	"desert_night": {"label": "Starry desert night", "file": "desert_night.webp",
		"energy": 1.0, "disc_energy": 3.5, "disc_size": 1.0, "glow": 0.5, "horizon_glow": 0.0},
}

static var _textures: Dictionary[String, Texture2D] = {}


static func ids() -> Array[String]:
	var list: Array[String] = []
	list.assign(SKIES.keys())
	return list


static func has(sky_id: String) -> bool:
	return SKIES.has(sky_id)


static func label(sky_id: String) -> String:
	return str(SKIES[sky_id]["label"]) if SKIES.has(sky_id) else "Plain (tinted by the sun)"


## The panorama texture, or null when the ID is unknown or the file is missing.
static func texture(sky_id: String) -> Texture2D:
	if not SKIES.has(sky_id):
		return null
	if not _textures.has(sky_id):
		var path := DIRECTORY.path_join(str(SKIES[sky_id]["file"]))
		_textures[sky_id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[sky_id]


## A sky material for the ID, or null to fall back to the plain sky.
static func material(sky_id: String) -> ShaderMaterial:
	var panorama := texture(sky_id)
	if panorama == null:
		return null
	var entry: Dictionary = SKIES[sky_id]
	var result := ShaderMaterial.new()
	result.shader = load(SHADER_PATH) as Shader
	result.set_shader_parameter(&"panorama", panorama)
	for key: String in ["energy", "disc_energy", "disc_size", "glow", "horizon_glow"]:
		result.set_shader_parameter(StringName(key), float(entry[key]))
	return result
