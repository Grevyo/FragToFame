class_name MagnetCatalog
extends RefCounted
## Every Magnet (weapon sticker) in the game. Each one is a 512 x 512 transparent PNG in
## res://assets/magnets, imported unchanged from the owner's artwork; the ID is "mag_" plus the
## file name. Magnets are applied to weapon slots as decals and are never baked into a Coat.
##
## "rarity" and "unlock" are stored for later (drops, rewards, collections); today every listed
## Magnet is available.

const ASSET_ROOT: String = "res://assets/magnets"
const RARITY_STANDARD: String = "standard"

const IDS: Array[String] = [
	"mag_ace", "mag_astronaut", "mag_checkered_flag", "mag_clutch_shield", "mag_crosshair", "mag_eight_ball",
	"mag_f2f_badge", "mag_flame", "mag_gem_crown", "mag_gg", "mag_ghost", "mag_goggle_bee", "mag_gold_trophy",
	"mag_headset", "mag_lightning_bolts", "mag_mvp", "mag_nt_keycap", "mag_ocean_wave", "mag_overtime",
	"mag_pixel_skull", "mag_plus_one", "mag_red_fox", "mag_rookie_pennant", "mag_space_invader",
	"mag_trophy_shield", "mag_watermelon",
]
## Names that plain capitalisation gets wrong.
const NAMES: Dictionary[String, String] = {
	"mag_f2f_badge": "F2F Badge", "mag_gg": "GG", "mag_mvp": "MVP", "mag_nt_keycap": "NT Keycap", "mag_plus_one": "+1",
}

static var _textures: Dictionary[String, Texture2D] = {}


static func ids() -> Array[String]:
	return IDS.duplicate()


static func has(magnet_id: String) -> bool:
	return IDS.has(magnet_id)


static func display_name(magnet_id: String) -> String:
	if NAMES.has(magnet_id):
		return NAMES[magnet_id]
	return magnet_id.trim_prefix("mag_").replace("_", " ").capitalize()


static func texture_path(magnet_id: String) -> String:
	return "%s/%s.png" % [ASSET_ROOT, magnet_id] if has(magnet_id) else ""


## The Magnet's artwork, or null for an unknown ID.
static func texture(magnet_id: String) -> Texture2D:
	if not has(magnet_id):
		return null
	if not _textures.has(magnet_id):
		_textures[magnet_id] = load(texture_path(magnet_id)) as Texture2D
	return _textures[magnet_id]


static func rarity(_magnet_id: String) -> String:
	return RARITY_STANDARD


## Whether the player may use the Magnet. Everything is available until unlocks exist.
static func is_unlocked(magnet_id: String) -> bool:
	return has(magnet_id)
