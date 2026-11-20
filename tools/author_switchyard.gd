extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Switchyard": a rail switching station built over a
## turbine works. Most of the play is on the surface: site A is the Machine Hall, an angled
## seven-sided shed overlooked by the Control Deck on its roof. Site B is the Turbine Vault 8 m
## underground, a hall of its own reached through a network of tunnels.
##
## Ways down (bots use every stair and ramp; the chute and the vent are drops for people):
##   Freight Ramp  — middle of the Freight Yard, down to the Junction (Main and East Doors)
##   Coal Stair    — Coal Lane, down to the Chute Room and the Coal Tunnel (West Door)
##   Coal Chute    — a drop from the Coal Cut into the Chute Room
##   Cable Gallery — an angled tunnel joining the Junction to the Coal Tunnel
##   East Culvert  — Tank Yard ramp, down to the bent Culvert (Culvert Door)
##   North Stair   — the defenders' stair from the Receiving Yard (North Door)
##   West Stairwell and Vent — inside the Machine Hall, straight from A to B
##
## Run:  <godot> --headless --path <project> --script res://tools/author_switchyard.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const DECK: float = 5.0
const VAULT: float = -8.0
const CEILING: float = -1.0
const SITE_A: Vector3 = Vector3(-2, 0, 3)
const SITE_B: Vector3 = Vector3(3, VAULT, 1)

## The playable outline: the perimeter wall follows it and the ground is laid inside it.
const OUTLINE: Array = [Vector2(-50, -62), Vector2(18, -62), Vector2(30, -56), Vector2(58, -56),
	Vector2(58, -8), Vector2(62, 6), Vector2(62, 58), Vector2(54, 74), Vector2(50, 98), Vector2(-42, 98),
	Vector2(-54, 82), Vector2(-60, 58), Vector2(-60, 16), Vector2(-56, 2), Vector2(-58, -34)]
## The Machine Hall's seven walls (also the Control Deck's outline).
const HALL: Array = [Vector2(-16, -12), Vector2(9, -12), Vector2(16, -6), Vector2(16, 8), Vector2(10, 14),
	Vector2(-11, 14), Vector2(-16, 9)]
## The Turbine Vault, the Junction south of it, the Chute Room and the tunnels.
const VAULT_HALL: Array = [Vector2(-9, -14), Vector2(12, -14), Vector2(21, -5), Vector2(21, 9), Vector2(13, 18),
	Vector2(-3, 18), Vector2(-9, 12)]
const JUNCTION: Array = [Vector2(-3, 18), Vector2(13, 18), Vector2(11, 27), Vector2(4, 30), Vector2(-3, 30),
	Vector2(-10, 28.2), Vector2(-4, 22.2)]
const CHUTE_ROOM: Array = [Vector2(-52, 2), Vector2(-34, 2), Vector2(-30, 6), Vector2(-30, 12), Vector2(-40, 22),
	Vector2(-52, 22)]
const CABLE_GALLERY: Array = [Vector2(-25.02, 10), Vector2(-19.38, 10), Vector2(-5.59, 23.79), Vector2(-8.41, 26.61)]
const CULVERT: Array = [Vector2(38, -11), Vector2(38, -7), Vector2(21, 1), Vector2(21, -3)]

## Openings in the surface (x1, x2, z1, z2).
const STAIRWELL_HOLE: Array = [-15, -12, -10, 0]
const VENT_HOLE: Array = [6, 9, 3, 6]
const RAMP_HOLE: Array = [-3, 3, 30, 50]
const NORTH_STAIR_HOLE: Array = [4, 8, -36, -16]
const CULVERT_HOLE: Array = [40, 44, -6, 14]
const COAL_STAIR_HOLE: Array = [-50, -46, 22, 42]
const CHUTE_HOLE: Array = [-36, -33, 8, 11]


func _official_id() -> String:
	return "map_f2f_switchyard"


## Revision 3: the expanded, angled rework with the tunnel network.
func _revision() -> int:
	return 3


func _build() -> void:
	controller.set_metadata("Switchyard", "F2F official",
		"Rail switching station over a turbine works. A: the Machine Hall, under the Control Deck. B: the Turbine Vault, 8 m below ground, reached by ramps, stairs, tunnels, a coal chute and a vent.")
	controller.set_lighting({"sun_yaw": 230.0, "sun_pitch": 38.0, "sun_energy": 1.1,
		"sun_color": "e2ecff", "ambient_color": "a9b6c6", "ambient_energy": 0.62})
	_ground()
	_machine_hall()
	_control_deck()
	_deck_routes()
	_north_side()
	_west_side()
	_east_side()
	_freight_yard()
	_sidings()
	_vault()
	_stairwell()
	_junction()
	_coal_works()
	_culvert()
	_north_stair()
	_gameplay()
	_callouts()
	_tactical()


# --- surface ------------------------------------------------------------------------------------

## The surface is one floor 1 m thick with the shafts cut out; it is also the tunnels' ceiling.
func _ground() -> void:
	layer("Ground and boundary")
	floor_shape(OUTLINE, 0.0, 1.0, "concrete",
		[STAIRWELL_HOLE, VENT_HOLE, RAMP_HOLE, NORTH_STAIR_HOLE, CULVERT_HOLE, COAL_STAIR_HOLE, CHUTE_HOLE])
	walls_around(OUTLINE, 8.0, 0.0, "concrete")


## Site A: the Machine Hall, seven walls 4.7 m high with five ways in.
func _machine_hall() -> void:
	layer("Switch house · Machine Hall (A)")
	# North Door, Pump Door, Loading Gate, the Breach in the south-west corner and the Coal Door.
	walls_around(HALL, DECK - 0.3, 0.0, "concrete", {0: [[19, 22]], 2: [[9, 12]], 4: [[7, 13]], 5: [[2.2, 4.9]], 6: [[6, 9]]})
	mass("wall", 3, 6, -12.3, -11.7, 1.9, "metal_dark", 2.8)
	mass("wall", 15.7, 16.3, 3, 6, 1.9, "metal_dark", 2.8)
	mass("wall", -3, 3, 13.7, 14.3, 0.9, "metal_painted", 3.8)
	mass("wall", -16.3, -15.7, 0, 3, 1.9, "metal_dark", 2.8)
	put("block", Vector3(-12.2, 0, 13.6), Vector3(1.4, 0.7, 1.0), 45.0, {}, "concrete")
	put("block", Vector3(-15.1, 0, 10.4), Vector3(1.2, 1.3, 0.9), 30.0, {}, "concrete")
	# Inside: a stair up to the deck along the north wall, the stairwell down and the vent.
	put("stairs", Vector3(-6, 0, -10.2), Vector3(3, DECK, 12), 90.0, {}, "metal_dark")
	mass("block", -15.7, -12, -11.7, -10, 1.1, "concrete")
	put("railing", Vector3(-15.05, 0, -5), Vector3(10, 1.05, 0.06), 90.0, {}, "hazard_paint")
	put("railing", Vector3(7.5, 0, 2.95), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(9.05, 0, 4.5), Vector3(3, 1.05, 0.06), 90.0, {}, "hazard_paint")
	for column: Vector3 in [Vector3(-8, 0, -5), Vector3(6, 0, -5), Vector3(-10, 0, 8)]:
		put("column", column, Vector3(1.2, DECK - 0.3, 1.2), 0.0, {}, "concrete")
	mass("block", 8, 11, 7, 10, 2.7, "metal_painted")
	mass("block", -2, 1, -7, -5, 2.2, "metal_dark")
	put("low_cover", Vector3(-5, 0, 0.5), Vector3(3.5, 1.05, 0.6), 90.0, {}, "hazard_paint")
	put("braced_crate", Vector3(-9.5, 0, 11), Vector3(1.5, 1.2, 1.2), 20.0)
	put("crate_stack", Vector3(11, 0, 11.2), Vector3(2.6, 2.4, 1.2), -45.0, {}, "metal_rust")
	put("storage_tank", Vector3(12.5, 0, -2), Vector3(3, 4.2, 3), 0.0, {}, "metal_painted")
	put("pipe_run", Vector3(5, 3.4, -11.2), Vector3(7, 0.6, 0.6), 0.0, {}, "metal_rust")
	for lamp_at: Vector3 in [Vector3(-9, 4.1, 3), Vector3(-1, 4.1, -4), Vector3(4, 4.1, 9), Vector3(11, 4.1, 1)]:
		lamp(lamp_at, 3.0, 10.0, "ffbb78")


## The Control Deck: the hall's roof at 5 m, a perch over site A through an open atrium.
func _control_deck() -> void:
	layer("Switch house · Control Deck")
	floor_shape(HALL, DECK, 0.3, "metal_painted", [[-6, 2, -3, 4], [-12, 0.3, -11.7, -8.7]])
	walls_around(HALL, 1.1, DECK, "metal_dark", {1: [[2.61, 6.61]], 2: [[2, 8]], 6: [[14, 20]]}, [], "wall_half", 0.4)
	put("railing", Vector3(-2, DECK, -3.05), Vector3(8, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-2, DECK, 4.05), Vector3(8, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-6.05, DECK, 0.5), Vector3(7, 1.05, 0.06), 90.0, {}, "hazard_paint")
	put("railing", Vector3(2.05, DECK, 0.5), Vector3(7, 1.05, 0.06), 90.0, {}, "hazard_paint")
	put("railing", Vector3(-5.85, DECK, -8.65), Vector3(12.3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(0.35, DECK, -10.2), Vector3(3, 1.05, 0.06), 90.0, {}, "hazard_paint")
	put("shipping_container", Vector3(-12, DECK, 4), Vector3(2.44, 2.6, 5.0), 0.0, {}, "metal_painted")
	mass("block", 5, 7.5, 6, 9, 2.2, "metal_painted", DECK)
	mass("block", 6, 9, -7, -5.5, 1.2, "metal_dark", DECK)
	put("crate_long", Vector3(-3, DECK, 9), Vector3(3.2, 1.1, 1.3), 15.0, {}, "metal_rust")
	layer("Canopy · hide to edit the deck")
	for pillar: Vector3 in [Vector3(-9.5, DECK, -7.5), Vector3(7.5, DECK, -7.5), Vector3(-9.5, DECK, 10), Vector3(7.5, DECK, 10)]:
		put("pillar", pillar, Vector3(0.45, 4.0, 0.45), 0.0, {}, "metal_dark")
	mass("roof", -10, 8, -8, 10.5, 0.35, "metal_dark", DECK + 4.0)
	spot(Vector3(-3, DECK + 3.8, 6), 5.0, 10.0, 60.0, "b8ddff")
	spot(Vector3(4, DECK + 3.8, -5), 5.0, 10.0, 60.0, "b8ddff")


## The three climbs to the deck from outside: West Stair, Deck Ramp and the angled Service Stair.
func _deck_routes() -> void:
	layer("Deck routes")
	put("stairs", Vector3(-20, 0, 1), Vector3(4, DECK, 12), 0.0, {}, "metal_dark")
	mass("platform", -22, -16, -11, -5, DECK, "concrete")
	mass("wall_half", -22.3, -22, -11, -5, 1.1, "metal_painted", DECK)
	mass("wall_half", -22, -16, -11.3, -11, 1.1, "metal_painted", DECK)
	mass("wall_half", -18, -16, -5.3, -5, 1.1, "metal_painted", DECK)
	put("ramp", Vector3(20.5, 0, 10), Vector3(5, DECK, 16), 0.0, {}, "concrete")
	mass("platform", 16, 23, -4, 2, DECK, "concrete")
	mass("wall_half", 23, 23.3, -4, 2, 1.1, "metal_painted", DECK)
	mass("wall_half", 16, 23, -4.3, -4, 1.1, "metal_painted", DECK)
	# The Service Stair climbs at an angle onto the hall's north-east face.
	put("stairs", Vector3(16.4, 0, -13.55), Vector3(4, DECK, 12), 139.4, {}, "metal_dark")
	lamp(Vector3(-19, 2.4, 9), 2.0, 9.0)
	lamp(Vector3(18, 2.4, 12), 2.0, 9.0)


## Defender side: the Depot, the Receiving Yard and the Boiler House.
func _north_side() -> void:
	layer("Depot and Receiving Yard")
	prism([Vector2(-50, -62), Vector2(-22, -62), Vector2(-22, -50), Vector2(-36, -44), Vector2(-57, -40)], 0.0, 7.0, "concrete")
	prism([Vector2(24, -62), Vector2(58, -56), Vector2(58, -40), Vector2(34, -42), Vector2(24, -50)], 0.0, 7.0, "concrete")
	prism([Vector2(-57, -30), Vector2(-38, -32), Vector2(-32, -20), Vector2(-36, -8), Vector2(-54, -4)], 0.0, 9.0, "metal_rust")
	put("storage_tank", Vector3(-44, 9.0, -18), Vector3(4, 3, 4), 0.0, {}, "metal_dark")
	# Walls that split the Receiving Yard from the Boiler Yard and the Tank Yard, with gaps.
	wall_line(Vector2(-32, -20), Vector2(-20, -17), 6.0, 0.0, "concrete", [[6.5, 10.5]])
	wall_line(Vector2(23, -4), Vector2(30, -16), 6.0, 0.0, "concrete")
	wall_line(Vector2(30, -16), Vector2(58, -20), 6.0, 0.0, "concrete", [[8, 12]])
	put("vehicle_truck", Vector3(-30, 0, -36), Vector3.ZERO, 70.0)
	put("shipping_container", Vector3(30, 0, -32), Vector3.ZERO, -20.0)
	put("shipping_container", Vector3(33.5, 0, -30.5), Vector3.ZERO, -20.0, {}, "metal_painted")
	put("crate_stack", Vector3(14, 0, -28), Vector3.ZERO, 30.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(-6, 0, -24))
	put("low_cover", Vector3(-12, 0, -32), Vector3(3.5, 1.05, 0.6), 15.0, {}, "concrete")
	put("low_cover", Vector3(14, 0, -40), Vector3(3.5, 1.05, 0.6), -10.0, {}, "concrete")
	mass("block", -18, -14, -30, -26, 3.0, "metal_painted")
	put("barrel_cluster", Vector3(-26, 0, -12))
	put("braced_crate", Vector3(-28, 0, -6), Vector3(1.5, 1.2, 1.2), 35.0)
	lamp(Vector3(0, 3.0, -14), 2.2, 10.0)
	lamp(Vector3(-24, 3.0, -14), 2.0, 9.0)


## West: the Coal Cut beside the hall and the Coal Lane from the sidings.
func _west_side() -> void:
	layer("Coal Lane and Coal Cut")
	prism([Vector2(-38, 68), Vector2(-27, 64), Vector2(-24, 40), Vector2(-27, 24), Vector2(-34, 22), Vector2(-38, 26)], 0.0, 7.0, "metal_rust")
	prism([Vector2(-60, 46), Vector2(-52, 44), Vector2(-50, 56), Vector2(-60, 60)], 0.0, 5.0, "metal_dark")
	put("railing", Vector3(-34.5, 0, 7.95), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-34.5, 0, 11.05), Vector3(3, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("railing", Vector3(-36.05, 0, 9.5), Vector3(3, 1.05, 0.06), 90.0, {}, "hazard_paint")
	mass("wall_half", -50.3, -50, 22, 42, 1.1, "concrete")
	mass("wall_half", -46, -45.7, 22, 42, 1.1, "concrete")
	put("railing", Vector3(-48, 0, 21.95), Vector3(4, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("crate_stack", Vector3(-42, 0, 52), Vector3.ZERO, 70.0, {}, "metal_rust")
	put("vehicle_cart", Vector3(-41, 0, 34), Vector3.ZERO, 20.0)
	put("barrel_cluster", Vector3(-55, 0, 30))
	prism([Vector2(-44, 12), Vector2(-40, 10), Vector2(-38, 15), Vector2(-42, 17)], 0.0, 2.4, "metal_rust")
	put("crate_stack", Vector3(-28, 0, 2), Vector3.ZERO, 15.0, {}, "metal_dark")
	put("barrel_cluster", Vector3(-26, 0, 15))
	put("pipe_run", Vector3(-46, 0, -1), Vector3(14, 3.6, 0.7), -12.0, {}, "metal_rust")
	lamp(Vector3(-34, 3.0, 13), 2.2, 10.0)
	lamp(Vector3(-46, 3.0, 45), 2.0, 10.0)


## East: Tank Row from the sidings and the Tank Yard beside the hall.
func _east_side() -> void:
	layer("Tank Row and Tank Yard")
	prism([Vector2(27, 66), Vector2(37, 70), Vector2(36, 26), Vector2(30, 22), Vector2(25, 30), Vector2(26, 48)], 0.0, 7.0, "concrete")
	put("storage_tank", Vector3(48, 0, 52), Vector3(7, 9, 7), 0.0, {}, "metal_painted")
	put("storage_tank", Vector3(56, 0, 34), Vector3(5, 7, 5), 0.0, {}, "metal_rust")
	put("storage_tank", Vector3(44, 0, 30), Vector3(3.5, 5, 3.5), 0.0, {}, "metal_dark")
	put("storage_tank", Vector3(52, 0, 0), Vector3(8, 11, 8), 0.0, {}, "concrete")
	put("storage_tank", Vector3(30, 0, -9), Vector3(4, 6, 4), 0.0, {}, "metal_rust")
	put("pipe_run", Vector3(46, 0, 19), Vector3(14, 3.8, 0.8), 8.0)
	mass("wall_half", 39.7, 40, -6, 14, 1.1, "concrete")
	mass("wall_half", 44, 44.3, -6, 14, 1.1, "concrete")
	put("railing", Vector3(42, 0, -6.05), Vector3(4, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("crate_stack", Vector3(28, 0, 8), Vector3.ZERO, 90.0, {}, "metal_painted")
	put("barrel_cluster", Vector3(34, 0, 14))
	mass("block", 50, 54, 12, 15, 1.6, "metal_dark")
	lamp(Vector3(36, 3.0, 4), 2.2, 10.0)
	lamp(Vector3(50, 3.0, 40), 2.0, 10.0)


## Mid: the Freight Yard, crossed by the angled gantry crane, with the Freight Ramp in its middle.
func _freight_yard() -> void:
	layer("Freight Yard")
	mass("wall_half", -3.3, -3, 30, 50, 1.1, "concrete")
	mass("wall_half", 3, 3.3, 30, 50, 1.1, "concrete")
	put("railing", Vector3(0, 0, 29.95), Vector3(6, 1.05, 0.06), 0.0, {}, "hazard_paint")
	put("shipping_container", Vector3(-12, 0, 32), Vector3.ZERO, 20.0)
	put("shipping_container", Vector3(-12, 2.6, 32), Vector3.ZERO, 20.0, {}, "metal_painted")
	put("shipping_container", Vector3(10, 0, 26), Vector3.ZERO, -55.0, {}, "metal_painted")
	put("shipping_container", Vector3(-16, 0, 54), Vector3.ZERO, 75.0)
	put("shipping_container", Vector3(-8, 0, 46), Vector3.ZERO, 10.0, {}, "metal_dark")
	put("vehicle_truck", Vector3(8, 0, 60), Vector3.ZERO, 105.0)
	put("crate_stack", Vector3(-7, 0, 20), Vector3.ZERO, 25.0, {}, "metal_rust")
	put("barrel_cluster", Vector3(7, 0, 19))
	put("sandbag_wall", Vector3(-1, 0, 53), Vector3(3, 1.1, 0.8))
	put("low_cover", Vector3(20, 0, 36), Vector3(3.5, 1.05, 0.6), 60.0, {}, "concrete")
	# The gantry crane: two legs and a beam across the yard at an angle.
	put("block", Vector3(-18, 0, 38), Vector3(1.2, 9.3, 1.2), 18.4, {}, "hazard_paint")
	put("block", Vector3(18, 0, 26), Vector3(1.2, 9.3, 1.2), 18.4, {}, "hazard_paint")
	put("block", Vector3(0, 8.5, 32), Vector3(39, 0.8, 1.2), 18.4, {}, "hazard_paint")
	# The Signal Box, turned 30° to the yard, with a roof perch and its stair.
	put("building", Vector3(14, 0, 44), Vector3(6, 4.5, 5), 30.0, {}, "metal_painted")
	put("catwalk", Vector3(14, 4.5, 44), Vector3(6, 1.22, 5), 30.0, {}, "steel_grating")
	put("stairs", Vector3(19.55, 0, 50.61), Vector3(3, 4.62, 12), 30.0, {}, "metal_dark")
	lamp(Vector3(0, 3.0, 17), 2.4, 10.0)
	lamp(Vector3(14, 3.6, 41.5), 2.0, 9.0)
	lamp(Vector3(-10, 3.0, 44), 2.0, 10.0)


## Attacker side: the Arrival Sidings and the angled wall with the Yard Gate.
func _sidings() -> void:
	layer("Arrival Sidings")
	wall_line(Vector2(-27, 64), Vector2(-6, 68), 6.0, 0.0, "concrete")
	wall_line(Vector2(6, 68), Vector2(27, 66), 6.0, 0.0, "concrete")
	put("shipping_container", Vector3(-30, 0, 84), Vector3.ZERO, 80.0, {}, "metal_dark")
	put("shipping_container", Vector3(30, 0, 82), Vector3.ZERO, 100.0)
	put("vehicle_truck", Vector3(-14, 0, 76), Vector3.ZERO, 85.0)
	put("crate_stack", Vector3(16, 0, 74), Vector3.ZERO, 10.0, {}, "metal_rust")
	lamp(Vector3(0, 3.0, 70), 2.2, 10.0)


# --- underground --------------------------------------------------------------------------------

## A wall from the tunnel floor to the underside of the surface.
func _deep_wall(a: Vector2, b: Vector2, gaps: Array = []) -> void:
	wall_line(a, b, CEILING - VAULT, VAULT, "concrete", gaps)


func _deep_floor(outline: Array) -> void:
	surface(outline, VAULT, 1.0, "concrete")


## Site B: the Turbine Vault, seven-sided, 7 m tall, with six doors and a gantry along the north.
func _vault() -> void:
	layer("Underground · Turbine Vault (B)")
	_deep_floor(VAULT_HALL)
	# North Door, Culvert Door, East and Main Doors (to the Junction), West Door and the stairwell.
	walls_around(VAULT_HALL, CEILING - VAULT, VAULT, "concrete",
		{0: [[13, 17]], 2: [[2, 6]], 4: [[2, 5], [9, 14]], 6: [[2, 6], [8, 12]]})
	# The gantry: a catwalk 4 m up along the north wall, climbed from the west side.
	put("catwalk", Vector3(-0.35, VAULT + 3.88, -12.2), Vector3(3, 1.22, 16.7), 90.0,
		{"rail_left": false, "rail_right": false}, "steel_grating")
	put("railing", Vector3(1.15, VAULT + 4.0, -10.75), Vector3(13.7, 1.05, 0.06), 0.0, {}, "metal_dark")
	put("railing", Vector3(7.97, VAULT + 4.0, -12.2), Vector3(3, 1.05, 0.06), 90.0, {}, "metal_dark")
	put("stairs", Vector3(-7.2, VAULT, -5.7), Vector3(3, 4, 10), 0.0, {}, "metal_dark")
	# Turbines, a generator, pipework and cover.
	put("storage_tank", Vector3(14, VAULT, 0), Vector3(5, 6, 5), 0.0, {}, "metal_painted")
	put("storage_tank", Vector3(10, VAULT, 12), Vector3(4, 5.5, 4), 0.0, {}, "metal_rust")
	mass("block", 12, 17, -9, -5, 1.0, "metal_dark", VAULT)
	mass("block", -6.5, -3.5, 7, 9, 2.0, "metal_painted", VAULT)
	put("crate_stack", Vector3(6, VAULT, -4), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_rust")
	put("braced_crate", Vector3(-2, VAULT, 4), Vector3(1.5, 1.2, 1.2), 30.0)
	put("low_cover", Vector3(2, VAULT, 9.5), Vector3(3.5, 1.05, 0.6), 0.0, {}, "hazard_paint")
	put("column", Vector3(1, VAULT, -7.5), Vector3(1.2, 7.0, 1.2), 0.0, {}, "concrete")
	put("column", Vector3(4, VAULT, 14), Vector3(1.2, 7.0, 1.2), 0.0, {}, "concrete")
	put("pipe_run", Vector3(16.5, VAULT + 5.0, -9.5), Vector3(12, 0.7, 0.7), -45.0, {}, "metal_rust")
	put("pipe_run", Vector3(-8.4, VAULT + 5.2, -1), Vector3(24, 0.6, 0.6), 90.0, {}, "metal_painted")
	put("pipe_run", Vector3(17, VAULT + 4.6, 13.5), Vector3(11, 0.6, 0.6), 48.0, {}, "metal_painted")
	for lamp_at: Vector3 in [Vector3(-4, VAULT + 5.6, 2), Vector3(6, VAULT + 5.6, -6), Vector3(8, VAULT + 5.6, 6),
			Vector3(17, VAULT + 5.6, 6), Vector3(0, VAULT + 6.2, -12), Vector3(2, VAULT + 5.6, 14)]:
		lamp(lamp_at, 2.8, 11.0, "9fd0ff")


## West Stairwell: from the hall floor down to a landing at -4, then down to the vault.
func _stairwell() -> void:
	layer("Underground · West Stairwell")
	_deep_floor([Vector2(-15.3, -14), Vector2(-9, -14), Vector2(-9, 4), Vector2(-15.3, 4)])
	mass("block", -15, -12, -10, 0, 4.0, "concrete", VAULT)
	put("stairs", Vector3(-13.5, VAULT + 4.0, -5), Vector3(3, 4, 10), 180.0, {}, "metal_dark")
	mass("platform", -15, -9, -14, -10, 4.0, "concrete", VAULT)
	put("stairs", Vector3(-10.5, VAULT, -5), Vector3(3, 4, 10), 0.0, {}, "metal_dark")
	mass("wall", -12.15, -11.85, -10, 0, 9.1, "concrete", VAULT)
	_deep_wall(Vector2(-15.3, 4), Vector2(-15.3, -14))
	_deep_wall(Vector2(-15.3, -14), Vector2(-9, -14))
	_deep_wall(Vector2(-15.3, 4), Vector2(-9, 4))
	lamp(Vector3(-12, VAULT + 6.0, -12), 2.2, 9.0, "ffd6a9")
	lamp(Vector3(-11, VAULT + 3.0, 2), 1.8, 7.0, "ffd6a9")


## The Junction below the Freight Yard: the Freight Ramp and the Cable Gallery meet here.
func _junction() -> void:
	layer("Underground · Freight Ramp and Junction")
	put("ramp", Vector3(0, VAULT, 40), Vector3(6, 8, 20), 180.0, {}, "concrete")
	_deep_wall(Vector2(-3.3, 30), Vector2(-3.3, 50))
	_deep_wall(Vector2(3.3, 30), Vector2(3.3, 50))
	_deep_floor(JUNCTION)
	walls_around(JUNCTION, CEILING - VAULT, VAULT, "concrete", {3: [[1, 7]], 5: [[2.25, 6.24]]}, [0])
	put("crate_stack", Vector3(8, VAULT, 24), Vector3(2.6, 2.4, 1.2), -20.0, {}, "metal_dark")
	put("barrel_cluster", Vector3(-4, VAULT, 25))
	put("low_cover", Vector3(4, VAULT, 21.5), Vector3(3, 1.05, 0.6), 10.0, {}, "hazard_paint")
	lamp(Vector3(3, VAULT + 5.0, 24), 2.4, 10.0, "ffc58a")
	lamp(Vector3(0, -3.0, 40), 2.4, 10.0, "ffc58a")
	# The Cable Gallery runs at 45° from the Junction up to the Coal Tunnel.
	_deep_floor(CABLE_GALLERY)
	_deep_wall(CABLE_GALLERY[0], CABLE_GALLERY[3])
	_deep_wall(CABLE_GALLERY[1], CABLE_GALLERY[2])
	put("pipe_run", Vector3(-15, VAULT + 5.2, 17.6), Vector3(20, 0.5, 0.5), -45.0, {}, "metal_dark")
	put("barrel_cluster", Vector3(-13.5, VAULT, 18.5))
	lamp(Vector3(-15, VAULT + 5.0, 18), 2.2, 9.0, "ffc58a")


## The Coal Stair and the Coal Chute down to the Chute Room, and the Coal Tunnel to the vault.
func _coal_works() -> void:
	layer("Underground · Coal Tunnel and Chute Room")
	put("stairs", Vector3(-48, VAULT, 32), Vector3(4, 8, 20), 180.0, {}, "metal_dark")
	_deep_wall(Vector2(-50.3, 22), Vector2(-50.3, 42))
	_deep_wall(Vector2(-45.7, 22), Vector2(-45.7, 42))
	_deep_floor(CHUTE_ROOM)
	walls_around(CHUTE_ROOM, CEILING - VAULT, VAULT, "concrete", {2: [[0, 4]], 4: [[6, 10]]})
	_deep_floor([Vector2(-30, 6), Vector2(-9, 6), Vector2(-9, 10), Vector2(-30, 10)])
	_deep_wall(Vector2(-30, 6), Vector2(-9, 6))
	_deep_wall(Vector2(-30, 10), Vector2(-9, 10), [[4.98, 10.62]])
	put("crate_stack", Vector3(-48, VAULT, 5), Vector3(2.6, 2.4, 1.2), 0.0, {}, "metal_dark")
	prism([Vector2(-44, 15), Vector2(-40, 13), Vector2(-37, 17), Vector2(-42, 20)], VAULT, 1.6, "metal_rust")
	put("barrel_cluster", Vector3(-16, VAULT, 7))
	put("pipe_run", Vector3(-19, VAULT + 5.2, 6.5), Vector3(20, 0.6, 0.6), 0.0, {}, "metal_rust")
	for lamp_at: Vector3 in [Vector3(-20, VAULT + 5.0, 8), Vector3(-42, VAULT + 4.5, 9), Vector3(-48, -3.0, 32)]:
		lamp(lamp_at, 2.4, 10.0, "ffc58a")


## The East Culvert: a ramp down from the Tank Yard and a bent tunnel to the vault.
func _culvert() -> void:
	layer("Underground · East Culvert")
	put("ramp", Vector3(42, VAULT, 4), Vector3(4, 8, 20), 180.0, {}, "concrete")
	_deep_wall(Vector2(39.7, -6), Vector2(39.7, 14))
	_deep_wall(Vector2(44.3, -6), Vector2(44.3, 14))
	var bend: Array = [Vector2(38, -12), Vector2(46, -12), Vector2(46, -6), Vector2(38, -6)]
	_deep_floor(bend)
	walls_around(bend, CEILING - VAULT, VAULT, "concrete", {2: [[2, 6]], 3: [[1, 5]]})
	_deep_floor(CULVERT)
	_deep_wall(CULVERT[0], CULVERT[3])
	_deep_wall(CULVERT[1], CULVERT[2])
	put("barrel_cluster", Vector3(43, VAULT, -10))
	put("pipe_run", Vector3(29.5, VAULT + 5.0, -5.5), Vector3(18, 0.6, 0.6), 25.2, {}, "metal_painted")
	for lamp_at: Vector3 in [Vector3(30, VAULT + 5.0, -4), Vector3(42, VAULT + 5.0, -9), Vector3(42, -3.0, 4)]:
		lamp(lamp_at, 2.4, 10.0, "ffc58a")


## The North Stair: the defenders' way down from the Receiving Yard to the North Door.
func _north_stair() -> void:
	layer("Underground · North Stair")
	put("stairs", Vector3(6, VAULT, -26), Vector3(4, 8, 20), 0.0, {}, "metal_dark")
	_deep_floor([Vector2(4, -16), Vector2(8, -16), Vector2(8, -14), Vector2(4, -14)])
	_deep_wall(Vector2(3.7, -36), Vector2(3.7, -14))
	_deep_wall(Vector2(8.3, -36), Vector2(8.3, -14))
	mass("wall_half", 3.7, 4, -36, -16, 1.1, "concrete")
	mass("wall_half", 8, 8.3, -36, -16, 1.1, "concrete")
	put("railing", Vector3(6, 0, -15.95), Vector3(4, 1.05, 0.06), 0.0, {}, "hazard_paint")
	lamp(Vector3(6, -3.0, -24), 2.4, 10.0, "ffc58a")


# --- gameplay -----------------------------------------------------------------------------------

func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(0, 0, 88), 0.0, Vector3(24, 3, 10))
	spawns("defence", Vector3(2, 0, -52), 180.0, Vector3(24, 3, 8))
	put("bombsite", SITE_A, Vector3(14, 3, 10), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Arrival Sidings", -40, 46, 70, 96)
	area("Yard Gate", -6, 6, 64, 70)
	area("Freight Yard", -14, 26, 22, 66, "mid")
	area("Yard West", -24, -14, 22, 66)
	area("Ramp Head", -5, 5, 50, 54)
	area("Signal Box", 10, 18, 40, 48, "", 4.62)
	area("Hall Apron", -10, 20, 14.3, 22)
	area("Loading Gate", -3, 3, 14.3, 17, "entrance_a")
	area("Breach", -16, -13, 11.5, 14.5, "entrance_a")
	area("Coal Lane", -60, -38, 26, 70)
	area("Coal Stair Top", -52, -44, 42, 46)
	area("Coal Cut", -54, -24, -2, 22)
	area("Coal Chute", -36, -33, 8, 11)
	area("Stair Foot", -24, -16, 7, 14)
	area("Stair Corridor", -18, -16.3, 3, 7)
	area("Coal Door", -18, -16.3, 0, 3, "entrance_a")
	area("West Stair", -22, -18, -5, 7)
	area("West Landing", -22, -16, -11, -5, "", DECK)
	area("Boiler Yard", -32, -16, -20, -2)
	area("Receiving Yard", -56, 58, -44, -16)
	area("Depot", -22, 24, -62, -44)
	area("North Door", 3, 6, -16, -12.3)
	area("Service Stair", 13, 22, -19, -10)
	area("Machine Hall", -15.7, 15.7, -11.7, 13.7)
	area("Hall Stair", -12, 0, -11.7, -8.7)
	area("Vent", 6, 9, 3, 6)
	area("Control Deck", -15.7, 15.7, -11.7, 13.7, "", DECK)
	area("Ramp Corridor", 16.3, 18, 6, 18)
	area("Pump Door", 16.3, 18, 3, 6, "entrance_a")
	area("Deck Ramp", 18, 23, 2, 18)
	area("Ramp Top", 16, 23, -4, 2, "", DECK)
	area("Tank Row", 37, 62, 22, 70)
	area("Tank Yard", 24, 58, -18, 22)
	area("Culvert Top", 39, 45, 14, 18)
	area("Boiler Gap", -26, -22, -20, -16)
	area("Pipe Gap", 36, 42, -22, -16)
	area("Freight Ramp", -3, 3, 30, 50, "", VAULT)
	area("Junction", -10, 13, 18, 30, "", VAULT)
	area("Main Door", -1, 4, 18, 20, "entrance_b", VAULT)
	area("East Door", 8, 11, 18, 20.5, "entrance_b", VAULT)
	area("Cable Gallery", -25, -5, 10, 27, "", VAULT)
	area("Turbine Vault", -9, 21, -14, 18, "", VAULT)
	area("Gantry", -8.7, 8, -13.7, -10.7, "", VAULT + 4.0)
	area("West Stairwell", -15.3, -9, -10, 4, "", VAULT)
	area("Stair Landing", -15, -9, -14, -10, "", VAULT + 4.0)
	area("Coal Tunnel", -30, -9, 6, 10, "", VAULT)
	area("West Door", -13, -9, 6, 10, "entrance_b", VAULT)
	area("Chute Room", -52, -30, 2, 22, "", VAULT)
	area("Coal Stair", -50, -46, 22, 42, "", VAULT)
	area("Culvert", 21, 38, -11, 1, "", VAULT)
	area("Culvert Door", 21, 25, -3, 0, "entrance_b", VAULT)
	area("Culvert Bend", 38, 46, -12, -6, "", VAULT)
	area("North Stair", 4, 8, -36, -14, "", VAULT)


func _tactical() -> void:
	layer("Tactics")
	anchor("Hall plant machine", "plant", SITE_A + Vector3(-3, 0, 2))
	anchor("Hall plant columns", "plant", SITE_A + Vector3(4, 0, -3))
	anchor("Vault plant crates", "plant", SITE_B + Vector3(-3, 0, 2))
	anchor("Vault plant turbine", "plant", SITE_B + Vector3(3, 0, -3))
	anchor("Yard hold", "default", Vector3(6, 0, 40))
	anchor("Ramp Head hold", "default", Vector3(0, 0, 53))
	anchor("Deck perch", "default", Vector3(-8, DECK, 6))
	anchor("Gantry post", "default", Vector3(3, VAULT + 4.0, -12))
	anchor("Coal Cut hold", "default", Vector3(-30, 0, 10))
	anchor("Junction hold", "default", Vector3(2, VAULT, 26))
	anchor("Gate smoke", "utility", Vector3(0, 0, 16))
	anchor("Ramp smoke", "utility", Vector3(0, 0, 52))
	anchor("Culvert smoke", "utility", Vector3(42, 0, 16))
	anchor("Coal Door smoke", "utility", Vector3(-17.2, 0, 2))
	anchor("Breach smoke", "utility", Vector3(-15, 0, 14))
	hint("ai_hold", Vector3(-12, 0, -6), 150.0, "A")
	hint("ai_hold", Vector3(8, 0, -8), 220.0, "A")
	hint("ai_hold", Vector3(-8, DECK, -4), 180.0, "A")
	hint("ai_hold", Vector3(-5, VAULT, -8), 150.0, "B")
	hint("ai_hold", Vector3(4, VAULT + 4.0, -12), 180.0, "B")
	hint("ai_hold", Vector3(16, VAULT, 8), 230.0, "B")
	hint("ai_cover", Vector3(9.5, 0, 6.4), 180.0, "A")
	hint("ai_cover", Vector3(-5.6, 0, -1.6), 180.0, "A")
	hint("ai_cover", Vector3(-5, VAULT, 6.4), 180.0, "B")
	hint("ai_cover", Vector3(6, VAULT, -2.6), 180.0, "B")
	hint("ai_angle", Vector3(0, 0, 16), 0.0, "A")
	hint("ai_angle", Vector3(-17.2, 0, 2), 90.0, "A")
	hint("ai_angle", Vector3(1.5, VAULT, 21), 0.0, "B")
	hint("ai_angle", Vector3(24, VAULT, -1.5), 270.0, "B")


func _check(analysis: MapAnalysis) -> bool:
	var sites := MapZones.bombsite_at(controller.document, SITE_A) == "A" \
		and MapZones.bombsite_at(controller.document, SITE_B) == "B"
	var routes: Dictionary[String, float] = {
		"West Stairwell": analysis.path_length(Vector3(-5, 0, 0), Vector3(-6, VAULT, 2)),
		"Freight Ramp": analysis.path_length(Vector3(0, 0, 53), Vector3(1.5, VAULT, 21)),
		"Coal Stair": analysis.path_length(Vector3(-48, 0, 45), Vector3(-11, VAULT, 8)),
		"Cable Gallery": analysis.path_length(Vector3(-4, VAULT, 26), Vector3(-22, VAULT, 8)),
		"North Stair": analysis.path_length(Vector3(6, 0, -38), Vector3(6, VAULT, -12)),
		"East Culvert": analysis.path_length(Vector3(42, 0, 16), Vector3(23, VAULT, -1.5)),
		"Gantry": analysis.path_length(Vector3(-4, VAULT, 2), Vector3(3, VAULT + 4.0, -12)),
		"Service Stair": analysis.path_length(Vector3(21, 0, -19), Vector3(10, DECK, -6)),
		"Signal Box": analysis.path_length(Vector3(22, 0, 58), Vector3(14, 4.62, 44)),
	}
	var ok := sites
	for route: String in routes:
		print("%s: %.1f m" % [route, routes[route]])
		ok = ok and routes[route] > 0.0 and routes[route] < 90.0
	if not ok:
		printerr("A site or one of the routes is wrong.")
		return false
	return analysis.issues.is_empty()
