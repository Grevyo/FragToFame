class_name InspectLibrary
extends RefCounted
## Weapon inspections as data: each is a short choreography of poses the viewmodel moves
## through when the player presses Inspect. Presentation only.
##
## A pose key is {"t": 0..1 share of the inspection, "pos": metres added to the viewmodel,
## "rot": degrees (x pitch, y yaw, z roll) added to it}. Keys may also turn the item about a
## point other than its centre: "pivot" is that point as a share of the item's size in weapon
## space (z -0.5 = muzzle / blade tip … 0.5 = butt / pommel). Between keys poses ease in and out.
## Every inspection starts and ends at rest (t 0 and t 1 have no offset).
##
## Weapons without an entry use [constant DEFAULT] (show the left side, then the right).

const DEFAULT_SECONDS: float = 3.2

const DEFAULT: Dictionary = {
	"seconds": DEFAULT_SECONDS,
	"keys": [
		{"t": 0.0},
		{"t": 0.15, "pos": Vector3(-0.15, 0.07, -0.12), "rot": Vector3(8, 0, 0)},
		{"t": 0.35, "pos": Vector3(-0.15, 0.07, -0.12), "rot": Vector3(8, -75, 12)},
		{"t": 0.5, "pos": Vector3(-0.15, 0.07, -0.12), "rot": Vector3(8, 0, 0)},
		{"t": 0.7, "pos": Vector3(-0.15, 0.07, -0.12), "rot": Vector3(8, 75, -12)},
		{"t": 0.85, "pos": Vector3(-0.15, 0.07, -0.12), "rot": Vector3(8, 0, 0)},
		{"t": 1.0},
	],
}

const INSPECTS: Dictionary[StringName, Dictionary] = {
	# Frag: tossed up, a full flip, caught, then rolled between the fingers.
	EquipmentCatalog.FRAG: {
		"seconds": 2.8,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.08, 0.02, -0.08), "rot": Vector3(-10, 0, 0)},
			{"t": 0.3, "pos": Vector3(-0.08, 0.2, -0.1), "rot": Vector3(-190, 20, 0)},
			{"t": 0.46, "pos": Vector3(-0.08, 0.03, -0.08), "rot": Vector3(-360, 30, 0)},
			{"t": 0.7, "pos": Vector3(-0.1, 0.05, -0.1), "rot": Vector3(-360, 160, 15)},
			{"t": 0.86, "pos": Vector3(-0.08, 0.03, -0.08), "rot": Vector3(-360, 360, 0)},
			{"t": 1.0, "rot": Vector3(-360, 360, 0)},
		],
	},
	# Flashbang: turned round to read the side, held up to the light, back.
	EquipmentCatalog.FLASH: {
		"seconds": 2.6,
		"keys": [
			{"t": 0.0},
			{"t": 0.2, "pos": Vector3(-0.1, 0.06, -0.08), "rot": Vector3(0, 0, 70)},
			{"t": 0.45, "pos": Vector3(-0.1, 0.06, -0.08), "rot": Vector3(0, 180, 70)},
			{"t": 0.65, "pos": Vector3(-0.08, 0.12, -0.12), "rot": Vector3(-25, 180, 10)},
			{"t": 0.85, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 360, 0)},
			{"t": 1.0, "rot": Vector3(0, 360, 0)},
		],
	},
	# Smoke: shaken like a can, then a quick look at the top.
	EquipmentCatalog.SMOKE: {
		"seconds": 2.4,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.06, 0.06, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.2, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.28, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.36, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.44, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.52, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.75, "pos": Vector3(-0.08, 0.06, -0.1), "rot": Vector3(-55, 30, 0)},
			{"t": 1.0},
		],
	},
	# Incendiary: the bottle swirled in a slow circle, then tipped to check the rag.
	EquipmentCatalog.FIRE: {
		"seconds": 3.0,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.08, 0.05, -0.08), "rot": Vector3(10, 0, 10)},
			{"t": 0.24, "pos": Vector3(-0.04, 0.05, -0.12), "rot": Vector3(-10, 0, 10)},
			{"t": 0.36, "pos": Vector3(-0.08, 0.05, -0.16), "rot": Vector3(-10, 0, -10)},
			{"t": 0.48, "pos": Vector3(-0.12, 0.05, -0.12), "rot": Vector3(10, 0, -10)},
			{"t": 0.6, "pos": Vector3(-0.08, 0.05, -0.08), "rot": Vector3(10, 0, 10)},
			{"t": 0.8, "pos": Vector3(-0.1, 0.1, -0.1), "rot": Vector3(-20, -40, 60)},
			{"t": 1.0},
		],
	},
}


static func has_inspect(id: StringName) -> bool:
	return INSPECTS.has(id)


static func for_item(id: StringName) -> Dictionary:
	return INSPECTS.get(id, DEFAULT)


static func seconds(id: StringName) -> float:
	return float(for_item(id).get("seconds", DEFAULT_SECONDS))


## The pose at [param progress] 0..1 of [param id]'s inspection:
## {"pos": Vector3, "rot": Vector3 degrees, "pivot": Vector3 share of the item's size}.
static func sample(id: StringName, progress: float) -> Dictionary:
	var keys: Array = for_item(id)["keys"]
	var t := clampf(progress, 0.0, 1.0)
	var before: Dictionary = keys[0]
	var after: Dictionary = keys[keys.size() - 1]
	for i: int in range(1, keys.size()):
		var key: Dictionary = keys[i]
		if float(key["t"]) >= t:
			before = keys[i - 1]
			after = key
			break
	var span := float(after["t"]) - float(before["t"])
	var blend := smoothstep(0.0, 1.0, (t - float(before["t"])) / span) if span > 0.0 else 1.0
	return {
		"pos": (before.get("pos", Vector3.ZERO) as Vector3).lerp(after.get("pos", Vector3.ZERO), blend),
		"rot": (before.get("rot", Vector3.ZERO) as Vector3).lerp(after.get("rot", Vector3.ZERO), blend),
		"pivot": (before.get("pivot", Vector3.ZERO) as Vector3).lerp(after.get("pivot", Vector3.ZERO), blend),
	}
