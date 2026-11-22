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
## Revision 3 (owner, 2026-11-22: flesh it out and give it its own character): a highland keep in
## low golden afternoon light under broken cloud and mountains. Timber-framed village houses
## under steep slate gables with chimneys, arrow slits and machicolations on the castle, a sanded
## tiltyard, a grass cloister garth, pennants on every tower and banners along the curtain.
func _revision() -> int:
	return 3


func _build() -> void:
	controller.set_metadata("Kestrel Keep", "F2F official",
		"Granite fortress above a village. A: the Tiltyard, by the West Gate road or the Breach. B: the Cloister, by the Orchard Walk or the Undercroft. Both open onto the Bailey behind the Gatehouse.")
	controller.set_lighting({"sun_yaw": 250.0, "sun_pitch": 24.0, "sun_energy": 1.2, "sun_color": "ffd9a6",
		"ambient_color": "a9b6c6", "ambient_energy": 0.58, "haze": 0.32, "sky": "highland_afternoon"})
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
	_highland_dressing()
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
	for house: Array in [[-50, -40, -3, 14, 6.5], [-50, -40, 14, 34, 7.5], [-32, -24, 6, 22, 6.0], [-32, -6, 22, 32, 7.0],
			[40, 50, -3, 14, 6.5], [40, 50, 14, 34, 7.5], [24, 32, 6, 22, 6.0], [6, 32, 22, 32, 7.0]]:
		_cottage(float(house[0]), float(house[1]), float(house[2]), float(house[3]), float(house[4]))
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


## A village house: limewashed walls under a steep slate gable along its long side, a chimney.
func _cottage(x1: float, x2: float, z1: float, z2: float, height: float) -> void:
	mass("building", x1, x2, z1, z2, height, "limewash")
	var along_x := x2 - x1 >= z2 - z1
	var span := (z2 - z1) if along_x else (x2 - x1)
	gable(x1 - 0.4, x2 + 0.4, z1 - 0.4, z2 + 0.4, height, height + span * 0.45, "slate", along_x)
	var stack := Vector2(x2 - 1.2, (z1 + z2) / 2.0) if along_x else Vector2((x1 + x2) / 2.0, z2 - 1.2)
	put("block", Vector3(stack.x, height, stack.y), Vector3(0.9, span * 0.45 + 1.4, 0.9), 0.0, {}, "mossy_stone")
	put("block", Vector3(stack.x, height + span * 0.45 + 1.4, stack.y), Vector3(1.1, 0.2, 1.1), 0.0, {}, "granite_blocks")


# --- highland character (revision 3) --------------------------------------------------------------

func _highland_dressing() -> void:
	layer("Ground finishes")
	# Each laid 2 cm proud (bots step 10 cm).
	mass("floor", -61, -30.4, -29.6, -4.4, 0.05, "sand", -0.03)          # the tiltyard, sanded
	mass("floor", 34, 53, -24, -6, 0.05, "grass_worn", -0.03)            # the cloister garth
	mass("floor", -66, 66, -45, -30.8, 0.05, "flagstones", -0.03)        # the Inner Ward
	layer("Village facades")
	dress_facades({
		"plinth": "mossy_stone", "plinth_h": 0.5,
		"window": {"type": "window", "size": Vector3(0.9, 1.1, 0.25), "props": {"panes_x": 3, "panes_y": 3, "shutters": false},
			"materials": ["wood_dark"]},
		"window_every": 3.0, "first_sill": 1.1, "storey": 2.8, "blank": 0.2,
		"door": {"type": "door", "size": Vector3(1.1, 2.2, 0.3), "props": {"panels": 4, "fanlight": false},
			"materials": ["wood_dark", "weathered_wood"]},
		"door_chance": 0.6, "extra": _timber_frame,
	}, Rect2(-66, -3, 132, 67))
	layer("Castle facades")
	dress_facades({
		"plinth": "mossy_stone", "plinth_h": 0.8,
		"window": {"type": "window", "size": Vector3(0.35, 1.3, 0.3), "props": {"panes_x": 1, "panes_y": 2, "shutters": false},
			"materials": ["metal_dark"]},
		"window_every": 3.5, "first_sill": 2.2, "storey": 4.0, "blank": 0.25, "min_height": 3.5,
		"extra": _machicolations,
	}, Rect2(-66, -54, 132, 51))
	layer("Heraldry")
	# Pennants on poles above every tower, banners along the curtain and the keep.
	for tower: Array in [[-66, -3.5, 13.0], [66, -3.5, 13.0], [-66, -54, 13.0], [66, -54, 13.0], [-10.5, 2, 9.0],
			[10.5, 2, 9.0], [-12, -46, 19.0], [12, -46, 19.0], [57, -9, 14.0]]:
		var at := Vector3(float(tower[0]), float(tower[2]), float(tower[1]))
		put("column", at, Vector3(0.18, 4.0, 0.18), 0.0, {}, "weathered_wood")
		put("banner", at + Vector3(0.75, 2.2, 0), Vector3(1.4, 1.6, 0.08), 0.0, {},
			"cloth_blue" if int(tower[0]) <= 0 else "cloth_red")
	for x: float in [-24.0, -16.0, 16.0, 24.0]:
		put("banner", Vector3(x, 2.6, -2.9), Vector3(1.4, 3.4, 0.12), 0.0, {}, "cloth_blue" if x < 0.0 else "cloth_red")
	for x: float in [-8.0, 8.0]:
		put("banner", Vector3(x, 9.0, -45.9), Vector3(1.8, 5.0, 0.12), 0.0, {}, "cloth_red")
	layer("Village life")
	# Hay and firewood by the houses, washing across the back of the green.
	for entry: Array in [
		["sack_pile", Vector3(-48.8, 0, 36.2), 0.0], ["pallet", Vector3(-46.5, 0, 36.4), 0.0],
		["sack_pile", Vector3(48.8, 0, 36.2), 180.0], ["pallet", Vector3(46.5, 0, 36.4), 0.0],
		["coopered_barrel", Vector3(-22.6, 0, 40.8), 0.0], ["coopered_barrel", Vector3(22.6, 0, 40.8), 0.0],
		["washing_line", Vector3(-30, 0, 62.0), 0.0], ["washing_line", Vector3(30, 0, 62.0), 0.0],
		["planter", Vector3(-19.5, 0, 34.0), 90.0], ["planter", Vector3(19.5, 0, 34.0), -90.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))


## Dark timber framing on a village wall: posts between the windows, rails at the floors.
func _timber_frame(run: Dictionary) -> void:
	var from: Vector2 = run["from"]
	var along: Vector2 = run["along"]
	var facing: Vector2 = run["facing"]
	var length := float(run["length"])
	var ground := float(run["ground"])
	var top := float(run["top"])
	var yaw := float(run["yaw"])
	var door_at := float(run["door_at"])
	for y: float in [ground + 0.55, ground + 2.6, top - 0.3]:
		if y + 0.2 <= top:
			band(from, along, facing, 0.0, length, y, 0.2, 0.07, "wood_dark", yaw)
	var slots := window_slots(length, 3.0, 0.9)
	var count := int(slots.x)
	var offset := slots.y
	var posts: Array[float] = [0.1, length - 0.1]
	for k: int in count - 1:
		posts.append(offset + 3.0 * (float(k) + 0.5))
	for t: float in posts:
		if door_at > 0.0 and absf(t - door_at) < 0.9:
			continue
		band(from, along, facing, t - 0.1, t + 0.1, ground + 0.55, top - ground - 0.6, 0.07, "wood_dark", yaw)


## A row of stone corbels under the top of a castle wall.
func _machicolations(run: Dictionary) -> void:
	var from: Vector2 = run["from"]
	var along: Vector2 = run["along"]
	var facing: Vector2 = run["facing"]
	var length := float(run["length"])
	var top := float(run["top"])
	var yaw := float(run["yaw"])
	if top - float(run["ground"]) < 5.0:
		return
	band(from, along, facing, 0.0, length, top - 0.5, 0.5, 0.45, "granite_blocks", yaw)
	var t := 0.5
	while t <= length - 0.5:
		band(from, along, facing, t - 0.18, t + 0.18, top - 1.1, 0.6, 0.35, "granite_blocks", yaw)
		t += 1.2
