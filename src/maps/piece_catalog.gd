class_name PieceCatalog
extends RefCounted
## Piece types understood by the map builder. Official and community maps use the same catalog.
##
## kind:
##   "block"     solid box              "ramp"   solid wedge rising toward local -Z
##   "stairs"    visual steps rising toward local -Z, walked on via a matching wedge collider
##   "compound"  several solid parts (see PieceShapes); every visible part has an equal collider
##   "marker"    gameplay point (spawns, training targets) — invisible as geometry in matches;
##               the FPS runtime spawns its own entities (e.g. target dummies) from them
##   "zone"      gameplay volume (bombsite, buy zone, callout area) — non-solid
##   "light"     placeable light source — non-solid
##   "anchor"    tactical anchor point with a stable ID (plant, default, utility)
##   "hint"      optional AI hint point (cover, hold, angle)
##
## All pieces use a bottom-centre origin: position is the centre of the piece's footprint at
## floor level. Rotation is yaw around Y in degrees (any angle; the editor snaps it).
##
## "walkable" marks floor-like pieces. MapAnalysis only reports unreachable navigation islands
## that rest on walkable pieces, so roofs, crate tops and wall tops are not "playable floor".
## "material" is the default MapMaterials id ("" = the development checker in "color").

const TYPES: Dictionary[String, Dictionary] = {
	# --- Structure -------------------------------------------------------------------------------
	"floor": {"label": "Floor", "kind": "block", "size": Vector3(4, 0.2, 4), "color": Color("3a4049"), "resizable": true, "group": "Structure", "walkable": true},
	"floor_sand": {"label": "Sand ground", "kind": "block", "size": Vector3(8, 0.2, 8), "color": Color("c9a66b"), "resizable": true, "group": "Structure", "walkable": true, "material": "sand"},
	"floor_paved": {"label": "Paved floor", "kind": "block", "size": Vector3(4, 0.2, 4), "color": Color("9c8f7c"), "resizable": true, "group": "Structure", "walkable": true, "material": "stone_paving"},
	"floor_tile": {"label": "Tiled floor", "kind": "block", "size": Vector3(4, 0.2, 4), "color": Color("b5683f"), "resizable": true, "group": "Structure", "walkable": true, "material": "tile_terracotta"},
	"floor_planks": {"label": "Plank floor", "kind": "block", "size": Vector3(4, 0.2, 4), "color": Color("8a6a46"), "resizable": true, "group": "Structure", "walkable": true, "material": "planks"},
	"platform": {"label": "Platform", "kind": "block", "size": Vector3(4, 1.5, 4), "color": Color("a58a66"), "resizable": true, "group": "Structure", "walkable": true, "material": "sandstone"},
	"ledge": {"label": "Ledge", "kind": "block", "size": Vector3(4, 0.3, 1.4), "color": Color("a58a66"), "resizable": true, "group": "Structure", "walkable": true, "material": "sandstone"},
	"roof": {"label": "Roof slab", "kind": "block", "size": Vector3(4, 0.3, 4), "color": Color("8c7458"), "resizable": true, "group": "Structure", "material": "mud_brick"},
	"building": {"label": "Building mass", "kind": "block", "size": Vector3(8, 5, 8), "color": Color("c8a878"), "resizable": true, "group": "Structure", "material": "adobe"},
	"wall": {"label": "Wall", "kind": "block", "size": Vector3(4, 3, 0.3), "color": Color("5b6370"), "resizable": true, "group": "Structure"},
	"wall_adobe": {"label": "Adobe wall", "kind": "block", "size": Vector3(4, 3, 0.4), "color": Color("c8a878"), "resizable": true, "group": "Structure", "material": "adobe"},
	"wall_plaster": {"label": "Plaster wall", "kind": "block", "size": Vector3(4, 3, 0.3), "color": Color("e4dccb"), "resizable": true, "group": "Structure", "material": "plaster_white"},
	"wall_stone": {"label": "Stone wall", "kind": "block", "size": Vector3(4, 3, 0.5), "color": Color("a58a66"), "resizable": true, "group": "Structure", "material": "sandstone"},
	"wall_half": {"label": "Half wall", "kind": "block", "size": Vector3(4, 1.1, 0.3), "color": Color("c8a878"), "resizable": true, "group": "Structure", "material": "adobe"},
	"wall_parapet": {"label": "Parapet wall", "kind": "compound", "size": Vector3(4, 1.4, 0.4), "color": Color("a58a66"), "resizable": true, "group": "Structure", "material": "sandstone"},
	"block": {"label": "Block", "kind": "block", "size": Vector3(2, 2, 2), "color": Color("6b7480"), "resizable": true, "group": "Structure"},
	"pillar": {"label": "Pillar", "kind": "block", "size": Vector3(0.8, 3, 0.8), "color": Color("5b6370"), "resizable": true, "group": "Structure"},
	"column": {"label": "Round column", "kind": "compound", "size": Vector3(0.8, 3.5, 0.8), "color": Color("a58a66"), "resizable": true, "group": "Structure", "material": "sandstone"},
	"wall_battlement": {"label": "Battlement wall", "kind": "compound", "size": Vector3(6, 4, 0.8), "color": Color("8f8a7e"), "resizable": true, "group": "Structure", "material": "granite_blocks"},
	"tower_round": {"label": "Round tower", "kind": "compound", "size": Vector3(5, 9, 5), "color": Color("8f8a7e"), "resizable": true, "group": "Structure", "material": "granite_blocks"},
	"catwalk": {"label": "Catwalk", "kind": "compound", "size": Vector3(2, 1.2, 6), "color": Color("4b5057"), "resizable": true, "group": "Structure", "walkable": true, "material": "steel_grating"},
	"railing": {"label": "Railing", "kind": "compound", "size": Vector3(4, 1.05, 0.08), "color": Color("33363a"), "resizable": true, "group": "Structure", "material": "metal_dark"},
	"drawn_surface": {"label": "Drawn surface", "kind": "surface", "size": Vector3.ONE, "color": Color("a58a66"), "resizable": true, "group": "", "walkable": true},
	"mesh_brush": {"label": "Mesh brush", "kind": "surface", "size": Vector3.ONE, "color": Color("a58a66"), "resizable": true, "group": ""},
	# --- Openings --------------------------------------------------------------------------------
	"doorway": {"label": "Doorway", "kind": "compound", "size": Vector3(3, 3, 0.4), "color": Color("c8a878"), "resizable": true, "group": "Openings", "material": "adobe"},
	"double_door": {"label": "Double doors (open)", "kind": "compound", "size": Vector3(4, 3, 0.4), "color": Color("c8a878"), "resizable": true, "group": "Openings", "material": "adobe"},
	"arch": {"label": "Arch", "kind": "compound", "size": Vector3(4, 4, 0.6), "color": Color("a58a66"), "resizable": true, "group": "Openings", "material": "sandstone"},
	"wall_window": {"label": "Window wall", "kind": "compound", "size": Vector3(4, 3, 0.4), "color": Color("c8a878"), "resizable": true, "group": "Openings", "material": "adobe"},
	"gate_portcullis": {"label": "Gate with raised portcullis", "kind": "compound", "size": Vector3(6, 6, 1.6), "color": Color("8f8a7e"), "resizable": true, "group": "Openings", "material": "granite_blocks"},
	# --- Slopes ----------------------------------------------------------------------------------
	"ramp": {"label": "Ramp", "kind": "ramp", "size": Vector3(3, 1.5, 5), "color": Color("b8542a"), "resizable": true, "group": "Slopes", "walkable": true},
	"ramp_earth": {"label": "Earth ramp", "kind": "ramp", "size": Vector3(4, 1.5, 6), "color": Color("b08a58"), "resizable": true, "group": "Slopes", "walkable": true, "material": "packed_earth"},
	"stairs": {"label": "Stairs", "kind": "stairs", "size": Vector3(2, 1.5, 3), "color": Color("b8542a"), "resizable": true, "group": "Slopes", "walkable": true},
	"stairs_stone": {"label": "Stone stairs", "kind": "stairs", "size": Vector3(3, 1.5, 4), "color": Color("a58a66"), "resizable": true, "group": "Slopes", "walkable": true, "material": "sandstone"},
	# --- Props -----------------------------------------------------------------------------------
	"crate": {"label": "Crate", "kind": "block", "size": Vector3(1.2, 1.2, 1.2), "color": Color("8a6a46"), "resizable": true, "group": "Props"},
	"crate_large": {"label": "Large crate", "kind": "block", "size": Vector3(2, 2, 2), "color": Color("8a6a46"), "resizable": true, "group": "Props"},
	"crate_long": {"label": "Long crate", "kind": "block", "size": Vector3(2.4, 1.0, 1.0), "color": Color("8a6a46"), "resizable": true, "group": "Props", "material": "planks"},
	"crate_stack": {"label": "Crate stack", "kind": "compound", "size": Vector3(2.4, 2.4, 1.2), "color": Color("8a6a46"), "resizable": true, "group": "Props", "material": "planks"},
	"barrel": {"label": "Barrel", "kind": "compound", "size": Vector3(0.7, 1.0, 0.7), "color": Color("7c4a32"), "resizable": true, "group": "Props", "material": "metal_rust"},
	"barrel_cluster": {"label": "Barrel cluster", "kind": "compound", "size": Vector3(1.5, 1.0, 1.4), "color": Color("7c4a32"), "resizable": true, "group": "Props", "material": "metal_rust"},
	"well": {"label": "Cistern well", "kind": "compound", "size": Vector3(3, 1.0, 3), "color": Color("a58a66"), "resizable": true, "group": "Props", "material": "sandstone"},
	"kiln": {"label": "Kiln", "kind": "compound", "size": Vector3(2.4, 2.6, 2.4), "color": Color("9a5a3c"), "resizable": true, "group": "Props", "material": "mud_brick"},
	"awning": {"label": "Awning", "kind": "compound", "size": Vector3(3, 2.8, 2), "color": Color("b84a3a"), "resizable": true, "group": "Props", "material": "cloth_red"},
	"pottery_jar": {"label": "Lidded pottery jar", "kind": "compound", "size": Vector3(0.8, 0.94, 0.8),
		"color": Color("a85035"), "resizable": true, "group": "Props", "material": "fired_clay"},
	"coopered_barrel": {"label": "Hooped timber barrel", "kind": "compound", "size": Vector3(0.82, 1.03, 0.82),
		"color": Color("836549"), "resizable": true, "group": "Props", "material": "weathered_wood"},
	"braced_crate": {"label": "Braced shipping crate", "kind": "compound", "size": Vector3(1.45, 1.1, 1.15),
		"color": Color("836549"), "resizable": true, "group": "Props", "material": "weathered_wood"},
	"stone_bench": {"label": "Stone workbench", "kind": "compound", "size": Vector3(1.7, 0.95, 0.74),
		"color": Color("bdb69f"), "resizable": true, "group": "Props", "material": "limestone"},
	"market_shelf": {"label": "Market shelf", "kind": "compound", "size": Vector3(1.45, 1.85, 0.52),
		"color": Color("836549"), "resizable": true, "group": "Props", "material": "weathered_wood"},
	"stone_trough": {"label": "Stone trough", "kind": "compound", "size": Vector3(1.9, 0.65, 0.86),
		"color": Color("bdb69f"), "resizable": true, "group": "Props", "material": "limestone"},
	"pipe_run": {"label": "Pipe run", "kind": "compound", "size": Vector3(6, 0.7, 0.7), "color": Color("6f7a52"), "resizable": true, "group": "Props", "material": "metal_painted"},
	"storage_tank": {"label": "Storage tank", "kind": "compound", "size": Vector3(4, 6, 4), "color": Color("8f8d86"), "resizable": true, "group": "Props", "material": "metal_painted"},
	"tree": {"label": "Tree", "kind": "compound", "size": Vector3(4, 7, 4), "color": Color("4f6b3a"), "resizable": true, "group": "Props", "material": "foliage"},
	"banner": {"label": "Hanging banner", "kind": "compound", "size": Vector3(1.4, 3.2, 0.12), "color": Color("b84a3a"), "resizable": true, "group": "Props", "material": "cloth_red"},
	# --- Cover (sightline blockers) --------------------------------------------------------------
	"low_cover": {"label": "Low cover", "kind": "block", "size": Vector3(3, 1.1, 0.4), "color": Color("5b6370"), "resizable": true, "group": "Cover"},
	"sandbag_wall": {"label": "Sandbag wall", "kind": "compound", "size": Vector3(3, 1.1, 0.8), "color": Color("a8946a"), "resizable": true, "group": "Cover", "material": "burlap"},
	"shipping_container": {"label": "Shipping container", "kind": "compound", "size": Vector3(2.44, 2.6, 6.1), "color": Color("7c4a32"), "resizable": true, "group": "Cover", "material": "metal_rust"},
	"market_stall": {"label": "Market stall", "kind": "compound", "size": Vector3(3, 2.6, 1.6), "color": Color("8a6a46"), "resizable": true, "group": "Cover", "material": "planks"},
	"cloth_screen": {"label": "Cloth screen", "kind": "compound", "size": Vector3(3, 2.6, 0.2), "color": Color("3f6f8f"), "resizable": true, "group": "Cover", "material": "cloth_blue"},
	# --- Vehicles --------------------------------------------------------------------------------
	"vehicle_truck": {"label": "Cargo truck", "kind": "compound", "size": Vector3(2.4, 2.6, 6.0), "color": Color("6f7a52"), "resizable": false, "group": "Vehicles", "material": "metal_painted"},
	"vehicle_car": {"label": "Town car", "kind": "compound", "size": Vector3(1.9, 1.5, 4.2), "color": Color("9c8f7c"), "resizable": false, "group": "Vehicles", "material": "metal_painted"},
	"vehicle_cart": {"label": "Hand cart", "kind": "compound", "size": Vector3(1.4, 1.2, 2.4), "color": Color("8a6a46"), "resizable": false, "group": "Vehicles", "material": "planks"},
	# --- Lights ----------------------------------------------------------------------------------
	"light_lamp": {"label": "Lamp light", "kind": "light", "size": Vector3(0.3, 0.3, 0.3), "color": Color("ffd9a0"), "resizable": false, "group": "Lights"},
	"light_spot": {"label": "Spot light (down)", "kind": "light", "size": Vector3(0.3, 0.3, 0.3), "color": Color("fff1d6"), "resizable": false, "group": "Lights"},
	# --- Gameplay --------------------------------------------------------------------------------
	"spawn_attack": {"label": "Attacker spawn", "kind": "marker", "size": Vector3(0.8, 1.8, 0.8), "color": Color("ff6a2a"), "resizable": false, "group": "Gameplay", "team": "attack"},
	"spawn_defence": {"label": "Defender spawn", "kind": "marker", "size": Vector3(0.8, 1.8, 0.8), "color": Color("2ec4d6"), "resizable": false, "group": "Gameplay", "team": "defence"},
	"bombsite": {"label": "Bombsite", "kind": "zone", "size": Vector3(6, 3, 6), "color": Color(0.95, 0.3, 0.3, 0.25), "resizable": true, "group": "Gameplay"},
	"buy_zone": {"label": "Buy zone", "kind": "zone", "size": Vector3(8, 3, 8), "color": Color(0.25, 0.8, 0.4, 0.2), "resizable": true, "group": "Gameplay"},
	# --- Tactics ---------------------------------------------------------------------------------
	"callout": {"label": "Callout area", "kind": "zone", "size": Vector3(6, 3, 6), "color": Color(0.85, 0.85, 0.95, 0.12), "resizable": true, "group": "Tactics"},
	"tactical_anchor": {"label": "Tactical anchor", "kind": "anchor", "size": Vector3(0.5, 0.5, 0.5), "color": Color("f2c94c"), "resizable": false, "group": "Tactics"},
	"ai_cover": {"label": "AI hint: cover spot", "kind": "hint", "size": Vector3(0.5, 1.0, 0.5), "color": Color("7bd389"), "resizable": false, "group": "Tactics"},
	"ai_hold": {"label": "AI hint: hold point", "kind": "hint", "size": Vector3(0.5, 1.0, 0.5), "color": Color("5aa9e6"), "resizable": false, "group": "Tactics"},
	"ai_angle": {"label": "AI hint: angle point", "kind": "hint", "size": Vector3(0.5, 1.0, 0.5), "color": Color("e07be0"), "resizable": false, "group": "Tactics"},
	# --- Training --------------------------------------------------------------------------------
	"target_dummy": {"label": "Target dummy", "kind": "marker", "size": Vector3(0.6, 1.8, 0.6), "color": Color("c9b48a"), "resizable": false, "group": "Training"},
	"course_start": {"label": "Course start", "kind": "zone", "size": Vector3(4, 3, 4), "color": Color(0.3, 0.85, 0.45, 0.25), "resizable": true, "group": "Training"},
	"course_checkpoint": {"label": "Course checkpoint", "kind": "zone", "size": Vector3(4, 3, 4), "color": Color(0.95, 0.8, 0.25, 0.25), "resizable": true, "group": "Training"},
	"course_finish": {"label": "Course finish", "kind": "zone", "size": Vector3(4, 3, 4), "color": Color(0.95, 0.35, 0.3, 0.25), "resizable": true, "group": "Training"},
}

const GROUP_ORDER: Array[String] = ["Structure", "Openings", "Slopes", "Props", "Cover", "Vehicles", "Lights",
	"Gameplay", "Tactics", "Training"]
const SOLID_KINDS: Array[String] = ["block", "ramp", "stairs", "compound", "surface"]
## Level slabs are placed by their walking surface. Raised platforms and ramps use their base.
const FLOOR_SLAB_TYPES: Array[String] = ["floor", "floor_sand", "floor_paved", "floor_tile", "floor_planks"]
## Kept for saved maps and prefabs. New pieces choose their finish in the inspector.
const MATERIAL_VARIANTS: Array[String] = [
	"floor_sand", "floor_paved", "floor_tile", "floor_planks",
	"wall_adobe", "wall_plaster", "wall_stone", "ramp_earth", "stairs_stone",
]


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


static func default_material(type: String) -> String:
	return str(info(type).get("material", ""))


static func is_resizable(type: String) -> bool:
	return bool(info(type).get("resizable", false))


static func is_solid(type: String) -> bool:
	return kind(type) in SOLID_KINDS


## Floor-like pieces: navigation that rests on them counts as playable floor.
static func is_walkable(type: String) -> bool:
	return bool(info(type).get("walkable", false))


static func palette_types_in_group(group: String) -> Array[String]:
	var list: Array[String] = []
	for type: String in TYPES:
		if TYPES[type]["group"] == group and type not in MATERIAL_VARIANTS:
			list.append(type)
	return list
