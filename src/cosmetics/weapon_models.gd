class_name WeaponModels
extends RefCounted
## Presentation data for every weapon that has a 3D model: where the model is, how to turn and
## scale it into the game's weapon space, its Coat texture layout and its five Magnet slots.
## Gameplay numbers stay in WeaponCatalog; nothing here affects how a weapon shoots.
##
## Weapon space (what WeaponVisual produces): barrel along -Z with the muzzle at -Z, up +Y, the
## weapon's LEFT side facing -X, centred on the model's bounds, [code]length[/code] metres long.
##
## "rotation" is the Euler rotation (degrees) that brings the raw model into that orientation.
## "coat_size" is the pixel size of the weapon's Coat texture (the size its kit exports).
## "kit" is the folder under authoring/coat_kits. "zones" are the kit's paint-zone masks, shipped
## in assets/weapons/<id>/zones for Coat composition.
## "slots" are the five Magnet slots: side ("left" / "right"), "z" along the weapon (-0.5 muzzle
## … 0.5 butt, as a share of its length), "y" up the weapon (-0.5 … 0.5, share of its height)
## and "size" in metres. tools/build_magnet_slots.gd projects them onto the mesh and stores the
## surface points in data/weapons/magnet_slots.json.

const SLOT_COUNT: int = 5
const ASSET_ROOT: String = "res://assets/weapons"
const SLOT_DATA_PATH: String = "res://data/weapons/magnet_slots.json"
const SLOT_FORMAT: String = "f2f.magnet_slots"
const SLOT_FORMAT_VERSION: int = 1

const DATA: Dictionary[StringName, Dictionary] = {
	&"wpn_ak47": {
		"rotation": Vector3(0, 0, 0), "length": 0.88, "kit": "AK-47", "coat_size": Vector2i(1024, 1024),
		"zones": ["01_receiver_and_cover", "02_handguard", "03_stock", "04_grip", "05_magazine", "06_barrel"],
		"slots": [["left", 0.05, 0.3, 0.045], ["left", 0.38, 0.17, 0.05], ["left", -0.17, 0.3, 0.035],
			["right", 0.05, 0.3, 0.045], ["right", 0.38, 0.17, 0.05]],
		"credit": {"title": "AK-47", "author": "", "license": "", "source": ""},
	},
	&"wpn_m4a1": {
		"rotation": Vector3(0, 0, 0), "length": 0.84, "kit": "M4A1", "coat_size": Vector2i(2048, 979),
		"zones": ["01_receiver_and_grip", "02_stock", "03_handguard", "04_magazine", "05_barrel"],
		"slots": [["left", 0.05, 0.2, 0.045], ["left", 0.38, 0.2, 0.045], ["left", -0.2, 0.33, 0.035],
			["right", 0.05, 0.2, 0.045], ["right", 0.38, 0.2, 0.045]],
		"credit": {"title": "M4A1", "author": "", "license": "", "source": ""},
	},
	&"wpn_desert_eagle": {
		"rotation": Vector3(0, 90, 0), "length": 0.27, "kit": "Desert-Eagle", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_slide_and_upper", "02_frame", "03_grip_panels"],
		"slots": [["left", -0.28, 0.33, 0.028], ["left", 0.05, 0.33, 0.028], ["left", 0.27, -0.15, 0.03],
			["right", -0.28, 0.33, 0.028], ["right", 0.27, -0.15, 0.03]],
		"credit": {"title": "Low-Poly Desert Eagle", "author": "TastyTony (https://sketchfab.com/TastyTony)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/low-poly-desert-eagle-b81da261345f4462b2c4412352162287"},
	},
	&"wpn_g17": {
		"rotation": Vector3(0, 90, 0), "length": 0.2, "kit": "G17", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_slide", "02_frame_and_grip", "03_barrel"],
		"slots": [["left", -0.25, 0.35, 0.024], ["left", 0.12, 0.35, 0.024], ["left", 0.3, -0.2, 0.026],
			["right", -0.25, 0.35, 0.024], ["right", 0.3, -0.2, 0.026]],
		"credit": {"title": "Low-Poly G17", "author": "TastyTony (https://sketchfab.com/TastyTony)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/low-poly-g17-60efc54ac59e47d18bdff94b2f5144ff"},
	},
	&"wpn_m1911": {
		"rotation": Vector3(0, 90, 0), "length": 0.22, "kit": "M1911", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_slide", "02_frame", "03_grip_panels"],
		"slots": [["left", -0.25, 0.33, 0.024], ["left", 0.1, 0.33, 0.024], ["left", 0.3, -0.12, 0.026],
			["right", -0.25, 0.33, 0.024], ["right", 0.3, -0.12, 0.026]],
		"credit": {"title": "Low-Poly M1911", "author": "TastyTony (https://sketchfab.com/TastyTony)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/low-poly-m1911-117f542d21954ae0a59afaedadcff338"},
	},
	&"wpn_mk23": {
		"rotation": Vector3(0, 0, 0), "length": 0.42, "kit": "Mk23-SOCOM", "coat_size": Vector2i(2048, 2048),
		# The source file lays the suppressor, a spare aiming module and a loose round beside the pistol.
		"hide": ["round_7", "LAM_old_16", "thread_protector_1"],
		"align": {"suppressor_base_2": "barrel_18", "suppressor_body_3": "barrel_18"},
		"zones": ["01_slide", "02_frame", "03_grip_texture", "04_suppressor", "05_magazine_base", "06_accessory_housings"],
		"slots": [["left", 0.2, 0.3, 0.026], ["left", -0.3, 0.33, 0.024], ["left", 0.38, -0.2, 0.026],
			["right", 0.2, 0.3, 0.026], ["right", -0.3, 0.33, 0.024]],
		"credit": {"title": "Low-Poly Mk23 Mod0", "author": "notcplkerry (https://sketchfab.com/notcplkerry)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/low-poly-mk23-mod0-9698a59bea1d4504a8ca6f8c79455671"},
	},
	&"wpn_l118a1": {
		"rotation": Vector3(0, 90, 0), "length": 1.18, "kit": "L118A1", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_stock_and_chassis", "02_barrel_and_action", "03_buttplate", "04_magazine", "05_scope_housing"],
		"slots": [["left", -0.08, -0.02, 0.04], ["left", 0.12, -0.08, 0.04], ["left", 0.4, -0.15, 0.05],
			["right", -0.08, -0.02, 0.04], ["right", 0.4, -0.15, 0.05]],
		"credit": {"title": "Low-Poly L118A1", "author": "TastyTony (https://sketchfab.com/TastyTony)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/low-poly-l118a1-5e2f001d6e6245bcacf2b1e2de8892f4"},
	},
	&"wpn_m24": {
		"rotation": Vector3(0, 180, 0), "length": 1.09, "kit": "M24", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_stock_and_chassis", "02_barrel_and_action", "03_buttplate", "04_bolt_and_stock_hardware"],
		"slots": [["left", -0.12, 0.22, 0.035], ["left", 0.1, 0.15, 0.035], ["left", 0.4, 0.02, 0.05],
			["right", -0.12, 0.22, 0.035], ["right", 0.4, 0.02, 0.05]],
		"credit": {"title": "M24 Low-Poly", "author": "GoldbergR (https://sketchfab.com/GoldbergR)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/m24-low-poly-1244656c19994cbe9126f2e0bb8dfbbe"},
	},
	&"wpn_sks": {
		"rotation": Vector3(0, 0, 0), "length": 1.02, "kit": "SKS", "coat_size": Vector2i(2048, 2048),
		"zones": ["01_wood_stock", "02_handguard", "03_receiver_and_cover", "04_magazine", "05_barrel"],
		"slots": [["left", -0.15, 0.15, 0.035], ["left", 0.08, 0.12, 0.035], ["left", 0.4, -0.1, 0.05],
			["right", -0.15, 0.15, 0.035], ["right", 0.4, -0.1, 0.05]],
		"credit": {"title": "Russian SKS", "author": "raveenpath45 (https://sketchfab.com/raveenpath45)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/russian-sks-2f44bffbd75a4b359fe1d2538b5d6d10"},
	},
	&"wpn_m14_ebr": {
		"rotation": Vector3(0, 0, 0), "length": 1.0, "kit": "M14-EBR", "coat_size": Vector2i(4096, 4096),
		"zones": ["01_receiver_and_rail", "02_handguard_panel", "03_grips", "04_magazine", "05_barrel", "06_stock_assembly", "07_scope_housing"],
		"slots": [["left", -0.16, 0.1, 0.035], ["left", 0.0, 0.05, 0.035], ["left", 0.09, -0.25, 0.035],
			["right", -0.16, 0.1, 0.035], ["right", 0.0, 0.05, 0.035]],
		"credit": {"title": "M14 EBR", "author": "3dartist63 (https://sketchfab.com/3dartist63)", "license": "CC-BY-4.0",
			"source": "https://sketchfab.com/3d-models/m14-ebr-4d3b43b49c69441881cc565fb341bcb1"},
	},
}

static var _slot_cache: Dictionary = {}


static func ids() -> Array[StringName]:
	var list: Array[StringName] = []
	list.assign(DATA.keys())
	return list


static func has_model(weapon_id: StringName) -> bool:
	return DATA.has(weapon_id)


static func info(weapon_id: StringName) -> Dictionary:
	return DATA.get(weapon_id, {})


static func model_path(weapon_id: StringName) -> String:
	return "%s/%s/model.glb" % [ASSET_ROOT, weapon_id]


static func coat_size(weapon_id: StringName) -> Vector2i:
	return info(weapon_id).get("coat_size", Vector2i.ZERO)


## Paint-zone mask paths of the weapon's Coat kit, in kit order.
static func zone_paths(weapon_id: StringName) -> Array[String]:
	var list: Array[String] = []
	for zone: String in info(weapon_id).get("zones", []):
		list.append("%s/%s/zones/%s.png" % [ASSET_ROOT, weapon_id, zone])
	return list


## Readable zone names ("Receiver and cover"), in kit order.
static func zone_names(weapon_id: StringName) -> Array[String]:
	var list: Array[String] = []
	for zone: String in info(weapon_id).get("zones", []):
		list.append(zone.substr(3).replace("_", " ").capitalize())
	return list


## The authored slot layout: [{"side", "z", "y", "size"}] (always five).
static func slot_specs(weapon_id: StringName) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for spec: Array in info(weapon_id).get("slots", []):
		list.append({"side": spec[0], "z": float(spec[1]), "y": float(spec[2]), "size": float(spec[3])})
	return list


## The slots projected onto the mesh, in weapon space: [{"position", "normal", "size", "uv"}].
## "uv" is the Coat texture coordinate under the slot (which part of a Coat a Magnet sits on).
## Empty until tools/build_magnet_slots.gd has been run for the weapon.
static func slots(weapon_id: StringName) -> Array[Dictionary]:
	if _slot_cache.is_empty():
		_load_slots()
	var list: Array[Dictionary] = []
	list.assign(_slot_cache.get(String(weapon_id), []))
	return list


static func _load_slots() -> void:
	_slot_cache = {"_loaded": []}
	if not FileAccess.file_exists(SLOT_DATA_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SLOT_DATA_PATH)) != OK or not json.data is Dictionary:
		return
	var data := json.data as Dictionary
	if data.get("format") != SLOT_FORMAT or int(data.get("format_version", 0)) != SLOT_FORMAT_VERSION:
		return
	var weapons := data.get("weapons", {}) as Dictionary
	for weapon_id: String in weapons:
		var list: Array[Dictionary] = []
		for raw: Dictionary in weapons[weapon_id] as Array:
			var p := raw["position"] as Array
			var n := raw["normal"] as Array
			var uv := raw.get("uv", [0.0, 0.0]) as Array
			list.append({"position": Vector3(p[0], p[1], p[2]), "normal": Vector3(n[0], n[1], n[2]), "size": float(raw["size"]),
				"uv": Vector2(uv[0], uv[1])})
		_slot_cache[weapon_id] = list
