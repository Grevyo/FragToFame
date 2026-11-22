extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Kilnmarket".
##
## This is NOT a map generator. It opens the shipped Creation Studio scene and performs the same
## operations a person performs there, one piece at a time with explicit coordinates: choose a
## palette piece, place it, edit it in the inspector, use layers, lighting, copy/paste and a
## prefab, validate, and save with the editor's Save. The result is an ordinary saved map
## document; the last step only copies that file into res://data/maps/official under the
## official map ID. Anyone with the editor can rebuild the map by following this list.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_kilnmarket.gd
## It prints the validation report and the route timings used to tune the layout.

func _official_id() -> String:
	return "map_f2f_kilnmarket"


## Version 2: the Overlook stair was lengthened so bots can always climb it.
## Version 3: lamp fixtures in its dark corners and everyday props along the walls.
## Version 4 (owner, 2026-11-22: flesh it out and give it its own character): a potters' quarter at
## a hazy noon. Paved yards and lanes, every street wall dressed (fired-clay plinths, painted
## shutters, vigas, doors), kiln chimneys and drying racks on the roofs, glazed-tile fountains,
## drying racks of pots, awnings and a hazy sky over terracotta hills.
func _revision() -> int:
	return 4


func _build() -> void:
	controller.set_metadata("Kilnmarket", "F2F official",
		"Potters' quarter at noon. Three lanes: the Salt Road to the Kiln Yard (A), Spice Row through the middle, and the Culvert to the Cistern (B).")
	controller.set_lighting({"sun_yaw": 215.0, "sun_pitch": 58.0, "sun_energy": 1.35, "sun_color": "fff0d6",
		"ambient_color": "d2bea0", "ambient_energy": 0.68, "haze": 0.45, "sky": "hazy_noon"})

	_ground_and_buildings()
	_a_side()
	_mid()
	_b_side()
	_lamps_and_props()
	_potters_quarter()
	_spawns_and_zones()
	_callouts()
	_tactical()


# --- the map ------------------------------------------------------------------------------------

func _ground_and_buildings() -> void:
	layer("Ground")
	put("floor_sand", Vector3(1, -1, 9), Vector3(122, 1, 106))
	layer("Buildings")
	# Town edge.
	mass("building", -60, 62, -44, -40, 6.0, "sandstone")
	mass("building", -60, -56, -44, 62, 6.0, "sandstone")
	mass("building", 58, 62, -44, 62, 6.0, "sandstone")
	mass("building", -60, 62, 58, 62, 6.0, "sandstone")
	# North-west quarter (around the Garrison and the Kiln Yard).
	mass("building", -56, -14, -40, -36, 5.5, "adobe")
	mass("building", -56, -40, -36, -26, 6.5, "plaster_ochre")
	mass("building", -34, -14, -30, -26, 5.0, "plaster_white")
	mass("building", -28, 0, -28, -18, 7.0, "adobe")
	# Between the Weighhouse and Potter's Passage.
	mass("building", -22, 0, -12, 4, 6.5, "plaster_white")
	mass("building", -22, -8, 4, 16, 5.5, "adobe")
	mass("building", -28, -22, -12, -4, 6.0, "mud_brick")
	# South-west blocks (inside the Salt Road loop).
	mass("building", -46, -8, 22, 44, 7.0, "adobe")
	mass("building", -46, -12, 44, 47, 5.0, "plaster_ochre")
	mass("building", -46, -28, 2, 22, 6.0, "plaster_white")
	mass("building", -56, -12, 55, 58, 5.0, "adobe")
	# East of Spice Row.
	mass("building", 0, 34, 10, 44, 7.5, "plaster_ochre")
	mass("building", 12, 34, 44, 47, 5.0, "adobe")
	mass("building", 8, 30, -12, 4, 6.5, "adobe")
	mass("building", 8, 34, 4, 10, 6.0, "plaster_white")
	mass("building", 30, 42, 4, 16, 5.5, "mud_brick")
	mass("building", 38, 58, 20, 58, 7.0, "adobe")
	mass("building", 46, 58, 4, 20, 6.0, "plaster_white")
	mass("building", 12, 58, 55, 58, 5.0, "plaster_ochre")
	# North-east quarter (around the Cistern).
	mass("building", 14, 58, -40, -36, 5.5, "adobe")
	mass("building", 36, 58, -36, -26, 6.5, "plaster_white")
	mass("building", 8, 30, -28, -18, 7.0, "plaster_ochre")
	mass("building", 14, 30, -30, -28, 5.0, "adobe")


func _a_side() -> void:
	layer("Buildings")
	# Kiln Gate: the Salt Road narrows to an arch before the yard.
	put("arch", Vector3(-51, 0, 2), Vector3(10, 5, 0.8), 0.0, {"opening_width": 4.6, "opening_height": 3.0}, "sandstone")
	# Potter's Steps: stairs up to a terrace, then down into the yard through a gap in its wall.
	put("stairs_stone", Vector3(-25, 0, 10.5), Vector3(6, 1.5, 5))
	mass("platform", -28, -22, -4, 8, 1.5, "sandstone")
	put("stairs_stone", Vector3(-30.5, 0, -2), Vector3(4, 1.5, 5), 270.0)
	put("wall_adobe", Vector3(-28, 0, 1), Vector3(2, 4.5, 0.4), 90.0)
	put("wall_half", Vector3(-28, 1.5, 1), Vector3(2, 1.1, 0.4), 90.0)
	# Garrison Lane: two offset walls so the defender spawn cannot see straight down the middle.
	put("wall_adobe", Vector3(2.25, 0, -27.6), Vector3(4.5, 4, 0.5))
	put("wall_adobe", Vector3(5.75, 0, -21), Vector3(4.5, 4, 0.5))
	# Weighhouse: a roofed passage from the Crossing into the yard.
	put("doorway", Vector3(-28, 0, -15), Vector3(6, 4, 0.5), 90.0, {"opening_width": 2.2, "opening_height": 2.6})
	put("arch", Vector3(0, 0, -15), Vector3(6, 4.5, 0.6), 90.0, {"opening_width": 3.0, "opening_height": 2.4}, "sandstone")
	mass("roof", -28, 0, -18, -12, 0.3, "mud_brick", 4.0)

	layer("Props")
	# Salt Road cover.
	put("vehicle_truck", Vector3(-48.5, 0, 26))
	put("crate_stack", Vector3(-54.6, 0, 14), Vector3.ZERO, 90.0)
	put("barrel_cluster", Vector3(-47.5, 0, 10))
	put("crate_large", Vector3(-54.5, 0, 36))
	put("crate_long", Vector3(-30, 0, 48))
	put("vehicle_car", Vector3(-22, 0, 53.4), Vector3.ZERO, 90.0)
	# Kiln Yard (site A).
	put("kiln", Vector3(-50.5, 0, -17.5))
	put("kiln", Vector3(-38, 0, -19))
	put("crate_large", Vector3(-44, 0, -12))
	put("crate_stack", Vector3(-40.4, 0, -13.5), Vector3.ZERO, 90.0)
	put("barrel_cluster", Vector3(-47, 0, -8.6))
	put("sandbag_wall", Vector3(-53, 0, -6))
	put("wall_half", Vector3(-36.5, 0, -22), Vector3(5, 1.1, 0.4))
	put("vehicle_cart", Vector3(-33, 0, -9))
	put("awning", Vector3(-48, 0, -25), Vector3(4, 2.8, 2))
	# Weighhouse interior.
	put("crate_stack", Vector3(-14, 0, -17.2))
	put("crate_long", Vector3(-22, 0, -12.7))
	layer("Lights")
	put("light_lamp", Vector3(-20, 3.4, -15), Vector3.ZERO, 0.0, {"energy": 2.0, "range": 10.0})
	put("light_lamp", Vector3(-8, 3.4, -15), Vector3.ZERO, 0.0, {"energy": 2.0, "range": 10.0})


func _mid() -> void:
	layer("Props")
	# Spice Row: stalls on alternating sides break the long view up the street.
	put("market_stall", Vector3(-0.8, 0, 36), Vector3.ZERO, 270.0)
	put("market_stall", Vector3(-7.2, 0, 29), Vector3.ZERO, 90.0)
	put("market_stall", Vector3(-0.8, 0, 22), Vector3.ZERO, 270.0)
	put("cloth_screen", Vector3(-5.75, 0, 13.6), Vector3(4.5, 2.8, 0.2), 0.0, {}, "cloth_red")
	put("barrel", Vector3(-7.4, 0, 40))
	# Dogleg.
	put("crate_large", Vector3(-6.6, 0, 5.4))
	put("barrel_cluster", Vector3(6.6, 0, 8.6))
	# Clock Lane (upper mid).
	put("awning", Vector3(1, 0, -3), Vector3(4, 2.8, 2), 90.0, {}, "cloth_striped")
	put("vehicle_cart", Vector3(6.8, 0, -1))
	put("crate", Vector3(7.2, 0, -7))
	# Dyers' Cut: hanging cloth, staggered so there is never a straight view through.
	put("cloth_screen", Vector3(14, 0, -16.5), Vector3(3, 2.8, 0.2), 90.0)
	# The other two screens are copies of the first (copy and paste).
	controller.select(controller.selected_id)
	studio.call("copy_selection")
	studio.call("paste_at", Vector3(20, 0, -13.5))
	controller.set_selection_material("cloth_red")
	studio.call("paste_at", Vector3(26, 0, -16.5))
	controller.set_selection_material("cloth_striped")
	controller.select("")
	layer("Buildings")
	put("double_door", Vector3(30, 0, -15), Vector3(6, 4, 0.5), 90.0, {"opening_width": 2.4, "opening_height": 2.6})


func _b_side() -> void:
	layer("Buildings")
	# Culvert: a roofed, lamp-lit tunnel that ends in a single doorway.
	mass("roof", 34, 38, 20, 47, 0.4, "mud_brick", 3.2)
	mass("roof", 34, 46, 16, 20, 0.4, "mud_brick", 3.2)
	mass("roof", 42, 46, 4, 16, 0.4, "mud_brick", 3.2)
	put("doorway", Vector3(44, 0, 4), Vector3(4, 3.2, 0.5), 0.0, {"opening_width": 2.4, "opening_height": 2.6}, "sandstone")
	# Overlook: the raised defender position above the Cistern, reached by stairs from the back.
	mass("platform", 40, 58, -26, -20, 2.5, "sandstone")
	# 6 m long (22.6°): steeper stairs only bake for bots by luck (MapAnalysis.bot_slope_limit).
	put("stairs_stone", Vector3(37, 0, -23), Vector3(3, 2.5, 6), 270.0)
	put("wall_parapet", Vector3(49, 2.5, -20.2), Vector3(18, 1.2, 0.4))
	layer("Lights")
	put("light_lamp", Vector3(36, 2.6, 36), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})
	put("light_lamp", Vector3(38, 2.6, 18), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})
	put("light_lamp", Vector3(44, 2.6, 10), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})

	layer("Props")
	# Cistern (site B).
	put("well", Vector3(45, 0, -9), Vector3(4, 1.1, 4))
	put("crate_large", Vector3(39.5, 0, -4.5))
	put("crate_stack", Vector3(51.4, 0, -12.5), Vector3.ZERO, 90.0)
	put("barrel_cluster", Vector3(50.5, 0, -3.6))
	put("sandbag_wall", Vector3(35.5, 0, -9), Vector3.ZERO, 90.0)
	put("crate", Vector3(56.8, 0, -18.6))
	# A stock prefab, placed as one unit, then saved again under a map-specific name.
	studio.call("select_prefab", "stock_crate_stack")
	studio.call("place_at", Vector3(33, 0, 1.6))
	controller.save_prefab("Cistern corner stack")
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	controller.select("")
	# Tanners' Lane and the caravan court.
	put("crate_long", Vector3(24, 0, 54.2))
	put("barrel", Vector3(30, 0, 47.6))
	put("crate_stack", Vector3(-9.6, 0, 56.8))
	put("barrel", Vector3(10.6, 0, 45))
	# Garrison.
	put("vehicle_car", Vector3(-10, 0, -38.6), Vector3.ZERO, 90.0)
	put("crate_stack", Vector3(11.4, 0, -39))


func _spawns_and_zones() -> void:
	layer("Gameplay")
	for x: float in [0.0, -2.0, 2.0, -4.0, 4.0]:
		put("spawn_attack", Vector3(x, 0, 53))
		put("spawn_defence", Vector3(x, 0, -36), Vector3.ZERO, 180.0)
	put("buy_zone", Vector3(0, 0, 51), Vector3(24, 3, 14), 0.0, {"team": "attack"})
	put("buy_zone", Vector3(0, 0, -34), Vector3(28, 3, 12), 0.0, {"team": "defence"})
	put("bombsite", Vector3(-44, 0, -14), Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", Vector3(45, 0, -9), Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Caravan Gate", -12, 12, 44, 58)
	area("West Bend", -56, -12, 47, 55)
	area("Salt Road", -56, -46, 6, 47)
	area("Kiln Gate", -56, -46, -2, 6, "entrance_a")
	area("Kiln Yard", -56, -28, -26, -2)
	area("Potter's Passage", -28, -8, 16, 22)
	area("Potter's Steps", -28, -22, 0, 16)
	area("Potter's Door", -34, -22, -4, 0, "entrance_a")
	area("Spice Row", -8, 0, 10, 44)
	area("Dogleg", -8, 8, 4, 10, "mid")
	area("Clock Lane", 0, 8, -12, 4)
	area("Crossing", 0, 8, -18, -12)
	area("Weighhouse", -26, 0, -18, -12)
	area("Weigh Door", -31, -26, -18, -12, "entrance_a")
	area("Dyers' Cut", 8, 28, -18, -12)
	area("Dyers' Door", 28, 33, -18, -12, "entrance_b")
	area("Garrison", -14, 14, -40, -28)
	area("Garrison Lane", 0, 8, -28, -18)
	area("Arcade", -40, -14, -36, -30)
	area("Arcade Turn", -40, -34, -30, -26)
	area("Barracks Lane", 14, 36, -36, -30)
	area("Barracks Turn", 30, 36, -30, -26)
	area("Cistern", 30, 58, -20, 4)
	area("Cistern Back", 30, 40, -26, -20)
	area("Overlook", 40, 58, -26, -20, "", 2.5)
	area("Tanners' Lane", 12, 38, 47, 55)
	area("Culvert", 34, 38, 20, 47)
	area("Culvert Bend", 34, 46, 16, 20)
	area("Culvert Mouth", 42, 46, 1, 16, "entrance_b")


func _tactical() -> void:
	layer("Tactics")
	var anchors: Array[Array] = [
		["Kiln plant open", "plant", Vector3(-44, 0, -9.8)],
		["Kiln plant safe", "plant", Vector3(-48.6, 0, -15.4)],
		["Cistern plant front", "plant", Vector3(45, 0, -5.4)],
		["Cistern plant back", "plant", Vector3(48.8, 0, -9.4)],
		["Gate hold", "default", Vector3(-51, 0, 10)],
		["Dogleg hold", "default", Vector3(-4, 0, 12)],
		["Culvert hold", "default", Vector3(36, 0, 24)],
		["Overlook post", "default", Vector3(48, 2.5, -23)],
		["Yard anchor", "default", Vector3(-40, 0, -23)],
		["Gate smoke", "utility", Vector3(-51, 0, 0)],
		["Crossing smoke", "utility", Vector3(4, 0, -15)],
		["Mouth smoke", "utility", Vector3(44, 0, 2)],
	]
	for anchor: Array in anchors:
		put("tactical_anchor", anchor[2] as Vector3, Vector3.ZERO, 0.0, {"name": anchor[0], "kind": anchor[1]})
	# AI hints: defenders hold these points and watch along their facing.
	put("ai_hold", Vector3(-44, 0, -23), Vector3.ZERO, 160.0, {"site": "A"})
	put("ai_hold", Vector3(-36.5, 0, -23.2), Vector3.ZERO, 195.0, {"site": "A"})
	put("ai_hold", Vector3(-53, 0, -7.6), Vector3.ZERO, 180.0, {"site": "A"})
	put("ai_hold", Vector3(48, 2.5, -22), Vector3.ZERO, 180.0, {"site": "B"})
	put("ai_hold", Vector3(33.5, 0, -7), Vector3.ZERO, 225.0, {"site": "B"})
	put("ai_hold", Vector3(54, 0, -17), Vector3.ZERO, 155.0, {"site": "B"})
	put("ai_cover", Vector3(-45.6, 0, -12), Vector3.ZERO, 180.0, {"site": "A"})
	put("ai_cover", Vector3(-39, 0, -15.4), Vector3.ZERO, 180.0, {"site": "A"})
	put("ai_cover", Vector3(47.6, 0, -9), Vector3.ZERO, 180.0, {"site": "B"})
	put("ai_cover", Vector3(39.5, 0, -6.2), Vector3.ZERO, 180.0, {"site": "B"})
	put("ai_angle", Vector3(-51, 0, 20), Vector3.ZERO, 0.0, {"site": "A"})
	put("ai_angle", Vector3(-25, 1.5, -1), Vector3.ZERO, 0.0, {"site": "A"})
	put("ai_angle", Vector3(44, 0, 6), Vector3.ZERO, 0.0, {"site": "B"})
	put("ai_angle", Vector3(31, 0, -15), Vector3.ZERO, 0.0, {"site": "B"})


## Lamp fixtures wherever reachable floor sat in shade with no lamp in reach (each placed on the
## nearest wall, or hung from the ceiling indoors), and everyday clutter against walls along the
## routes, clear of doors, stairs, bombsites, spawns and timing chokepoints.
func _lamps_and_props() -> void:
	layer("Lamps")
	for entry: Array in [
		["lamp_hanging", Vector3(-2.00, 3.10, -16.00), 0.0],
		["lamp_wall", Vector3(34.25, 2.10, 26.00), 90.0],
		# Shaded lanes and yards (open to the sky, but in shadow with no lamp in reach).
		["lamp_wall", Vector3(-55.75, 2.10, -20.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, -8.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, 4.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, 18.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, 28.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, 42.00), 90.0],
		["lamp_wall", Vector3(-55.75, 2.10, 50.00), 90.0],
		["lamp_wall", Vector3(-39.75, 2.10, -28.00), 90.0],
		["lamp_wall", Vector3(-38.00, 2.10, 47.25), 0.0],
		["lamp_wall", Vector3(-32.00, 2.10, -35.75), 0.0],
		["lamp_wall", Vector3(-24.00, 2.10, 47.25), 0.0],
		["lamp_wall", Vector3(-20.00, 2.10, 16.25), 0.0],
		["lamp_wall", Vector3(-20.00, 2.10, -35.75), 0.0],
		["lamp_wall", Vector3(-10.00, 2.10, 44.25), 0.0],
		["lamp_wall", Vector3(-12.00, 2.10, 16.25), 0.0],
		["lamp_wall", Vector3(-2.00, 2.10, -39.75), 0.0],
		["lamp_wall", Vector3(-7.75, 2.10, 30.83), 90.0],
		["lamp_wall", Vector3(0.25, 2.10, 4.00), 90.0],
		["lamp_wall", Vector3(3.81, 2.10, -21.50), 180.0],
		["lamp_wall", Vector3(6.00, 2.10, 44.25), 0.0],
		["lamp_wall", Vector3(10.00, 2.10, -39.75), 0.0],
		["lamp_wall", Vector3(16.00, 2.10, -17.75), 0.0],
		["lamp_wall", Vector3(20.00, 2.10, 47.25), 0.0],
		["lamp_wall", Vector3(22.00, 2.10, -35.75), 0.0],
		["lamp_wall", Vector3(30.25, 2.10, -18.83), 90.0],
		["lamp_wall", Vector3(30.00, 2.10, 47.25), 0.0],
		["lamp_wall", Vector3(32.00, 2.10, -35.75), 0.0],
		["lamp_wall", Vector3(30.25, 2.10, -4.00), 90.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))
	layer("Street life")
	for entry: Array in [
		["sack_pile", Vector3(-22.00, 0.00, -17.39), 0.0],
		["sack_pile", Vector3(-44.00, 0.00, 54.39), 180.0],
		["market_shelf", Vector3(-18.00, 0.00, 54.68), 180.0],
		["pottery_jar", Vector3(45.00, 0.00, -19.54), 0.0],
		["barrel_cluster", Vector3(-46.76, 0.00, 17.00), -90.0],
		["pottery_jar", Vector3(-11.00, 0.00, -12.46), 180.0],
		["braced_crate", Vector3(18.00, 0.00, -17.37), 0.0],
		["pottery_jar", Vector3(35.54, 0.00, -31.00), -90.0],
		["sack_pile", Vector3(-55.39, 0.00, -24.00), 90.0],
		["market_shelf", Vector3(56.00, 0.00, -19.68), 0.0],
		["pottery_jar", Vector3(-0.46, 0.00, 33.00), -90.0],
		["barrel_cluster", Vector3(-27.00, 0.00, -30.76), 180.0],
		["planter", Vector3(7.64, 0.00, -4.00), -90.0],
		["braced_crate", Vector3(-55.36, 0.00, -17.00), 90.0],
		["pottery_jar", Vector3(57.54, 0.00, -11.00), -90.0],
		["sack_pile", Vector3(-27.39, 0.00, 20.00), 90.0],
		["market_shelf", Vector3(22.00, 0.00, 47.32), 0.0],
		["pottery_jar", Vector3(-32.00, 0.00, 47.46), 0.0],
		["market_shelf", Vector3(34.32, 0.00, 29.00), 90.0],
		["planter", Vector3(30.36, 0.00, -8.00), 90.0],
		["braced_crate", Vector3(28.00, 0.00, -30.63), 180.0],
		["pottery_jar", Vector3(12.00, 0.00, -12.46), 180.0],
		["sack_pile", Vector3(-0.61, 0.00, 17.00), -90.0],
		["braced_crate", Vector3(45.00, 0.00, 19.37), 180.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))


# --- the potters' quarter (version 4) -----------------------------------------------------------

## Paving, dressed street walls, roofs that read as a working potters' town, and racks of pots.
func _potters_quarter() -> void:
	layer("Paving")
	# Each finish laid 2 cm proud of the sand (bots step 10 cm).
	for entry: Array in [
		[-56, -28, -26, -2, "tile_terracotta"],   # Kiln Yard
		[-56, -46, -2, 47, "packed_earth"],       # Kiln Gate and the Salt Road
		[-8, 0, 10, 44, "cobblestone"],           # Spice Row
		[-8, 8, 4, 10, "cobblestone"],            # Dogleg
		[0, 8, -28, 4, "flagstones"],             # Clock Lane, Crossing, Garrison Lane
		[-14, 14, -40, -28, "stone_paving"],      # Garrison
		[8, 28, -18, -12, "packed_earth"],        # Dyers' Cut
		[30, 58, -20, 4, "limestone"],            # Cistern
		[-12, 12, 44, 58, "packed_earth"],        # Caravan Gate
		[12, 38, 47, 55, "cobblestone"],          # Tanners' Lane
	]:
		mass("floor", float(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]), 0.05, str(entry[4]), -0.03)
	layer("Facades")
	dress_facades({
		"plinth": "fired_clay", "plinth_h": 0.6,
		"cornice": "tile_terracotta", "cornice_h": 0.35,
		"window": {"type": "window", "size": Vector3(1.0, 1.4, 0.3),
			"props": {"panes_x": 2, "panes_y": 2, "shutters": true},
			"materials": ["cloth_blue", "wood_dark", "cloth_blue", "weathered_wood"]},
		"window_every": 4.0, "first_sill": 1.2, "storey": 3.0, "blank": 0.3,
		"door": {"type": "door", "size": Vector3(1.3, 2.5, 0.3), "props": {"panels": 2, "fanlight": false},
			"materials": ["cloth_blue", "wood_dark", "weathered_wood"]},
		"door_chance": 0.5, "beams": "wood_dark",
		"extra": _glazed_panel,
	}, Rect2(-56, -40, 114, 98))
	layer("Roofs")
	_roofs()
	layer("Pottery")
	_pottery()


## Above some doors a glazed tile panel, the potters' sign.
func _glazed_panel(run: Dictionary) -> void:
	var door_at := float(run["door_at"])
	if door_at < 0.0 or int(run["pick"]) % 2 == 1:
		return
	band(run["from"] as Vector2, run["along"] as Vector2, run["facing"] as Vector2, door_at - 0.9, door_at + 0.9,
		float(run["ground"]) + 2.75, 0.5, 0.06, "cloth_blue", float(run["yaw"]))
	band(run["from"] as Vector2, run["along"] as Vector2, run["facing"] as Vector2, door_at - 0.7, door_at + 0.7,
		float(run["ground"]) + 2.85, 0.3, 0.08, "limewash", float(run["yaw"]))


## Kiln chimneys, water jars and drying racks on the flat roofs, a parapet round each.
func _roofs() -> void:
	var tops: Array[Dictionary] = []
	for piece: Dictionary in controller.document.pieces:
		if str(piece["type"]) == "building":
			tops.append(footprint(piece))
	for fp: Dictionary in tops:
		var half: Vector2 = fp["half"]
		var centre: Vector2 = fp["centre"]
		var top := float(fp["top"])
		if half.x < 1.5 or half.y < 1.5:
			continue
		var pick := pick_at(centre, 7)
		match pick % 4:
			0:
				# A kiln chimney: a brick stack with a soot-black crown.
				var at := centre + Vector2(half.x - 1.2, -half.y + 1.2)
				put("column", Vector3(at.x, top, at.y), Vector3(1.1, 3.6, 1.1), 0.0, {}, "red_brick")
				put("column", Vector3(at.x, top + 3.6, at.y), Vector3(1.3, 0.5, 1.3), 0.0, {}, "metal_dark")
			1:
				# Water jars by a roof hatch.
				for k: int in 3:
					put("pottery_jar", Vector3(centre.x - 1.0 + k * 0.9, top, centre.y + half.y - 0.8), Vector3.ZERO, float(k * 40), {}, "fired_clay")
				put("block", Vector3(centre.x + 1.5, top, centre.y), Vector3(1.2, 0.4, 1.2), 0.0, {}, "weathered_wood")
			2:
				# A drying rack of new pots under a canvas shade.
				if half.x >= 3.0 and half.y >= 2.5:
					put("awning", Vector3(centre.x, top, centre.y), Vector3(4.0, 2.4, 3.0), 0.0, {}, "canvas")
					for k: int in 2:
						put("market_shelf", Vector3(centre.x - 0.8 + k * 1.6, top, centre.y), Vector3.ZERO, 0.0, {}, "weathered_wood")
			_:
				pass


## Pots stacked against the walls of the yards, as a potters' quarter keeps them: clear of the
## doors, stairs, spawns and the routes' chokepoints.
func _pottery() -> void:
	for entry: Array in [
		# Kiln Yard: racks of fired pots along the north wall, a stack by the kilns.
		["market_shelf", Vector3(-52.5, 0, -25.6), 0.0],
		["market_shelf", Vector3(-44.0, 0, -25.6), 0.0],
		["pottery_jar", Vector3(-55.3, 0, -12.0), 0.0],
		["pottery_jar", Vector3(-55.3, 0, -11.1), 30.0],
		["pottery_jar", Vector3(-54.5, 0, -11.5), 60.0],
		["kiln", Vector3(-31.2, 0, -24.0), 0.0],
		# Cistern: jars at the well and along the east wall.
		["pottery_jar", Vector3(57.3, 0, -2.0), 0.0],
		["pottery_jar", Vector3(57.3, 0, -1.1), 45.0],
		["pottery_jar", Vector3(57.3, 0, 0.8), 15.0],
		["stone_trough", Vector3(42.0, 0, 3.4), 0.0],
		# Garrison: the potters' guild stores.
		["market_shelf", Vector3(-12.0, 0, -39.6), 0.0],
		["market_shelf", Vector3(12.0, 0, -39.6), 0.0],
		["pottery_jar", Vector3(13.3, 0, -33.0), 0.0],
		["pottery_jar", Vector3(13.3, 0, -32.1), 70.0],
		# Caravan Gate: crates of pots waiting for the caravans.
		["braced_crate", Vector3(-10.8, 0, 56.6), 0.0],
		["braced_crate", Vector3(10.8, 0, 56.6), 0.0],
		["pottery_jar", Vector3(-11.3, 0, 54.6), 20.0],
		["pottery_jar", Vector3(11.3, 0, 54.6), 50.0],
		# Tanners' Lane and the West Bend.
		["pottery_jar", Vector3(36.6, 0, 54.4), 0.0],
		["pottery_jar", Vector3(-55.3, 0, 52.0), 0.0],
		["pottery_jar", Vector3(-55.3, 0, 52.9), 35.0],
	]:
		put(str(entry[0]), entry[1] as Vector3, Vector3.ZERO, float(entry[2]))
