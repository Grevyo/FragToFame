class_name WeaponCatalog
extends RefCounted
## The weapons available in the FPS runtime. All names and numbers are original to F2F.
##
## Prices and kill rewards live in [ShopCatalog]; armour handling in [DamageModel].

const VANTA_RIFLE: StringName = &"wpn_vanta_rifle"
const KESTREL_PISTOL: StringName = &"wpn_kestrel_pistol"
const WASP_SMG: StringName = &"wpn_wasp_smg"

## Sandbox loadout order: slot keys 1, 2, 3.
const SANDBOX_LOADOUT: Array[StringName] = [VANTA_RIFLE, KESTREL_PISTOL, WASP_SMG]
## Everyone spawns with this sidearm in matches.
const DEFAULT_SECONDARY: StringName = KESTREL_PISTOL

const DATA: Dictionary[StringName, Dictionary] = {
	VANTA_RIFLE: {
		"id": "wpn_vanta_rifle", "name": "VK-12 Vanta", "slot": 1, "category": "primary",
		"automatic": true, "armour_penetration": 0.78,
		# Measured reference: 215 u/s with a rifle against 250 u/s unencumbered.
		"mobility": 0.86,
		"damage": 34.0, "rpm": 600.0, "magazine": 30, "reserve": 90, "reload_time": 2.5,
		"draw_time": 0.5, "range": 250.0, "falloff_per_10m": 0.97,
		"base_spread": 0.18, "run_spread": 5.0, "air_spread": 9.0, "crouch_multiplier": 0.7,
		"bloom_per_shot": 0.32, "bloom_max": 2.6, "bloom_recovery": 7.0,
		"recovery_delay": 0.12, "recovery_rate": 16.0, "view_punch": 0.5,
		# Climbs for ~9 shots, drifts left, swings right, then wobbles. Learnable, not random.
		"recoil_up": [0.0, 0.95, 1.05, 1.15, 1.15, 1.05, 0.95, 0.8, 0.65, 0.5,
			0.35, 0.25, 0.2, 0.15, 0.1, 0.1, 0.1, 0.05, 0.05, 0.05,
			0.05, 0.05, 0.0, 0.0, 0.05, 0.05, 0.0, 0.0, 0.0, 0.0],
		"recoil_yaw": [0.0, 0.05, -0.05, 0.1, 0.05, -0.1, -0.2, -0.3, -0.4, -0.45,
			-0.5, -0.45, -0.35, 0.2, 0.5, 0.6, 0.6, 0.55, 0.5, 0.35,
			0.1, -0.2, -0.4, -0.45, -0.4, -0.3, 0.1, 0.3, 0.35, 0.3],
	},
	KESTREL_PISTOL: {
		"id": "wpn_kestrel_pistol", "name": "P-4 Kestrel", "slot": 2, "category": "secondary",
		"automatic": false, "armour_penetration": 0.5,
		# Estimate (owner's choice, 2026-11-15): light weapons run at the full 250 u/s; only
		# the unencumbered and rifle speeds were measured.
		"mobility": 1.0,
		"damage": 30.0, "rpm": 380.0, "magazine": 12, "reserve": 36, "reload_time": 2.1,
		"draw_time": 0.35, "range": 150.0, "falloff_per_10m": 0.88,
		"base_spread": 0.25, "run_spread": 2.6, "air_spread": 6.0, "crouch_multiplier": 0.8,
		"bloom_per_shot": 0.7, "bloom_max": 3.0, "bloom_recovery": 5.5,
		"recovery_delay": 0.08, "recovery_rate": 12.0, "view_punch": 0.6,
		"recoil_up": [0.0, 1.6, 1.8, 1.9, 2.0],
		"recoil_yaw": [0.0, 0.1, -0.15, 0.2, -0.2],
	},
	WASP_SMG: {
		"id": "wpn_wasp_smg", "name": "M-5 Wasp", "slot": 3, "category": "primary",
		"automatic": true, "armour_penetration": 0.6,
		"mobility": 1.0,  # Estimate, as for the pistol.
		"damage": 25.0, "rpm": 800.0, "magazine": 25, "reserve": 100, "reload_time": 2.3,
		"draw_time": 0.4, "range": 120.0, "falloff_per_10m": 0.82,
		"base_spread": 0.3, "run_spread": 1.6, "air_spread": 5.0, "crouch_multiplier": 0.8,
		"bloom_per_shot": 0.22, "bloom_max": 2.2, "bloom_recovery": 8.0,
		"recovery_delay": 0.1, "recovery_rate": 15.0, "view_punch": 0.45,
		"recoil_up": [0.0, 0.55, 0.6, 0.65, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2,
			0.15, 0.1, 0.1, 0.05, 0.05, 0.05, 0.05, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0],
		"recoil_yaw": [0.0, 0.1, 0.15, -0.1, -0.2, -0.25, -0.2, 0.1, 0.3, 0.35,
			0.3, 0.1, -0.2, -0.3, -0.3, -0.1, 0.2, 0.3, 0.25, 0.0,
			-0.2, -0.3, -0.2, 0.1, 0.2],
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
