class_name WeaponCatalog
extends RefCounted
## The ten modelled weapons available in the FPS runtime. Balance numbers are F2F's own.
##
## Prices and kill rewards live in [ShopCatalog]; armour handling in [DamageModel].

const AK47: StringName = &"wpn_ak47"
const M4A1: StringName = &"wpn_m4a1"
const SKS: StringName = &"wpn_sks"
const M14_EBR: StringName = &"wpn_m14_ebr"
const L118A1: StringName = &"wpn_l118a1"
const M24: StringName = &"wpn_m24"
const G17: StringName = &"wpn_g17"
const M1911: StringName = &"wpn_m1911"
const MK23: StringName = &"wpn_mk23"
const DESERT_EAGLE: StringName = &"wpn_desert_eagle"

## Sandbox loadout: primary in slot 1, secondary in slot 2.
const SANDBOX_LOADOUT: Array[StringName] = [AK47, G17]
## Everyone spawns with this sidearm in matches.
const DEFAULT_SECONDARY: StringName = G17

## Recognise weapon IDs already stored in match statistics.
const RETIRED_NAMES: Dictionary[StringName, String] = {
	&"wpn_vanta_rifle": "VK-12 Vanta",
	&"wpn_kestrel_pistol": "P-4 Kestrel",
	&"wpn_wasp_smg": "M-5 Wasp",
}

const DATA: Dictionary[StringName, Dictionary] = {
	AK47: {
		"id": "wpn_ak47", "name": "AK-47", "slot": 1, "category": "primary",
		"automatic": true, "armour_penetration": 0.78, "mobility": 0.86,
		"damage": 36, "rpm": 600, "magazine": 30, "reserve": 90, "reload_time": 2.5,
		"draw_time": 0.5, "range": 250, "falloff_per_10m": 0.97,
		"base_spread": 0.2, "run_spread": 5.2, "air_spread": 9, "crouch_multiplier": 0.7,
		"bloom_per_shot": 0.34, "bloom_max": 2.8, "bloom_recovery": 7,
		"recovery_delay": 0.12, "recovery_rate": 15, "view_punch": 0.55,
		"recoil_up": [0, 1.026, 1.134, 1.242, 1.242, 1.134, 1.026, 0.864, 0.702, 0.54, 0.378, 0.27, 0.216, 0.162, 0.108, 0.108, 0.108, 0.054, 0.054, 0.054, 0.054, 0.054, 0, 0, 0.054, 0.054, 0, 0, 0, 0],
		"recoil_yaw": [0, 0.05, -0.05, 0.1, 0.05, -0.1, -0.2, -0.3, -0.4, -0.45, -0.5, -0.45, -0.35, 0.2, 0.5, 0.6, 0.6, 0.55, 0.5, 0.35, 0.1, -0.2, -0.4, -0.45, -0.4, -0.3, 0.1, 0.3, 0.35, 0.3],
	},
	M4A1: {
		"id": "wpn_m4a1", "name": "M4A1", "slot": 1, "category": "primary",
		"automatic": true, "armour_penetration": 0.7, "mobility": 0.86,
		"damage": 31, "rpm": 667, "magazine": 30, "reserve": 90, "reload_time": 2.4,
		"draw_time": 0.5, "range": 250, "falloff_per_10m": 0.96,
		"base_spread": 0.16, "run_spread": 4.8, "air_spread": 9, "crouch_multiplier": 0.7,
		"bloom_per_shot": 0.28, "bloom_max": 2.4, "bloom_recovery": 7.5,
		"recovery_delay": 0.11, "recovery_rate": 17, "view_punch": 0.45,
		"recoil_up": [0, 0.836, 0.924, 1.012, 1.012, 0.924, 0.836, 0.704, 0.572, 0.44, 0.308, 0.22, 0.176, 0.132, 0.088, 0.088, 0.088, 0.044, 0.044, 0.044, 0.044, 0.044, 0, 0, 0.044, 0.044, 0, 0, 0, 0],
		"recoil_yaw": [-0, -0.045, 0.045, -0.09, -0.045, 0.09, 0.18, 0.27, 0.36, 0.405, 0.45, 0.405, 0.315, -0.18, -0.45, -0.54, -0.54, -0.495, -0.45, -0.315, -0.09, 0.18, 0.36, 0.405, 0.36, 0.27, -0.09, -0.27, -0.315, -0.27],
	},
	SKS: {
		"id": "wpn_sks", "name": "SKS", "slot": 1, "category": "primary",
		"automatic": false, "armour_penetration": 0.8, "mobility": 0.86,
		"damage": 48, "rpm": 300, "magazine": 10, "reserve": 40, "reload_time": 2.8,
		"draw_time": 0.55, "range": 300, "falloff_per_10m": 0.98,
		"base_spread": 0.12, "run_spread": 5.5, "air_spread": 10, "crouch_multiplier": 0.65,
		"bloom_per_shot": 0.9, "bloom_max": 3.2, "bloom_recovery": 5,
		"recovery_delay": 0.15, "recovery_rate": 11, "view_punch": 0.7,
		"recoil_up": [0, 1.9, 2.1, 2.2, 2.2],
		"recoil_yaw": [0, 0.15, -0.2, 0.25, -0.2],
	},
	M14_EBR: {
		"id": "wpn_m14_ebr", "name": "M14 EBR", "slot": 1, "category": "primary",
		"automatic": false, "armour_penetration": 0.85, "mobility": 0.82,
		"damage": 55, "rpm": 280, "magazine": 20, "reserve": 40, "reload_time": 3,
		"draw_time": 0.6, "range": 350, "falloff_per_10m": 0.985,
		"base_spread": 0.08, "run_spread": 6, "air_spread": 11, "crouch_multiplier": 0.6,
		"bloom_per_shot": 1, "bloom_max": 3.4, "bloom_recovery": 4.8,
		"recovery_delay": 0.16, "recovery_rate": 10, "view_punch": 0.75,
		"recoil_up": [0, 2.1, 2.3, 2.4, 2.4],
		"recoil_yaw": [0, -0.15, 0.2, -0.25, 0.2],
	},
	L118A1: {
		"id": "wpn_l118a1", "name": "L118A1", "slot": 1, "category": "primary",
		"automatic": false, "armour_penetration": 0.97, "mobility": 0.8,
		"damage": 115, "rpm": 40, "magazine": 10, "reserve": 20, "reload_time": 3.6,
		"draw_time": 0.8, "range": 500, "falloff_per_10m": 1,
		"base_spread": 0.04, "run_spread": 8, "air_spread": 14, "crouch_multiplier": 0.5,
		"bloom_per_shot": 3, "bloom_max": 4, "bloom_recovery": 3,
		"recovery_delay": 0.3, "recovery_rate": 6, "view_punch": 1.2,
		"recoil_up": [0, 4],
		"recoil_yaw": [0, 0.3],
	},
	M24: {
		"id": "wpn_m24", "name": "M24", "slot": 1, "category": "primary",
		"automatic": false, "armour_penetration": 0.95, "mobility": 0.82,
		"damage": 105, "rpm": 45, "magazine": 5, "reserve": 20, "reload_time": 3.4,
		"draw_time": 0.75, "range": 500, "falloff_per_10m": 1,
		"base_spread": 0.05, "run_spread": 7.5, "air_spread": 13, "crouch_multiplier": 0.5,
		"bloom_per_shot": 2.8, "bloom_max": 4, "bloom_recovery": 3.2,
		"recovery_delay": 0.28, "recovery_rate": 6.5, "view_punch": 1.1,
		"recoil_up": [0, 3.6],
		"recoil_yaw": [0, -0.3],
	},
	G17: {
		"id": "wpn_g17", "name": "G17", "slot": 2, "category": "secondary",
		"automatic": false, "armour_penetration": 0.5, "mobility": 1,
		"damage": 28, "rpm": 400, "magazine": 17, "reserve": 51, "reload_time": 2,
		"draw_time": 0.35, "range": 150, "falloff_per_10m": 0.88,
		"base_spread": 0.25, "run_spread": 2.5, "air_spread": 6, "crouch_multiplier": 0.8,
		"bloom_per_shot": 0.65, "bloom_max": 2.8, "bloom_recovery": 5.8,
		"recovery_delay": 0.08, "recovery_rate": 12.5, "view_punch": 0.55,
		"recoil_up": [0, 1.5, 1.7, 1.8, 1.9],
		"recoil_yaw": [0, 0.1, -0.15, 0.2, -0.2],
	},
	M1911: {
		"id": "wpn_m1911", "name": "M1911", "slot": 2, "category": "secondary",
		"automatic": false, "armour_penetration": 0.58, "mobility": 1,
		"damage": 36, "rpm": 330, "magazine": 7, "reserve": 28, "reload_time": 2.1,
		"draw_time": 0.38, "range": 150, "falloff_per_10m": 0.9,
		"base_spread": 0.24, "run_spread": 2.7, "air_spread": 6.2, "crouch_multiplier": 0.8,
		"bloom_per_shot": 0.85, "bloom_max": 3.1, "bloom_recovery": 5.2,
		"recovery_delay": 0.09, "recovery_rate": 11.5, "view_punch": 0.7,
		"recoil_up": [0, 2, 2.2, 2.3, 2.4],
		"recoil_yaw": [0, -0.12, 0.18, -0.22, 0.2],
	},
	MK23: {
		"id": "wpn_mk23", "name": "Mk23 SOCOM", "slot": 2, "category": "secondary",
		"automatic": false, "armour_penetration": 0.55, "mobility": 1,
		"damage": 33, "rpm": 350, "magazine": 12, "reserve": 36, "reload_time": 2.2,
		"draw_time": 0.42, "range": 160, "falloff_per_10m": 0.9,
		"base_spread": 0.22, "run_spread": 2.8, "air_spread": 6.4, "crouch_multiplier": 0.8,
		"bloom_per_shot": 0.7, "bloom_max": 2.9, "bloom_recovery": 5.6,
		"recovery_delay": 0.08, "recovery_rate": 12, "view_punch": 0.6,
		"recoil_up": [0, 1.7, 1.9, 2, 2.1],
		"recoil_yaw": [0, 0.1, -0.14, 0.18, -0.18],
	},
	DESERT_EAGLE: {
		"id": "wpn_desert_eagle", "name": "Desert Eagle", "slot": 2, "category": "secondary",
		"automatic": false, "armour_penetration": 0.85, "mobility": 1,
		"damage": 58, "rpm": 220, "magazine": 7, "reserve": 21, "reload_time": 2.3,
		"draw_time": 0.45, "range": 200, "falloff_per_10m": 0.93,
		"base_spread": 0.28, "run_spread": 3.4, "air_spread": 7.5, "crouch_multiplier": 0.8,
		"bloom_per_shot": 1.6, "bloom_max": 4, "bloom_recovery": 4.2,
		"recovery_delay": 0.12, "recovery_rate": 9, "view_punch": 1,
		"recoil_up": [0, 3.2, 3.5, 3.6, 3.6],
		"recoil_yaw": [0, 0.25, -0.3, 0.35, -0.3],
	},
}

static var _cache: Dictionary[StringName, WeaponDefinition] = {}


static func ids() -> Array[StringName]:
	var list: Array[StringName] = []
	for id: StringName in DATA:
		list.append(id)
	return list


static func has(id: StringName) -> bool:
	return DATA.has(id)


## Returns the shared, read-only definition for [param id], or null if unknown.
static func get_definition(id: StringName) -> WeaponDefinition:
	if not DATA.has(id):
		return null
	if not _cache.has(id):
		_cache[id] = WeaponDefinition.from_dict(DATA[id])
	return _cache[id]


## Display label for a recorded weapon, including retired weapons in older saves.
static func recorded_name(id: StringName) -> String:
	var definition := get_definition(id)
	return definition.display_name if definition != null else RETIRED_NAMES.get(id, String(id))
