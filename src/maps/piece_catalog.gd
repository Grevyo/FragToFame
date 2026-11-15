class_name PieceCatalog
extends RefCounted
## Every piece type the map editor can place. Official and community maps use the same catalog.
##
## kind:
##   "block"   solid box            "ramp"   solid wedge rising toward local -Z
##   "stairs"  visual steps rising toward local -Z, walked on via a hidden slope
##   "marker"  gameplay point (spawns) — invisible in matches
##   "zone"    gameplay volume (bombsite, buy zone, callout) — non-solid
##
## All pieces use a bottom-centre origin: position is the centre of the piece's footprint at
## floor level. Rotation is around Y in 90° steps (Milestone 3).

const TYPES: Dictionary[String, Dictionary] = {
	"floor": {"label": "Floor", "kind": "block", "size": Vector3(4, 0.2, 4), "color": Color("3a4049"), "resizable": true, "group": "Structure"},
	"wall": {"label": "Wall", "kind": "block", "size": Vector3(4, 3, 0.3), "color": Color("5b6370"), "resizable": true, "group": "Structure"},
	"block": {"label": "Block", "kind": "block", "size": Vector3(2, 2, 2), "color": Color("6b7480"), "resizable": true, "group": "Structure"},
	"pillar": {"label": "Pillar", "kind": "block", "size": Vector3(0.8, 3, 0.8), "color": Color("5b6370"), "resizable": true, "group": "Structure"},
	"ramp": {"label": "Ramp", "kind": "ramp", "size": Vector3(3, 1.5, 5), "color": Color("b8542a"), "resizable": true, "group": "Structure"},
	"stairs": {"label": "Stairs", "kind": "stairs", "size": Vector3(2, 1.5, 3), "color": Color("b8542a"), "resizable": true, "group": "Structure"},
	"crate": {"label": "Crate", "kind": "block", "size": Vector3(1.2, 1.2, 1.2), "color": Color("8a6a46"), "resizable": true, "group": "Props"},
	"crate_large": {"label": "Large crate", "kind": "block", "size": Vector3(2, 2, 2), "color": Color("8a6a46"), "resizable": true, "group": "Props"},
	"low_cover": {"label": "Low cover", "kind": "block", "size": Vector3(3, 1.1, 0.4), "color": Color("5b6370"), "resizable": true, "group": "Props"},
	"spawn_attack": {"label": "Attacker spawn", "kind": "marker", "size": Vector3(0.8, 1.8, 0.8), "color": Color("ff6a2a"), "resizable": false, "group": "Gameplay", "team": "attack"},
	"spawn_defence": {"label": "Defender spawn", "kind": "marker", "size": Vector3(0.8, 1.8, 0.8), "color": Color("2ec4d6"), "resizable": false, "group": "Gameplay", "team": "defence"},
	"bombsite": {"label": "Bombsite", "kind": "zone", "size": Vector3(6, 3, 6), "color": Color(0.95, 0.3, 0.3, 0.25), "resizable": true, "group": "Gameplay"},
	"buy_zone": {"label": "Buy zone", "kind": "zone", "size": Vector3(8, 3, 8), "color": Color(0.25, 0.8, 0.4, 0.2), "resizable": true, "group": "Gameplay"},
	"callout": {"label": "Callout area", "kind": "zone", "size": Vector3(6, 3, 6), "color": Color(0.85, 0.85, 0.95, 0.12), "resizable": true, "group": "Gameplay"},
}

const GROUP_ORDER: Array[String] = ["Structure", "Props", "Gameplay"]


static func has_type(type: String) -> bool:
	return TYPES.has(type)


static func info(type: String) -> Dictionary:
	return TYPES.get(type, {})


static func kind(type: String) -> String:
	return str(info(type).get("kind", ""))


static func label(type: String) -> String:
	return str(info(type).get("label", type))


static func default_size(type: String) -> Vector3:
	return info(type).get("size", Vector3.ONE)


static func color(type: String) -> Color:
	return info(type).get("color", Color.WHITE)


static func is_resizable(type: String) -> bool:
	return bool(info(type).get("resizable", false))


static func is_solid(type: String) -> bool:
	return kind(type) in ["block", "ramp", "stairs"]


static func types_in_group(group: String) -> Array[String]:
	var list: Array[String] = []
	for type: String in TYPES:
		if TYPES[type]["group"] == group:
			list.append(type)
	return list
