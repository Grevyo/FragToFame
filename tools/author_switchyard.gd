extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Switchyard": a rail switching station built over a
## turbine vault. Most of the play is on the surface: site A is the Machine Hall, overlooked by
## the Control Deck on its roof. Site B is the Turbine Vault 8 m underground.
##
## Ways down to the vault: the Freight Ramp in the middle of the yard, the West Stairwell inside
## the hall, the defenders' North Stair, the East Culvert ramp from the Tank Yard, the Coal
## Chute (a drop from the Coal Cut) and the Vent (a drop from site A). Bots use the stairs and
## ramps; the chute and the vent are for people.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_switchyard.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const DECK: float = 5.0
const VAULT: float = -8.0
const SITE_A: Vector3 = Vector3(-2, 0, 2)
const SITE_B: Vector3 = Vector3(-1, VAULT, 1)
## Openings in the surface (x1, x2, z1, z2).
const STAIRWELL_HOLE: Array = [-14, -11, -10, 0]
const RAMP_HOLE: Array = [-3, 3, 14, 34]
const CHUTE_HOLE: Array = [-36, -33, 8, 11]
const NORTH_STAIR_HOLE: Array = [2, 6, -30, -10]
const CULVERT_HOLE: Array = [26, 30, -6, 14]
const VENT_HOLE: Array = [6, 9, 2, 5]


func _official_id() -> String:
	return "map_f2f_switchyard"


## Revision 2: the underground rework (site B moved to the Turbine Vault).
func _revision() -> int:
	return 2


func _build() -> void:
	controller.set_metadata("Switchyard", "F2F official",
		"Rail switching station over a turbine vault. A: the Machine Hall, under the Control Deck. B: the Turbine Vault, 8 m below ground, reached by two ramps, two stairs, a coal chute and a vent.")
	controller.set_lighting({"sun_yaw": 230.0, "sun_pitch": 38.0, "sun_energy": 1.1,
		"sun_color": "e2ecff", "ambient_color": "a9b6c6", "ambient_energy": 0.62})
	_ground()
	_machine_hall()
	_control_deck()
	_stair_tower()
	_deck_routes()
	_yards()
	_vault()
	_ways_down()
	_tunnels()
	_props()
	_gameplay()
	_callouts()
	_tactical()


## The surface is one slab 1 m thick with the openings cut out; it is also the vault's ceiling.
func _ground() -> void:
	layer("Ground and boundary")
	slab_with_holes("floor", -46, 46, -48, 74, 1.0, "concrete", -1.0,
		[STAIRWELL_HOLE, RAMP_HOLE, CHUTE_HOLE, NORTH_STAIR_HOLE, CULVERT_HOLE, VENT_HOLE])
	for wall: Array in [[-46, 46, -48.5, -48], [-46, 46, 74, 74.5]]:
		mass("wall", wall[0], wall[1], wall[2], wall[3], 8.0, "concrete")
	for wall: Array in [[-46.5, -46, -48, 74], [46, 46.5, -48, 74]]:
		mass("wall", wall[0], wall[1], wall[2], wall[3], 8.0, "concrete")


## Site A: the Machine Hall, walls 4.7 m high, four doors, a stairwell and a vent down.
func _machine_hall() -> void:
	layer("Switch house · Machine Hall (A)")
	mass("wall", -14, -4, 9.7, 10.3, 4.7, "concrete")
	put("doorway", Vector3(0, 0, 10), Vector3(8, 4.7, 0.6), 0.0, {"opening_width": 6.0, "opening_height": 3.6}, "metal_painted")
	mass("wall", 4, 14, 9.7, 10.3, 4.7, "concrete")
	mass("wall", -14, -2, -10.3, -9.7, 4.7, "concrete")
	put("doorway", Vector3(0, 0, -10), Vector3(4, 4.7, 0.6), 0.0, {"opening_width": 2.4, "opening_height": 2.7}, "metal_dark")
	mass("wall", 2, 14, -10.3, -9.7, 4.7, "concrete")
	mass("wall", -14.3, -13.7, -10, 0, 4.7, "concrete")
	put("doorway", Vector3(-14, 0, 2), Vector3(4, 4.7, 0.6), 90.0, {"opening_width": 2.0, "opening_height": 2.6}, "metal_dark")
	mass("wall", -14.3, -13.7, 4, 10, 4.7, "concrete")
	mass("wall", 13.7, 14.3, -10, 4, 4.7, "concrete")
	put("doorway", Vector3(14, 0, 6), Vector3(4, 4.7, 0.6), 90.0, {"opening_width": 2.0, "opening_height": 2.6}, "metal_dark")
	mass("wall", 13.7, 14.3, 8, 10, 4.7, "concrete")
	for column: Vector3 in [Vector3(-7, 0, -5), Vector3(4, 0, -5), Vector3(-10, 0, 6.5)]:
		put("column", column, Vector3(1.2, 4.7, 1.2), 0.0, {}, "concrete")
	mass("block", 2, 5, 4, 7, 2.7, "metal_painted")
	mass("block", -2, 1, -7.5, -5.5, 2.2, "metal_dark")
	put("low_cover", Vector3(-4, 0, -1), Vector3(3.5, 1.05, 0.6), 90.0, {}, "hazard_paint")
	put("braced_crate", Vector3(-9, 0, 7.5), Vector3(1.5, 1.2, 1.2))
	put("crate_stack", Vector3(9.5, 0, 8.4), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(-3, 3.4, -9.2), Vector3(20, 0.6, 0.6), 0.0, {}, "metal_rust")
	# The vent drops 8 m into the vault; rails on two sides.
	put("railing", Vector3(7.5, 0, 1.95), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(9.05, 0, 3.5), Vector3(3, 1.05, 0.06), 90.0, {}, "hazard_paint")
	for lamp_at: Vector3 in [Vector3(-8, 4.1, 3), Vector3(-1, 4.1, -3), Vector3(6, 4.1, 7), Vector3(10, 4.1, -1)]:
		lamp(lamp_at, 3.0, 10.0, "ffbb78")


## The Control Deck: the hall's roof at 5 m, a perch over site A through an open atrium.
func _control_deck() -> void:
	layer("Switch house · Control Deck")
	slab_with_holes("floor", -14, 14, -10, 10, 0.3, "metal_painted", DECK - 0.3, [[8, 14, -10, -2], [-6, 2, -2, 4]])
	put("railing", Vector3(-2, DECK, -2.05), Vector3(8, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-2, DECK, 4.05), Vector3(8, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-6.05, DECK, 1), Vector3(6, 1.05, 0.06), 90.0, {}, "hazard_paint")
	put("railing", Vector3(2.05, DECK, 1), Vector3(6, 1.05, 0.06), 90.0, {}, "hazard_paint")
	mass("wall", -8, 8, -10.3, -9.7, 4.0, "concrete", DECK)
	mass("wall_half", -14, -12, -10.3, -9.7, 1.1, "metal_dark", DECK)
	mass("wall_half", -14, 14, 9.7, 10.3, 1.1, "metal_dark", DECK)
	mass("wall_half", -14.3, -13.7, -4, 9.7, 1.1, "metal_dark", DECK)
	mass("wall_half", 13.7, 14.3, 2, 9.7, 1.1, "metal_dark", DECK)
	mass("block", -4, -1, -6.4, -5, 1.2, "metal_dark", DECK)
	mass("block", 4.5, 6.5, 5.5, 8.5, 2.2, "metal_painted", DECK)
	put("crate_long", Vector3(-3, DECK, 7), Vector3(3.2, 1.1, 1.3), 0.0, {}, "metal_rust")
	put("shipping_container", Vector3(-10.5, DECK, -6.5), Vector3(2.44, 2.6, 5.0), 0.0, {}, "metal_painted")
	layer("Canopy · hide to edit the deck")
	for pillar: Vector3 in [Vector3(-7.5, DECK, -7.5), Vector3(7.5, DECK, -7.5), Vector3(-7.5, DECK, 7.5), Vector3(7.5, DECK, 7.5)]:
		put("pillar", pillar, Vector3(0.45, 4.0, 0.45), 0.0, {}, "metal_dark")
	mass("roof", -9, 9, -9, 9, 0.35, "metal_dark", DECK + 4.0)
	spot(Vector3(-3, DECK + 3.8, 6), 5.0, 10.0, 60.0, "b8ddff")
	spot(Vector3(4, DECK + 3.8, -5), 5.0, 10.0, 60.0, "b8ddff")


## A switchback stair from the hall up to the deck in the north-east corner.
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
func _deck_routes() -> void:
	layer("Deck routes · west stair, deck ramp, service stair")
	put("stairs", Vector3(-18, 0, 2), Vector3(4, DECK, 12), 0.0, {}, "metal_dark")
	mass("platform", -20, -14, -10, -4, DECK, "concrete")
	mass("wall_half", -20.3, -20, -10, -4, 1.1, "metal_painted", DECK)
	mass("wall_half", -20, -14, -10.3, -10, 1.1, "metal_painted", DECK)
	put("ramp", Vector3(18.5, 0, 10), Vector3(5, DECK, 16), 0.0, {}, "concrete")
	mass("platform", 14, 21, -4, 2, DECK, "concrete")
	mass("wall_half", 21, 21.3, -4, 2, 1.1, "metal_painted", DECK)
	mass("wall_half", 14, 21, -4.3, -4, 1.1, "metal_painted", DECK)
	put("stairs", Vector3(-10, 0, -16), Vector3(4, DECK, 12), 180.0, {}, "metal_dark")
	put("railing", Vector3(-12.05, 0, -16), Vector3(12, 1.05, 0.06), 90.0)


## Walls between the spawn road, the three lanes and the Receiving Yard.
func _yards() -> void:
	layer("Yard buildings and walls")
	for wall: Array in [[-30, -5], [5, 30]]:
		mass("wall", wall[0], wall[1], 56, 56.6, 6.0, "concrete")
	mass("building", -46, -40, 56, 74, 7.0, "concrete")
	mass("building", 40, 46, 56, 74, 7.0, "concrete")
	mass("building", -46, -40, -16, 56, 8.0, "metal_rust")
	mass("building", -30, -22, 20, 56, 7.0, "concrete")
	mass("wall", -22.6, -22, 14, 20, 6.0, "concrete")
	mass("building", -36, -28, -10, -2, 6.0, "metal_dark")
	mass("building", 40, 46, -16, 56, 8.0, "metal_painted")
	mass("building", 22, 30, 22, 56, 7.0, "concrete")
	mass("wall", -34, -20, -16.6, -16, 6.0, "concrete")
	mass("wall", -20.6, -20, -16, -10, 6.0, "concrete")
	mass("wall", 21, 34, -16.6, -16, 6.0, "concrete")
	mass("wall", 21, 21.6, -16, -4, 6.0, "concrete")
	mass("building", -46, -24, -48, -36, 7.0, "concrete")
	mass("building", 24, 46, -48, -36, 7.0, "concrete")
	mass("building", -46, -40, -36, -16, 8.0, "metal_rust")
	mass("building", 40, 46, -36, -16, 8.0, "metal_painted")
	mass("building", 7, 13, 34, 39, 4.5, "metal_painted")
	put("catwalk", Vector3(10, 4.5, 36.5), Vector3(8, 1.22, 7), 0.0, {}, "steel_grating")
	put("stairs", Vector3(10, 0, 46), Vector3(3, 4.62, 12), 0.0, {}, "metal_dark")
	for leg: float in [-17.0, 17.0]:
		mass("pillar", leg - 0.5, leg + 0.5, 27.5, 28.5, 9.3, "hazard_paint")
	mass("block", -17.5, 17.5, 27.4, 28.6, 0.8, "hazard_paint", 8.5)
	mass("building", -26, -18, -30, -24, 3.5, "concrete")
	mass("building", 14, 20, -30, -24, 3.5, "metal_painted")
	put("low_cover", Vector3(-6, 0, -27), Vector3(3.5, 1.05, 0.6), 0.0, {}, "concrete")
	put("low_cover", Vector3(10, 0, -33), Vector3(3.5, 1.05, 0.6), 0.0, {}, "concrete")


## Site B: the Turbine Vault under the hall, 7 m tall, with a gantry along its east wall.
func _vault() -> void:
	layer("Underground · Turbine Vault (B)")
	mass("floor", -8, 14, -10, 10, 1.0, "concrete", VAULT - 1.0)
	_underground_wall(-8.6, -8, -10, 0)
	_underground_wall(-8.6, -8, 3, 4)
	_underground_wall(-8.6, -8, 8, 10)
	_underground_wall(-8, 2, -10.6, -10)
	_underground_wall(6, 14.6, -10.6, -10)
	_underground_wall(14, 14.6, -6, 10)
	_underground_wall(-8, -3, 10, 10.6)
	_underground_wall(3, 14, 10, 10.6)
	# The gantry: a catwalk 4 m up along the east wall, climbed from the vault floor.
	put("catwalk", Vector3(12, VAULT + 3.88, -5.5), Vector3(4, 1.22, 9), 0.0, {}, "steel_grating")
	put("stairs", Vector3(12.5, VAULT, 4), Vector3(3, 4, 10), 0.0, {}, "metal_dark")
	# Turbines, pipework and cover.
	put("storage_tank", Vector3(-4, VAULT, -6), Vector3(3.6, 5.5, 3.6), 0.0, {}, "metal_painted")
	put("storage_tank", Vector3(7.8, VAULT, 7.6), Vector3(3.2, 5.5, 3.2), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(0, VAULT + 5.0, -9.3), Vector3(16, 0.7, 0.7), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(-7.4, VAULT + 4.4, 0), Vector3(18, 0.6, 0.6), 90.0, {}, "metal_painted")
	put("braced_crate", Vector3(-3, VAULT, 3.5), Vector3(1.5, 1.2, 1.2))
	put("crate_stack", Vector3(3.5, VAULT, -3), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("low_cover", Vector3(0.5, VAULT, 6), Vector3(3.5, 1.05, 0.6), 0.0, {}, "hazard_paint")
	put("column", Vector3(5, VAULT, 4), Vector3(1.2, 7.0, 1.2), 0.0, {}, "concrete")
	for lamp_at: Vector3 in [Vector3(-4, VAULT + 5.6, 2), Vector3(5, VAULT + 5.6, -4), Vector3(8, VAULT + 5.6, 5), Vector3(12, VAULT + 6.0, -6)]:
		lamp(lamp_at, 2.8, 11.0, "9fd0ff")


## The stairwell inside the hall and the three long climbs between the surface and the vault.
func _ways_down() -> void:
	layer("Underground · ways down")
	# West Stairwell: from the hall down to a landing at -4, then down to the vault floor.
	mass("floor", -14, -8, -14, 3, 1.0, "concrete", VAULT - 1.0)
	mass("block", -14, -11, -10, 0, 4.0, "concrete", VAULT)
	put("stairs", Vector3(-12.5, VAULT + 4.0, -5), Vector3(3, 4, 10), 180.0, {}, "metal_dark")
	mass("platform", -14, -8, -14, -10, 4.0, "concrete", VAULT)
	put("stairs", Vector3(-9.5, VAULT, -5), Vector3(3, 4, 10), 0.0, {}, "metal_dark")
	mass("wall", -11.15, -10.85, -10, 0, 9.1, "concrete", VAULT)
	_underground_wall(-14.6, -14, -14.6, 3)
	_underground_wall(-14, -8, -14.6, -14)
	_underground_wall(-8.6, -8, -14, -10)
	_underground_wall(-14, -8, 3, 4)
	lamp(Vector3(-11, VAULT + 6.0, -12), 2.2, 9.0, "ffd6a9")
	# Freight Ramp: down from the middle of the Freight Yard into the Ramp Tunnel.
	put("ramp", Vector3(0, VAULT, 24), Vector3(6, 8, 20), 180.0, {}, "concrete")
	_underground_wall(-3.6, -3, 10, 34)
	_underground_wall(3, 3.6, 10, 34)
	mass("wall_half", -3.3, -3, 14, 34, 1.1, "concrete")
	mass("wall_half", 3, 3.3, 14, 34, 1.1, "concrete")
	put("railing", Vector3(0, 0, 13.95), Vector3(6, 1.05, 0.06), 0.0, {}, "hazard_paint")
	# North Stair: the defenders' way down from the Receiving Yard.
	put("stairs", Vector3(4, VAULT, -20), Vector3(4, 8, 20), 0.0, {}, "metal_dark")
	_underground_wall(1.4, 2, -30, -10)
	_underground_wall(6, 6.6, -30, -10)
	put("railing", Vector3(1.95, 0, -20), Vector3(20, 1.05, 0.06), 90.0)
	put("railing", Vector3(6.05, 0, -20), Vector3(20, 1.05, 0.06), 90.0)
	# East Culvert: a ramp down from the Tank Yard to the culvert tunnel.
	put("ramp", Vector3(28, VAULT, 4), Vector3(4, 8, 20), 180.0, {}, "concrete")
	_underground_wall(25.4, 26, -6, 14)
	_underground_wall(30, 30.6, -10, 14)
	mass("wall_half", 25.7, 26, -6, 14, 1.1, "concrete")
	mass("wall_half", 30, 30.3, -6, 14, 1.1, "concrete")
	put("railing", Vector3(28, 0, -6.05), Vector3(4, 1.05, 0.06), 0.0, {}, "hazard_paint")
	# Coal Chute: an open shaft from the Coal Cut, railed on two sides.
	put("railing", Vector3(-34.5, 0, 7.95), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-34.5, 0, 11.05), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")


## Tunnels at vault level: the Ramp Tunnel, the Coal Tunnel and Chute Room, and the Culvert.
func _tunnels() -> void:
	layer("Underground · tunnels")
	mass("floor", -3, 3, 10, 14, 1.0, "concrete", VAULT - 1.0)
	# Coal Tunnel and the Chute Room under the shaft.
	mass("floor", -30, -8, 4, 8, 1.0, "concrete", VAULT - 1.0)
	mass("floor", -38, -30, 4, 14, 1.0, "concrete", VAULT - 1.0)
	_underground_wall(-30, -14, 3.4, 4)
	_underground_wall(-30, -8, 8, 8.6)
	_underground_wall(-38.6, -38, 4, 14)
	_underground_wall(-38, -30, 14, 14.6)
	_underground_wall(-38, -30, 3.4, 4)
	_underground_wall(-30, -29.4, 8.6, 14)
	put("crate_stack", Vector3(-36, VAULT, 5.2), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_dark")
	put("barrel_cluster", Vector3(-20, VAULT, 7))
	put("pipe_run", Vector3(-19, VAULT + 5.2, 4.5), Vector3(22, 0.6, 0.6), 0.0, {}, "metal_rust")
	# The Culvert from the East Culvert ramp to the vault's east wall.
	mass("floor", 14, 30, -10, -6, 1.0, "concrete", VAULT - 1.0)
	_underground_wall(14, 30.6, -10.6, -10)
	_underground_wall(14, 25.4, -6, -5.4)
	put("pipe_run", Vector3(22, VAULT + 5.0, -9.4), Vector3(16, 0.7, 0.7), 0.0, {}, "metal_painted")
	put("barrel_cluster", Vector3(23, VAULT, -7))
	for lamp_at: Vector3 in [Vector3(0, VAULT + 5.0, 12), Vector3(-22, VAULT + 5.0, 6), Vector3(-34, VAULT + 4.0, 9),
			Vector3(20, VAULT + 5.0, -8), Vector3(0, -3.0, 22), Vector3(28, -3.0, 4), Vector3(4, -3.0, -20)]:
		lamp(lamp_at, 2.4, 10.0, "ffc58a")


## A wall from the vault floor up to the underside of the surface slab.
func _underground_wall(x1: float, x2: float, z1: float, z2: float) -> void:
	mass("wall", x1, x2, z1, z2, -1.0 - VAULT, "concrete", VAULT)


func _props() -> void:
	layer("Freight Yard")
	put("shipping_container", Vector3(-10, 0, 24), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(-10, 2.6, 24.5), Vector3.ZERO, 0.0, {}, "metal_painted")
	put("shipping_container", Vector3(11, 0, 28), Vector3.ZERO, 90.0, {}, "metal_painted")
	put("shipping_container", Vector3(-15, 0, 44), Vector3.ZERO, 90.0)
	put("shipping_container", Vector3(16, 0, 46), Vector3.ZERO, 0.0, {}, "metal_dark")
	put("vehicle_truck", Vector3(-4, 0, 44), Vector3.ZERO, 90.0)
	put("crate_stack", Vector3(-7, 0, 15), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(7, 0, 15))
	put("sandbag_wall", Vector3(-6, 0, 37), Vector3(3, 1.1, 0.8))
	layer("Coal Lane and Boiler Yard")
	put("crate_stack", Vector3(-37, 0, 46), Vector3.ZERO, 90.0, {}, "metal_rust")
	put("vehicle_cart", Vector3(-33, 0, 36), Vector3.ZERO, 20.0)
	mass("block", -40, -36, 24, 28, 2.4, "metal_rust")
	put("barrel_cluster", Vector3(-31.5, 0, 22))
	mass("block", -30, -26, 15, 18, 1.6, "metal_dark")
	put("pipe_run", Vector3(-31, 0, 4), Vector3(18, 4.2, 0.7), 0.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(-24, 0, -13))
	put("braced_crate", Vector3(-38, 0, -13), Vector3(1.5, 1.2, 1.2))
	layer("Tank Row and Tank Yard")
	put("storage_tank", Vector3(36, 0, 44), Vector3(4, 6, 4))
	put("storage_tank", Vector3(33, 0, 30), Vector3(3.5, 5, 3.5), 0.0, {}, "metal_rust")
	mass("block", 36, 40, 22, 25, 1.6, "metal_dark")
	put("storage_tank", Vector3(36, 0, 2), Vector3(7, 10, 7), 0.0, {}, "concrete")
	put("storage_tank", Vector3(36, 0, -11), Vector3(4, 6, 4), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(31, 0, 19), Vector3(18, 4.0, 0.8))
	put("crate_stack", Vector3(24.5, 0, -12), Vector3.ZERO, 90.0, {}, "metal_painted")
	layer("Receiving Yard")
	put("vehicle_truck", Vector3(-30, 0, -26), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(26, 0, -28), Vector3.ZERO, 0.0)
	put("shipping_container", Vector3(30, 0, -28), Vector3.ZERO, 0.0, {}, "metal_painted")
	put("crate_stack", Vector3(11, 0, -20), Vector3.ZERO, 90.0, {}, "metal_rust")
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
	spawns("defence", Vector3(0, 0, -38), 180.0, Vector3(24, 3, 8))
	put("bombsite", SITE_A, Vector3(12, 3, 9), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(12, 3, 10), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Attack Road", -40, 40, 56.6, 74)
	area("Yard Gate", -5, 5, 50, 56.6)
	area("Freight Yard", -22, 22, 20, 50, "mid")
	area("Ramp Head", -5, 5, 34, 38)
	area("Signal Box", 6, 14, 33, 40, "", 4.62)
	area("Box Stair", 8.5, 11.5, 40, 52)
	area("Stair Foot", -22, -14, 8, 14)
	area("Deck Ramp Foot", 14, 22, 18, 22)
	area("Loading Gate", -5, 5, 10.3, 14, "entrance_a")
	area("Coal Lane", -40, -30, 20, 56)
	area("Coal Cut", -40, -22, 6, 20)
	area("Coal Chute", -36, -33, 8, 11)
	area("Boiler Yard", -40, -20.6, -16, 6)
	area("Tank Row", 30, 40, 22, 56)
	area("Tank Cut", 22, 40, 14, 22)
	area("Tank Yard", 21.6, 40, -16, 14)
	area("Stair Corridor", -16, -14.3, 4, 8)
	area("Coal Door", -16, -14.3, 0, 4, "entrance_a")
	area("Ramp Corridor", 14.3, 16, 8, 18)
	area("Pump Door", 14.3, 16, 4, 8, "entrance_a")
	area("Machine Hall", -13.7, 13.7, -9.7, 9.7)
	area("Vent", 6, 9, 2, 5)
	area("Stair Tower", 8, 14, -10, -2)
	area("North Door", -2, 2, -16, -10.3)
	area("Receiving Yard", -40, 40, -36, -16)
	area("Depot", -24, 24, -48, -36)
	area("Service Stair", -12, -8, -22, -10)
	area("West Stair", -20, -16, -4, 8)
	area("West Landing", -20, -14, -10, -4, "", DECK)
	area("Deck Ramp", 16, 21, 2, 18)
	area("Ramp Top", 14, 21, -4, 2, "", DECK)
	area("Control Deck", -13.7, 13.7, -9.7, 9.7, "", DECK)
	area("Boiler Gap", -40, -34, -20, -16.6)
	area("Pipe Gap", 34, 40, -20, -16.6)
	area("Freight Ramp", -3, 3, 14, 34, "", VAULT)
	area("Ramp Tunnel", -3, 3, 10, 14, "entrance_b", VAULT)
	area("Turbine Vault", -8, 14, -10, 10, "", VAULT)
	area("Gantry", 10, 14, -10, -1, "", VAULT + 4.0)
	area("West Stairwell", -14, -8, -10, 3, "", VAULT)
	area("Stair Landing", -14, -8, -14, -10, "", VAULT + 4.0)
	area("Coal Tunnel", -30, -8, 4, 8, "", VAULT)
	area("Chute Room", -38, -30, 4, 14, "", VAULT)
	area("North Stair", 2, 6, -30, -10, "", VAULT)
	area("Culvert", 14, 26, -10, -6, "entrance_b", VAULT)
	area("Culvert Ramp", 26, 30, -6, 14, "", VAULT)


func _tactical() -> void:
	layer("Tactics")
	anchor("Hall plant machine", "plant", SITE_A + Vector3(-3, 0, 2))
	anchor("Hall plant columns", "plant", SITE_A + Vector3(3, 0, -3))
	anchor("Vault plant crates", "plant", SITE_B + Vector3(-3, 0, 1))
	anchor("Vault plant turbine", "plant", SITE_B + Vector3(2, 0, -2))
	anchor("Yard hold", "default", Vector3(8, 0, 24))
	anchor("Ramp Head hold", "default", Vector3(0, 0, 37))
	anchor("Deck perch", "default", Vector3(-8, DECK, 6))
	anchor("Gantry post", "default", Vector3(12, VAULT + 4.0, -5))
	anchor("Coal Cut hold", "default", Vector3(-28, 0, 12))
	anchor("Gate smoke", "utility", Vector3(0, 0, 12))
	anchor("Ramp smoke", "utility", Vector3(0, 0, 36))
	anchor("Culvert smoke", "utility", Vector3(28, 0, 16))
	anchor("Coal Door smoke", "utility", Vector3(-15.2, 0, 2))
	hint("ai_hold", Vector3(-11, 0, -7), 150.0, "A")
	hint("ai_hold", Vector3(6.5, 0, -6.5), 220.0, "A")
	hint("ai_hold", Vector3(-8, DECK, -4), 180.0, "A")
	hint("ai_hold", Vector3(-6, VAULT, -8), 150.0, "B")
	hint("ai_hold", Vector3(12, VAULT + 4.0, -7), 225.0, "B")
	hint("ai_hold", Vector3(-6, VAULT, 8), 60.0, "B")
	hint("ai_cover", Vector3(3.5, 0, 3.4), 180.0, "A")
	hint("ai_cover", Vector3(-5, 0, -2.6), 180.0, "A")
	hint("ai_cover", Vector3(-3, VAULT, 2.4), 180.0, "B")
	hint("ai_cover", Vector3(3.5, VAULT, -1.6), 180.0, "B")
	hint("ai_angle", Vector3(0, 0, 12), 0.0, "A")
	hint("ai_angle", Vector3(-15.5, 0, 2), 0.0, "A")
	hint("ai_angle", Vector3(0, VAULT, 12), 0.0, "B")
	hint("ai_angle", Vector3(18, VAULT, -8), 0.0, "B")


func _check(analysis: MapAnalysis) -> bool:
	var sites := MapZones.bombsite_at(controller.document, SITE_A) == "A" \
		and MapZones.bombsite_at(controller.document, SITE_B) == "B"
	var routes: Dictionary[String, float] = {
		"West Stairwell": analysis.path_length(Vector3(-5, 0, 0), Vector3(-6, VAULT, 1.5)),
		"Freight Ramp": analysis.path_length(Vector3(0, 0, 37), Vector3(0, VAULT, 12)),
		"North Stair": analysis.path_length(Vector3(4, 0, -32), Vector3(4, VAULT, -8)),
		"East Culvert": analysis.path_length(Vector3(28, 0, 16), Vector3(20, VAULT, -8)),
		"Gantry": analysis.path_length(Vector3(8, VAULT, 2), Vector3(12, VAULT + 4.0, -6)),
	}
	var ok := sites
	for route: String in routes:
		print("%s: %.1f m" % [route, routes[route]])
		ok = ok and routes[route] > 0.0 and routes[route] < 60.0
	if not ok:
		printerr("A site or one of the ways down to the vault is wrong.")
		return false
	return analysis.issues.is_empty()
