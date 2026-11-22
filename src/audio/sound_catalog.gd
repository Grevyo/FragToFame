class_name SoundCatalog
extends RefCounted
## Every sound slot in the game and the recipe [SoundSynth] makes its original effect from
## (Milestone 22). A slot is a stable ID; [SoundLibrary] plays a supplied file of the same name
## in its place when one exists, so any effect can be replaced later without code changes.
##
## Footsteps come in [constant FOOTSTEP_VARIANTS] variants per surface so steps do not repeat.

const FOOTSTEP_VARIANTS: int = 3
const SURFACES: Array[StringName] = [&"stone", &"sand", &"wood", &"metal"]

## Weapon ID -> its shot slot.
const SHOT_FOR: Dictionary[StringName, StringName] = {
	WeaponCatalog.AK47: &"shot_ak47",
	WeaponCatalog.M4A1: &"shot_m4a1",
	WeaponCatalog.SKS: &"shot_sks",
	WeaponCatalog.M14_EBR: &"shot_m14_ebr",
	WeaponCatalog.L118A1: &"shot_l118a1",
	WeaponCatalog.M24: &"shot_m24",
	WeaponCatalog.G17: &"shot_g17",
	WeaponCatalog.M1911: &"shot_m1911",
	WeaponCatalog.MK23: &"shot_mk23",
	WeaponCatalog.DESERT_EAGLE: &"shot_desert_eagle",
}

## Map material ID prefix -> footstep surface (anything else is stone).
const SURFACE_OF_MATERIAL: Dictionary[String, StringName] = {
	"sand": &"sand", "dirt": &"sand", "packed_earth": &"sand", "gravel": &"sand", "grass": &"sand",
	"foliage": &"sand", "burlap": &"sand", "canvas": &"sand", "cloth": &"sand",
	"planks": &"wood", "wood": &"wood", "weathered_wood": &"wood",
	"metal": &"metal", "steel": &"metal", "hazard_paint": &"metal",
}

## How far each kind of sound carries (metres to silence). Shots carry furthest.
const RANGE: Dictionary[StringName, float] = {
	&"shot": 90.0, &"sniper": 140.0, &"explosion": 110.0, &"footstep": 26.0, &"land": 22.0,
	&"reload": 14.0, &"knife": 12.0, &"hit": 20.0, &"bounce": 22.0, &"utility": 45.0, &"bomb": 40.0,
}


## Every slot ID, sorted.
static func slots() -> Array[StringName]:
	var list: Array[StringName] = []
	list.assign(recipes().keys())
	list.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return list


static func has(slot: StringName) -> bool:
	return recipes().has(slot)


## The recipe for [param slot] (empty when unknown).
static func recipe(slot: StringName) -> Dictionary:
	return recipes().get(slot, {})


## The generator's seed for [param slot] (fixed per slot, so regenerating gives the same file).
static func seed_for(slot: StringName) -> int:
	return hash(String(slot)) & 0x7fffffff


## The shot slot for [param weapon_id] ("" for one without a shot sound).
static func shot_for(weapon_id: StringName) -> StringName:
	return SHOT_FOR.get(weapon_id, &"")


## A footstep slot for [param surface], variant [param step] (any integer; wraps).
static func footstep(surface: StringName, step: int) -> StringName:
	var known := surface if SURFACES.has(surface) else &"stone"
	return StringName("step_%s_%d" % [known, posmod(step, FOOTSTEP_VARIANTS) + 1])


## The footstep surface of a map material ID.
static func surface_of(material_id: String) -> StringName:
	for prefix: String in SURFACE_OF_MATERIAL:
		if material_id.begins_with(prefix):
			return SURFACE_OF_MATERIAL[prefix]
	return &"stone"


## Slot ID -> recipe. Built once.
static func recipes() -> Dictionary[StringName, Dictionary]:
	if not _recipes.is_empty():
		return _recipes
	# Shots: [body low-pass Hz, thump Hz, crack decay s, tail decay s, length s, gain of the tail]
	var shots: Dictionary[StringName, Array] = {
		&"shot_ak47": [4200.0, 78.0, 0.07, 0.34, 0.75, 0.42],
		&"shot_m4a1": [6800.0, 105.0, 0.055, 0.28, 0.65, 0.36],
		&"shot_sks": [5200.0, 70.0, 0.08, 0.4, 0.85, 0.45],
		&"shot_m14_ebr": [4800.0, 64.0, 0.085, 0.42, 0.9, 0.48],
		&"shot_l118a1": [3600.0, 48.0, 0.11, 0.75, 1.5, 0.6],
		&"shot_m24": [4000.0, 54.0, 0.1, 0.65, 1.3, 0.55],
		&"shot_g17": [8000.0, 170.0, 0.04, 0.18, 0.4, 0.3],
		&"shot_m1911": [6200.0, 130.0, 0.05, 0.22, 0.45, 0.34],
		&"shot_mk23": [6800.0, 145.0, 0.045, 0.2, 0.42, 0.32],
		&"shot_desert_eagle": [4600.0, 92.0, 0.07, 0.36, 0.7, 0.45],
	}
	for slot: StringName in shots:
		var p: Array = shots[slot]
		_recipes[slot] = {"length": p[4], "layers": [
			{"type": "noise", "gain": 1.0, "attack": 0.0008, "decay": p[2], "lowpass": p[0], "highpass": 120.0},
			{"type": "tone", "gain": 0.9, "attack": 0.001, "decay": float(p[2]) * 1.6, "freq": p[1], "freq_end": float(p[1]) * 0.55},
			{"type": "noise", "gain": p[5], "delay": 0.02, "attack": 0.01, "decay": p[3], "lowpass": 1400.0},
		]}
	_recipes[&"dry_fire"] = {"length": 0.12, "layers": [
		{"type": "tone", "gain": 0.6, "decay": 0.012, "freq": 2600.0, "harmonics": 0.6},
		{"type": "noise", "gain": 0.5, "decay": 0.01, "highpass": 2500.0}]}
	_recipes[&"reload_out"] = {"length": 0.25, "layers": [
		{"type": "tone", "gain": 0.7, "decay": 0.02, "freq": 1900.0, "harmonics": 0.8},
		{"type": "noise", "gain": 0.6, "decay": 0.03, "highpass": 1800.0},
		{"type": "noise", "gain": 0.3, "delay": 0.08, "decay": 0.05, "lowpass": 900.0}]}
	_recipes[&"reload_in"] = {"length": 0.35, "layers": [
		{"type": "noise", "gain": 0.5, "decay": 0.03, "lowpass": 1500.0},
		{"type": "tone", "gain": 0.8, "delay": 0.12, "decay": 0.025, "freq": 1500.0, "harmonics": 0.9},
		{"type": "noise", "gain": 0.7, "delay": 0.12, "decay": 0.03, "highpass": 1500.0}]}
	_recipes[&"weapon_draw"] = {"length": 0.25, "layers": [
		{"type": "noise", "gain": 0.6, "attack": 0.03, "decay": 0.05, "highpass": 2000.0, "lowpass": 7000.0},
		{"type": "tone", "gain": 0.4, "delay": 0.1, "decay": 0.02, "freq": 2200.0, "harmonics": 0.5}]}
	_recipes[&"knife_swing"] = {"length": 0.3, "layers": [
		{"type": "noise", "gain": 1.0, "attack": 0.06, "decay": 0.07, "highpass": 700.0, "lowpass": 3500.0}]}
	_recipes[&"throw"] = {"length": 0.35, "layers": [
		{"type": "noise", "gain": 1.0, "attack": 0.09, "decay": 0.08, "highpass": 400.0, "lowpass": 2200.0}]}
	_recipes[&"hit_body"] = {"length": 0.2, "layers": [
		{"type": "tone", "gain": 1.0, "decay": 0.04, "freq": 160.0, "freq_end": 80.0},
		{"type": "noise", "gain": 0.7, "decay": 0.03, "lowpass": 1300.0}]}
	_recipes[&"hit_head"] = {"length": 0.35, "layers": [
		{"type": "tone", "gain": 0.8, "decay": 0.07, "freq": 1750.0, "harmonics": 0.7},
		{"type": "tone", "gain": 0.8, "decay": 0.04, "freq": 170.0, "freq_end": 90.0},
		{"type": "noise", "gain": 0.5, "decay": 0.025, "highpass": 2500.0}]}
	_recipes[&"hit_confirm"] = {"length": 0.12, "layers": [
		{"type": "tone", "gain": 1.0, "decay": 0.02, "freq": 1300.0}], "peak": 0.5}
	_recipes[&"kill_confirm"] = {"length": 0.3, "layers": [
		{"type": "tone", "gain": 1.0, "decay": 0.05, "freq": 980.0},
		{"type": "tone", "gain": 0.9, "delay": 0.07, "decay": 0.07, "freq": 1470.0}], "peak": 0.55}
	for surface: StringName in SURFACES:
		for variant: int in FOOTSTEP_VARIANTS:
			_recipes[footstep(surface, variant)] = _footstep(surface, variant, 1.0)
	_recipes[&"land"] = _footstep(&"stone", 0, 1.8)
	_recipes[&"grenade_bounce"] = {"length": 0.2, "layers": [
		{"type": "tone", "gain": 0.8, "decay": 0.03, "freq": 640.0, "harmonics": 0.8},
		{"type": "noise", "gain": 0.6, "decay": 0.015, "highpass": 900.0}]}
	_recipes[&"frag_explode"] = {"length": 2.0, "layers": [
		{"type": "noise", "gain": 1.0, "attack": 0.002, "decay": 0.18, "lowpass": 3200.0},
		{"type": "tone", "gain": 1.0, "decay": 0.35, "freq": 52.0, "freq_end": 28.0},
		{"type": "noise", "gain": 0.6, "delay": 0.05, "attack": 0.05, "decay": 0.55, "lowpass": 700.0},
		{"type": "noise", "gain": 0.35, "delay": 0.1, "decay": 0.3, "crackle": 0.8, "lowpass": 5000.0}]}
	_recipes[&"flash_pop"] = {"length": 0.9, "layers": [
		{"type": "noise", "gain": 1.0, "decay": 0.06, "highpass": 1200.0},
		{"type": "tone", "gain": 0.4, "decay": 0.25, "freq": 3100.0, "wobble": 1.0},
		{"type": "tone", "gain": 0.5, "decay": 0.05, "freq": 140.0, "freq_end": 70.0}]}
	_recipes[&"smoke_hiss"] = {"length": 2.4, "layers": [
		{"type": "noise", "gain": 0.4, "decay": 0.03, "lowpass": 1500.0},
		{"type": "noise", "gain": 0.7, "delay": 0.05, "attack": 0.25, "decay": 0.6, "highpass": 2600.0}]}
	_recipes[&"fire_ignite"] = {"length": 1.8, "layers": [
		{"type": "noise", "gain": 0.9, "attack": 0.04, "decay": 0.12, "lowpass": 1800.0},
		{"type": "noise", "gain": 0.6, "delay": 0.05, "attack": 0.2, "decay": 0.5, "lowpass": 900.0},
		{"type": "noise", "gain": 0.6, "delay": 0.1, "decay": 0.5, "crackle": 1.0, "lowpass": 4500.0}]}
	_recipes[&"bomb_beep"] = {"length": 0.16, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.003, "decay": 0.04, "freq": 1650.0}], "peak": 0.6}
	_recipes[&"bomb_planted"] = {"length": 0.6, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.003, "decay": 0.05, "freq": 1100.0},
		{"type": "tone", "gain": 1.0, "delay": 0.16, "attack": 0.003, "decay": 0.05, "freq": 1650.0},
		{"type": "tone", "gain": 1.0, "delay": 0.32, "attack": 0.003, "decay": 0.08, "freq": 2200.0}], "peak": 0.6}
	_recipes[&"bomb_defused"] = {"length": 0.7, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.005, "decay": 0.12, "freq": 700.0, "freq_end": 420.0},
		{"type": "noise", "gain": 0.4, "decay": 0.02, "highpass": 2000.0}], "peak": 0.6}
	_recipes[&"bomb_explode"] = {"length": 3.0, "layers": [
		{"type": "noise", "gain": 1.0, "attack": 0.003, "decay": 0.3, "lowpass": 2600.0},
		{"type": "tone", "gain": 1.0, "decay": 0.6, "freq": 40.0, "freq_end": 22.0},
		{"type": "noise", "gain": 0.7, "delay": 0.08, "attack": 0.08, "decay": 0.9, "lowpass": 500.0},
		{"type": "noise", "gain": 0.4, "delay": 0.15, "decay": 0.5, "crackle": 0.9, "lowpass": 4000.0}]}
	_recipes[&"defuse_tick"] = {"length": 0.08, "layers": [
		{"type": "tone", "gain": 0.6, "decay": 0.008, "freq": 3000.0, "harmonics": 0.4},
		{"type": "noise", "gain": 0.4, "decay": 0.006, "highpass": 3000.0}], "peak": 0.5}
	_recipes[&"round_start"] = {"length": 0.5, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.01, "decay": 0.1, "freq": 660.0, "harmonics": 0.3},
		{"type": "tone", "gain": 1.0, "delay": 0.12, "attack": 0.01, "decay": 0.12, "freq": 990.0, "harmonics": 0.3}], "peak": 0.5}
	_recipes[&"round_end"] = {"length": 0.7, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.01, "decay": 0.15, "freq": 990.0, "harmonics": 0.3},
		{"type": "tone", "gain": 1.0, "delay": 0.15, "attack": 0.01, "decay": 0.2, "freq": 660.0, "harmonics": 0.3}], "peak": 0.5}
	_recipes[&"ui_click"] = {"length": 0.06, "layers": [
		{"type": "tone", "gain": 1.0, "decay": 0.01, "freq": 1250.0},
		{"type": "noise", "gain": 0.3, "decay": 0.004, "highpass": 3000.0}], "peak": 0.4}
	_recipes[&"ui_buy"] = {"length": 0.25, "layers": [
		{"type": "tone", "gain": 1.0, "decay": 0.03, "freq": 1600.0},
		{"type": "tone", "gain": 0.7, "delay": 0.05, "decay": 0.05, "freq": 2400.0}], "peak": 0.45}
	_recipes[&"ui_denied"] = {"length": 0.25, "layers": [
		{"type": "tone", "gain": 1.0, "attack": 0.005, "decay": 0.06, "freq": 220.0, "harmonics": 0.8}], "peak": 0.45}
	return _recipes


static var _recipes: Dictionary[StringName, Dictionary] = {}


static func _footstep(surface: StringName, variant: int, weight: float) -> Dictionary:
	var shift := 1.0 + 0.08 * (variant - 1)
	var layers: Array[Dictionary] = []
	match surface:
		&"sand":
			layers = [{"type": "noise", "gain": 1.0, "attack": 0.012, "decay": 0.06 * weight, "lowpass": 1300.0 * shift, "highpass": 150.0},
				{"type": "noise", "gain": 0.4, "delay": 0.02, "decay": 0.04, "crackle": 0.6, "lowpass": 3000.0}]
		&"wood":
			layers = [{"type": "tone", "gain": 0.9, "decay": 0.05 * weight, "freq": 210.0 * shift, "freq_end": 150.0 * shift, "harmonics": 0.5},
				{"type": "noise", "gain": 0.6, "decay": 0.025, "lowpass": 1800.0}]
		&"metal":
			layers = [{"type": "tone", "gain": 0.7, "decay": 0.09 * weight, "freq": 880.0 * shift, "harmonics": 0.9, "wobble": 0.5},
				{"type": "tone", "gain": 0.5, "decay": 0.06, "freq": 1370.0 * shift},
				{"type": "noise", "gain": 0.6, "decay": 0.02, "highpass": 1500.0}]
		_:
			layers = [{"type": "noise", "gain": 1.0, "decay": 0.035 * weight, "lowpass": 2400.0 * shift, "highpass": 220.0},
				{"type": "tone", "gain": 0.6, "decay": 0.03 * weight, "freq": 120.0 * shift, "freq_end": 80.0}]
	return {"length": 0.25 * weight, "layers": layers}
