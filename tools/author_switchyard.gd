extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Switchyard": a rail switching station whose two
## bombsites are stacked in one building. The Machine Hall (B) is on the ground floor and the
## Control Deck (A) is its roof. An inner stair tower and a drop hatch join them; outside, a
## west stair, an east freight ramp and a defenders' service stair climb to the deck.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_switchyard.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const DECK: float = 5.0
const SITE_A: Vector3 = Vector3(1, DECK, 1)
const SITE_B: Vector3 = Vector3(-3, 0, 3)


func _official_id() -> String:
	return "map_f2f_switchyard"


func _build() -> void:
	controller.set_metadata("Switchyard", "F2F official",
		"Rail switching station. Both bombsites share one building: the Machine Hall (B) on the ground and the Control Deck (A) on its roof, joined by an inner stair and a drop hatch.")
	controller.set_lighting({"sun_yaw": 230.0, "sun_pitch": 38.0, "sun_energy": 1.1,
		"sun_color": "e2ecff", "ambient_color": "a9b6c6", "ambient_energy": 0.68})
	_ground()
	_house_ground_floor()
	_house_deck()
	_stair_tower()
	_outside_routes()
	_yards()
	_props()
	_gameplay()
	_callouts()
	_tactical()


func _ground() -> void:
	layer("Ground and boundary")
	mass("floor", -46, 46, -48, 74, 1.0, "concrete", -1.0)
	for wall: Array in [[-46, 46, -48.5, -48], [-46, 46, 74, 74.5]]:
		mass("wall", wall[0], wall[1], wall[2], wall[3], 8.0, "concrete")
	for wall: Array in [[-46.5, -46, -48, 74], [46, 46.5, -48, 74]]:
		mass("wall", wall[0], wall[1], wall[2], wall[3], 8.0, "concrete")


## The Machine Hall: walls 4.7 m high, four ways in.
func _house_ground_floor() -> void:
	layer("Switch house · Machine Hall")
	# South wall and the Loading Gate.
	mass("wall", -14, -4, 9.7, 10.3, 4.7, "concrete")
	put("doorway", Vector3(0, 0, 10), Vector3(8, 4.7, 0.6), 0.0, {"opening_width": 6.0, "opening_height": 3.6}, "metal_painted")
	mass("wall", 4, 14, 9.7, 10.3, 4.7, "concrete")
	# North wall and the North Door.
	mass("wall", -14, -2, -10.3, -9.7, 4.7, "concrete")
	put("doorway", Vector3(0, 0, -10), Vector3(4, 4.7, 0.6), 0.0, {"opening_width": 2.4, "opening_height": 2.7}, "metal_dark")
	mass("wall", 2, 14, -10.3, -9.7, 4.7, "concrete")
	# West wall and the Coal Door.
	mass("wall", -14.3, -13.7, -10, 0, 4.7, "concrete")
	put("doorway", Vector3(-14, 0, 2), Vector3(4, 4.7, 0.6), 90.0, {"opening_width": 2.0, "opening_height": 2.6}, "metal_dark")
	mass("wall", -14.3, -13.7, 4, 10, 4.7, "concrete")
	# East wall and the Pump Door.
	mass("wall", 13.7, 14.3, -10, 4, 4.7, "concrete")
	put("doorway", Vector3(14, 0, 6), Vector3(4, 4.7, 0.6), 90.0, {"opening_width": 2.0, "opening_height": 2.6}, "metal_dark")
	mass("wall", 13.7, 14.3, 8, 10, 4.7, "concrete")
	# Columns carrying the deck, and the machines.
	for column: Vector3 in [Vector3(-7, 0, -5), Vector3(4, 0, -5), Vector3(-10, 0, 6.5)]:
		put("column", column, Vector3(1.2, 4.7, 1.2), 0.0, {}, "concrete")
	mass("block", 4, 8, 2, 5.4, 2.7, "metal_painted")
	mass("block", -2, 1, -7.5, -5.5, 2.2, "metal_dark")
	put("low_cover", Vector3(-4, 0, -1), Vector3(3.5, 1.05, 0.6), 90.0, {}, "hazard_paint")
	put("braced_crate", Vector3(-11.5, 0, 0.5), Vector3(1.5, 1.2, 1.2))
	put("crate_stack", Vector3(9.5, 0, 8.4), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(-3, 3.4, -9.2), Vector3(20, 0.6, 0.6), 0.0, {}, "metal_rust")
	for lamp_at: Vector3 in [Vector3(-8, 4.1, 3), Vector3(-1, 4.1, -3), Vector3(6, 4.1, 7), Vector3(10, 4.1, -1)]:
		lamp(lamp_at, 3.0, 10.0, "ffbb78")


## The Control Deck: the hall's roof at 5 m, with a hatch over site B.
func _house_deck() -> void:
	layer("Switch house · Control Deck")
	# Deck slabs around the stair tower (x 8..14, z -10..-2) and the hatch (x -8..-6, z 3..5).
	mass("floor", -14, 8, -10, 3, 0.3, "metal_painted", DECK - 0.3)
	mass("floor", -14, -8, 3, 5, 0.3, "metal_painted", DECK - 0.3)
	mass("floor", -6, 8, 3, 5, 0.3, "metal_painted", DECK - 0.3)
	mass("floor", -14, 8, 5, 10, 0.3, "metal_painted", DECK - 0.3)
	mass("floor", 8, 14, -2, 10, 0.3, "metal_painted", DECK - 0.3)
	put("railing", Vector3(-7, DECK, 5.1), Vector3(2, 1.05, 0.06), 0.0, {}, "hazard_paint")
	# Deck edge: a solid back wall, half walls elsewhere, gaps where the three outside routes arrive.
	mass("wall", -8, 8, -10.3, -9.7, 4.0, "concrete", DECK)
	mass("wall_half", -14, -12, -10.3, -9.7, 1.1, "metal_dark", DECK)
	mass("wall_half", -14, 14, 9.7, 10.3, 1.1, "metal_dark", DECK)
	mass("wall_half", -14.3, -13.7, -4, 9.7, 1.1, "metal_dark", DECK)
	mass("wall_half", 13.7, 14.3, 2, 9.7, 1.1, "metal_dark", DECK)
	# Consoles and cover on the deck.
	mass("block", -4, -1, -6, -4.6, 1.2, "metal_dark", DECK)
	mass("block", 4.5, 6.5, 5.5, 8.5, 2.2, "metal_painted", DECK)
	put("crate_long", Vector3(-3, DECK, 7), Vector3(3.2, 1.1, 1.3), 0.0, {}, "metal_rust")
	put("shipping_container", Vector3(-10.5, DECK, -6.5), Vector3(2.44, 2.6, 5.0), 0.0, {}, "metal_painted")
	layer("Canopy · hide to edit the deck")
	for pillar: Vector3 in [Vector3(-7.5, DECK, -7.5), Vector3(7.5, DECK, -7.5), Vector3(-7.5, DECK, 7.5), Vector3(7.5, DECK, 7.5)]:
		put("pillar", pillar, Vector3(0.45, 4.0, 0.45), 0.0, {}, "metal_dark")
	mass("roof", -9, 9, -9, 9, 0.35, "metal_dark", DECK + 4.0)
	spot(Vector3(-3, DECK + 3.8, 0), 5.0, 10.0, 60.0, "b8ddff")
	spot(Vector3(4, DECK + 3.8, 2), 5.0, 10.0, 60.0, "b8ddff")


## A switchback stair between the hall and the deck in the north-east corner.
func _stair_tower() -> void:
	layer("Switch house · Stair tower")
	put("stairs", Vector3(12.5, 0, -5), Vector3(3, DECK / 2.0, 6), 0.0, {}, "metal_dark")
	mass("platform", 8, 14, -10, -8, DECK / 2.0, "concrete")
	mass("block", 8, 11, -8, -2, DECK / 2.0, "concrete")
	put("stairs", Vector3(9.5, DECK / 2.0, -5), Vector3(3, DECK / 2.0, 6), 180.0, {}, "metal_dark")
	mass("wall", 10.85, 11.15, -8, -2, DECK + 1.1, "concrete")
	put("railing", Vector3(8.05, DECK, -6), Vector3(8, 1.05, 0.06), 90.0)
	put("railing", Vector3(12.5, DECK, -2.05), Vector3(3, 1.05, 0.06))
	mass("wall", 8, 14, -10.3, -9.7, 4.0, "concrete", DECK)
	mass("wall", 13.7, 14.3, -10, -2, 4.0, "concrete", DECK)
	lamp(Vector3(11, 3.6, -9), 2.2, 8.0, "ffd6a9")


## The three climbs to the deck from outside.
func _outside_routes() -> void:
	layer("Outside routes · stair, ramp, service stair")
	# West stair from the yard, rising north to the West Landing.
	put("stairs", Vector3(-18, 0, 2), Vector3(4, DECK, 12), 0.0, {}, "metal_dark")
	mass("platform", -20, -14, -10, -4, DECK, "concrete")
	mass("wall_half", -20.3, -20, -10, -4, 1.1, "metal_painted", DECK)
	mass("wall_half", -20, -14, -10.3, -10, 1.1, "metal_painted", DECK)
	# East freight ramp from the yard, rising north to the Ramp Top.
	put("ramp", Vector3(18.5, 0, 10), Vector3(5, DECK, 16), 0.0, {}, "concrete")
	mass("platform", 14, 21, -4, 2, DECK, "concrete")
	mass("wall_half", 21, 21.3, -4, 2, 1.1, "metal_painted", DECK)
	mass("wall_half", 14, 21, -4.3, -4, 1.1, "metal_painted", DECK)
	# Defenders' service stair from the Receiving Yard, rising south onto the deck.
	put("stairs", Vector3(-10, 0, -16), Vector3(4, DECK, 12), 180.0, {}, "metal_dark")
	put("railing", Vector3(-12.05, 0, -16), Vector3(12, 1.05, 0.06), 90.0)


## Walls between the spawn road, the three lanes and the Receiving Yard.
func _yards() -> void:
	layer("Yard buildings and walls")
	# The attackers' road (z 56..74) opens into the three lanes.
	for wall: Array in [[-30, -5], [5, 30]]:
		mass("wall", wall[0], wall[1], 56, 56.6, 6.0, "concrete")
	mass("building", -46, -40, 56, 74, 7.0, "concrete")
	mass("building", 40, 46, 56, 74, 7.0, "concrete")
	# West lane: the Coal Lane between the coal sheds, turning east at the Coal Cut.
	mass("building", -46, -40, -16, 56, 8.0, "metal_rust")
	mass("building", -30, -22, 20, 56, 7.0, "concrete")
	mass("wall", -22.6, -22, 14, 20, 6.0, "concrete")
	mass("building", -36, -28, -10, -2, 6.0, "metal_dark")
	# East lane: Tank Row between the pump houses, turning west at the Tank Cut.
	mass("building", 40, 46, -16, 56, 8.0, "metal_painted")
	mass("building", 22, 30, 22, 56, 7.0, "concrete")
	# North walls with one gap each into the Receiving Yard.
	mass("wall", -34, -20, -16.6, -16, 6.0, "concrete")
	mass("wall", -20.6, -20, -16, -10, 6.0, "concrete")
	mass("wall", 21, 34, -16.6, -16, 6.0, "concrete")
	mass("wall", 21, 21.6, -16, -4, 6.0, "concrete")
	# The Receiving Yard's depot buildings.
	mass("building", -46, -24, -48, -36, 7.0, "concrete")
	mass("building", 24, 46, -48, -36, 7.0, "concrete")
	mass("building", -46, -40, -36, -16, 8.0, "metal_rust")
	mass("building", 40, 46, -36, -16, 8.0, "metal_painted")
	# The Signal Box splits the Freight Yard.
	mass("building", 7, 13, 34, 39, 4.5, "metal_painted")
	# Its roof is a railed catwalk reached by a stair from the south: a perch over the yard.
	put("catwalk", Vector3(10, 4.5, 36.5), Vector3(8, 1.22, 7), 0.0, {}, "steel_grating")
	put("stairs", Vector3(10, 0, 46), Vector3(3, 4.62, 12), 0.0, {}, "metal_dark")
	# A gantry crane spans the yard overhead.
	for leg: float in [-17.0, 17.0]:
		mass("pillar", leg - 0.5, leg + 0.5, 27.5, 28.5, 9.3, "hazard_paint")
	mass("block", -17.5, 17.5, 27.4, 28.6, 0.8, "hazard_paint", 8.5)
	# The Receiving Yard's guard hut, fuel store and barriers.
	mass("building", -26, -18, -30, -24, 3.5, "concrete")
	mass("building", 14, 20, -30, -24, 3.5, "metal_painted")
	put("low_cover", Vector3(-6, 0, -27), Vector3(3.5, 1.05, 0.6), 0.0, {}, "concrete")
	put("low_cover", Vector3(6, 0, -27), Vector3(3.5, 1.05, 0.6), 0.0, {}, "concrete")


func _props() -> void:
	layer("Freight Yard")
	put("shipping_container", Vector3(-10, 0, 24), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(-10, 2.6, 24.5), Vector3.ZERO, 0.0, {}, "metal_painted")
	put("shipping_container", Vector3(11, 0, 28), Vector3.ZERO, 90.0, {}, "metal_painted")
	put("shipping_container", Vector3(-15, 0, 44), Vector3.ZERO, 90.0)
	put("shipping_container", Vector3(16, 0, 46), Vector3.ZERO, 0.0, {}, "metal_dark")
	put("vehicle_truck", Vector3(-4, 0, 44), Vector3.ZERO, 90.0)
	put("crate_stack", Vector3(-3, 0, 15), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(4, 0, 14.5))
	put("sandbag_wall", Vector3(-2, 0, 34), Vector3(3, 1.1, 0.8))
	layer("Coal Lane and Boiler Yard")
	put("crate_stack", Vector3(-37, 0, 46), Vector3.ZERO, 90.0, {}, "metal_rust")
	put("vehicle_cart", Vector3(-33, 0, 36), Vector3.ZERO, 20.0)
	mass("block", -40, -36, 24, 28, 2.4, "metal_rust")
	put("barrel_cluster", Vector3(-31.5, 0, 22))
	mass("block", -34, -30, 10, 13, 1.6, "metal_dark")
	put("pipe_run", Vector3(-31, 0, 4), Vector3(18, 4.2, 0.7), 0.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(-24, 0, -13))
	put("braced_crate", Vector3(-38, 0, -13), Vector3(1.5, 1.2, 1.2))
	layer("Tank Row and Tank Yard")
	put("storage_tank", Vector3(36, 0, 44), Vector3(4, 6, 4))
	put("storage_tank", Vector3(33, 0, 30), Vector3(3.5, 5, 3.5), 0.0, {}, "metal_rust")
	mass("block", 36, 40, 22, 25, 1.6, "metal_dark")
	put("storage_tank", Vector3(32, 0, 0), Vector3(8, 10, 8), 0.0, {}, "concrete")
	put("storage_tank", Vector3(36, 0, -11), Vector3(4, 6, 4), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(31, 0, 10), Vector3(18, 4.0, 0.8))
	put("crate_stack", Vector3(24.5, 0, -12), Vector3.ZERO, 90.0, {}, "metal_painted")
	layer("Receiving Yard")
	put("vehicle_truck", Vector3(-30, 0, -26), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(26, 0, -28), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(30, 0, -28), Vector3.ZERO, 0.0, {}, "metal_painted")
	put("crate_stack", Vector3(10, 0, -22), Vector3.ZERO, 90.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(-4, 0, -20))
	layer("Lights")
	lamp(Vector3(-17, 2.4, 9), 2.0, 9.0)
	lamp(Vector3(15, 2.4, 12), 2.0, 9.0)
	lamp(Vector3(0, 3.0, 11), 2.4, 10.0)
	lamp(Vector3(-10, 3.0, -11), 2.0, 9.0)
	lamp(Vector3(10, 3.6, 33.5), 2.0, 9.0)


func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(0, 0, 66), 0.0, Vector3(24, 3, 10))
	spawns("defence", Vector3(0, 0, -36), 180.0, Vector3(24, 3, 10))
	put("bombsite", SITE_B, Vector3(12, 3, 9), 0.0, {"site": "B"})
	put("bombsite", SITE_A, Vector3(12, 3, 9), 0.0, {"site": "A"})


func _callouts() -> void:
	layer("Tactics")
	area("Attack Road", -40, 40, 56.6, 74)
	area("Yard Gate", -5, 5, 50, 56.6)
	area("Freight Yard", -22, 22, 20, 50, "mid")
	area("Signal Box", 6, 14, 33, 40, "", 4.62)
	area("Box Stair", 8.5, 11.5, 40, 52)
	area("Stair Foot", -22, -14, 8, 14)
	area("Ramp Foot", 14, 22, 18, 22)
	area("Loading Gate", -5, 5, 10.3, 14, "entrance_b")
	area("Coal Lane", -40, -30, 20, 56)
	area("Coal Cut", -40, -22, 6, 20)
	area("Boiler Yard", -40, -20.6, -16, 6)
	area("Tank Row", 30, 40, 22, 56)
	area("Tank Cut", 22, 40, 14, 22)
	area("Tank Yard", 21.6, 40, -16, 14)
	area("Stair Corridor", -16, -14.3, 4, 8)
	area("Coal Door", -16, -14.3, 0, 4, "entrance_b")
	area("Ramp Corridor", 14.3, 16, 8, 18)
	area("Pump Door", 14.3, 16, 4, 8, "entrance_b")
	area("Machine Hall", -13.7, 13.7, -9.7, 9.7)
	area("Stair Tower", 8, 14, -10, -2)
	area("North Door", -3, 3, -16, -10.3)
	area("Receiving Yard", -40, 40, -36, -16)
	area("Depot", -24, 24, -48, -36)
	area("Service Stair", -12, -8, -22, -10)
	area("West Stair", -20, -16, -4, 8)
	area("West Landing", -20, -14, -10, -4, "entrance_a", DECK)
	area("Freight Ramp", 16, 21, 2, 18)
	area("Ramp Top", 14, 21, -4, 2, "entrance_a", DECK)
	area("Control Deck", -13.7, 13.7, -9.7, 9.7, "", DECK)
	area("Boiler Gap", -40, -34, -20, -16.6)
	area("Pipe Gap", 34, 40, -20, -16.6)


func _tactical() -> void:
	layer("Tactics")
	anchor("Deck plant open", "plant", SITE_A + Vector3(-2, 0, 2))
	anchor("Deck plant console", "plant", SITE_A + Vector3(3, 0, -3))
	anchor("Hall plant gate", "plant", SITE_B + Vector3(1, 0, 3))
	anchor("Hall plant hatch", "plant", SITE_B + Vector3(-4, 0, 1))
	anchor("Yard hold", "default", Vector3(0, 0, 26))
	anchor("Stair Foot hold", "default", Vector3(-18, 0, 14))
	anchor("Ramp Foot hold", "default", Vector3(18, 0, 21))
	anchor("Deck back post", "default", Vector3(-6, DECK, -8))
	anchor("Gate smoke", "utility", Vector3(0, 0, 12))
	anchor("Stair smoke", "utility", Vector3(-18, 0, 9))
	anchor("Ramp smoke", "utility", Vector3(18.5, 0, 17))
	hint("ai_hold", Vector3(-6, DECK, -6), 160.0, "A")
	hint("ai_hold", Vector3(8, DECK, 5), 270.0, "A")
	hint("ai_hold", Vector3(-11, DECK, 6), 135.0, "A")
	hint("ai_hold", Vector3(-6, 0, -6), 180.0, "B")
	hint("ai_hold", Vector3(10, 0, 3), 230.0, "B")
	hint("ai_hold", Vector3(-11, 0, 8), 120.0, "B")
	hint("ai_cover", Vector3(-2.5, DECK, -6.6), 180.0, "A")
	hint("ai_cover", Vector3(5.5, DECK, 4.6), 180.0, "A")
	hint("ai_cover", Vector3(6, 0, 1.4), 180.0, "B")
	hint("ai_cover", Vector3(-0.5, 0, -8.2), 180.0, "B")
	hint("ai_angle", Vector3(-17, DECK, -7), 0.0, "A")
	hint("ai_angle", Vector3(17.5, DECK, -1), 0.0, "A")
	hint("ai_angle", Vector3(0, 0, 12), 0.0, "B")
	hint("ai_angle", Vector3(15, 0, 6), 0.0, "B")


func _check(analysis: MapAnalysis) -> bool:
	var stacked := MapZones.bombsite_at(controller.document, SITE_A) == "A" \
		and MapZones.bombsite_at(controller.document, SITE_B) == "B"
	var inner := analysis.path_length(Vector3(12.5, 0, 0), Vector3(9.5, DECK, 0))
	print("Inner stair hall → deck: %.1f m" % inner)
	if not stacked or inner < 0.0 or inner > 30.0:
		printerr("The stacked sites or the inner stair are wrong.")
		return false
	return analysis.issues.is_empty()
