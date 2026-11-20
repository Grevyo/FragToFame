extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Kestrel Keep": a granite fortress above a village.
## The defenders hold the keep; the attackers come up from the village green. Three ways into
## each site: a long gate road on the outside, a short way through the curtain wall (the Breach
## for A, the Undercroft tunnel for B), and an arch from the central Bailey. The Gatehouse in the
## middle has a walkable gallery over the market square.
##
## It is also the stress test for the Creation Studio's stone catalogue: battlement walls, round
## towers, a raised portcullis, banners, trees, ramparts and stairs at scale.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_kestrel_keep.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const SITE_A: Vector3 = Vector3(-44, 0, -17)
const SITE_B: Vector3 = Vector3(44, 0, -17)
const RAMPART: float = 4.0
const GALLERY: float = 4.5


func _official_id() -> String:
	return "map_f2f_kestrel_keep"


## Revision 2: lamp fixtures in its dark corners and everyday props along the walls.
func _revision() -> int:
	return 2


func _build() -> void:
	controller.set_metadata("Kestrel Keep", "F2F official",
		"Granite fortress above a village. A: the Tiltyard, by the West Gate road or the Breach. B: the Cloister, by the Orchard Walk or the Undercroft. Both open onto the Bailey behind the Gatehouse.")
	controller.set_lighting({"sun_yaw": 140.0, "sun_pitch": 34.0, "sun_energy": 1.05, "sun_color": "fff2dc",
		"ambient_color": "b7c0c8", "ambient_energy": 0.62})
	_ground()
	_curtain()
	_gatehouse()
	_tiltyard()
	_bailey()
	_cloister()
	_inner_ward()
	_market()
	_village()
	_lamps_and_props()
	_gameplay()
	_callouts()
	_tactical()


func _ground() -> void:
	layer("Ground and boundary")
	mass("floor", -66, 66, -54, -4, 1.0, "cobblestone", -1.0)
	mass("floor", -66, 66, -4, 2, 1.0, "packed_earth", -1.0)
	mass("floor", -66, -24, 2, 22, 1.0, "packed_earth", -1.0)
	mass("floor", -24, 24, 2, 22, 1.0, "stone_paving", -1.0)
	mass("floor", 24, 66, 2, 22, 1.0, "packed_earth", -1.0)
	mass("floor", -66, 66, 22, 64, 1.0, "packed_earth", -1.0)
	for wall: Array in [[-66, 66, -55, -54], [-66, 66, 64, 65]]:
		mass("wall_battlement", wall[0], wall[1], wall[2], wall[3], 9.0, "granite_blocks")
	for wall: Array in [[-67, -66, -54, 64], [66, 67, -54, 64]]:
		mass("wall_stone", wall[0], wall[1], wall[2], wall[3], 9.0, "granite_blocks")


## The south face of the keep, z -4..-3, with its gates, the Breach and the Undercroft.
func _curtain() -> void:
	layer("Curtain wall")
	for segment: Array in [[-66, -57], [-51, -38], [-33, -9], [9, 33], [39, 51], [57, 66]]:
		mass("wall_battlement", segment[0], segment[1], -4, -3, 7.0, "granite_blocks")
	# West Gate: the long road's gate, its portcullis raised.
	put("gate_portcullis", Vector3(-54, 0, -3.5), Vector3(6, 7, 1.6), 0.0,
		{"opening_width": 4.2, "opening_height": 4.6, "clearance": 3.2})
	# Lych Gate: the Orchard Walk's arch.
	put("arch", Vector3(54, 0, -3.5), Vector3(6, 7, 1.2), 0.0, {"opening_width": 4.2, "opening_height": 3.4}, "granite_blocks")
	# The Breach: the wall has fallen between x -38 and -33; rubble narrows the gap.
	mass("block", -38, -36.6, -5, -2, 2.2, "mossy_stone")
	mass("block", -34.4, -33, -4.6, -2.4, 3.0, "mossy_stone")
	mass("block", -36.6, -34.4, -4, -3, 0.08, "mossy_stone")
	put("wall_battlement", Vector3(-38.6, 0, -3.5), Vector3(1.2, 4.5, 1.0), 0.0, {"merlon_height": 0.6}, "mossy_stone")
	# The Undercroft: a vaulted tunnel through the wall at x 33..39.
	mass("wall", 33, 33.6, -10, 6, 3.2, "granite_blocks")
	mass("wall", 38.4, 39, -10, 6, 3.2, "granite_blocks")
	mass("roof", 33, 39, -10, 6, 0.5, "granite_blocks", 3.2)
	mass("wall_battlement", 33, 39, -4, -3, 3.3, "granite_blocks", 3.7)
	lamp(Vector3(36, 2.6, 2), 2.2, 8.0, "ffc58a")
	lamp(Vector3(36, 2.6, -6), 2.2, 8.0, "ffc58a")
	# Corner towers.
	for tower: Vector3 in [Vector3(-66, 0, -3.5), Vector3(66, 0, -3.5), Vector3(-66, 0, -54), Vector3(66, 0, -54)]:
		put("tower_round", tower, Vector3(8, 13, 8))


## The Gatehouse straddles the curtain: a passage below, a gallery above the market.
func _gatehouse() -> void:
	layer("Gatehouse")
	mass("building", -9, -2.5, -8, 1, GALLERY, "granite_blocks")
	mass("building", 2.5, 9, -8, 1, GALLERY, "granite_blocks")
	mass("block", -2.5, 2.5, -8, 1, GALLERY - 4.0, "granite_blocks", 4.0)
	for mouth: float in [1.0, -8.0]:
		put("gate_portcullis", Vector3(0, 0, mouth), Vector3(5, 4, 0.6), 0.0,
			{"opening_width": 4.4, "opening_height": 3.9, "clearance": 2.9})
	lamp(Vector3(0, 3.2, -3.5), 2.0, 7.0, "ffc58a")
	layer("Gatehouse · gallery")
	put("wall_parapet", Vector3(0, GALLERY, 0.8), Vector3(18, 1.4, 0.4), 0.0, {}, "granite_blocks")
	put("wall_parapet", Vector3(-8.8, GALLERY, -3.5), Vector3(9, 1.4, 0.4), 90.0, {}, "granite_blocks")
	mass("platform", 9, 12, -8, -4, GALLERY, "granite_blocks")
	put("stairs_stone", Vector3(10.5, 0, -14), Vector3(3, GALLERY, 12), 180.0)
	for tower: Vector3 in [Vector3(-10.5, 0, 2), Vector3(10.5, 0, 2)]:
		put("tower_round", tower, Vector3(4, 9, 4))
	put("banner", Vector3(-5.5, 1.4, 1.1), Vector3(1.4, 3.0, 0.12))
	put("banner", Vector3(5.5, 1.4, 1.1), Vector3(1.4, 3.0, 0.12))


## Site A: the Tiltyard, with a rampart along its west wall.
func _tiltyard() -> void:
	layer("Tiltyard (A)")
	# The wall between the Tiltyard and the Bailey, with the Bailey Arch.
	put("wall_battlement", Vector3(-30, 0, -26), Vector3(8, 6, 0.8), 90.0, {}, "granite_blocks")
	put("arch", Vector3(-30, 0, -19.5), Vector3(5, 6, 0.8), 90.0, {"opening_width": 3.4, "opening_height": 3.0}, "granite_blocks")
	put("wall_battlement", Vector3(-30, 0, -10.5), Vector3(13, 6, 0.8), 90.0, {}, "granite_blocks")
	# Rampart along the west wall, climbed by a stair from the yard.
	mass("platform", -66, -61, -30, -4, RAMPART, "granite_blocks")
	put("stairs_stone", Vector3(-56, 0, -24.5), Vector3(3, RAMPART, 10), 90.0)
	put("wall_parapet", Vector3(-61.2, RAMPART, -12), Vector3(16, 1.4, 0.4), 90.0, {}, "granite_blocks")
	# The tilt barrier and the yard's cover.
	put("low_cover", Vector3(-46, 0, -25), Vector3(12, 1.1, 0.3), 0.0, {}, "weathered_wood")
	put("well", Vector3(-40, 0, -12), Vector3(3, 1.1, 3), 0.0, {}, "mossy_stone")
	put("vehicle_cart", Vector3(-50, 0, -13), Vector3.ZERO, 70.0)
	put("crate_stack", Vector3(-47, 0, -8), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("stone_trough", Vector3(-36, 0, -22), Vector3(2, 0.7, 0.9), 90.0)
	put("braced_crate", Vector3(-53, 0, -19), Vector3(1.5, 1.2, 1.2))
	put("sandbag_wall", Vector3(-41, 0, -7), Vector3(3, 1.1, 0.8))
	put("banner", Vector3(-46, 2.5, -29.4), Vector3(1.6, 3.2, 0.12), 0.0, {}, "cloth_blue")
	lamp(Vector3(-44, 3.6, -28.5), 1.6, 10.0)


## The Bailey behind the Gatehouse joins both sites' arches and the Keep Gate.
func _bailey() -> void:
	layer("Bailey")
	mass("building", -26, -16, -28, -21, 4.0, "weathered_wood")
	mass("roof", -27, -15, -29, -20, 0.3, "slate", 4.0)
	put("kiln", Vector3(18, 0, -24), Vector3(2.6, 2.8, 2.6), 0.0, {}, "mud_brick")
	put("vehicle_cart", Vector3(-8, 0, -16), Vector3.ZERO, 10.0)
	put("crate_stack", Vector3(20, 0, -13), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")
	put("stone_bench", Vector3(-12, 0, -26), Vector3(1.8, 0.95, 0.8))
	put("coopered_barrel", Vector3(23, 0, -27))
	put("coopered_barrel", Vector3(24, 0, -26))
	put("tree", Vector3(-20, 0, -12), Vector3(4, 7, 4))


## Site B: the Cloister, with a covered arcade and the chapel.
func _cloister() -> void:
	layer("Cloister (B)")
	put("wall_battlement", Vector3(30, 0, -26), Vector3(8, 6, 0.8), 90.0, {}, "granite_blocks")
	put("arch", Vector3(30, 0, -19.5), Vector3(5, 6, 0.8), 90.0, {"opening_width": 3.4, "opening_height": 3.0}, "granite_blocks")
	put("wall_battlement", Vector3(30, 0, -13.5), Vector3(7, 6, 0.8), 90.0, {}, "granite_blocks")
	# The chapel fills the east end; its west front faces the site.
	mass("building", 56, 66, -30, -10, 10.0, "limestone")
	mass("roof", 55.5, 66, -30.5, -9.5, 0.4, "slate", 10.0)
	put("tower_round", Vector3(57, 0, -9), Vector3(4, 14, 4), 0.0, {}, "limestone")
	# The arcade along the north wall: a roof on columns.
	mass("roof", 31, 56, -30, -26, 0.35, "slate", 3.6)
	for x: float in [34.0, 39.0, 44.0, 49.0, 54.0]:
		put("column", Vector3(x, 0, -26.3), Vector3(0.7, 3.6, 0.7), 0.0, {}, "limestone")
	put("stone_bench", Vector3(41, 0, -28), Vector3(1.8, 0.95, 0.8))
	put("stone_bench", Vector3(51, 0, -28), Vector3(1.8, 0.95, 0.8))
	# Site cover: a tomb, crates and a cart.
	mass("block", 42, 46, -19, -17, 1.2, "limestone")
	put("braced_crate", Vector3(50, 0, -14), Vector3(1.5, 1.2, 1.2))
	put("crate_stack", Vector3(36, 0, -9), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("vehicle_cart", Vector3(49, 0, -22), Vector3.ZERO, 100.0)
	put("market_shelf", Vector3(38, 0, -21), Vector3(1.5, 1.85, 0.52), 90.0)
	put("banner", Vector3(56, 3, -20), Vector3(1.6, 3.4, 0.12), 90.0, {}, "cloth_red")
	lamp(Vector3(44, 3.0, -28), 1.6, 9.0)


## The defenders' Inner Ward and the Great Keep.
func _inner_ward() -> void:
	layer("Inner Ward")
	for segment: Array in [[-66, -49], [-43, -3], [3, 43], [49, 66]]:
		mass("wall_battlement", segment[0], segment[1], -30.8, -30, 6.0, "granite_blocks")
	put("arch", Vector3(-46, 0, -30.4), Vector3(6, 6, 0.8), 0.0, {"opening_width": 4.4, "opening_height": 3.2}, "granite_blocks")
	put("gate_portcullis", Vector3(0, 0, -30.4), Vector3(6, 6, 0.8), 0.0, {"opening_width": 4.6, "opening_height": 4.0, "clearance": 3.0})
	put("arch", Vector3(46, 0, -30.4), Vector3(6, 6, 0.8), 0.0, {"opening_width": 4.4, "opening_height": 3.2}, "granite_blocks")
	mass("building", -12, 12, -54, -46, 16.0, "granite_blocks")
	for tower: Vector3 in [Vector3(-12, 0, -46), Vector3(12, 0, -46)]:
		put("tower_round", tower, Vector3(5, 19, 5))
	mass("building", -66, -40, -54, -45, 6.0, "limestone")
	mass("roof", -66, -40, -54, -44.5, 0.35, "slate", 6.0)
	mass("building", 40, 66, -54, -45, 6.0, "limestone")
	mass("roof", 40, 66, -54, -44.5, 0.35, "slate", 6.0)
	put("crate_stack", Vector3(-24, 0, -36), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("vehicle_cart", Vector3(26, 0, -38), Vector3.ZERO, 80.0)
	put("tree", Vector3(-32, 0, -40), Vector3(4.5, 8, 4.5))
	put("tree", Vector3(32, 0, -40), Vector3(4.5, 8, 4.5))
	put("banner", Vector3(-6, 6, -45.9), Vector3(2, 5, 0.12), 0.0, {}, "cloth_blue")
	put("banner", Vector3(6, 6, -45.9), Vector3(2, 5, 0.12), 0.0, {}, "cloth_blue")


## The market square in front of the Gatehouse.
func _market() -> void:
	layer("Market")
	mass("block", -1.5, 1.5, 11, 14, 0.6, "limestone")
	put("column", Vector3(0, 0.6, 12.5), Vector3(0.9, 4.5, 0.9), 0.0, {}, "limestone")
	put("market_stall", Vector3(-14, 0, 8), Vector3(3, 2.6, 1.6), 90.0)
	put("market_stall", Vector3(14, 0, 9), Vector3(3, 2.6, 1.6), 270.0)
	put("market_stall", Vector3(-10, 0, 18), Vector3(3, 2.6, 1.6), 180.0)
	put("market_stall", Vector3(9, 0, 18), Vector3(3, 2.6, 1.6), 180.0)
	put("vehicle_cart", Vector3(-19, 0, 14), Vector3.ZERO, 0.0)
	put("pottery_jar", Vector3(17, 0, 15))
	put("pottery_jar", Vector3(17.8, 0, 15.6))
	put("crate_stack", Vector3(5, 0, 4), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("stone_trough", Vector3(-6, 0, 3.5), Vector3(2, 0.7, 0.9))
	lamp(Vector3(0, 4.2, 9), 2.0, 12.0)


## Village houses between the gate roads and the alleys; the attackers' green to the south.
func _village() -> void:
	layer("Village houses")
	# West block: West Road (x -64..-50) | houses | Tanner's Alley (x -40..-32) | houses | market.
	for house: Array in [[-50, -40, -3, 14, 6.5], [-50, -40, 14, 34, 7.5], [-32, -24, 6, 22, 6.0], [-32, -6, 22, 32, 7.0]]:
		mass("building", house[0], house[1], house[2], house[3], house[4], "limewash")
		mass("roof", house[0] - 0.4, house[1] + 0.4, house[2] - 0.4, house[3] + 0.4, 0.35, "slate", house[4])
	for house: Array in [[40, 50, -3, 14, 6.5], [40, 50, 14, 34, 7.5], [24, 32, 6, 22, 6.0], [6, 32, 22, 32, 7.0]]:
		mass("building", house[0], house[1], house[2], house[3], house[4], "limewash")
		mass("roof", house[0] - 0.4, house[1] + 0.4, house[2] - 0.4, house[3] + 0.4, 0.35, "slate", house[4])
	# South of the cross streets (z 32..40): the green's edge.
	for house: Array in [[-66, -20, 40, 64, 7.0], [20, 66, 40, 64, 7.0]]:
		mass("building", house[0], house[1], house[2], house[3], house[4], "limewash")
	mass("building", -66, -64, -3, 40, 7.0, "granite_blocks")
	mass("building", 64, 66, -3, 40, 7.0, "granite_blocks")
	layer("Village props")
	put("well", Vector3(-57, 0, 26), Vector3(3, 1.1, 3), 0.0, {}, "mossy_stone")
	put("vehicle_cart", Vector3(-60, 0, 8), Vector3.ZERO, 0.0)
	put("crate_stack", Vector3(-53, 0, -0.5), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("braced_crate", Vector3(-35, 0, 18), Vector3(1.5, 1.2, 1.2))
	put("coopered_barrel", Vector3(-38.5, 0, 4))
	put("braced_crate", Vector3(35, 0, 20), Vector3(1.5, 1.2, 1.2))
	put("coopered_barrel", Vector3(38.5, 9, 10))
	# The Orchard Walk (x 50..64): a row of fruit trees.
	for tree: Vector3 in [Vector3(56, 0, 30), Vector3(60, 0, 20), Vector3(54, 0, 12), Vector3(60, 0, 4)]:
		put("tree", tree, Vector3(4, 6.5, 4))
	put("vehicle_cart", Vector3(-2, 0, 36), Vector3.ZERO, 90.0)
	put("crate_stack", Vector3(12, 0, 37), Vector3(2.4, 2.4, 1.2), 0.0, {}, "planks")
	put("tree", Vector3(-12, 0, 52), Vector3(5, 8, 5))
	put("tree", Vector3(12, 0, 54), Vector3(5, 8, 5))
	layer("Lights")
	lamp(Vector3(-36, 3.0, 8), 1.8, 9.0)
	lamp(Vector3(-57, 3.4, 12), 1.8, 10.0)
	lamp(Vector3(57, 3.4, 12), 1.8, 10.0)
	lamp(Vector3(0, 3.4, 30), 1.8, 10.0)


func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(0, 0, 50), 0.0, Vector3(26, 3, 10))
	spawns("defence", Vector3(0, 0, -38), 180.0, Vector3(26, 3, 8))
	put("bombsite", SITE_A, Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Village Green", -20, 20, 40, 64)
	area("High Street", -6, 6, 22, 40)
	area("West Street", -64, -6, 32, 40)
	area("East Street", 6, 64, 32, 40)
	area("West Road", -64, -50, -3, 32)
	area("West Gate", -57, -51, -6, -1, "entrance_a")
	area("Tanner's Alley", -40, -32, 2, 32)
	area("Breach", -38, -33, -6, -1, "entrance_a")
	area("Market", -24, 24, 2, 22)
	area("Gatehouse", -2.5, 2.5, -8, 1, "mid")
	area("Gallery", -9, 12, -8, 1, "", GALLERY)
	area("Mill Alley", 32, 40, 6, 32)
	area("Undercroft", 33.6, 38.4, -10, 6, "entrance_b")
	area("Orchard Walk", 50, 64, -3, 32)
	area("Lych Gate", 51, 57, -6, -1, "entrance_b")
	area("Tiltyard", -61, -30, -30, -4)
	area("Rampart", -66, -61, -30, -4, "", RAMPART)
	area("Rampart Stair", -61, -51, -26, -23)
	area("Bailey Arch A", -32, -28, -22, -17)
	area("Bailey", -29.6, 29.6, -30, -8)
	area("Gallery Stair", 9, 12, -20, -8)
	area("Bailey Arch B", 28, 32, -22, -17)
	area("Cloister", 30.4, 56, -26, -4)
	area("Arcade", 31, 56, -30, -26)
	area("Chapel Steps", 54, 56, -10, -4)
	area("Inner Ward", -66, 66, -45, -30.8)
	area("Keep Gate", -3, 3, -32, -29)
	area("Armoury Arch", -49, -43, -32, -29)
	area("Cloister Arch", 43, 49, -32, -29)


func _tactical() -> void:
	layer("Tactics")
	anchor("Tiltyard plant well", "plant", SITE_A + Vector3(3, 0, 3))
	anchor("Tiltyard plant barrier", "plant", SITE_A + Vector3(-3, 0, -5))
	anchor("Cloister plant tomb", "plant", SITE_B + Vector3(-3, 0, 1))
	anchor("Cloister plant arcade", "plant", SITE_B + Vector3(4, 0, -5))
	anchor("Gate road hold", "default", Vector3(-57, 0, 10))
	anchor("Alley hold", "default", Vector3(-36, 0, 12))
	anchor("Market hold", "default", Vector3(0, 0, 16))
	anchor("Gallery post", "default", Vector3(-4, GALLERY, -2))
	anchor("Mill hold", "default", Vector3(36, 0, 14))
	anchor("Orchard hold", "default", Vector3(57, 0, 10))
	anchor("West Gate smoke", "utility", Vector3(-54, 0, 1))
	anchor("Breach smoke", "utility", Vector3(-35.5, 0, 0))
	anchor("Gatehouse smoke", "utility", Vector3(0, 0, 4))
	anchor("Undercroft smoke", "utility", Vector3(36, 0, 7))
	anchor("Lych Gate smoke", "utility", Vector3(54, 0, 1))
	hint("ai_hold", Vector3(-63.5, RAMPART, -14), 150.0, "A")
	hint("ai_hold", Vector3(-38, 0, -27), 200.0, "A")
	hint("ai_hold", Vector3(-52, 0, -27), 170.0, "A")
	hint("ai_hold", Vector3(52, 0, -24), 200.0, "B")
	hint("ai_hold", Vector3(36, 0, -25), 160.0, "B")
	hint("ai_hold", Vector3(-3, GALLERY, -1), 180.0, "B")
	hint("ai_cover", Vector3(-40, 0, -14), 180.0, "A")
	hint("ai_cover", Vector3(-46, 0, -24), 180.0, "A")
	hint("ai_cover", Vector3(44, 0, -20), 180.0, "B")
	hint("ai_cover", Vector3(50, 0, -16), 180.0, "B")
	hint("ai_angle", Vector3(-54, 0, -7), 0.0, "A")
	hint("ai_angle", Vector3(-35.5, 0, -6), 0.0, "A")
	hint("ai_angle", Vector3(36, 0, -11), 0.0, "B")
	hint("ai_angle", Vector3(54, 0, -7), 0.0, "B")


func _check(analysis: MapAnalysis) -> bool:
	var rampart := analysis.path_length(Vector3(-50, 0, -20), Vector3(-63.5, RAMPART, -14))
	var gallery := analysis.path_length(Vector3(0, 0, -14), Vector3(-4, GALLERY, -2))
	print("Yard → rampart: %.1f m; bailey → gallery: %.1f m" % [rampart, gallery])
	if rampart < 0.0 or gallery < 0.0:
		printerr("The rampart or the gallery cannot be reached.")
		return false
	return analysis.issues.is_empty()


## Lamp fixtures wherever reachable floor sat in shade with no lamp in reach (each placed on the
## nearest wall, or hung from the ceiling indoors), and everyday clutter against walls along the
## routes, clear of doors, stairs, bombsites, spawns and timing chokepoints.
func _lamps_and_props() -> void:
	layer("Lamps")
	for entry: Array in [
		["lamp_hanging", Vector3(-26.00, 3.10, -29.00), 0.0],
		["lamp_wall", Vector3(-4.00, 2.10, -45.75), 0.0],
		["lamp_wall", Vector3(36.00, 2.10, -29.75), 0.0],
		["lamp_wall", Vector3(52.00, 2.10, -29.75), 0.0],
		["lamp_wall", Vector3(55.86, 2.10, -7.25), -33.0],
		["lamp_wall", Vector3(62.97, 2.10, -6.00), -129.0],
		["lamp_wall", Vector3(63.75, 2.10, 3.00), -90.0],
		# Shaded lanes and yards (open to the sky, but in shadow with no lamp in reach).
		["lamp_wall", Vector3(-60.00, 2.10, -44.75), 0.0],
		["lamp_wall", Vector3(-58.00, 2.10, -2.75), 0.0],
		["lamp_wall", Vector3(-58.41, 2.10, -26.25), 180.0],
		["lamp_wall", Vector3(-50.25, 2.10, 23.00), -90.0],
		["lamp_wall", Vector3(-52.00, 2.10, 39.75), 180.0],
		["lamp_wall", Vector3(-50.25, 2.10, 7.00), -90.0],
		["lamp_wall", Vector3(-48.00, 2.10, -44.75), 0.0],
		["lamp_wall", Vector3(-38.00, 2.10, 39.75), 180.0],
		["lamp_wall", Vector3(-36.00, 2.10, -29.75), 0.0],
		["lamp_wall", Vector3(-33.40, 2.10, -2.15), 0.0],
		["lamp_wall", Vector3(-32.25, 2.10, 29.00), -90.0],
		["lamp_wall", Vector3(-32.25, 2.10, 15.00), -90.0],
		["lamp_wall", Vector3(-30.65, 2.10, -15.14), -90.0],
		["lamp_wall", Vector3(-26.00, 2.10, 39.75), 180.0],
		["lamp_wall", Vector3(-22.00, 2.10, -2.75), 0.0],
		["lamp_wall", Vector3(-20.00, 2.10, -20.75), 0.0],
		["lamp_wall", Vector3(-16.00, 2.10, 32.25), 0.0],
		["lamp_wall", Vector3(-12.00, 2.10, -43.45), 0.0],
		["lamp_wall", Vector3(-19.75, 2.10, 57.00), 90.0],
		["lamp_wall", Vector3(-10.00, 2.10, -31.05), 180.0],
		["lamp_wall", Vector3(-8.56, 2.10, 2.77), 69.0],
		["lamp_wall", Vector3(-10.00, 2.10, 32.25), 0.0],
		["lamp_wall", Vector3(-2.75, 2.10, -30.00), 90.0],
		["lamp_wall", Vector3(4.00, 2.10, -31.05), 180.0],
		["lamp_wall", Vector3(9.93, 2.10, 4.01), -16.0],
		["lamp_wall", Vector3(6.00, 2.10, 21.75), 180.0],
		["lamp_wall", Vector3(12.00, 2.10, -43.45), 0.0],
		["lamp_wall", Vector3(23.75, 2.10, 11.00), -90.0],
		["lamp_wall", Vector3(16.00, 2.10, 32.25), 0.0],
		["lamp_wall", Vector3(22.00, 2.10, -2.75), 0.0],
		["lamp_wall", Vector3(19.75, 2.10, 49.00), -90.0],
		["lamp_wall", Vector3(19.75, 2.10, 59.00), -90.0],
		["lamp_wall", Vector3(23.75, 2.10, 19.00), -90.0],
		["lamp_wall", Vector3(29.35, 2.10, -25.00), -90.0],
		["lamp_wall", Vector3(28.00, 2.10, 32.25), 0.0],
		["lamp_wall", Vector3(29.35, 2.10, -11.00), -90.0],
		["lamp_wall", Vector3(32.75, 2.10, 1.00), -90.0],
		["lamp_wall", Vector3(32.25, 2.10, 13.00), 90.0],
		["lamp_wall", Vector3(32.25, 2.10, 25.00), 90.0],
		["lamp_wall", Vector3(42.00, 2.10, -44.75), 0.0],
		["lamp_wall", Vector3(42.00, 2.10, 34.25), 0.0],
		["lamp_wall", Vector3(52.00, 2.10, -44.75), 0.0],
		["lamp_wall", Vector3(50.25, 2.10, 33.00), 90.0],
		["lamp_wall", Vector3(63.75, 2.10, 17.00), -90.0],
		["lamp_wall", Vector3(63.75, 2.10, 27.00), -90.0],
		["lamp_wall", Vector3(65.75, 2.10, -39.00), -90.0],
		["lamp_wall", Vector3(63.75, 2.10, 37.00), -90.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))
	layer("Street life")
	for entry: Array in [
		["sack_pile", Vector3(28.00, 0.00, 32.61), 0.0],
		["coopered_barrel", Vector3(60.00, 0.00, -31.27), 180.0],
		["pottery_jar", Vector3(46.00, 0.00, 39.54), 180.0],
		["planter", Vector3(18.00, 0.00, -4.36), 180.0],
		["notice_board", Vector3(-8.00, 0.00, 21.87), 180.0],
		["stone_trough", Vector3(14.00, 0.00, 21.51), 180.0],
		["brazier", Vector3(11.59, 4.50, -4.46), 180.0],
		["sack_pile", Vector3(-40.00, 0.00, 34.61), 0.0],
		["coopered_barrel", Vector3(-16.00, 0.00, 32.47), 0.0],
		["pottery_jar", Vector3(42.00, 0.00, -4.46), 180.0],
		["planter", Vector3(-50.00, 0.00, 39.64), 180.0],
		["notice_board", Vector3(10.00, 0.00, 32.13), 0.0],
		["stone_trough", Vector3(30.00, 0.00, 5.51), 180.0],
		["brazier", Vector3(-26.00, 0.00, -4.46), 180.0],
		["sack_pile", Vector3(-28.00, 0.00, 32.61), 0.0],
		["coopered_barrel", Vector3(-11.65, 0.00, 4.00), -30.0],
		["pottery_jar", Vector3(-6.00, 0.00, -8.46), 180.0],
		["planter", Vector3(-60.64, 0.00, -7.00), 90.0],
		["notice_board", Vector3(11.48, 0.00, 3.71), 30.0],
		["stone_trough", Vector3(-40.00, 0.00, -29.51), 0.0],
		["brazier", Vector3(18.00, 0.00, -29.54), 0.0],
		["sack_pile", Vector3(-20.00, 0.00, -31.41), 180.0],
		["coopered_barrel", Vector3(28.00, 0.00, -29.53), 0.0],
		["pottery_jar", Vector3(6.00, 0.00, 21.54), 180.0],
		["planter", Vector3(-18.00, 0.00, -4.36), 180.0],
		["notice_board", Vector3(32.87, 0.00, -9.00), -90.0],
		["stone_trough", Vector3(60.00, 0.00, -9.51), 0.0],
		["brazier", Vector3(38.00, 0.00, 39.54), 180.0],
		["sack_pile", Vector3(-62.00, 0.00, 39.39), 180.0],
		["coopered_barrel", Vector3(-30.00, 0.00, -31.27), 180.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))
