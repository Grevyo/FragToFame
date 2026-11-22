extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Rooftops": the top of a skyscraper at dusk, played on
## two floors. The upper floor is the roof deck in the open air: the plant deck (site A), the
## helipad, the lift crown under its mast, a garden terrace, a skylit court and the dock where the
## window-cleaning gondola parks. The lower floor is the tower's top storey under the roof slab:
## the Sky Lounge (site B) open to the city on its west side, the lift lobby, an open-plan office
## and a service corridor. Four stairs and an atrium join the floors.
##
## Around the tower the facade drops away below the parapet, other towers stand at a distance and
## the city lies far below in the painted dusk sky.
##
## Routes (attackers start at the Gondola Dock in the south, defenders on the Spawn Terrace north):
##   A: East Ledge along the parapet (long), Mid Lane and the Duct Gate, or up the Service Hatch
##      from the office below.
##   B: down the Garden Stair to the Bar Door, or down the Atrium into the Lift Lobby and the Lobby
##      Door. Defenders come down the North Stair and the Service Corridor.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_rooftops.gd
## (add `-- --dry-run` to validate and print timings without publishing).

## The top storey's floor; the roof deck is at 0 and its slab (0.3 m) is the storey's ceiling.
const FLOOR: float = -4.5
const SLAB: float = 0.3
const TOWER: Rect2 = Rect2(-44, -58, 88, 116)
const SITE_A: Vector3 = Vector3(30, 0, -15)
const SITE_B: Vector3 = Vector3(-29.5, FLOOR, -15)

## Openings in the roof deck (x1, x2, z1, z2): three stairs and the atrium.
const NORTH_HOLE: Array = [-18, -13, -42, -30]
const GARDEN_HOLE: Array = [-42, -37, 0, 12]
const ATRIUM_HOLE: Array = [-14, -4, 12, 26]
const HATCH_HOLE: Array = [26, 31, -4, 8]

## Rooms of the top storey (x1, x2, z1, z2); everything else under the roof is solid.
const CORRIDOR: Array = [-20, -11, -42, -26]
const LOUNGE: Array = [-44, -16, -26, -4]
const LANDING: Array = [-44, -34, -4, 12]
const LOBBY: Array = [-16, 8, -14, 12]
const ATRIUM: Array = [-14, -4, 12, 26]
const OFFICE: Array = [8, 44, -24, 20]


func _official_id() -> String:
	return "map_f2f_rooftops"


func _revision() -> int:
	return 2


func _build() -> void:
	controller.set_metadata("Rooftops", "F2F official",
		"The top of a skyscraper at dusk, on two floors. A: the Plant Deck on the roof, by the East Ledge, the Duct Gate or the Service Hatch. B: the Sky Lounge on the storey below, by the Garden Stair or down the Atrium and through the Lift Lobby.")
	controller.set_lighting({"sun_yaw": 255.0, "sun_pitch": 7.0, "sun_energy": 1.0, "sun_color": "ffaa6a",
		"ambient_color": "6c7096", "ambient_energy": 0.62, "haze": 0.28, "sky": "city_dusk"})
	_roof_deck()
	_top_storey()
	_stairs()
	_parapets()
	_roof_structures()
	_plant_deck()
	_helipad()
	_garden()
	_dock()
	_rooms()
	_facades()
	_lights()
	_tower_and_city()
	_gameplay()
	_callouts()
	_tactical()


# --- the two floors -------------------------------------------------------------------------------

func _roof_deck() -> void:
	layer("Roof deck")
	var outline: Array = [Vector2(TOWER.position.x, TOWER.position.y), Vector2(TOWER.end.x, TOWER.position.y),
		Vector2(TOWER.end.x, TOWER.end.y), Vector2(TOWER.position.x, TOWER.end.y)]
	# Gravel ballast over the membrane, concrete walkways, the garden's turf and the helipad.
	floor_shape(outline, 0.0, SLAB, "gravel", [NORTH_HOLE, GARDEN_HOLE, ATRIUM_HOLE, HATCH_HOLE], [
		[_rect(-43, -22, -4, 44), "grass_worn"],
		[_rect(-20, 20, 42, 57.4), "concrete"],
		[_rect(-16, 16, -57.4, -44), "concrete"],
		[_rect(18, 43, -26, -4), "steel_grating"],
		[_rect(8, 18, -26, 42), "concrete"],
		[_rect(34, 43, -4, 42), "concrete"],
	])


func _top_storey() -> void:
	layer("Top storey · floor")
	var outline: Array = [Vector2(TOWER.position.x, TOWER.position.y), Vector2(TOWER.end.x, TOWER.position.y),
		Vector2(TOWER.end.x, TOWER.end.y), Vector2(TOWER.position.x, TOWER.end.y)]
	floor_shape(outline, FLOOR, 0.6, "concrete", [], [
		[_rect(LOUNGE[0], LOUNGE[1], LOUNGE[2], LOUNGE[3]), "planks"],
		[_rect(LANDING[0], LANDING[1], LANDING[2], LANDING[3]), "planks"],
		[_rect(LOBBY[0], LOBBY[1], LOBBY[2], LOBBY[3]), "limestone"],
		[_rect(ATRIUM[0], ATRIUM[1], ATRIUM[2], ATRIUM[3]), "limestone"],
		[_rect(OFFICE[0], OFFICE[1], OFFICE[2], OFFICE[3]), "slate"],
	])
	layer("Top storey · core")
	# Everything under the roof that is not a room is the building's core and service space.
	slab_with_holes("building", TOWER.position.x, TOWER.end.x, TOWER.position.y, TOWER.end.y,
		-SLAB - FLOOR, "render", FLOOR, [CORRIDOR, LOUNGE, LANDING, LOBBY, ATRIUM, OFFICE])
	# Walls between rooms, with their doors.
	layer("Top storey · walls")
	wall_line(Vector2(-44, -4), Vector2(-34, -4), -SLAB - FLOOR, FLOOR, "render", [[3.6, 6.2]])        # Bar Door
	wall_line(Vector2(-16, -14), Vector2(-16, -4), -SLAB - FLOOR, FLOOR, "render", [[4.0, 6.8]])         # Lobby Door
	wall_line(Vector2(8, -14), Vector2(8, 12), -SLAB - FLOOR, FLOOR, "glass", [[11.0, 14.0]], "wall", 0.2) # Office Door
	put("doorway", Vector3(-18, FLOOR, -26), Vector3(4, -SLAB - FLOOR, 0.5), 0.0,
		{"opening_width": 2.6, "opening_height": 2.7}, "render")                                           # Lounge North Door
	# The office's curtain wall and the lounge's open west side over the city.
	for z: float in [-23.0, -18.0, -13.0, -8.0, -3.0, 2.0, 7.0, 12.0, 17.0]:
		put("pillar", Vector3(43.7, FLOOR, z), Vector3(0.4, -SLAB - FLOOR, 0.4), 0.0, {}, "metal_dark")
	mass("wall", 43.8, 44, -24, 20, -SLAB - FLOOR, "glass", FLOOR)
	put("block", Vector3(-43.8, FLOOR, -15), Vector3(22, 1.2, 0.4), 90.0, {}, "limestone")
	put("railing", Vector3(-43.8, FLOOR + 1.2, -15), Vector3(22, 1.05, 0.08), 90.0, {}, "metal_dark")
	put("block", Vector3(-43.8, FLOOR, 4), Vector3(16, 1.2, 0.4), 90.0, {}, "limestone")
	put("railing", Vector3(-43.8, FLOOR + 1.2, 4), Vector3(16, 1.05, 0.08), 90.0, {}, "metal_dark")
	for z: float in [-24.0, -16.0, -8.0, 0.0, 8.0]:
		put("pillar", Vector3(-43.7, FLOOR, z), Vector3(0.5, -SLAB - FLOOR, 0.5), 0.0, {}, "limestone")


## Stairs between the floors: 4.5 m over 12 m (about 21°), inside the openings in the roof. Each
## stair's top meets the deck at the opening's edge with no gap.
func _stairs() -> void:
	layer("Stairs")
	put("stairs", Vector3(-15.5, FLOOR, -36), Vector3(5, -FLOOR, 12), 0.0, {}, "concrete")      # North Stair (top north)
	put("stairs", Vector3(-39.5, FLOOR, 6), Vector3(5, -FLOOR, 12), 180.0, {}, "limestone")    # Garden Stair (top south)
	put("stairs", Vector3(-6.5, FLOOR, 20.25), Vector3(5, -FLOOR, 11.5), 180.0, {}, "limestone") # Atrium Stair (top south)
	put("stairs", Vector3(28.5, FLOOR, 2), Vector3(5, -FLOOR, 12), 0.0, {}, "metal_dark")   # Service Hatch (top north)
	# Railings round the openings, open only at the top of each stair.
	_rail(Vector2(-18, -42), Vector2(-18, -30))
	_rail(Vector2(-13, -42), Vector2(-13, -30))
	_rail(Vector2(-18, -30), Vector2(-13, -30))
	_rail(Vector2(-42, 0), Vector2(-42, 12))
	_rail(Vector2(-37, 0), Vector2(-37, 12))
	_rail(Vector2(-42, 0), Vector2(-37, 0))
	_rail(Vector2(-14, 12), Vector2(-4, 12))
	_rail(Vector2(-14, 12), Vector2(-14, 26))
	_rail(Vector2(-4, 12), Vector2(-4, 26))
	_rail(Vector2(-14, 26), Vector2(-9, 26))
	_rail(Vector2(26, -4), Vector2(26, 6))
	_rail(Vector2(31, -4), Vector2(31, 6))


func _rail(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) / 2.0
	var yaw := rad_to_deg(atan2(-(b.y - a.y), b.x - a.x))
	put("railing", Vector3(mid.x, 0, mid.y), Vector3(a.distance_to(b), 1.05, 0.08), yaw, {}, "metal_dark")


## Round the roof's edge: a stone parapet with a steel and glass balustrade on top, 2.25 m in all,
## so nobody goes over.
func _parapets() -> void:
	layer("Parapet")
	var x1 := TOWER.position.x + 0.2
	var x2 := TOWER.end.x - 0.2
	var z1 := TOWER.position.y + 0.2
	var z2 := TOWER.end.y - 0.2
	for side: Array in [[Vector2(x1, z1), Vector2(x2, z1)], [Vector2(x2, z1), Vector2(x2, z2)],
			[Vector2(x2, z2), Vector2(x1, z2)], [Vector2(x1, z2), Vector2(x1, z1)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var mid := (a + b) / 2.0
		var yaw := rad_to_deg(atan2(-(b.y - a.y), b.x - a.x))
		var length := a.distance_to(b) + 0.4
		put("block", Vector3(mid.x, 0, mid.y), Vector3(length, 1.2, 0.4), yaw, {}, "limestone")
		put("block", Vector3(mid.x, 1.2, mid.y), Vector3(length, 1.0, 0.06), yaw, {}, "glass")
		put("railing", Vector3(mid.x, 1.2, mid.y), Vector3(length, 1.05, 0.12), yaw, {}, "metal_dark")


# --- the roof deck ----------------------------------------------------------------------------------

func _roof_structures() -> void:
	layer("Roof structures")
	# The lift crown in the middle and its mast.
	mass("building", -8, 2, -10, 6, 7.0, "concrete")
	mass("building", 2, 8, -10, 6, 5.0, "concrete")
	mass("block", -8.3, 2.3, -10.3, 6.3, 0.4, "metal_dark", 7.0)
	put("column", Vector3(-3, 7.4, -2), Vector3(1.6, 3.0, 1.6), 0.0, {}, "metal_painted")
	put("column", Vector3(-3, 10.4, -2), Vector3(0.8, 18.0, 0.8), 0.0, {}, "metal_painted")
	put("column", Vector3(-3, 28.4, -2), Vector3(0.3, 6.0, 0.3), 0.0, {}, "metal_dark")
	# The north plant room between the defenders' terrace and mid.
	mass("building", -10, 6, -38, -28, 4.5, "concrete")
	# The lift motor room beside the skylit court, and the cooling block east of mid.
	mass("building", 2, 8, 6, 24, 4.5, "concrete")
	mass("building", 18, 34, 6, 44, 5.5, "metal_painted")
	for at: Vector2 in [Vector2(22, 12), Vector2(30, 12), Vector2(22, 22), Vector2(30, 22), Vector2(22, 34), Vector2(30, 34)]:
		put("storage_tank", Vector3(at.x, 5.5, at.y), Vector3(5, 3.4, 5), 0.0, {}, "metal_painted")
	# The gondola garage and an air-handling bank breaking the view up from the dock.
	mass("building", -6, 8, 30, 40, 4.0, "metal_painted")
	mass("block", -22, -15, 30, 38, 2.6, "metal_dark")
	# A hedge of planters between the garden and the skylit court, with a gap.
	mass("block", -23, -22, 8, 20, 1.6, "hedge")
	mass("block", -23, -22, 24, 36, 1.6, "hedge")
	# Solar panels on low frames over the lounge, and the water tanks on the west terrace.
	for z: float in [-22.0, -16.0, -10.0]:
		for x: float in [-38.0, -30.0, -22.0]:
			put("block", Vector3(x, 0, z), Vector3(5.0, 0.9, 2.6), 0.0, {}, "metal_dark")
			put("block", Vector3(x, 0.9, z), Vector3(5.2, 0.08, 2.8), 0.0, {}, "glass")
	for at: Vector2 in [Vector2(-38, -40), Vector2(-31, -40)]:
		put("storage_tank", Vector3(at.x, 0, at.y), Vector3(5, 5.5, 5), 0.0, {}, "concrete")


## Site A: the plant deck, steel grating among chillers, fans and duct runs.
func _plant_deck() -> void:
	layer("Plant Deck (A)")
	# The duct wall along its west side, open at the Duct Gate.
	mass("block", 17.6, 18.4, -26, -17, 3.2, "metal_painted")
	mass("block", 17.6, 18.4, -12, -4, 3.2, "metal_painted")
	put("pipe_run", Vector3(18, 3.2, -15), Vector3(22, 0.8, 0.8), 90.0, {}, "metal_painted")
	# Its south edge beside the hatch, low enough to see over.
	mass("block", 18.4, 26, -4.4, -3.6, 1.1, "metal_dark")
	# Chillers with fan discs on top, a duct, and crates of spares.
	for unit: Array in [[26, -20, 0.0], [35, -11, 0.0]]:
		put("block", Vector3(float(unit[0]), 0, float(unit[1])), Vector3(4.0, 2.2, 2.4), float(unit[2]), {}, "metal_painted")
		for dx: float in [-1.0, 1.0]:
			put("column", Vector3(float(unit[0]) + dx, 2.2, float(unit[1])), Vector3(1.6, 0.3, 1.6), 0.0, {}, "metal_dark")
	put("pipe_run", Vector3(31, 0, -24.6), Vector3(10, 1.2, 1.2), 0.0, {}, "metal_rust")
	put("braced_crate", Vector3(23, 0, -9), Vector3(1.5, 1.2, 1.2), 15.0)
	put("crate_stack", Vector3(39, 0, -20), Vector3(2.4, 2.4, 1.2), 90.0, {}, "metal_dark")
	put("barrel_cluster", Vector3(32, 0, -6.5))


## The helipad on the defenders' side: a raised deck with its markings, reached by a ramp.
func _helipad() -> void:
	layer("Helipad")
	mass("platform", 22, 40, -56, -40, 1.2, "concrete")
	put("ramp", Vector3(18, 0, -48), Vector3(4, 1.2, 8), 270.0, {}, "concrete")
	# The H and the touchdown circle, painted (laid 2 cm proud).
	mass("floor", 28, 29, -52, -44, 0.05, "plaster_white", 1.17)
	mass("floor", 33, 34, -52, -44, 0.05, "plaster_white", 1.17)
	mass("floor", 29, 33, -48.5, -47.5, 0.05, "plaster_white", 1.17)
	for k: int in 16:
		var angle := TAU * float(k) / 16.0
		put("block", Vector3(31 + cos(angle) * 6.0, 1.2, -48 + sin(angle) * 6.0), Vector3(1.8, 0.05, 0.4),
			-rad_to_deg(angle) + 90.0, {}, "hazard_paint")
	for corner: Vector2 in [Vector2(22.4, -55.6), Vector2(39.6, -55.6), Vector2(22.4, -40.4), Vector2(39.6, -40.4)]:
		put("block", Vector3(corner.x, 1.2, corner.y), Vector3(0.3, 0.2, 0.3), 0.0, {}, "lamp_glass")
	put("block", Vector3(31, 1.2, -40.2), Vector3(18, 1.0, 0.3), 0.0, {}, "metal_dark")


## The garden terrace on the west side: lawn, planters, trees and a pergola.
func _garden() -> void:
	layer("Garden terrace")
	for tree: Vector2 in [Vector2(-40, 38), Vector2(-28, 30), Vector2(-40, 22), Vector2(-27, 14)]:
		put("planter", Vector3(tree.x, 0, tree.y), Vector3(2.4, 0.8, 2.4), 0.0, {}, "limestone")
		put("tree", Vector3(tree.x, 0.8, tree.y), Vector3(3.2, 5.0, 3.2))
	for z: float in [26.0, 32.0]:
		put("park_bench", Vector3(-33, 0, z), Vector3(1.8, 0.9, 0.62), 90.0)
	# The pergola: posts and beams over a timber deck.
	mass("floor", -36, -26, 40, 44, 0.05, "planks", -0.03)
	for x: float in [-35.5, -31.0, -26.5]:
		for z: float in [40.5, 43.5]:
			put("pillar", Vector3(x, 0, z), Vector3(0.25, 2.8, 0.25), 0.0, {}, "weathered_wood")
	for z: float in [40.5, 43.5]:
		put("block", Vector3(-31, 2.8, z), Vector3(10, 0.22, 0.22), 0.0, {}, "weathered_wood")
	for x: float in [-35.0, -33.0, -31.0, -29.0, -27.0]:
		put("block", Vector3(x, 3.02, 42), Vector3(0.16, 0.16, 4.0), 0.0, {}, "weathered_wood")


## The attackers' dock: the window-cleaning gondola's crane on its track.
func _dock() -> void:
	layer("Gondola Dock")
	for x: float in [-18.0, 18.0]:
		mass("block", x - 0.15, x + 0.15, 44, 56, 0.06, "metal_dark", 0.0)
	put("block", Vector3(-11, 0, 52), Vector3(4, 2.6, 3), 0.0, {}, "hazard_paint")
	put("block", Vector3(-11, 2.6, 52), Vector3(1.4, 4.0, 1.4), 0.0, {}, "hazard_paint")
	put("block", Vector3(-11, 6.6, 54.5), Vector3(1.0, 1.0, 12.0), 0.0, {}, "hazard_paint")
	put("block", Vector3(-11, 4.8, 60.0), Vector3(4.0, 1.4, 1.2), 0.0, {}, "metal_painted")
	put("shipping_container", Vector3(14, 0, 50), Vector3(2.44, 2.6, 6.0), 0.0, {}, "metal_painted")
	put("crate_stack", Vector3(-3, 0, 45.4), Vector3(2.4, 2.4, 1.2), 0.0, {}, "metal_dark")


# --- the top storey ---------------------------------------------------------------------------------

func _rooms() -> void:
	layer("Sky Lounge (B)")
	# The bar along the lounge's east wall, sofas and low tables facing the view.
	mass("block", -19.5, -17.5, -24, -16, 1.1, "wood_dark", FLOOR)
	mass("block", -19.7, -17.3, -24.2, -15.8, 0.08, "limestone", FLOOR + 1.1)
	for sofa: Array in [[-38, -20, 90.0], [-38, -10, 90.0], [-30, -6, 0.0]]:
		put("block", Vector3(float(sofa[0]), FLOOR, float(sofa[1])), Vector3(3.2, 0.8, 1.0), float(sofa[2]), {}, "cloth_red")
	for table: Vector2 in [Vector2(-35.5, -20), Vector2(-35.5, -10)]:
		put("block", Vector3(table.x, FLOOR, table.y), Vector3(1.2, 0.5, 1.2), 0.0, {}, "wood_dark")
	put("planter", Vector3(-24, FLOOR, -24.8), Vector3(1.6, 1.0, 0.6), 0.0, {}, "wood_dark")
	put("crate_large", Vector3(-27, FLOOR, -11), Vector3(2.0, 2.0, 2.0), 20.0, {}, "planks")
	layer("Lift Lobby")
	for x: float in [-12.0, -6.0, 0.0]:
		put("planter", Vector3(x, FLOOR, -13.4), Vector3(1.6, 1.0, 0.6), 0.0, {}, "limestone")
	put("stone_bench", Vector3(2, FLOOR, 0), Vector3(1.8, 0.95, 0.8), 90.0)
	put("notice_board", Vector3(-15.6, FLOOR, 6), Vector3(1.4, 2.1, 0.14), 90.0)
	layer("Open Office")
	# Rows of desks with screens, and partitions, leaving aisles to the hatch and the door.
	for row: float in [-20.0, -12.0, 12.0, 16.0]:
		for x: float in [12.0, 17.0, 22.0, 34.0, 39.0]:
			put("block", Vector3(x, FLOOR, row), Vector3(1.8, 0.75, 0.9), 0.0, {}, "planks")
			put("block", Vector3(x, FLOOR + 0.75, row - 0.25), Vector3(0.7, 0.45, 0.06), 0.0, {}, "metal_dark")
	for screen: Vector3 in [Vector3(15, FLOOR, -16), Vector3(37, FLOOR, -16), Vector3(19, FLOOR, 4)]:
		put("cloth_screen", screen, Vector3(3, 1.6, 0.2), 0.0, {}, "cloth_blue")
	for rack: float in [38.5, 41.0]:
		put("block", Vector3(rack, FLOOR, -23.5), Vector3(2.0, 2.2, 0.8), 0.0, {}, "metal_dark")
	put("crate_stack", Vector3(12, FLOOR, 2), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")


# --- dressing -------------------------------------------------------------------------------------

func _facades() -> void:
	layer("Roof facades")
	dress_facades({
		"plinth": "hazard_paint", "plinth_h": 0.25, "cornice": "metal_dark", "cornice_h": 0.3,
		"window": {"type": "shutter_panel", "size": Vector3(1.8, 1.2, 0.2), "props": {}, "materials": ["metal_dark", "metal_painted"]},
		"window_every": 4.5, "first_sill": 1.6, "storey": 3.0, "blank": 0.35, "min_ground": -0.5,
		"door": {"type": "door", "size": Vector3(1.2, 2.3, 0.3), "props": {"panels": 1, "fanlight": false}, "materials": ["metal_painted"]},
		"door_chance": 0.5,
		"lamp": {"type": "lamp_bulkhead", "size": Vector3(0.34, 0.24, 0.16), "props": {"energy": 1.4, "range": 7.0}, "material": "metal_painted"},
		"lamp_every": 9.0, "lamp_y": 2.6,
	}, TOWER)
	layer("Storey facades")
	dress_facades({
		"plinth": "metal_dark", "plinth_h": 0.12, "cornice": "plaster_white", "cornice_h": 0.25,
		"door": {"type": "door", "size": Vector3(1.1, 2.3, 0.3), "props": {"panels": 1, "fanlight": true}, "materials": ["wood_dark", "glass"]},
		"door_chance": 0.7, "max_ground": FLOOR + 0.5, "min_height": 2.0,
		"extra": _wall_panels,
	}, TOWER)


## Timber panels along the storey's walls between the doors.
func _wall_panels(run: Dictionary) -> void:
	var length := float(run["length"])
	var door_at := float(run["door_at"])
	var t := 1.5
	while t <= length - 1.5:
		if door_at < 0.0 or absf(t - door_at) > 1.8:
			band(run["from"] as Vector2, run["along"] as Vector2, run["facing"] as Vector2, t - 1.0, t + 1.0,
				float(run["ground"]) + 0.9, 1.6, 0.06, "planks", float(run["yaw"]))
		t += 3.0


func _lights() -> void:
	layer("Lights")
	# Floodlights over the plant deck and the dock, red warning lights on the mast and the crane.
	spot(Vector3(30, 7.0, -15), 5.0, 14.0, 60.0, "dfe8ff")
	spot(Vector3(36, 6.0, 20), 3.5, 12.0, 60.0, "dfe8ff")
	spot(Vector3(0, 6.0, 50), 4.0, 14.0, 60.0, "ffe2b8")
	spot(Vector3(13, 6.0, 0), 3.5, 12.0, 60.0, "dfe8ff")
	lamp(Vector3(-3, 34.6, -2), 3.0, 6.0, "ff2a1a")
	lamp(Vector3(-3, 18.0, -2), 1.6, 4.0, "ff2a1a")
	lamp(Vector3(-11, 7.4, 60.0), 1.2, 4.0, "ff2a1a")
	for corner: Vector2 in [Vector2(-43.4, -57.4), Vector2(43.4, -57.4), Vector2(43.4, 57.4), Vector2(-43.4, 57.4)]:
		put("block", Vector3(corner.x, 2.25, corner.y), Vector3(0.3, 0.3, 0.3), 0.0, {}, "lamp_glass")
		lamp(Vector3(corner.x, 2.6, corner.y), 1.2, 4.0, "ff2a1a")
	# Garden bollard lamps and lanterns on the pergola.
	for at: Vector2 in [Vector2(-34, 10), Vector2(-34, 20), Vector2(-24, 40), Vector2(-42, 30)]:
		put("lamp_post", Vector3(at.x, 0, at.y), Vector3(0.3, 1.2, 0.3), 0.0, {"energy": 1.4, "range": 6.0})
	put("lamp_hanging", Vector3(-31, 2.2, 42), Vector3(0.5, 0.6, 0.5), 0.0, {"energy": 1.5, "range": 7.0})
	# Ceiling lights on the storey: warm pendants in the lounge, cool panels elsewhere.
	for at: Vector2 in [Vector2(-36, -20), Vector2(-28, -20), Vector2(-36, -10), Vector2(-28, -10), Vector2(-21, -12)]:
		put("lamp_hanging", Vector3(at.x, -1.3, at.y), Vector3(0.6, 0.9, 0.6), 0.0, {"energy": 2.6, "range": 11.0})
	for at: Vector2 in [Vector2(-15.5, -34), Vector2(-15.5, -28), Vector2(-39, -1), Vector2(-39, 8), Vector2(-10, -6),
			Vector2(0, -6), Vector2(-10, 6), Vector2(0, 6), Vector2(-9, 18), Vector2(14, -18), Vector2(26, -18),
			Vector2(38, -18), Vector2(14, -4), Vector2(38, -4), Vector2(14, 10), Vector2(26, 14), Vector2(38, 10)]:
		lamp(Vector3(at.x, -0.9, at.y), 2.8, 13.0, "f4f1ea")


## Below the parapet the tower's facade drops away; other towers stand round it at a distance.
func _tower_and_city() -> void:
	layer("Tower and skyline (scenery)")
	var bottom := -70.0
	mass("building", TOWER.position.x, TOWER.end.x, TOWER.position.y, TOWER.end.y, FLOOR - 0.6 - bottom, "glass", bottom)
	# Spandrel bands between the storeys, all the way down.
	var y := FLOOR - 0.9
	while y > bottom:
		mass("block", TOWER.position.x - 0.15, TOWER.end.x + 0.15, TOWER.position.y - 0.15, TOWER.end.y + 0.15, 0.6, "concrete", y)
		y -= 4.5
	# The top storey's own band and the roof's edge.
	var x1 := TOWER.position.x
	var x2 := TOWER.end.x
	var z1 := TOWER.position.y
	var z2 := TOWER.end.y
	for rim: Array in [[x1 - 0.3, x2 + 0.3, z1 - 0.3, z1], [x1 - 0.3, x2 + 0.3, z2, z2 + 0.3],
			[x1 - 0.3, x1, z1, z2], [x2, x2 + 0.3, z1, z2]]:
		mass("block", float(rim[0]), float(rim[1]), float(rim[2]), float(rim[3]), 0.6, "limestone", -0.6)
	# Neighbouring towers: [x, z, width, depth, top, material], with lit floors here and there.
	for tower: Array in [[-120, -60, 30, 30, 26.0, "glass"], [-110, 50, 26, 34, -12.0, "concrete"],
			[-80, 140, 36, 28, 40.0, "glass"], [30, 150, 30, 30, -30.0, "concrete"], [130, 90, 34, 30, 12.0, "glass"],
			[140, -20, 28, 40, -6.0, "glass"], [110, -130, 30, 30, 48.0, "concrete"], [10, -150, 40, 26, 6.0, "glass"],
			[-100, -150, 30, 30, -20.0, "glass"]]:
		var x := float(tower[0])
		var z := float(tower[1])
		var w := float(tower[2])
		var d := float(tower[3])
		var top := float(tower[4])
		put("building", Vector3(x, bottom - 40.0, z), Vector3(w, top - bottom + 40.0, d), 0.0, {}, str(tower[5]))
		put("block", Vector3(x, top, z), Vector3(w * 0.5, 3.0, d * 0.5), 0.0, {}, "metal_dark")
		var floor_y := top - 3.0
		var k := 0
		while floor_y > bottom + 10.0:
			if pick_at(Vector2(x, floor_y), k) % 3 == 0:
				put("block", Vector3(x, floor_y, z), Vector3(w + 0.1, 1.2, d + 0.1), 0.0, {}, "lamp_glass")
			floor_y -= 4.0
			k += 1
		if top > 20.0:
			lamp(Vector3(x, top + 3.4, z), 3.0, 8.0, "ff2a1a")


# --- gameplay -------------------------------------------------------------------------------------

func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(0, 0, 50), 0.0, Vector3(24, 3, 10))
	spawns("defence", Vector3(0, 0, -50), 180.0, Vector3(24, 3, 10))
	put("bombsite", SITE_A, Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Gondola Dock", -20, 20, 42, 57.4)
	area("Dock East", 20, 43, 44, 57.4)
	area("East Ledge", 34, 43, 6, 44)
	area("Ledge Corner", 34, 43, -4, 6, "entrance_a")
	area("Mid Lane", 8, 18, 6, 42, "mid")
	area("Crown Court", 8, 18, -10, 6)
	area("Duct Alley", 8, 17.6, -26, -10)
	area("Duct Gate", 17.6, 18.4, -17, -12, "entrance_a")
	area("Plant Deck", 18.4, 43, -26, -4)
	area("Service Hatch", 26, 31, -4, 6, "entrance_a")
	area("Helipad", 22, 40, -56, -40, "", 1.2)
	area("Helipad Walk", 6, 43, -40, -26)
	area("Spawn Terrace", -16, 16, -57.4, -44)
	area("North Plant", -10, 6, -44, -38)
	area("North Stair", -18, -13, -42, -30)
	area("West Terrace", -43, -18, -57.4, -26)
	area("Solar Field", -43, -10, -26, -4)
	area("Skylit Court", -22, 2, 6, 30)
	area("Atrium", -14, -4, 12, 26)
	area("Garden", -43, -23, -4, 40)
	area("Garden Stair", -42, -37, 0, 12)
	area("Pergola", -43, -20, 40, 44)
	area("Service Corridor", -20, -11, -42, -26, "", FLOOR)
	area("Lounge Door", -20, -16, -27, -25, "entrance_b", FLOOR)
	area("Sky Lounge", -44, -16, -26, -4, "", FLOOR)
	area("Bar Landing", -44, -34, -4, 12, "", FLOOR)
	area("Bar Door", -40.4, -37.8, -5, -3, "entrance_b", FLOOR)
	area("Lift Lobby", -16, 8, -14, 12, "", FLOOR)
	area("Lobby Door", -17, -15, -10, -7.2, "entrance_b", FLOOR)
	area("Atrium Floor", -14, -4, 12, 26, "", FLOOR)
	area("Open Office", 8, 44, -24, 20, "", FLOOR)
	area("Office Door", 7, 9, -3, 0, "", FLOOR)


func _tactical() -> void:
	layer("Tactics")
	anchor("Plant Deck chillers", "plant", SITE_A + Vector3(-3, 0, 2))
	anchor("Plant Deck grating", "plant", SITE_A + Vector3(4, 0, -3))
	anchor("Lounge sofas", "plant", SITE_B + Vector3(-3, 0, 3))
	anchor("Lounge bar", "plant", SITE_B + Vector3(4, 0, -3))
	anchor("Ledge hold", "default", Vector3(38, 0, 20))
	anchor("Mid hold", "default", Vector3(13, 0, 20))
	anchor("Garden hold", "default", Vector3(-32, 0, 18))
	anchor("Lobby hold", "default", Vector3(-6, FLOOR, 0))
	anchor("Ledge smoke", "utility", Vector3(38, 0, 2))
	anchor("Duct smoke", "utility", Vector3(14, 0, -15))
	anchor("Garden Stair smoke", "utility", Vector3(-39.5, 0, 14))
	anchor("Lobby smoke", "utility", Vector3(-12, FLOOR, -8))
	hint("ai_hold", Vector3(36, 0, -22), 180.0, "A")
	hint("ai_hold", Vector3(22, 0, -22), 150.0, "A")
	hint("ai_hold", Vector3(40, 0, -8), 200.0, "A")
	hint("ai_hold", Vector3(-24, FLOOR, -22), 210.0, "B")
	hint("ai_hold", Vector3(-38, FLOOR, -24), 160.0, "B")
	hint("ai_hold", Vector3(-20, FLOOR, -8), 250.0, "B")
	hint("ai_cover", Vector3(26, 0, -17.5), 180.0, "A")
	hint("ai_cover", Vector3(35, 0, -13.5), 180.0, "A")
	hint("ai_cover", Vector3(-27, FLOOR, -13.5), 180.0, "B")
	hint("ai_cover", Vector3(-35.5, FLOOR, -17), 180.0, "B")
	hint("ai_angle", Vector3(38, 0, 0), 0.0, "A")
	hint("ai_angle", Vector3(14, 0, -15), 90.0, "A")
	hint("ai_angle", Vector3(-38.5, FLOOR, -2), 0.0, "B")
	hint("ai_angle", Vector3(-13, FLOOR, -8.5), 90.0, "B")


func _check(analysis: MapAnalysis) -> bool:
	var ok := true
	for route: Array in [["dock → hatch top", Vector3(0, 0, 50), Vector3(28.5, 0, -6)],
			["dock → garden stair foot", Vector3(0, 0, 50), Vector3(-39.5, FLOOR, -2)],
			["dock → atrium foot", Vector3(0, 0, 50), Vector3(-6.5, FLOOR, 10)],
			["terrace → north stair foot", Vector3(0, 0, -50), Vector3(-15.5, FLOOR, -28)],
			["helipad", Vector3(0, 0, -50), Vector3(31, 1.2, -48)]]:
		var length := analysis.path_length(route[1] as Vector3, route[2] as Vector3)
		print("%s: %.1f m" % [route[0], length])
		if length < 0.0:
			printerr("No route: ", route[0])
			ok = false
	return ok and analysis.issues.is_empty()


static func _rect(x1: float, x2: float, z1: float, z2: float) -> Array:
	return [Vector2(x1, z1), Vector2(x2, z1), Vector2(x2, z2), Vector2(x1, z2)]
