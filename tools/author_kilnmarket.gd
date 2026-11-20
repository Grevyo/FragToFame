extends SceneTree
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

const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"
const STAGING_DIR: String = "user://authoring/kilnmarket"
const OFFICIAL_ID: String = "map_f2f_kilnmarket"

var studio: Node
var controller: MapEditController


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	studio = (load(STUDIO) as PackedScene).instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	studio.set("storage", MapStorage.new(STAGING_DIR))
	studio.set("autosave", MapAutosave.new(STAGING_DIR.path_join("autosave")))
	studio.set("tactic_storage", TacticStorage.new(STAGING_DIR.path_join("tactics")))
	controller = studio.get("controller") as MapEditController
	(studio.get("ui") as StudioUI).confirm_dialog.hide()

	# Start from the blank template and clear it.
	studio.call("load_template", "blank")
	studio.call("select_all")
	controller.delete_selection()
	controller.set_metadata("Kilnmarket", "F2F official",
		"Desert pottery town. Three lanes: the Salt Road to the Kiln Yard (A), Spice Row through the middle, and the Culvert to the Cistern (B).")
	controller.set_lighting({"sun_yaw": 215.0, "sun_pitch": 55.0, "sun_energy": 1.25, "sun_color": "fff0d8",
		"ambient_color": "c8b8a0", "ambient_energy": 0.7})

	_ground_and_buildings()
	_a_side()
	_mid()
	_b_side()
	_lamps_and_props()
	_spawns_and_zones()
	_callouts()
	_tactical()

	var report: Dictionary = studio.call("validation_report")
	print("\n== Kilnmarket: %d pieces ==" % controller.document.pieces.size())
	for error: String in report["errors"]:
		print("ERROR: ", error)
	for warning: String in report["warnings"]:
		print("Warning: ", warning)
	print(report["timing_text"])
	print("navmesh: %d polygons, analysis %d ms" % [(studio.get("analysis") as MapAnalysis).polygon_count(),
		(studio.get("analysis") as MapAnalysis).bake_msec])

	var err: Error = studio.call("save_map")
	print("save: ", error_string(err), "  ->  ", studio.get("current_path"))
	if err == OK and (report["errors"] as Array).is_empty():
		_publish(str(studio.get("current_path")))
	studio.queue_free()
	await process_frame
	quit(0 if err == OK else 1)


## Publishing step: the saved file is copied to the official folder under the official map ID.
func _publish(saved_path: String) -> void:
	var doc := MapStorage.new(STAGING_DIR).load_path(saved_path)
	doc.map_id = OFFICIAL_ID
	doc.revision = 3
	# Version 2: the Overlook stair was lengthened so bots can always climb it.
	# Version 3: lamp fixtures in its dark corners and everyday props along the walls.
	doc.content_version = 3
	doc.content_hash = doc.content_fingerprint()
	DirAccess.make_dir_recursive_absolute(OfficialMaps.DIRECTORY)
	var file := FileAccess.open(OfficialMaps.path_for(OFFICIAL_ID), FileAccess.WRITE)
	file.store_string(doc.to_json() + "\n")
	file.close()
	print("published: ", OfficialMaps.path_for(OFFICIAL_ID))


# --- editor operations --------------------------------------------------------------------------

func _layer(layer_name: String) -> void:
	for entry: Dictionary in controller.document.layers:
		if entry["name"] == layer_name:
			studio.set("active_layer", entry["id"])
			return
	studio.set("active_layer", controller.add_layer(layer_name))


## Palette → click to place → inspector edits (size, rotation, props, material).
func put(type: String, position: Vector3, size: Vector3 = Vector3.ZERO, rotation: float = 0.0,
		props: Dictionary = {}, material: String = "") -> String:
	studio.call("_on_piece_type_selected", type)
	var id: String = studio.call("place_at", position)
	var piece := controller.document.get_piece(id)
	piece["position"] = position  # Lights are placed raised; the inspector sets the exact height.
	if size != Vector3.ZERO:
		piece["size"] = size
	piece["rotation_y"] = rotation
	(piece["props"] as Dictionary).merge(props, true)
	piece["material"] = material
	controller.update_piece(piece, "Edit properties")
	return id


## A box-shaped piece covering x1..x2 by z1..z2 from the ground up to [param height].
func mass(type: String, x1: float, x2: float, z1: float, z2: float, height: float, material: String = "",
		base: float = 0.0) -> String:
	return put(type, Vector3((x1 + x2) / 2.0, base, (z1 + z2) / 2.0), Vector3(x2 - x1, height, z2 - z1), 0.0, {}, material)


func area(area_name: String, x1: float, x2: float, z1: float, z2: float, role: String = "", base: float = 0.0) -> String:
	return put("callout", Vector3((x1 + x2) / 2.0, base, (z1 + z2) / 2.0), Vector3(x2 - x1, 3.0, z2 - z1), 0.0,
		{"name": area_name, "role": role})


# --- the map ------------------------------------------------------------------------------------

func _ground_and_buildings() -> void:
	_layer("Ground")
	put("floor_sand", Vector3(1, -1, 9), Vector3(122, 1, 106))
	_layer("Buildings")
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
	_layer("Buildings")
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

	_layer("Props")
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
	_layer("Lights")
	put("light_lamp", Vector3(-20, 3.4, -15), Vector3.ZERO, 0.0, {"energy": 2.0, "range": 10.0})
	put("light_lamp", Vector3(-8, 3.4, -15), Vector3.ZERO, 0.0, {"energy": 2.0, "range": 10.0})


func _mid() -> void:
	_layer("Props")
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
	_layer("Buildings")
	put("double_door", Vector3(30, 0, -15), Vector3(6, 4, 0.5), 90.0, {"opening_width": 2.4, "opening_height": 2.6})


func _b_side() -> void:
	_layer("Buildings")
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
	_layer("Lights")
	put("light_lamp", Vector3(36, 2.6, 36), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})
	put("light_lamp", Vector3(38, 2.6, 18), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})
	put("light_lamp", Vector3(44, 2.6, 10), Vector3.ZERO, 0.0, {"energy": 1.8, "range": 9.0})

	_layer("Props")
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
	_layer("Gameplay")
	for x: float in [0.0, -2.0, 2.0, -4.0, 4.0]:
		put("spawn_attack", Vector3(x, 0, 53))
		put("spawn_defence", Vector3(x, 0, -36), Vector3.ZERO, 180.0)
	put("buy_zone", Vector3(0, 0, 51), Vector3(24, 3, 14), 0.0, {"team": "attack"})
	put("buy_zone", Vector3(0, 0, -34), Vector3(28, 3, 12), 0.0, {"team": "defence"})
	put("bombsite", Vector3(-44, 0, -14), Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", Vector3(45, 0, -9), Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	_layer("Tactics")
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
	_layer("Tactics")
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
	_layer("Lamps")
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
	_layer("Street life")
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
