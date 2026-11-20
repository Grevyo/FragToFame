class_name EquipmentCatalog
extends RefCounted
## The knife and the four kinds of thrown utility, as data. Balance numbers are F2F's own.
##
## [WeaponCatalog.get_definition] serves these too, so the loadout, kill feed and statistics
## treat them like any other weapon. Prices live in [ShopCatalog]. Which knife model a player
## holds is cosmetic only (see [CosmeticProfile]); every knife plays the same.
##
## Utility detonation ("detonate"):
##   "fuse"   explodes after "fuse" seconds wherever it is (frag, flash)
##   "rest"   pops once it has come to rest, but no sooner than "fuse" seconds (smoke)
##   "impact" bursts on the first floor it touches, or after "fuse" seconds in the air (fire)

const KNIFE: StringName = &"wpn_knife"
const FRAG: StringName = &"utl_frag"
const FLASH: StringName = &"utl_flash"
const SMOKE: StringName = &"utl_smoke"
const FIRE: StringName = &"utl_fire"

const KIND_FRAG: StringName = &"frag"
const KIND_FLASH: StringName = &"flash"
const KIND_SMOKE: StringName = &"smoke"
const KIND_FIRE: StringName = &"fire"

## Utility in shop and HUD order.
const UTILITY: Array[StringName] = [FLASH, SMOKE, FRAG, FIRE]
## Most pieces of utility one player may carry at once.
const UTILITY_CARRY_LIMIT: int = 4
## Loadout key for the utility slot (the knife uses 3).
const UTILITY_SLOT: int = 4

## Throw speeds (m/s) for the three throws: both buttons, left only, right only.
const THROW_SPEED_FULL: float = 19.0
const THROW_SPEED_MEDIUM: float = 12.5
const THROW_SPEED_LOB: float = 6.5
## Throws leave a little above the crosshair, the way an arm releases.
const THROW_LIFT_DEGREES: float = 6.0
## Share of the thrower's own velocity the grenade inherits.
const THROW_INHERIT: float = 1.0

const DATA: Dictionary[StringName, Dictionary] = {
	KNIFE: {
		"id": "wpn_knife", "name": "Knife", "slot": 3, "category": "melee",
		"automatic": true, "armour_penetration": 0.85, "mobility": 1.0, "draw_time": 0.4,
		"magazine": 0, "reserve": 0, "range": 1.7,
		"equipment": {
			# Quick slash (left button, repeats while held) and heavy stab (right button).
			"light": {"damage": 34, "backstab": 90, "interval": 0.42, "first_interval": 0.32, "range": 1.7},
			"heavy": {"damage": 62, "backstab": 180, "interval": 1.05, "range": 1.45},
			# A hit counts as from behind when the victim faces within this many degrees of the swing.
			"backstab_angle": 60.0,
		},
	},
	FLASH: {
		"id": "utl_flash", "name": "Flashbang", "slot": UTILITY_SLOT, "category": "utility",
		"automatic": false, "mobility": 0.98, "draw_time": 0.55, "magazine": 2, "reserve": 0,
		"equipment": {
			"kind": "flash", "detonate": "fuse", "fuse": 1.55,
			# Full blindness for someone looking straight at it up close; less when turned away,
			# further off, or behind cover (the flash needs a clear line to the eyes).
			"max_blind": 4.8, "range": 24.0, "full_range": 5.0, "behind_share": 0.22,
			"colour": Color(0.86, 0.88, 0.9),
		},
	},
	SMOKE: {
		"id": "utl_smoke", "name": "Smoke grenade", "slot": UTILITY_SLOT, "category": "utility",
		"automatic": false, "mobility": 0.98, "draw_time": 0.55, "magazine": 1, "reserve": 0,
		"equipment": {
			"kind": "smoke", "detonate": "rest", "fuse": 1.4, "max_fuse": 6.0,
			"radius": 3.1, "height": 3.3, "bloom": 1.1, "duration": 17.5, "fade": 2.0,
			"colour": Color(0.55, 0.6, 0.58),
		},
	},
	FRAG: {
		"id": "utl_frag", "name": "Frag grenade", "slot": UTILITY_SLOT, "category": "utility",
		"automatic": false, "mobility": 0.98, "draw_time": 0.55, "magazine": 1, "reserve": 0,
		"armour_penetration": 0.55,
		"equipment": {
			"kind": "frag", "detonate": "fuse", "fuse": 1.6,
			# Damage falls from "damage" at the centre to nothing at "radius"; walls block it.
			"damage": 98, "radius": 7.5,
			"colour": Color(0.32, 0.38, 0.24),
		},
	},
	FIRE: {
		"id": "utl_fire", "name": "Incendiary", "slot": UTILITY_SLOT, "category": "utility",
		"automatic": false, "mobility": 0.98, "draw_time": 0.55, "magazine": 1, "reserve": 0,
		"armour_penetration": 1.0,
		"equipment": {
			"kind": "fire", "detonate": "impact", "fuse": 2.0,
			# Burning floor: patches spread over the ground within "radius" of the burst (never up
			# walls or over drops of more than "step" metres) and burn for "duration" seconds.
			"radius": 3.2, "step": 0.7, "duration": 7.0, "dps": 38.0, "tick": 0.25,
			# A burst in the air drops this far to find a floor, otherwise it fizzles.
			"drop": 3.0,
			"colour": Color(0.7, 0.32, 0.12),
		},
	},
}


static func is_utility(id: StringName) -> bool:
	return UTILITY.has(id)


static func utility_kind(id: StringName) -> StringName:
	return StringName(str(DATA.get(id, {}).get("equipment", {}).get("kind", "")))


## Most of [param id] one player may carry (2 flashbangs, 1 of everything else).
static func carry_limit(id: StringName) -> int:
	return int(DATA.get(id, {}).get("magazine", 0)) if is_utility(id) else 0


static func params(id: StringName) -> Dictionary:
	return DATA.get(id, {}).get("equipment", {})
