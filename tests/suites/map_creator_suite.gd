extends TestSuite
## Milestone 16, stages A and B: the map creator as a level-design tool (multi-select, group
## edits, clipboard, prefabs, gizmos, snapping, measuring, overhead view, catalogue, materials,
## lighting, autosave, layers, playtest options) and its AI support (navmesh analysis,
## reachability, islands, timings, callout areas, anchors, hints, tactic compatibility).

const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"
const TEST_DIR: String = "user://tests/map_creator"


func suite_name() -> String:
	return "Map creator tools and AI support (Milestone 16)"


func run() -> void:
	_wipe(TEST_DIR)
	_test_format()
	_test_catalogue()
	_test_lamp_fixtures_and_props()
	_test_detailed_materials()
	_test_building_dressing()
	_test_snapping()
	_test_controller_groups()
	_test_clipboard_and_prefabs()
	_test_layers_and_lighting()
	_test_autosave()
	_test_tactical_queries()
	await _test_collision_matches_visuals()
	await _test_analysis()
	await _test_studio_tools()
	await _test_draw_tools()
	await _test_snap_placement()
	await _test_lower_floor_snap()
	await _test_geometry_palette_and_textures()
	await _test_tactic_compatibility()
	await _test_playtest_options()
	await _test_draw_navmesh_bot_playtest()
	_wipe(TEST_DIR)


# --- helpers ------------------------------------------------------------------------------------

func _piece(type: String, position: Vector3, size: Vector3 = Vector3.ZERO, rotation: float = 0.0, props: Dictionary = {}) -> Dictionary:
	var piece := MapDocument.make_piece(type, position, rotation, size)
	(piece["props"] as Dictionary).merge(props, true)
	return piece


## A small flat arena: 30 x 30 m floor, one spawn per team, both sites and buy zones.
func _arena(map_name: String = "Analysis arena") -> MapDocument:
	var doc := MapDocument.create(map_name)
	doc.add_piece(_piece("floor", Vector3(0, -0.2, 0), Vector3(30, 0.2, 30)))
	doc.add_piece(_piece("spawn_attack", Vector3(0, 0, 12)))
	doc.add_piece(_piece("spawn_defence", Vector3(0, 0, -12), Vector3.ZERO, 180.0))
	doc.add_piece(_piece("bombsite", Vector3(-10, 0, -8), Vector3(6, 3, 6), 0.0, {"site": "A"}))
	doc.add_piece(_piece("bombsite", Vector3(10, 0, -8), Vector3(6, 3, 6), 0.0, {"site": "B"}))
	doc.add_piece(_piece("buy_zone", Vector3(0, 0, 12), Vector3(8, 3, 4), 0.0, {"team": "attack"}))
	doc.add_piece(_piece("buy_zone", Vector3(0, 0, -12), Vector3(8, 3, 4), 0.0, {"team": "defence"}))
	return doc


func _host() -> Node3D:
	var host := Node3D.new()
	host.name = "AnalysisHost"
	tree.root.add_child(host)
	return host


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe(path.path_join(sub))
		dir.remove(sub)
	for file_name: String in dir.get_files():
		dir.remove(file_name)


func _key(code: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	return event


# --- data ---------------------------------------------------------------------------------------

func _test_format() -> void:
	section("Map format v2 and the v1 migration")
	var doc := MapDocument.create("Format")
	var wall := doc.add_piece(_piece("wall_adobe", Vector3(1, 0, 2), Vector3.ZERO, 37.5))
	var piece := doc.get_piece(wall)
	piece["material"] = "sandstone"
	piece["group"] = "grp_4"
	doc.replace_piece(piece)
	doc.lighting = {"sun_yaw": 200.0, "sun_pitch": 50.0}
	doc.layers.append({"id": "layer_1", "name": "Props", "visible": false, "locked": true})
	doc.prefabs.append({"id": "pf_1", "name": "Pair", "pieces": [_piece("crate", Vector3.ZERO), _piece("crate", Vector3(2, 0, 0))]})
	var copy := MapDocument.from_json(doc.to_json())
	check(copy != null and int(copy.to_dict()["format_version"]) == 2, "documents are written as format version 2")
	var loaded := copy.get_piece(wall)
	check(is_equal_approx(float(loaded["rotation_y"]), 37.5) and loaded["material"] == "sandstone" and loaded["group"] == "grp_4",
		"free rotation, material and group survive the round trip")
	check(copy.lighting == doc.lighting and copy.layers.size() == 2 and not copy.is_layer_visible("layer_1")
		and copy.is_layer_locked("layer_1"), "lighting and layers survive the round trip")
	check(copy.prefabs.size() == 1 and (copy.prefabs[0]["pieces"] as Array).size() == 2 and copy.allocate_prefab_id() == "pf_2",
		"saved prefabs survive the round trip and their IDs are never reused")
	check(copy.allocate_group_id() == "grp_5", "group IDs are never reused")

	var v1 := {"format": "f2f.map", "format_version": 1, "map_id": "map_v1_sample", "name": "Old map", "revision": 3,
		"next_piece_number": 3, "pieces": [
			{"id": "pc_1", "type": "floor", "position": [0, -0.2, 0], "rotation_y": 0, "size": [8, 0.2, 8], "props": {}},
			{"id": "pc_2", "type": "callout", "position": [0, 0, 0], "rotation_y": 90, "size": [4, 3, 4], "props": {"name": "Yard"}},
		]}
	var migrated := MapDocument.from_dict(v1)
	check(migrated != null and migrated.pieces.size() == 2 and migrated.revision == 3, "a version 1 map still loads")
	check(migrated != null and migrated.get_piece("pc_1")["layer"] == MapDocument.DEFAULT_LAYER
		and migrated.get_piece("pc_1")["material"] == "" and migrated.get_piece("pc_1")["group"] == ""
		and migrated.content_version == 0 and migrated.lighting.is_empty() and migrated.prefabs.is_empty(),
		"the migration gives old pieces the default layer, no material and no group")
	check(migrated != null and MapDocument.from_json(migrated.to_json()) != null
		and int(migrated.to_dict()["format_version"]) == 2, "a migrated map saves as version 2")
	var newer := doc.to_dict()
	newer["format_version"] = 3
	check(MapDocument.from_dict(newer) == null, "a newer map format is refused")

	var rotated := _piece("wall", Vector3.ZERO, Vector3(4, 3, 0.4), 45.0)
	var box := MapDocument.piece_aabb(rotated)
	check(absf(box.size.x - box.size.z) < 0.01 and box.size.x > 3.0, "the AABB of a 45° piece encloses its rotated footprint")
	check(MapDocument.piece_contains(rotated, Vector3(1.2, 1, -1.2)) and not MapDocument.piece_contains(rotated, Vector3(1.2, 1, 1.2)),
		"containment uses the oriented box")

	section("Content version")
	var storage := MapStorage.new(TEST_DIR)
	var saved := _arena("Content version")
	check(storage.save(saved) == OK and saved.content_version == 1 and saved.content_hash.length() == 64,
		"the first save sets content version 1")
	saved.name = "Renamed only"
	saved.lighting = {"sun_yaw": 90.0}
	var site := saved.pieces_of_type("bombsite")[0].duplicate(true)
	site["material"] = "sandstone"
	saved.replace_piece(site)
	saved.add_piece(_piece("light_lamp", Vector3(0, 3, 0)))
	check(storage.save(saved) == OK and saved.revision == 2 and saved.content_version == 1,
		"cosmetic edits (name, lighting, material, lights) keep the content version")
	saved.add_piece(_piece("crate", Vector3(3, 0, 3)))
	check(storage.save(saved) == OK and saved.content_version == 2, "a gameplay edit raises the content version")
	var reloaded := storage.load_map(saved.map_id)
	check(reloaded != null and reloaded.content_version == 2 and reloaded.content_hash == reloaded.content_fingerprint(),
		"the content version and hash are stored in the file")


func _test_lamp_fixtures_and_props() -> void:
	section("Lamp fixtures and street props")
	var fixtures: Array[String] = ["lamp_wall", "lamp_post", "lamp_hanging", "lamp_bulkhead", "brazier"]
	var listed := PieceCatalog.palette_types_in_group("Lights")
	check(fixtures.all(func(type: String) -> bool: return listed.has(type) and PieceCatalog.is_fixture(type)),
		"the Lights palette offers wall lanterns, street lamps, hanging lamps, bulkheads and braziers")
	var props_listed := PieceCatalog.palette_types_in_group("Props")
	check(["pallet", "sack_pile", "planter", "park_bench", "notice_board", "bollard", "washing_line"].all(
		func(type: String) -> bool: return props_listed.has(type)), "the Props palette offers the new street props")
	check(not PieceCatalog.is_fixture("light_lamp") and not PieceCatalog.is_fixture("crate"),
		"bare lights and ordinary props are not fixtures")
	var defaults := MapDocument.default_props("lamp_wall")
	check(defaults.has("energy") and defaults.has("range") and defaults.has("color"), "a placed fixture starts with its light settings")
	var lantern := MapBuilder.build_piece(_piece("lamp_wall", Vector3(2, 1, 3), Vector3.ZERO, 90.0, {"energy": 3.0, "range": 12.0}),
		MapBuilder.Mode.RUNTIME)
	var light := lantern.get_node_or_null("Light") as OmniLight3D
	var size := PieceCatalog.default_size("lamp_wall")
	check(light != null and is_equal_approx(light.light_energy, 3.0) and is_equal_approx(light.omni_range, 12.0)
		and light.position.is_equal_approx(PieceCatalog.fixture_light_position("lamp_wall", size)),
		"a wall lantern carries its own light at the lantern, with the brightness and range set in the inspector")
	check(light != null and light.position.y > 0.0 and light.position.y < size.y and absf(light.position.z) < size.z * 0.5,
		"the lantern's light sits inside the piece")
	var glowing := false
	for mesh_node: Node in lantern.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh_node as MeshInstance3D).material_override as StandardMaterial3D
		glowing = glowing or (material != null and material.emission_enabled)
	check(glowing and lantern.find_children("*", "CollisionShape3D", true, false).size() > 0,
		"the lantern glass glows and the fixture is solid")
	lantern.free()
	var preview := MapBuilder.build_preview([_piece("lamp_post", Vector3.ZERO)])
	check(preview.find_children("*", "Light3D", true, false).is_empty(), "placement previews carry no light")
	preview.free()
	var line := PieceShapes.parts("washing_line", Vector3(5, 3, 0.2), {})
	var lowest := INF
	for part: Dictionary in line:
		if str(part["mat"]) != "wood_dark":
			lowest = minf(lowest, (part["pos"] as Vector3).y - (part["size"] as Vector3).y * 0.5)
	check(lowest >= 2.0 - 0.001, "washing hangs at or above 2 m so players walk under it")


func _test_catalogue() -> void:
	section("Piece catalogue, shapes and materials")
	for type: String in ["wall_adobe", "wall_half", "wall_parapet", "floor_sand", "floor_tile", "arch", "doorway", "double_door",
			"wall_window", "ramp_earth", "stairs_stone", "ledge", "crate_stack", "barrel", "barrel_cluster", "vehicle_truck",
			"vehicle_car", "vehicle_cart", "awning", "market_stall", "cloth_screen", "sandbag_wall", "light_lamp", "light_spot",
			"tactical_anchor", "ai_cover", "ai_hold", "ai_angle"]:
		check(PieceCatalog.has_type(type) and PieceCatalog.GROUP_ORDER.has(str(PieceCatalog.info(type)["group"])),
			"catalogue has %s in a palette group" % type)
	var materials_ok := true
	var parts_ok := true
	for type: String in PieceCatalog.TYPES:
		var default_material := PieceCatalog.default_material(type)
		materials_ok = materials_ok and (default_material.is_empty() or MapMaterials.has_material(default_material))
		if PieceCatalog.kind(type) != "compound":
			continue
		var size := PieceCatalog.default_size(type)
		var box := AABB(Vector3(-size.x / 2.0, 0, -size.z / 2.0), size).grow(0.9)
		for part: Dictionary in PieceShapes.parts(type, size, MapDocument.default_props(type)):
			var part_size: Vector3 = part["size"]
			var fixed := str(part["mat"])
			parts_ok = parts_ok and part_size.x > 0.0 and part_size.y > 0.0 and part_size.z > 0.0 \
				and box.has_point(part["pos"] as Vector3) and (fixed.is_empty() or MapMaterials.has_material(fixed))
	check(materials_ok, "every default material exists in the palette")
	check(parts_ok, "every compound part has a positive size, sits inside its piece and uses a known material")
	var door := PieceShapes.parts("doorway", Vector3(3, 3, 0.4), {"opening_width": 1.4, "opening_height": 2.2})
	check(door.size() == 3 and is_equal_approx((door[0]["size"] as Vector3).x, 0.8)
		and is_equal_approx((door[2]["size"] as Vector3).y, 0.8), "a doorway is two jambs and a lintel around the opening")
	var wide := PieceShapes.parts("doorway", Vector3(3, 3, 0.4), {"opening_width": 99.0, "opening_height": 99.0})
	check((wide[0]["size"] as Vector3).x > 0.0 and wide.size() == 3, "opening sizes are clamped to the wall")
	check(MapMaterials.material("adobe") != null and MapMaterials.material("adobe") == MapMaterials.material("adobe")
		and MapMaterials.material("no_such") == null, "palette materials are generated once and shared")
	check(MapMaterials.for_piece("wall", "sandstone") == MapMaterials.material("sandstone")
		and MapMaterials.for_piece("wall_adobe", "") == MapMaterials.material("adobe")
		and MapMaterials.for_piece("wall", "") == BlockBuilder.checker_material(PieceCatalog.color("wall")),
		"a piece uses its own material, else the type default, else the dev checker")
	var bad := _arena()
	var odd := bad.pieces[0].duplicate(true)
	odd["material"] = "vantablack"
	bad.replace_piece(odd)
	check(not (MapValidator.validate(bad)["errors"] as Array).is_empty(), "the validator rejects an unknown material")
	var tilted := _arena()
	tilted.add_piece(_piece("crate", Vector3(2, 0, 2), Vector3.ZERO, 30.0))
	check((MapValidator.validate(tilted)["errors"] as Array).is_empty(), "the validator accepts free rotation")


func _test_detailed_materials() -> void:
	section("Detailed map materials")
	var detailed: Array[String] = ["sandstone", "stone_paving", "cobblestone", "limewash", "limestone", "fired_clay",
		"weathered_wood", "brass"]
	var valid := true
	for id: String in detailed:
		var finish := MapMaterials.material(id)
		if finish == null or not finish.normal_enabled or finish.normal_texture == null:
			valid = false
			continue
		var colour := finish.albedo_texture.get_image()
		var normals := finish.normal_texture.get_image()
		var swatch := MapMaterials.swatch(id)
		var tile_size := Vector2i(MapMaterials.TEXTURE_SIZE, MapMaterials.TEXTURE_SIZE)
		valid = valid and colour.get_size() == tile_size and normals.get_size() == tile_size
		valid = valid and colour.has_mipmaps() and normals.has_mipmaps() and finish.uv1_world_triplanar
		valid = valid and swatch.get_size() == Vector2(MapMaterials.SWATCH_SIZE, MapMaterials.SWATCH_SIZE)
	check(valid, "upgraded and new materials have shared world-aligned colour and normal maps plus compact swatches")
	var masonry := MapMaterials.material("sandstone")
	var albedo := masonry.albedo_texture.get_image()
	var relief := masonry.normal_texture.get_image()
	check(albedo.get_pixel(31, 1).get_luminance() < albedo.get_pixel(31, 16).get_luminance() - 0.08
		and absf(relief.get_pixel(31, 2).g - 0.5) > 0.03,
		"brick mortar is visibly darker and has a normal gradient along its edge")
	check(MapMaterials.material("brass").metallic > 0.5 and MapMaterials.material("brass").roughness < masonry.roughness,
		"brass and stone use different lighting responses")


func _test_building_dressing() -> void:
	section("Windows, doors and wall piers")
	for type: String in ["window", "door", "wall_pier"]:
		check(PieceCatalog.has_type(type) and PieceCatalog.is_solid(type), "%s is a solid catalogue piece" % type)
	var plain := PieceShapes.parts("window", Vector3(1.2, 1.6, 0.3), {"panes_x": 1, "panes_y": 1, "shutters": false})
	var barred := PieceShapes.parts("window", Vector3(1.2, 1.6, 0.3), {"panes_x": 3, "panes_y": 2, "shutters": false})
	var shuttered := PieceShapes.parts("window", Vector3(1.2, 1.6, 0.3), {"panes_x": 3, "panes_y": 2, "shutters": true})
	check(barred.size() == plain.size() + 3, "glazing bars follow panes across and down (%d, %d)" % [plain.size(), barred.size()])
	check(shuttered.size() == barred.size() + 2, "open shutters add two leaves")
	var glazed := false
	for part: Dictionary in plain:
		glazed = glazed or str(part["mat"]) == "glass"
	check(glazed and MapMaterials.has_material("glass"), "windows are glazed with the glass material")
	var door := PieceShapes.parts("door", Vector3(1.2, 2.4, 0.3), {"panels": 3, "fanlight": true})
	var low := PieceShapes.parts("door", Vector3(1.2, 2.0, 0.3), {"panels": 3, "fanlight": true})
	check(low.size() == door.size() - 2, "a door too short for a fanlight leaves it out")
	var step_ok := false
	for part: Dictionary in door:
		if str(part["mat"]) == "granite_blocks":
			step_ok = (part["size"] as Vector3).y <= 0.1
	check(step_ok, "the door step is low enough for bots to walk over")
	var pier := PieceShapes.parts("wall_pier", Vector3(0.9, 3.6, 0.9), {})
	var top := 0.0
	for part: Dictionary in pier:
		top = maxf(top, (part["pos"] as Vector3).y + (part["size"] as Vector3).y / 2.0)
	check(pier.size() == 3 and is_equal_approx(top, 3.6), "a wall pier has base, shaft and cap and stands its full height")
	check(MapDocument.default_props("window").has("panes_x") and MapDocument.default_props("door").has("panels"),
		"window and door defaults are editable properties")
	var stones := PieceShapes.parts("coping_stones", Vector3(4.5, 0.24, 0.84), {"stone_length": 0.9, "seed": 3})
	var again := PieceShapes.parts("coping_stones", Vector3(4.5, 0.24, 0.84), {"stone_length": 0.9, "seed": 3})
	var heights: Dictionary[float, bool] = {}
	var same := stones.size() == again.size()
	for i in stones.size():
		heights[snappedf((stones[i]["size"] as Vector3).y, 0.001)] = true
		same = same and stones[i]["size"] == again[i]["size"]
	check(stones.size() == 5 and heights.size() > 1 and same, "coping stones are separate, uneven and repeatable for one seed")

	section("Surface relief")
	var flat := MapMaterials.material("mud_brick", 0.0)
	var normal := MapMaterials.material("mud_brick")
	var deep := MapMaterials.material("mud_brick", 2.5)
	check(not flat.normal_enabled and normal.normal_enabled and deep.normal_scale > normal.normal_scale * 2.4,
		"relief 0 is flat and higher relief deepens the bumps (%.2f vs %.2f)" % [deep.normal_scale, normal.normal_scale])
	check(deep.ao_enabled and deep.ao_texture != null and deep.albedo_texture == normal.albedo_texture,
		"relief shades grooves with an occlusion map and shares the palette textures")
	check(MapMaterials.material("mud_brick", 2.5) == deep and MapMaterials.material("glass", 3.0).normal_enabled == false,
		"relief variants are cached, and plain materials stay smooth")
	var relief_wall := _piece("wall", Vector3.ZERO, Vector3(4, 3, 0.4), 0.0, {"relief": 2.5})
	relief_wall["material"] = "mud_brick"
	var built := MapBuilder.build_piece(relief_wall, MapBuilder.Mode.RUNTIME)
	var mesh := built.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(is_equal_approx((mesh.material_override as StandardMaterial3D).normal_scale, deep.normal_scale),
		"a piece's relief property reaches the built mesh")
	built.free()


	section("Ground textures and uneven ground")
	for id: String in ["dirt", "gravel", "granite_setts", "grass_worn", "flagstones"]:
		var ground := MapMaterials.material(id)
		check(ground != null and ground.normal_enabled and ground.ao_texture != null, "%s is a relief ground texture" % id)
	check(MapMaterials.material("dirt").albedo_texture.get_image().get_data()
		!= MapMaterials.material("gravel").albedo_texture.get_image().get_data(), "dirt and gravel are different surfaces")
	check(PieceCatalog.is_walkable("ground_mounds") and PieceCatalog.kind("ground_mounds") == "surface"
		and PieceCatalog.default_material("ground_mounds") == "dirt", "uneven ground is a walkable dirt surface piece")
	var patch_size := Vector3(10, 0.9, 7)
	var patch_props := MapDocument.default_props("ground_mounds")
	patch_props["seed"] = 4
	var grid := GroundMounds.heights(patch_size, patch_props)
	var values: PackedFloat32Array = grid[2]
	var columns: int = grid[0]
	var rows: int = grid[1]
	var rim_flat := true
	for column: int in columns + 1:
		rim_flat = rim_flat and is_equal_approx(values[column], -GroundMounds.EDGE_SINK) and is_equal_approx(values[rows * (columns + 1) + column], -GroundMounds.EDGE_SINK)
	var highest := 0.0
	for value: float in values:
		highest = maxf(highest, value)
	check(rim_flat, "uneven ground sinks just below the floor at its edges, so no seam shows")
	check(highest > 0.25 and highest <= patch_size.y + 0.001, "mounds rise without exceeding the piece height (%.2f m)" % highest)
	var steep := GroundMounds.heights(Vector3(6, 4, 6), {"feature": 1.0, "seed": 2, "edge": 0.5})
	var mounds := MapBuilder.build_piece(_piece("ground_mounds", Vector3.ZERO, Vector3(6, 4, 6), 0.0, {"feature": 1.0, "seed": 2, "edge": 0.5}), MapBuilder.Mode.RUNTIME)
	var visual := mounds.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var faces := visual.mesh.get_faces()
	var worst := 0.0
	var upward := true
	for i: int in range(0, faces.size(), 3):
		var face_normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		if absf(face_normal.y) > 0.2:
			worst = maxf(worst, rad_to_deg(face_normal.angle_to(Vector3.UP)))
			upward = upward and face_normal.y > 0.0
	check(worst <= GroundMounds.MAX_SLOPE_DEGREES + 0.01 and (steep[2] as PackedFloat32Array).size() > 0,
		"even tall, tight mounds are lowered to a walkable slope (steepest %.1f°)" % worst)
	check(upward, "the ground's faces point up")
	var collider := mounds.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	check((collider.shape as ConcavePolygonShape3D).get_faces() == faces, "uneven ground collides exactly where it is drawn")
	mounds.free()
	var again_grid := GroundMounds.heights(patch_size, patch_props)
	patch_props["seed"] = 5
	check(again_grid[2] == values and GroundMounds.heights(patch_size, patch_props)[2] != values,
		"one seed gives the same ground and another seed different ground")
	var tiny := MapDocument.create("Tiny ground")
	tiny.add_piece(_piece("ground_mounds", Vector3.ZERO, Vector3(0.2, 0.5, 4)))
	check(MapValidator.validate(tiny)["errors"].any(func(e: String) -> bool: return e.contains("uneven ground")),
		"the validator rejects uneven ground too small to form")

	section("Atmosphere")
	var sky_sun := DirectionalLight3D.new()
	var outdoors := Environment.new()
	MapLighting.apply_atmosphere({"haze": 0.5, "sun_color": "ffd8a8"}, sky_sun, outdoors)
	check(sky_sun.shadow_enabled and sky_sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"the sun casts soft split shadows")
	check(outdoors.background_mode == Environment.BG_SKY and outdoors.sky != null and outdoors.ssao_enabled
		and outdoors.sdfgi_enabled and outdoors.fog_enabled, "maps get a sky, occlusion, global illumination and haze")
	MapLighting.apply_atmosphere({"haze": 0.0}, sky_sun, outdoors)
	check(not outdoors.fog_enabled, "haze 0 turns the haze off")
	sky_sun.free()


func _test_snapping() -> void:
	section("Snapping and measuring")
	check(MapSnapping.snap_position(Vector3(1.3, 0.7, -2.6), 0.5) == Vector3(1.5, 0.7, -2.5), "grid snap keeps height")
	check(is_equal_approx(MapSnapping.snap_angle(52.0, 15.0), 45.0) and is_equal_approx(MapSnapping.snap_angle(-10.0, 45.0), 0.0)
		and is_equal_approx(MapSnapping.snap_angle(350.0, 45.0), 0.0), "angle snap rounds to the step and wraps")
	var doc := MapDocument.create("Snap")
	doc.add_piece(_piece("floor", Vector3(0, -0.2, 0), Vector3(20, 0.2, 20)))
	var block := doc.add_piece(_piece("block", Vector3(4, 0, 0), Vector3(2, 2, 2)))
	var none: Array[String] = []
	check(is_equal_approx(MapSnapping.surface_height(doc, 4, 0, none, -5.0), 2.0)
		and is_equal_approx(MapSnapping.surface_height(doc, -4, 0, none, -5.0), 0.0)
		and is_equal_approx(MapSnapping.surface_height(doc, 40, 0, none, -5.0), -5.0),
		"snap-to-surface finds the top of the piece under a point")
	check(is_equal_approx(MapSnapping.surface_height(doc, 4, 0, [block], -5.0), 0.0), "the moved piece itself is ignored")
	var moving := AABB(Vector3(1.2, 0, -1), Vector3(1.6, 1, 2))  # Right face at 2.8, block face at 3.0.
	var offset := MapSnapping.edge_offset(doc, moving, none)
	check(is_equal_approx(offset.x, 0.2), "snap-to-edge closes a 0.2 m gap to the nearest face")
	check(MapSnapping.edge_offset(doc, AABB(Vector3(-8, 0, -1), Vector3(1, 1, 2)), none).x == 0.0, "no edge snap when nothing is near")
	var result := MapSnapping.measure(Vector3(0, 0, 0), Vector3(3, 2, 4))
	check(is_equal_approx(float(result["horizontal"]), 5.0) and is_equal_approx(float(result["height"]), 2.0)
		and is_equal_approx(float(result["distance"]), sqrt(29.0)), "measure reports distance, flat distance and height")
	check(is_equal_approx(float(result["seconds"]), 5.0 / 6.35) and is_equal_approx(float(result["seconds_rifle"]), 5.0 / (6.35 * 0.86)),
		"measure converts the run to seconds at the measured speeds")


func _test_controller_groups() -> void:
	section("Multi-select and group edits (undo/redo)")
	var ctl := MapEditController.new(MapDocument.create("Groups"))
	var a := ctl.add_piece(_piece("crate", Vector3(0, 0, 0)))
	var b := ctl.add_piece(_piece("crate", Vector3(2, 0, 0)))
	var c := ctl.add_piece(_piece("wall", Vector3(1, 0, 4)))
	ctl.select_many([a, b])
	check(ctl.selection == [a, b] and ctl.selected_id == b, "select_many selects several pieces; the last is primary")
	ctl.toggle_selection([c])
	check(ctl.selection.size() == 3, "shift-click adds a piece")
	ctl.toggle_selection([c])
	check(ctl.selection == [a, b], "shift-click on a selected piece removes it")
	ctl.select_many([a, "pc_999", b, a])
	check(ctl.selection == [a, b], "unknown and repeated IDs are dropped")

	check(ctl.move_selection(Vector3(1, 0, 3)) and ctl.document.get_piece(a)["position"] == Vector3(1, 0, 3)
		and ctl.document.get_piece(b)["position"] == Vector3(3, 0, 3), "group move shifts every selected piece")
	ctl.undo()
	check(ctl.document.get_piece(a)["position"] == Vector3.ZERO and ctl.document.get_piece(b)["position"] == Vector3(2, 0, 0),
		"one undo reverts the whole group move")
	ctl.redo()
	check(ctl.document.get_piece(b)["position"] == Vector3(3, 0, 3), "redo reapplies it")
	ctl.undo()

	check(ctl.rotate_selection(90.0, Vector3(1, 0, 0)), "group rotate is applied")
	var pa: Vector3 = ctl.document.get_piece(a)["position"]
	var pb: Vector3 = ctl.document.get_piece(b)["position"]
	check(pa.is_equal_approx(Vector3(1, 0, 1)) and pb.is_equal_approx(Vector3(1, 0, -1))
		and is_equal_approx(float(ctl.document.get_piece(a)["rotation_y"]), 90.0), "group rotate turns positions and yaw around the pivot")
	ctl.undo()
	check((ctl.document.get_piece(a)["position"] as Vector3).is_equal_approx(Vector3.ZERO)
		and is_zero_approx(float(ctl.document.get_piece(a)["rotation_y"])), "undo restores the group rotation")
	ctl.select(c)
	ctl.rotate_selection(45.0)
	check(ctl.document.get_piece(c)["position"] == Vector3(1, 0, 4) and is_equal_approx(float(ctl.document.get_piece(c)["rotation_y"]), 45.0),
		"a single piece rotates in place by any angle")
	ctl.undo()

	ctl.select_many([a, b])
	var copies := ctl.duplicate_selection(Vector3(0, 0, 5))
	check(copies.size() == 2 and ctl.document.pieces.size() == 5 and ctl.selection == copies
		and ctl.document.get_piece(copies[1])["position"] == Vector3(2, 0, 5), "group duplicate copies with an offset and selects the copies")
	ctl.undo()
	check(ctl.document.pieces.size() == 3 and ctl.selection.is_empty(), "one undo removes every copy")
	ctl.redo()
	check(ctl.document.pieces.size() == 5 and ctl.document.index_of(copies[0]) >= 0, "redo brings the copies back with the same IDs")
	ctl.undo()

	ctl.select_many([a, c])
	var order_before: Array[String] = []
	for piece: Dictionary in ctl.document.pieces:
		order_before.append(str(piece["id"]))
	check(ctl.delete_selection() and ctl.document.pieces.size() == 1 and ctl.selection.is_empty(), "group delete removes the selection")
	ctl.undo()
	var order_after: Array[String] = []
	for piece: Dictionary in ctl.document.pieces:
		order_after.append(str(piece["id"]))
	check(order_after == order_before, "undo restores deleted pieces at their original positions in the list")
	ctl.redo()
	check(ctl.document.pieces.size() == 1, "redo deletes them again")
	ctl.undo()

	ctl.select_many([a, b])
	var group := ctl.group_selection()
	check(not group.is_empty() and ctl.document.get_piece(a)["group"] == group and ctl.group_members(b) == [a, b],
		"grouping makes the pieces select as one unit")
	ctl.undo()
	check(ctl.document.get_piece(a)["group"] == "" and ctl.group_members(a) == [a], "undo removes the group")
	ctl.redo()
	ctl.select_many([a, b])
	check(ctl.ungroup_selection() and ctl.document.get_piece(b)["group"] == "", "ungroup clears the group")

	ctl.select_many([a, b, c])
	check(ctl.set_selection_material("sandstone") and ctl.document.get_piece(c)["material"] == "sandstone",
		"a material is applied to the whole selection")
	ctl.undo()
	check(ctl.document.get_piece(c)["material"] == "", "undo restores the materials")

	var before := ctl.selected_pieces()
	ctl.preview_pieces(MapSnapping.moved(before, Vector3(4, 0, 0)))
	ctl.preview_pieces(MapSnapping.moved(before, Vector3(7, 0, 0)))
	ctl.commit_previews(before, "Move")
	check(ctl.document.get_piece(a)["position"] == Vector3(7, 0, 0), "a multi-piece drag ends at the final position")
	ctl.undo()
	check(ctl.document.get_piece(a)["position"] == Vector3.ZERO and ctl.document.get_piece(c)["position"] == Vector3(1, 0, 4),
		"a multi-piece drag is one undo step")
	var probe: WeakRef = weakref(ctl)
	ctl = null
	check(probe.get_ref() == null, "a controller with group history is freed")


func _test_clipboard_and_prefabs() -> void:
	section("Copy/paste between maps and prefabs")
	MapClipboard.clear()
	var first := MapEditController.new(MapDocument.create("Source"))
	var a := first.add_piece(_piece("crate", Vector3(10, 0, 10)))
	var b := first.add_piece(_piece("barrel", Vector3(12, 0, 10)))
	first.select_many([a, b])
	first.group_selection()
	check(MapClipboard.copy(first.selected_pieces()) == 2 and MapClipboard.has_content(), "copy stores the selection")
	var second := MapEditController.new(MapDocument.create("Target"))
	var existing := second.add_piece(_piece("wall", Vector3.ZERO))
	second.select(existing)
	second.group_selection()
	var pasted := second.place_relative(MapClipboard.contents(), Vector3(0, 0, -6), 0.0, "Paste")
	check(pasted.size() == 2 and second.document.pieces.size() == 3, "paste adds the pieces to a different map")
	var p0: Vector3 = second.document.get_piece(pasted[0])["position"]
	var p1: Vector3 = second.document.get_piece(pasted[1])["position"]
	check(p0.is_equal_approx(Vector3(-1, 0, -6)) and p1.is_equal_approx(Vector3(1, 0, -6)), "pasted pieces keep their layout around the paste point")
	var pasted_group := str(second.document.get_piece(pasted[0])["group"])
	check(not pasted_group.is_empty() and pasted_group == second.document.get_piece(pasted[1])["group"]
		and second.group_members(pasted[0]).size() == 2, "a pasted group stays one group with a fresh group ID")
	check(second.selection == pasted, "the pasted pieces are selected")
	second.undo()
	check(second.document.pieces.size() == 1, "paste is one undo step")
	second.redo()
	check(second.document.pieces.size() == 3 and MapClipboard.size() == 2, "redo re-pastes; the clipboard is unchanged")

	second.select_many(pasted)
	var prefab_id := second.save_prefab("Crate and barrel")
	check(prefab_id == "pf_1" and second.document.prefabs.size() == 1 and second.is_dirty(), "the selection is saved as a prefab in the map")
	var placed := second.place_prefab(prefab_id, Vector3(20, 0, 20), 90.0)
	check(placed.size() == 2 and second.group_members(placed[0]).size() == 2, "a prefab is placed as one grouped unit")
	var q0: Vector3 = second.document.get_piece(placed[0])["position"]
	check(absf(q0.x - 20.0) < 0.01 and q0.z > 20.5 and is_equal_approx(float(second.document.get_piece(placed[0])["rotation_y"]), 90.0),
		"a rotated prefab turns around its pivot")
	second.undo()
	check(second.document.index_of(placed[0]) < 0 and second.document.prefabs.size() == 1, "undo removes the placed prefab only")
	var restored := MapDocument.from_json(second.document.to_json())
	check(restored != null and restored.prefab(prefab_id)["name"] == "Crate and barrel", "prefabs are stored as map data")
	check(second.delete_prefab(prefab_id) and second.document.prefabs.is_empty(), "a prefab can be deleted")
	second.undo()
	check(second.document.prefabs.size() == 1, "undo restores the prefab")
	check(MapPrefabs.stock().size() >= 3 and not MapPrefabs.find(second.document, "stock_doorway").is_empty(),
		"stock prefabs (doorway, stair run, crate stack) are available in every map")
	var stock := second.place_prefab("stock_stair_run", Vector3(-20, 0, 0))
	check(stock.size() == 2 and second.document.get_piece(stock[0])["type"] == "stairs_stone", "a stock prefab places catalogue pieces")
	check(second.place_prefab("pf_404", Vector3.ZERO).is_empty(), "an unknown prefab places nothing")


func _test_layers_and_lighting() -> void:
	section("Layers and lighting")
	var ctl := MapEditController.new(_arena("Layers"))
	var layer := ctl.add_layer("Props")
	check(layer == "layer_1" and ctl.document.layers.size() == 2, "a layer is added")
	var crate := ctl.add_piece(_piece("crate", Vector3(2, 0, 2)))
	check(ctl.set_selection_layer(layer) and ctl.document.get_piece(crate)["layer"] == layer, "the selection moves to the layer")
	check(ctl.set_layer_field(layer, "visible", false) and not ctl.document.is_layer_visible(layer), "a layer can be hidden")
	check(ctl.set_layer_field(layer, "locked", true) and ctl.document.is_layer_locked(layer), "a layer can be locked")
	ctl.undo()
	check(not ctl.document.is_layer_locked(layer), "layer edits are undoable")
	var fingerprint := ctl.document.content_fingerprint()
	ctl.set_layer_field(layer, "visible", true)
	check(ctl.document.content_fingerprint() == fingerprint, "layers never change the gameplay content")
	check(ctl.remove_layer(layer) and ctl.document.layers.size() == 1
		and ctl.document.get_piece(crate)["layer"] == MapDocument.DEFAULT_LAYER, "removing a layer moves its pieces to Default")
	ctl.undo()
	check(ctl.document.layers.size() == 2 and ctl.document.get_piece(crate)["layer"] == layer, "undo restores the layer and its pieces")
	check(not ctl.remove_layer(MapDocument.DEFAULT_LAYER) and not ctl.set_selection_layer("layer_77"), "the default layer cannot be removed")

	check(ctl.set_lighting({"sun_yaw": 120.0, "sun_pitch": 30.0, "sun_energy": 2.0, "ambient_energy": 0.4})
		and float(ctl.document.lighting["sun_yaw"]) == 120.0, "lighting is stored in the map")
	ctl.undo()
	check(ctl.document.lighting.is_empty(), "lighting edits are undoable")
	var settings := MapLighting.normalised({"sun_pitch": 400.0, "sun_energy": -3.0, "ambient_color": "not a colour"})
	check(float(settings["sun_pitch"]) == 90.0 and float(settings["sun_energy"]) == 0.0
		and settings["ambient_color"] == MapLighting.DEFAULTS["ambient_color"], "lighting values are clamped")
	var down := MapLighting.sun_direction({"sun_yaw": 0.0, "sun_pitch": 90.0})
	check(down.is_equal_approx(Vector3.DOWN), "a 90° sun shines straight down")
	var sun := DirectionalLight3D.new()
	var environment := Environment.new()
	MapLighting.apply({}, sun, environment)
	check(is_equal_approx(sun.light_energy, 1.0) and environment.ambient_light_source == Environment.AMBIENT_SOURCE_BG,
		"empty lighting leaves the scene defaults alone")
	MapLighting.apply({"sun_yaw": 90.0, "sun_pitch": 40.0, "sun_energy": 1.5, "ambient_energy": 0.3}, sun, environment)
	check(is_equal_approx(sun.rotation_degrees.x, -40.0) and is_equal_approx(sun.rotation_degrees.y, 90.0)
		and is_equal_approx(sun.light_energy, 1.5) and is_equal_approx(environment.ambient_light_energy, 0.3),
		"lighting is applied to the sun and the ambient light")
	sun.free()
	var lamp := MapBuilder.build_piece(_piece("light_lamp", Vector3(0, 3, 0), Vector3.ZERO, 0.0, {"energy": 2.5, "range": 6.0}), MapBuilder.Mode.RUNTIME)
	var spot := MapBuilder.build_piece(_piece("light_spot", Vector3(0, 3, 0)), MapBuilder.Mode.RUNTIME)
	check(lamp.get_node("Light") is OmniLight3D and is_equal_approx((lamp.get_node("Light") as OmniLight3D).omni_range, 6.0)
		and spot.get_node("Light") is SpotLight3D, "placed lights emit in the runtime")
	lamp.free()
	spot.free()


func _test_autosave() -> void:
	section("Autosave files")
	var autosave := MapAutosave.new(TEST_DIR.path_join("autosave"))
	var doc := _arena("Unsaved work")
	check(autosave.write(doc, "user://maps/somewhere.f2fmap.json") == OK and FileAccess.file_exists(autosave.path_for(doc.map_id)),
		"a recovery copy is written")
	var listing := autosave.list()
	check(listing.size() == 1 and listing[0]["map_id"] == doc.map_id and listing[0]["name"] == "Unsaved work", "recovery copies are listed")
	var entry := autosave.read(str(listing[0]["path"]))
	check(not entry.is_empty() and (entry["document"] as MapDocument).pieces.size() == doc.pieces.size()
		and entry["source_path"] == "user://maps/somewhere.f2fmap.json", "a recovery copy restores the document and its source path")
	var broken := FileAccess.open(TEST_DIR.path_join("autosave/broken.autosave.json"), FileAccess.WRITE)
	broken.store_string("{\"format\": \"f2f.map_autosave\", \"format_version\": 9}")
	broken.close()
	check(autosave.read(TEST_DIR.path_join("autosave/broken.autosave.json")).is_empty() and autosave.list().size() == 1,
		"unsupported recovery files are ignored")
	autosave.clear(doc.map_id)
	check(autosave.list().is_empty(), "clearing removes the recovery copy")


func _test_tactical_queries() -> void:
	section("Callout areas, anchors and AI hints")
	var doc := _arena("Tactical")
	var yard := doc.add_piece(_piece("callout", Vector3(-10, 0, -8), Vector3(12, 3, 12), 0.0, {"name": "Yard"}))
	var corner := doc.add_piece(_piece("callout", Vector3(-12, 0, -10), Vector3(4, 3, 4), 0.0, {"name": "Yard Corner", "role": "entrance_a"}))
	var plant := doc.add_piece(_piece("tactical_anchor", Vector3(-10, 0, -8), Vector3.ZERO, 0.0, {"name": "Open plant", "kind": "plant"}))
	doc.add_piece(_piece("tactical_anchor", Vector3(5, 0, 5), Vector3.ZERO, 0.0, {"name": "Smoke", "kind": "utility"}))
	var hold := doc.add_piece(_piece("ai_hold", Vector3(-8, 0, -4), Vector3.ZERO, 180.0, {"site": "A"}))
	doc.add_piece(_piece("ai_cover", Vector3(8, 0, -4), Vector3.ZERO, 0.0, {"site": "B"}))
	check(MapTactical.area_id_at(doc, Vector3(-6, 0, -6)) == yard and MapTactical.area_name_at(doc, Vector3(-6, 0, -6)) == "Yard",
		"a point resolves to its callout area by stable ID")
	check(MapTactical.area_id_at(doc, Vector3(-12, 0, -10)) == corner, "the smallest containing area wins")
	check(MapTactical.area_id_at(doc, Vector3(12, 0, 12)).is_empty() and MapTactical.area_name(doc, yard) == "Yard"
		and MapTactical.area_name(doc, plant).is_empty(), "outside every area there is no area")
	check(MapTactical.areas_with_role(doc, "entrance_a").size() == 1, "areas can carry a timing role")
	check(MapTactical.anchors(doc).size() == 2 and MapTactical.anchors(doc, "plant").size() == 1, "anchors are listed by kind")
	check(MapTactical.anchor_near(doc, Vector3(-10.6, 0, -8.3)).get("id", "") == plant
		and MapTactical.anchor_near(doc, Vector3(-13, 0, -8)).is_empty(), "anchors are snap targets within their radius")
	check(MapTactical.hints(doc, "ai_hold", "A").size() == 1 and MapTactical.hints(doc, "ai_hold", "B").is_empty()
		and MapTactical.hints(doc, "ai_cover").size() == 1, "AI hints are read by type and bombsite")
	var watch := MapTactical.hint_watch_point(doc.get_piece(hold), 10.0)
	check(watch.is_equal_approx(Vector3(-8, 1.5, 6)), "a hold hint watches along its facing")
	var copy := MapDocument.from_json(doc.to_json())
	check(copy != null and copy.get_piece(plant)["props"]["kind"] == "plant" and copy.get_piece(hold)["props"]["site"] == "A",
		"anchors and hints keep their IDs and props through save and load")
	var editor_anchor := MapBuilder.build_piece(doc.get_piece(plant), MapBuilder.Mode.EDITOR)
	var runtime_anchor := MapBuilder.build_piece(doc.get_piece(plant), MapBuilder.Mode.RUNTIME)
	check(editor_anchor.get_child_count() > 0 and runtime_anchor.get_child_count() == 0, "anchors are visible in the editor only")
	editor_anchor.free()
	runtime_anchor.free()
	var rotated_site := _piece("bombsite", Vector3(0, 0, 0), Vector3(10, 3, 2), 45.0, {"site": "C"})
	check(MapZones.contains(rotated_site, Vector3(3, 0, -3)) and not MapZones.contains(rotated_site, Vector3(3, 0, 3)),
		"rotated zones test points against their own orientation")
	doc.add_piece(_piece("callout", Vector3(8, 0, 8), Vector3(4, 3, 4), 0.0, {"name": "yard"}))
	check((MapValidator.validate(doc)["warnings"] as Array).any(func(w: String) -> bool: return w.contains("named")),
		"the validator warns about duplicate area names")


# --- scenes -------------------------------------------------------------------------------------

func _test_collision_matches_visuals() -> void:
	section("Collision matches visuals (every solid catalogue piece)")
	var world := _host()
	var mismatched: Array[String] = []
	var x := 0.0
	for type: String in PieceCatalog.TYPES:
		if not PieceCatalog.is_solid(type):
			continue
		var piece := _piece(type, Vector3(x, 0, 0))
		if type == "drawn_surface":
			piece = PolygonSurface.piece(PackedVector3Array([
				Vector3(x, 0, 0), Vector3(x + 4, 1, 0), Vector3(x + 4, 1, 4), Vector3(x, 0, 4),
			]), 0.2)
		elif type == "mesh_brush":
			piece = BrushGeometry.piece([[x, 0, 0], [x + 4, 0, 0], [x + 4, 2, 4], [x, 2, 4]],
				[0, 1, 2, 0, 2, 3])
		var node := MapBuilder.build_piece(piece, MapBuilder.Mode.RUNTIME)
		world.add_child(node)
		x += 12.0
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		var shapes := node.find_children("*", "CollisionShape3D", true, false)
		var ok := not meshes.is_empty() and not shapes.is_empty()
		if PieceCatalog.kind(type) in ["block", "compound"]:
			ok = ok and meshes.size() == shapes.size()
			for mesh_node: Node in meshes:
				var mesh := (mesh_node as MeshInstance3D).mesh
				var shape := (mesh_node.get_parent().get_node("Collision") as CollisionShape3D).shape
				if mesh is BoxMesh:
					ok = ok and shape is BoxShape3D and (shape as BoxShape3D).size.is_equal_approx((mesh as BoxMesh).size)
				elif mesh is CylinderMesh:
					var cylinder := mesh as CylinderMesh
					if is_equal_approx(cylinder.top_radius, cylinder.bottom_radius):
						ok = ok and shape is CylinderShape3D and is_equal_approx((shape as CylinderShape3D).radius, cylinder.top_radius) \
							and is_equal_approx((shape as CylinderShape3D).height, cylinder.height)
					else:
						ok = ok and shape is ConvexPolygonShape3D and (shape as ConvexPolygonShape3D).points.size() >= 32
				else:
					ok = false
		elif PieceCatalog.kind(type) == "surface" and ok:
			var mesh := (meshes[0] as MeshInstance3D).mesh
			var shape := (shapes[0] as CollisionShape3D).shape as ConcavePolygonShape3D
			ok = shape != null and shape.get_faces() == mesh.get_faces()
		if not ok:
			mismatched.append(type)
	check(mismatched.is_empty(), "each visible part has a collider of the same shape and size (%s)" % ", ".join(mismatched))
	await wait_physics_frames(2)
	var space := world.get_world_3d().direct_space_state
	var door := MapBuilder.build_piece(_piece("doorway", Vector3(0, 0, 40), Vector3(3, 3, 0.4)), MapBuilder.Mode.RUNTIME)
	var stairs := MapBuilder.build_piece(_piece("stairs_stone", Vector3(20, 0, 40), Vector3(3, 1.5, 4)), MapBuilder.Mode.RUNTIME)
	var barrel := MapBuilder.build_piece(_piece("barrel", Vector3(40, 0, 40)), MapBuilder.Mode.RUNTIME)
	var trough := MapBuilder.build_piece(_piece("stone_trough", Vector3(60, 0, 40)), MapBuilder.Mode.RUNTIME)
	var shelf := MapBuilder.build_piece(_piece("market_shelf", Vector3(80, 0, 40)), MapBuilder.Mode.RUNTIME)
	var jar := MapBuilder.build_piece(_piece("pottery_jar", Vector3(100, 0, 40)), MapBuilder.Mode.RUNTIME)
	for node: Node3D in [door, stairs, barrel, trough, shelf, jar]:
		world.add_child(node)
	await wait_physics_frames(2)
	var basin := _ray(space, Vector3(60, 2, 40), Vector3(60, -1, 40))
	var rim := _ray(space, Vector3(60.9, 2, 40), Vector3(60.9, -1, 40))
	check(not basin.is_empty() and not rim.is_empty()
		and is_equal_approx((basin["position"] as Vector3).y, 0.208)
		and is_equal_approx((rim["position"] as Vector3).y, 0.65),
		"the trough has an inset basin and a solid rim")
	check(_ray(space, Vector3(80, 0.72, 42), Vector3(80, 0.72, 38)).is_empty()
		and not _ray(space, Vector3(80, 0.962, 42), Vector3(80, 0.962, 38)).is_empty(),
		"the shelf openings pass rays while a board blocks them")
	check(not _ray(space, Vector3(99.4, 0.423, 40), Vector3(100.6, 0.423, 40)).is_empty()
		and _ray(space, Vector3(100.32, 0.82, 42), Vector3(100.32, 0.82, 38)).is_empty(),
		"the jar has a solid belly and tapered clearance around the neck")
	check(_ray(space, Vector3(0, 1.2, 43), Vector3(0, 1.2, 37)).is_empty(), "a shot passes through the doorway opening")
	check(not _ray(space, Vector3(1.2, 1.2, 43), Vector3(1.2, 1.2, 37)).is_empty()
		and not _ray(space, Vector3(0, 2.7, 43), Vector3(0, 2.7, 37)).is_empty(), "the jamb and the lintel stop a shot")
	check(not _ray(space, Vector3(15, 0.3, 39), Vector3(25, 0.3, 39)).is_empty(), "nothing passes under a stair run from the side")
	var step := _ray(space, Vector3(20, 5, 40), Vector3(20, -5, 40))
	check(not step.is_empty() and absf((step["position"] as Vector3).y - 0.75) < 0.1, "stairs are walked at half height in the middle")
	check(not _ray(space, Vector3(38, 0.5, 40), Vector3(42, 0.5, 40)).is_empty()
		and _ray(space, Vector3(38, 0.5, 40.6), Vector3(42, 0.5, 40.6)).is_empty(), "a barrel collides as a cylinder, not a box")
	world.queue_free()
	await wait_frames(1)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Hitscan.LAYER_WORLD))


func _test_analysis() -> void:
	section("Navigation analysis: reachability, islands, bot-unpathable routes, timings")
	var host := _host()
	var arena := _arena()
	arena.add_piece(_piece("callout", Vector3(0, 0, 0), Vector3(6, 3, 6), 0.0, {"name": "Centre", "role": "mid"}))
	arena.add_piece(_piece("callout", Vector3(-10, 0, -2), Vector3(4, 3, 4), 0.0, {"name": "West Door", "role": "entrance_a"}))
	arena.add_piece(_piece("callout", Vector3(10, 0, -2), Vector3(4, 3, 4), 0.0, {"name": "East Door", "role": "entrance_b"}))
	arena.add_piece(_piece("crate_large", Vector3(6, 0, 6)))
	var clean := MapAnalysis.analyse(arena, host)
	check(clean.polygon_count() > 0 and is_equal_approx(clean.navmesh.agent_radius, NavigationBuilder.AGENT_RADIUS)
		and is_equal_approx(clean.navmesh.agent_max_climb, NavigationBuilder.AGENT_MAX_CLIMB)
		and is_equal_approx(clean.navmesh.agent_height, NavigationBuilder.AGENT_HEIGHT)
		and is_equal_approx(clean.navmesh.agent_max_slope, NavigationBuilder.AGENT_MAX_SLOPE), "the analysis bakes with the bot agent settings")
	check(clean.issues.is_empty(), "a connected arena has no navigation warnings (%s)" % str(clean.issues))
	check(clean.is_reachable(Vector3(-10, 0, -8)) and not clean.is_reachable(Vector3(60, 0, 0)), "reachability is answered per point")
	check(not clean.is_reachable(Vector3(6, 2, 6), 0.5), "a crate top is not reachable (and is not reported as playable floor)")
	check(host.get_child_count() == 0, "the temporary map build is removed after the analysis")
	var straight := clean.path_length(Vector3(0, 0, 12), Vector3(0, 0, -12))
	check(absf(straight - 24.0) < 0.6, "path length matches a straight run (%.2f m)" % straight)

	var to_mid := clean.timing("Centre (mid)", "Attackers from spawn")
	check(not to_mid.is_empty() and absf(float(to_mid["length_min"]) - 12.0) < 0.6, "timing: spawn to mid (%s)" % str(to_mid.get("length_min", "?")))
	check(not to_mid.is_empty() and is_equal_approx(float(to_mid["seconds"]), float(to_mid["length_min"]) / 6.35)
		and is_equal_approx(float(to_mid["seconds_rifle"]), float(to_mid["length_min"]) / (6.35 * 0.86)),
		"timing uses 6.35 m/s and the rifle's 0.86 mobility")
	check(not clean.timing("West Door (entrance A)", "Attackers from spawn").is_empty()
		and not clean.timing("East Door (entrance B)", "Defenders from spawn").is_empty()
		and not clean.timing("Site A", "Defenders from spawn").is_empty(), "timings cover each team to every entrance and site")
	var rotation := clean.timing("Site A ↔ Site B")
	check(not rotation.is_empty() and absf(float(rotation["length_min"]) - 20.0) < 0.8, "timing: rotation between the sites")
	check(not clean.timing("West Door (entrance A) ↔ East Door (entrance B)", "Crossings").is_empty(), "timing: crossing between entrances")
	var text := clean.timing_text()
	check(text.contains("Rotations:") and text.contains("Centre (mid)") and text.contains("AK-47"), "the readout lists every route")
	var overlay := clean.overlay_mesh()
	check(overlay.get_surface_count() == 1 and overlay.surface_get_array_len(0) >= 3, "the navmesh overlay mesh is built from the baked polygons")

	var report := MapAnalysis.full_validation(arena, host)
	check((report["errors"] as Array).is_empty() and str(report["timing_text"]).contains("Site A") and (report["timings"] as Array).size() > 6,
		"validation output includes the route timings")
	var empty_report := MapAnalysis.full_validation(MapDocument.create("Empty"), host)
	check(not (empty_report["errors"] as Array).is_empty() and empty_report["analysis"] == null, "structural errors skip the navigation pass")

	# Site B on a separate slab across a 6 m gap: unreachable objective and an island.
	var split := _arena("Split")
	var floor_piece := split.pieces[0].duplicate(true)
	floor_piece["size"] = Vector3(14, 0.2, 30)
	floor_piece["position"] = Vector3(-8, -0.2, 0)
	split.replace_piece(floor_piece)
	for piece: Dictionary in split.pieces.duplicate(true):
		if PieceCatalog.kind(str(piece["type"])) == "marker" or piece["type"] == "buy_zone":
			piece["position"] = (piece["position"] as Vector3) + Vector3(-8, 0, 0)
			split.replace_piece(piece)
	split.add_piece(_piece("floor", Vector3(10, -0.2, -8), Vector3(8, 0.2, 8)))
	var broken := MapAnalysis.analyse(split, host)
	var objective := broken.issues_with("unreachable_objective")
	check(objective.size() == 2 and str(objective[0]["text"]).contains("bombsite B") and str(objective[0]["text"]).contains("Attacker"),
		"a spawn that cannot reach a bombsite is reported for each team (%s)" % str(objective))
	check(broken.issues_with("island").size() == 1 and not broken.has_issue("bot_unpathable"), "floor nobody can reach is an unreachable island")
	check((MapAnalysis.full_validation(split, host)["warnings"] as Array).any(func(w: String) -> bool: return w.contains("Unreachable floor")),
		"navigation findings appear in the validation warnings")
	check(broken.timing("Site B", "Attackers from spawn")["length_min"] == -1.0 and broken.timing_text().contains("no route"),
		"the timing readout says when there is no route")

	# A 0.6 m platform: people jump onto it, bots cannot path there.
	var ledge := _arena("Ledge")
	ledge.add_piece(_piece("platform", Vector3(10, 0, 8), Vector3(6, 0.6, 6)))
	ledge.add_piece(_piece("callout", Vector3(10, 0.6, 8), Vector3(6, 3, 6), 0.0, {"name": "Stage"}))
	var jump := MapAnalysis.analyse(ledge, host)
	var unpathable := jump.issues_with("bot_unpathable")
	check(unpathable.size() == 1 and str(unpathable[0]["text"]).contains("Stage") and str(unpathable[0]["text"]).contains("0.1 m"),
		"a step that needs a jump is reported as bot-unpathable, by area name (%s)" % str(jump.issues))
	check(not jump.has_issue("island"), "a jump-only platform is not also called an island")
	# The same platform with stairs is fine.
	ledge.add_piece(_piece("stairs_stone", Vector3(10, 0, 13), Vector3(3, 0.6, 4)))
	var fixed := MapAnalysis.analyse(ledge, host)
	check(fixed.issues.is_empty() and fixed.is_reachable(Vector3(10, 0.6, 8)), "adding stairs clears the warning (%s)" % str(fixed.issues))
	var solid_routes := _arena("Solid industrial routes")
	solid_routes.add_piece(_piece("ramp", Vector3(8, 0, 2), Vector3(5, 5, 16)))
	solid_routes.add_piece(_piece("stairs", Vector3(-8, 0, 2), Vector3(5, 5, 12), 180))
	solid_routes.add_piece(_piece("column", Vector3(4, 0, -3), Vector3(3, 4.7, 3)))
	var industrial := MapAnalysis.analyse(solid_routes, host)
	check(industrial.issues.is_empty() and industrial.is_reachable(Vector3(8, 2.5, 2))
		and industrial.is_reachable(Vector3(-8, 2.5, 2)),
		"solid ramps and stairs stay walkable without reporting pockets inside them or a column (%s)" % str(industrial.issues))

	var steep_map := _arena("Steep stair")
	steep_map.add_piece(_piece("stairs_stone", Vector3(10, 0, 6), Vector3(3, 4, 8)))
	var steep := MapAnalysis.analyse(steep_map, host).issues_with("steep_slope")
	check(MapAnalysis.bot_slope_limit() > 20.0 and MapAnalysis.bot_slope_limit() < 26.6 and steep.size() == 1
		and str(steep[0]["text"]).contains("lengthen it to"),
		"a stair steeper than the bots can follow is reported with the length it needs (%s)" % str(steep))

	# A closed six-sided brush standing on the floor: the bake leaves a pocket inside it.
	var brushed := _arena("Brush building")
	var ring: Array = []
	var faces: Array = []
	for level: float in [0.0, 4.0]:
		for i: int in 6:
			var angle := TAU * float(i) / 6.0
			ring.append([10.0 + 3.5 * cos(angle), level, 8.0 + 3.5 * sin(angle)])
	for index: int in [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5]:
		faces.append(index + 6)
	for i: int in 6:
		faces.append_array([i, (i + 1) % 6, (i + 1) % 6 + 6, i, (i + 1) % 6 + 6, i + 6])
	brushed.add_piece(BrushGeometry.piece(ring, faces, true))
	var enclosed := MapAnalysis.analyse(brushed, host)
	check(not enclosed.has_issue("island"),
		"a pocket sealed inside a closed brush is not reported as unreachable floor (%s)" % str(enclosed.issues))
	check(MapAnalysis._inside_brush(Vector3(4, 4, 4), {"vertices": [[0, 0, 0], [1, 0, 0], [0, 0, 1]], "faces": [0, 1, 2]},
		Vector3(0.5, 1, 0.5)) == false, "an open brush sheet encloses nothing")

	var off := _arena("Off mesh")
	off.add_piece(_piece("spawn_attack", Vector3(40, 0, 0)))
	check(MapAnalysis.analyse(off, host).has_issue("spawn_off_navmesh"), "a spawn off the walkable ground is reported")
	host.queue_free()
	await wait_frames(1)


func _test_studio_tools() -> void:
	section("Creation Studio: selection, clipboard, gizmos, snapping, views")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	ui.confirm_dialog.hide()
	studio.set("storage", MapStorage.new(TEST_DIR))
	studio.set("autosave", MapAutosave.new(TEST_DIR.path_join("studio_autosave")))
	studio.set("tactic_storage", TacticStorage.new(TEST_DIR.path_join("tactics")))
	var ctl := studio.get("controller") as MapEditController
	var view := studio.get_node("MapView") as MapEditorView
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var gizmo := studio.get("gizmo") as EditorGizmo

	studio.call("_on_piece_type_selected", "crate")
	var a: String = studio.call("place_at", Vector3(-2, 0, 0))
	var b: String = studio.call("place_at", Vector3(2, 0, 0))
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	await wait_frames(1)
	var screen_a := camera.unproject_position(Vector3(-2, 0.6, 0))
	var screen_b := camera.unproject_position(Vector3(2, 0.6, 0))
	check(studio.call("click_select", screen_a) == a and ctl.selection == [a], "a click selects the piece under the cursor")
	check(studio.call("click_select", screen_b, true) == b and ctl.selection == [a, b], "shift-click adds to the selection")
	studio.call("click_select", screen_b, true)
	check(ctl.selection == [a], "shift-click again removes it")
	check(str(studio.call("click_select", Vector2(4, 4))).is_empty() and ctl.selection.is_empty(), "clicking empty space clears the selection")
	var rect := Rect2(screen_a, Vector2.ZERO).expand(screen_b).grow(30.0)
	check(int(studio.call("box_select", rect)) >= 2 and ctl.is_selected(a) and ctl.is_selected(b), "box select takes every piece inside the rectangle")
	check(int(studio.call("box_select", Rect2(screen_a, Vector2.ZERO).grow(12.0))) == 1 and ctl.selection == [a], "a small box selects one piece")
	check(int(studio.call("box_select", Rect2(screen_b, Vector2.ZERO).grow(12.0), true)) == 2, "shift box select adds to the selection")

	studio.call("_handle_key", _key(KEY_G, true))
	check(not str(ctl.document.get_piece(a)["group"]).is_empty(), "Ctrl+G groups the selection")
	ctl.select("")
	studio.call("click_select", screen_a)
	check(ctl.selection.size() == 2, "clicking one piece of a group selects the group")
	studio.call("click_select", screen_a, false, true)
	check(ctl.selection == [a], "Alt+click selects a single piece of a group")
	ctl.select("")
	studio.call("click_select", screen_a)
	studio.call("_handle_key", _key(KEY_RIGHT))
	check((ctl.document.get_piece(a)["position"] as Vector3).x == -1.0 and (ctl.document.get_piece(b)["position"] as Vector3).x == 3.0,
		"arrow keys nudge the whole selection")
	studio.call("_handle_key", _key(KEY_Z, true))
	check((ctl.document.get_piece(b)["position"] as Vector3).x == 2.0, "Ctrl+Z undoes the group nudge")

	ctl.select_many([a, b])
	studio.call("_handle_key", _key(KEY_C, true))
	var before_paste := ctl.document.pieces.size()
	var pasted: Array[String] = studio.call("paste_at", Vector3(0, 0, -6))
	check(pasted.size() == 2 and ctl.document.pieces.size() == before_paste + 2, "Ctrl+C then paste adds copies at the paste point")
	studio.call("_handle_key", _key(KEY_D, true))
	check(ctl.document.pieces.size() == before_paste + 4 and ctl.selection.size() == 2, "Ctrl+D duplicates the selection")
	studio.call("_handle_key", _key(KEY_DELETE))
	check(ctl.document.pieces.size() == before_paste + 2, "Delete removes the whole selection")
	studio.call("load_template", "blank")
	var in_other_map: Array[String] = studio.call("paste_at", Vector3(4, 0, 4))
	check(in_other_map.size() == 2 and ctl.document.get_piece(in_other_map[0])["type"] == "crate", "the clipboard pastes into another map")
	studio.call("_handle_key", _key(KEY_A, true))
	check(ctl.selection.size() == ctl.document.pieces.size(), "Ctrl+A selects everything")

	section("Creation Studio: gizmos and numeric transform")
	ctl.select("")
	studio.call("_on_piece_type_selected", "wall")
	var wall: String = studio.call("place_at", Vector3(0, 0, -4))
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	ctl.select(wall)
	studio.call("_process", 0.0)
	check(gizmo.visible and gizmo.position.is_equal_approx(Vector3(0, 0, -4)), "the gizmo sits on the selection")
	studio.call("_set_snap", 0.5)
	check(studio.call("gizmo_begin", "x"), "a move drag starts on the X handle")
	studio.call("gizmo_apply", 1.7)
	check((ctl.document.get_piece(wall)["position"] as Vector3).is_equal_approx(Vector3(1.5, 0, -4)), "the move gizmo snaps to the grid size")
	studio.call("gizmo_end")
	studio.call("gizmo_begin", "y")
	studio.call("gizmo_apply", 2.1)
	studio.call("gizmo_end")
	check((ctl.document.get_piece(wall)["position"] as Vector3).is_equal_approx(Vector3(1.5, 2, -4)), "the Y handle moves pieces vertically")
	ctl.undo()
	ctl.undo()
	check((ctl.document.get_piece(wall)["position"] as Vector3).is_equal_approx(Vector3(0, 0, -4)), "each gizmo drag is one undo step")
	studio.call("_handle_key", _key(KEY_T))
	check(gizmo.mode == EditorGizmo.Mode.ROTATE and gizmo.handles() == ["ring"], "T switches to the rotate gizmo")
	studio.call("_on_action", &"angle_snap", 15.0)
	studio.call("gizmo_begin", "ring")
	studio.call("gizmo_apply", 50.0)
	studio.call("gizmo_end")
	check(is_equal_approx(float(ctl.document.get_piece(wall)["rotation_y"]), 45.0), "the rotate gizmo snaps to the angle snap")
	studio.call("_handle_key", _key(KEY_R))
	check(is_equal_approx(float(ctl.document.get_piece(wall)["rotation_y"]), 60.0), "R rotates by the angle snap")
	studio.call("_handle_key", _key(KEY_X))
	studio.call("gizmo_begin", "y")
	studio.call("gizmo_apply", 1.0)
	studio.call("gizmo_end")
	check(is_equal_approx((ctl.document.get_piece(wall)["size"] as Vector3).y, 4.0), "the scale gizmo resizes along its axis")
	studio.call("gizmo_begin", "x")
	studio.call("gizmo_apply", -99.0)
	studio.call("gizmo_end")
	check((ctl.document.get_piece(wall)["size"] as Vector3).x >= MapValidator.MIN_SIZE, "scaling never goes below the minimum size")
	studio.call("gizmo_begin", "z")
	studio.call("gizmo_apply", 3.0)
	studio.call("gizmo_cancel")
	check(is_equal_approx((ctl.document.get_piece(wall)["size"] as Vector3).z, 0.3), "a cancelled gizmo drag changes nothing")
	studio.call("_handle_key", _key(KEY_G))
	var ray_origin := camera.project_ray_origin(camera.unproject_position(gizmo.global_position + Vector3(1.0, 0, 0)))
	var ray_normal := camera.project_ray_normal(camera.unproject_position(gizmo.global_position + Vector3(1.0, 0, 0)))
	check(absf(EditorGizmo.axis_parameter(gizmo.global_position, Vector3.RIGHT, ray_origin, ray_normal) - 1.0) < 0.05,
		"a mouse ray maps to a distance along a gizmo axis")
	studio.call("_process", 0.0)
	check(gizmo.handle_at(camera, camera.unproject_position(gizmo.global_position + Vector3.RIGHT * gizmo.length * 0.6)) == "x",
		"gizmo handles are picked on screen")
	ui.piece_edited.emit(_edited(ctl.document.get_piece(wall), Vector3(3.25, 0, -4), 12.5))
	check((ctl.document.get_piece(wall)["position"] as Vector3).x == 3.25 and is_equal_approx(float(ctl.document.get_piece(wall)["rotation_y"]), 12.5),
		"the inspector's numeric transform sets exact position and rotation")
	studio.call("_on_action", &"material", "plaster_white")
	check(ctl.document.get_piece(wall)["material"] == "plaster_white", "the inspector's material choice is applied")
	var crate_ids: Array[String] = []
	studio.call("_on_piece_type_selected", "crate")
	crate_ids.append(str(studio.call("place_at", Vector3(6, 0, 6))))
	crate_ids.append(str(studio.call("place_at", Vector3(8, 0, 6))))
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	ctl.select_many(crate_ids)
	studio.call("_on_action", &"group_move", Vector3(7, 0, 0))
	check((ctl.document.get_piece(crate_ids[0])["position"] as Vector3).is_equal_approx(Vector3(6, 0, 0)), "the multi-selection panel moves the group numerically")
	studio.call("_on_action", &"group_rotate", 90.0)
	check((ctl.document.get_piece(crate_ids[0])["position"] as Vector3).is_equal_approx(Vector3(7, 0, 1)), "and rotates it around its pivot")

	section("Creation Studio: snapping, measuring, overhead view, layers, prefabs")
	studio.call("load_template", "blank")
	studio.call("_set_snap", 1.0)
	studio.call("_on_piece_type_selected", "block")
	var block: String = studio.call("place_at", Vector3(0, 0, 0))
	var top_screen := camera.unproject_position(Vector3(0, 2, 0))
	var stacked: Variant = studio.call("placement_point", top_screen)
	check(stacked != null and is_equal_approx((stacked as Vector3).y, 2.0), "snap-to-surface places on top of the piece under the cursor")
	studio.call("_on_action", &"snap_surface", false)
	var flat: Variant = studio.call("placement_point", top_screen)
	check(flat != null and is_equal_approx((flat as Vector3).y, 0.0), "with snap-to-surface off the build plane is used")
	studio.call("_on_action", &"snap_surface", true)
	studio.call("_on_piece_type_selected", "crate")
	var crate: String = studio.call("place_at", Vector3(3, 0, 0))
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	ctl.select(crate)
	studio.call("_begin_drag", camera.unproject_position(Vector3(3, 0, 0)))
	var on_block: Vector3 = studio.call("drag_offset", Vector3(-3, 0, 0), top_screen)
	check(is_equal_approx(on_block.y, 2.0), "dragging over another piece lifts the dragged piece onto it")
	studio.call("_on_action", &"snap_edge", true)
	studio.call("_set_snap", 0.125)
	var near_edge: Vector3 = studio.call("drag_offset", Vector3(-1.25, 0, 0))
	check(is_equal_approx(near_edge.x, -1.4), "snap-to-edge pulls the dragged piece flush against its neighbour (%.3f)" % near_edge.x)
	studio.call("_cancel_drag")
	studio.call("_on_action", &"snap_edge", false)
	studio.call("_set_snap", 1.0)

	studio.call("_handle_key", _key(KEY_M))
	check(studio.get("tool") == StudioUI.Tool.MEASURE, "M selects the measuring tool")
	check((studio.call("add_measure_point", Vector3(0, 0, 0)) as Dictionary).is_empty(), "the first click only sets the start")
	var measured: Dictionary = studio.call("add_measure_point", Vector3(6, 2, 8))
	check(is_equal_approx(float(measured["horizontal"]), 10.0) and is_equal_approx(float(measured["height"]), 2.0)
		and view.get_node("MeasureLine").visible, "the second click measures distance and height and draws the line")
	studio.call("_handle_key", _key(KEY_ESCAPE))
	check(studio.get("tool") == StudioUI.Tool.SELECT and not view.get_node("MeasureLine").visible, "leaving the tool clears the measurement")

	var perspective := camera.global_transform
	studio.call("_handle_key", _key(KEY_TAB))
	check(camera.overhead and camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		and camera.global_transform.basis.z.is_equal_approx(Vector3.UP), "Tab switches to an overhead orthographic view")
	check(studio.call("click_select", camera.unproject_position(Vector3(3, 1.2, 0))) == crate, "picking works in the overhead view")
	studio.call("_handle_key", _key(KEY_TAB))
	check(not camera.overhead and camera.projection == Camera3D.PROJECTION_PERSPECTIVE
		and camera.global_transform.is_equal_approx(perspective), "Tab again restores the 3D view")

	studio.call("_on_action", &"layer_add", "Props")
	var layer := str(studio.get("active_layer"))
	check(layer != MapDocument.DEFAULT_LAYER and ctl.document.layers.size() == 2, "a new layer becomes the active layer")
	studio.call("_on_piece_type_selected", "barrel")
	var barrel: String = studio.call("place_at", Vector3(-4, 0, 4))
	studio.call("_set_tool", StudioUI.Tool.SELECT)
	check(ctl.document.get_piece(barrel)["layer"] == layer, "new pieces go to the active layer")
	studio.call("_on_action", &"layer_visible", [layer, false])
	await wait_frames(1)
	check(not view.node_for(barrel).visible and view.node_for(block).visible, "hiding a layer hides its pieces in the editor")
	check(str(studio.call("click_select", camera.unproject_position(Vector3(-4, 0.5, 4)))) != barrel, "hidden pieces cannot be picked")
	var runtime := MapBuilder.build(ctl.document, MapBuilder.Mode.RUNTIME)
	check(runtime.get_node(barrel) != null and (runtime.get_node(barrel) as Node3D).visible, "hidden layers are still built for play")
	runtime.free()
	studio.call("_on_action", &"layer_visible", [layer, true])
	studio.call("_on_action", &"layer_locked", [layer, true])
	check(str(studio.call("click_select", camera.unproject_position(Vector3(-4, 0.5, 4)))) != barrel and view.node_for(barrel).visible,
		"locked pieces stay visible but cannot be picked")
	studio.call("_on_action", &"layer_locked", [layer, false])

	ctl.select_many([block, crate])
	studio.call("_on_action", &"prefab_save", "Block and crate")
	check(ctl.document.prefabs.size() == 1, "Save selection as prefab stores it in the map")
	check(studio.call("select_prefab", "pf_1") and studio.get("tool") == StudioUI.Tool.PLACE, "choosing a prefab arms the place tool")
	var count := ctl.document.pieces.size()
	var first: String = studio.call("place_at", Vector3(-10, 0, -10))
	check(ctl.document.pieces.size() == count + 2 and ctl.group_members(first).size() == 2, "a click places the prefab as one unit")
	ctl.undo()
	ctl.undo()
	check(ctl.document.pieces.size() == count, "placing a prefab is undoable")
	studio.call("_set_tool", StudioUI.Tool.SELECT)

	section("Creation Studio: lighting, navmesh overlay, validation, autosave")
	var sun := studio.get_node("Sun") as DirectionalLight3D
	var default_rotation := sun.rotation_degrees
	studio.call("_on_action", &"lighting", {"sun_yaw": 100.0, "sun_pitch": 35.0, "sun_energy": 1.4, "ambient_energy": 0.5})
	check(is_equal_approx(sun.rotation_degrees.y, 100.0) and is_equal_approx(sun.light_energy, 1.4), "lighting edits show in the editor")
	ctl.undo()
	check(sun.rotation_degrees.is_equal_approx(default_rotation), "undoing lighting restores the default sun")
	studio.call("_on_piece_type_selected", "light_lamp")
	var lamp: String = studio.call("place_at", Vector3(2, 0, 6))
	check(is_equal_approx((ctl.document.get_piece(lamp)["position"] as Vector3).y, 2.4) and view.node_for(lamp).get_node("Light") is OmniLight3D,
		"a placed lamp is raised above the floor and lights the editor view")
	studio.call("_set_tool", StudioUI.Tool.SELECT)

	var analysis := studio.call("refresh_navmesh") as MapAnalysis
	check(analysis != null and analysis.polygon_count() > 0 and view.has_overlay(), "Refresh navmesh bakes and shows the overlay")
	studio.call("_on_action", &"navmesh", false)
	check(not view.has_overlay(), "the overlay can be hidden")
	var report: Dictionary = studio.call("validation_report")
	check(report.has("timing_text") and report.has("tactic_warnings") and (report["errors"] as Array).is_empty(),
		"validation in the studio includes timings and tactic warnings")
	check(str(studio.call("show_timings")).length() > 0 and ui.message_dialog.visible, "the Timings button shows the readout")
	ui.message_dialog.hide()

	check(ctl.is_dirty() and bool(studio.call("autosave_now")), "unsaved work is autosaved")
	var autosave := studio.get("autosave") as MapAutosave
	var recovery := autosave.list()
	var piece_count := ctl.document.pieces.size()
	var map_id := ctl.document.map_id
	check(recovery.size() == 1 and recovery[0]["map_id"] == map_id, "the recovery copy is listed")
	studio.call("load_template", "blank")
	check(bool(studio.call("recover_autosave", str(recovery[0]["path"]))) and ctl.document.map_id == map_id
		and ctl.document.pieces.size() == piece_count and ctl.is_dirty(), "recovery restores the unsaved map and keeps it unsaved")
	check(int(studio.call("save_map")) == OK and autosave.list().is_empty() and not bool(studio.call("autosave_now")),
		"saving removes the recovery copy; a clean map is not autosaved")
	ui.message_dialog.hide()
	await despawn(studio)

	section("Creation Studio: recovery offer and official maps")
	studio = spawn_scene(STUDIO)
	await wait_frames(2)
	ui = studio.get_node("UI/StudioUI") as StudioUI
	ui.confirm_dialog.hide()
	studio.set("storage", MapStorage.new(TEST_DIR))
	studio.set("autosave", MapAutosave.new(TEST_DIR.path_join("studio_autosave")))
	ctl = studio.get("controller") as MapEditController
	studio.call("_on_piece_type_selected", "crate")
	studio.call("place_at", Vector3(1, 0, 1))
	studio.call("autosave_now")
	studio.call("_offer_recovery")
	check(ui.confirm_dialog.visible and ui.confirm_dialog.dialog_text.contains("Recover"), "opening the studio offers to recover autosaved work")
	ui.confirm_dialog.hide()
	(studio.get("autosave") as MapAutosave).clear(ctl.document.map_id)
	ctl.mark_saved()
	check(bool(studio.call("load_official", OfficialMaps.DEFAULT_ID)) and bool(studio.get("official_source")), "an official map opens in the studio")
	check(int(studio.call("save_map")) == OK and not OfficialMaps.is_official(ctl.document.map_id)
		and ctl.document.name.ends_with("(copy)") and not bool(studio.get("official_source")),
		"saving an official map creates the player's own copy with a new ID")
	ui.message_dialog.hide()
	await despawn(studio)


func _test_draw_tools() -> void:
	section("Creation Studio: draw geometry")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var ghost := studio.get_node("Ghost") as Node3D
	var ctl := studio.get("controller") as MapEditController
	studio.set("storage", MapStorage.new(TEST_DIR.path_join("draw")))
	studio.set("snap_surface", false)
	studio.set("build_level", 2.0)
	studio.call("_set_snap", 0.5)
	studio.call("set_overhead", true)
	var start := camera.unproject_position(Vector3(-3.48, 2.0, 2.04))
	var end := camera.unproject_position(Vector3(4.13, 2.0, -2.88))
	var base_count := ctl.document.pieces.size()
	var layer := ctl.add_layer("Drawn geometry")
	studio.set("active_layer", layer)
	ui.tool_selected.emit(StudioUI.Tool.DRAW_FLOOR)
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = start
	studio.call("_on_left_press", press)
	studio.call("_preview_draw", end)
	var draw_mesh := studio.get("_draw_box") as MeshInstance3D
	check(ghost.visible and draw_mesh.visible and (draw_mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(7.5, 0.2, 5.0))
		and ctl.document.pieces.size() == base_count, "dragging previews the exact snapped footprint before committing")
	studio.call("_finish_draw", end)
	var floor_id := ctl.selected_id
	var floor := ctl.document.get_piece(floor_id)
	check(floor.get("type") == "floor" and floor.get("layer") == layer
		and (floor.get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.25, 1.8, -0.5))
		and not ghost.visible, "the new floor finishes flush with the draw plane on the active layer")
	check(ctl.undo() and ctl.document.pieces.size() == base_count and ctl.redo()
		and ctl.document.get_piece(floor_id) == floor, "one undo and redo remove and restore the entire stroke")

	studio.call("_handle_key", _key(KEY_4))
	var draw_heights := ui.get("_draw_heights") as Dictionary
	(draw_heights[StudioUI.Tool.DRAW_WALL] as SpinBox).value = 4.0
	(ui.get("_wall_thickness") as SpinBox).value = 0.5
	studio.call("_begin_draw", camera.unproject_position(Vector3(0, 2, 0)))
	studio.call("_finish_draw", camera.unproject_position(Vector3(3, 2, -4)))
	var wall_id := ctl.selected_id
	var wall := ctl.document.get_piece(wall_id)
	var wall_size := wall.get("size", Vector3.ZERO) as Vector3
	var wall_direction := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(float(wall.get("rotation_y", 0.0))))
	check(wall.get("type") == "wall" and wall_size.is_equal_approx(Vector3(5.0, 4.0, 0.5))
		and wall_direction.distance_to(Vector3(0.6, 0.0, -0.8)) < 0.0001,
		"diagonal walls follow both endpoints and use the configured height and depth")

	studio.call("_handle_key", _key(KEY_5))
	studio.call("_begin_draw", start)
	studio.call("_finish_draw", start)
	check(ctl.document.pieces.size() == base_count + 2, "a click without a footprint creates no block")
	studio.call("_begin_draw", start)
	studio.call("_handle_key", _key(KEY_ESCAPE))
	studio.call("_finish_draw", end)
	check(ctl.document.pieces.size() == base_count + 2 and studio.get("tool") == StudioUI.Tool.DRAW_BLOCK,
		"Escape cancels the stroke and keeps the drawing tool armed")
	ctl.set_layer_field(layer, "locked", true)
	studio.call("_begin_draw", start)
	studio.call("_finish_draw", end)
	check(ctl.document.pieces.size() == base_count + 2, "drawing respects a locked layer")
	ctl.set_layer_field(layer, "locked", false)
	studio.call("_begin_draw", start)
	studio.call("_finish_draw", end)
	var block := ctl.selected_piece()
	check(block.get("type") == "block" and is_equal_approx((block.get("position", Vector3.ZERO) as Vector3).y, 2.0),
		"a solid block rises from the drawing plane")

	var saved := int(studio.call("save_map")) == OK
	var storage := studio.get("storage") as MapStorage
	var reopened := storage.load_path(str(studio.get("current_path")))
	check(saved and reopened != null and reopened.get_piece(floor_id) == floor and reopened.get_piece(wall_id) == wall,
		"drawn pieces save as ordinary map geometry and reopen with the same dimensions")
	if reopened != null:
		var runtime_wall := MapBuilder.build_piece(reopened.get_piece(wall_id), MapBuilder.Mode.RUNTIME)
		var shape_node := runtime_wall.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
		check((shape_node.shape as BoxShape3D).size.is_equal_approx(wall_size),
			"the FPS runtime builds matching solid collision for a drawn wall")
		runtime_wall.free()
	await despawn(studio)


func _test_snap_placement() -> void:
	section("Creation Studio: snap marker and floor levels")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ctl := studio.get("controller") as MapEditController
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	var cursor := studio.get_node("Cursor") as MeshInstance3D
	var ghost := studio.get_node("Ghost") as Node3D
	var doc := MapDocument.create("Snap placement")
	doc.add_piece(_piece("block", Vector3.ZERO, Vector3(1.4, 2.0, 1.4)))
	ctl.set_document(doc)
	studio.call("set_overhead", true)
	studio.call("_set_snap", 1.0)
	var surface := camera.unproject_position(Vector3(0.1, 2.0, -0.1))
	var edge := camera.unproject_position(Vector3(0.63, 2.0, 0.0))
	var hover: Variant = studio.call("_cursor_anchor", surface)
	studio.call("_update_snap_marker", hover)
	check(hover == Vector3(0.0, 2.0, 0.0) and cursor.mesh is ImmediateMesh
		and is_zero_approx(cursor.position.x) and is_zero_approx(cursor.position.z),
		"the marker is centred on the exact snapped grid intersection")
	check(studio.call("placement_point", edge) == Vector3(1.0, 0.0, 0.0),
		"a snapped point outside the clicked surface falls back to the grid height")

	ui.tool_selected.emit(StudioUI.Tool.DRAW_FLOOR)
	studio.call("_begin_draw", surface)
	var far := camera.unproject_position(Vector3(3.0, 0.0, -4.0))
	var endpoint: Variant = studio.call("_cursor_anchor", far)
	var drawn := studio.call("_draw_piece_at", far) as Dictionary
	var drawn_box := MapDocument.piece_aabb(drawn)
	check(endpoint == Vector3(3.0, 2.0, -4.0)
		and studio.call("placement_point", far) == Vector3(3.0, 0.0, -4.0)
		and is_equal_approx(drawn_box.end.y, 2.0),
		"the drag marker and drawn floor stay on the same starting elevation")
	studio.call("_finish_draw", far)

	var all_slabs_flush := true
	var anchor := Vector3(8.0, 4.0, -8.0)
	for type: String in ["floor", "floor_sand", "floor_paved", "floor_tile", "floor_planks"]:
		ui.piece_type_selected.emit(type)
		studio.call("_update_place_ghost", anchor)
		var id: String = studio.call("place_at", anchor)
		var slab := MapDocument.piece_aabb(ctl.document.get_piece(id))
		var preview := studio.get("_place_preview") as Node3D
		var mesh := preview.get_child(0) as MeshInstance3D
		# Measure the actual mesh at the snapped base, excluding the render-only lift.
		var preview_top := ghost.position.y + mesh.position.y + mesh.get_aabb().end.y
		all_slabs_flush = all_slabs_flush and is_equal_approx(slab.end.y, anchor.y) \
			and is_equal_approx(preview_top, slab.end.y)
	check(all_slabs_flush, "every palette floor has the same flush surface as its preview and the draw tool")

	ui.piece_type_selected.emit("platform")
	var platform: String = studio.call("place_at", anchor)
	check(is_equal_approx(MapDocument.piece_aabb(ctl.document.get_piece(platform)).position.y, anchor.y),
		"raised platforms place by their base")
	var view := studio.get_node("MapView") as MapEditorView
	var doorway := ctl.add_piece(_piece("doorway", Vector3(18, 5, 3), Vector3(8, 4, 0.6), 90,
		{"opening_width": 5.0, "opening_height": 3.0}))
	var equipment := ctl.add_piece(_piece("block", Vector3(14, 5, 3)))
	check(view.pick(Vector3(22, 6, 3), Vector3.LEFT).get("piece_id") == equipment
		and view.pick(Vector3(22, 6, 6), Vector3.LEFT).get("piece_id") == doorway,
		"picking through a raised, rotated doorway reaches the equipment, and its frame is selectable")
	await despawn(studio)


func _test_lower_floor_snap() -> void:
	section("Creation Studio: stacked floors and sloped placement")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ctl := studio.get("controller") as MapEditController
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var view := studio.get_node("MapView") as MapEditorView
	ctl.set_document(MapDocument.create("Lower floor snap"))
	ctl.add_piece(_piece("ramp", Vector3(4, -4, -4), Vector3(4, 4, 8)))
	var upper_layer := ctl.add_layer("Upper slab")
	var slab := _piece("floor", Vector3(4, 1.8, -4), Vector3(6, 0.2, 10))
	slab["layer"] = upper_layer
	ctl.add_piece(slab)
	studio.call("set_overhead", true)
	studio.call("_set_snap", 1.0)
	var cursor := camera.unproject_position(Vector3(4.2, -2.2, -3.6))
	var upper: Variant = studio.call("placement_point", cursor)
	check(upper is Vector3 and (upper as Vector3).is_equal_approx(Vector3(4, 2, -4)),
		"the visible upper slab takes precedence (%s)" % str(upper))
	ctl.set_layer_field(upper_layer, "visible", false)
	var lower: Variant = studio.call("placement_point", cursor)
	check(lower is Vector3 and (lower as Vector3).is_equal_approx(Vector3(4, -2, -4)),
		"hiding the upper layer snaps to the lower ramp at the snapped X/Z (%s)" % str(lower))
	check(view.pick(Vector3(1, -1, -3.6), Vector3.RIGHT).is_empty(), "the empty space above a ramp does not intercept selection")
	studio.call("_on_piece_type_selected", "crate")
	var crate := str(studio.call("place_at", lower))
	check((ctl.document.get_piece(crate)["position"] as Vector3).is_equal_approx(Vector3(4, -2, -4)),
		"placing a crate uses the same ramp height as the cursor")

	ctl.add_piece(PolygonSurface.piece(PackedVector3Array([
		Vector3(14, -4, 0), Vector3(18, -2, 0), Vector3(18, -2, 1.75),
		Vector3(16, -3, 1.75), Vector3(16, -3, 4), Vector3(14, -4, 4),
	]), 0.2))
	var on_surface: Variant = view.surface_anchor(Vector3(17.2, 4, 1.1), Vector3.DOWN, 1.0)
	check(on_surface is Vector3 and (on_surface as Vector3).is_equal_approx(Vector3(17, -2.5, 1)),
		"a drawn slope also uses the height at the snapped grid intersection (%s)" % str(on_surface))
	check(view.surface_anchor(Vector3(17.2, 4, 1.67), Vector3.DOWN, 1.0) == null,
		"grid snapping never places a piece in a notch in a drawn surface")
	check(view.surface_anchor(Vector3(17, -4, 1), Vector3.UP, 1.0) == null,
		"a covered passage ceiling is not treated as a floor when picked from below")
	ctl.add_piece(_piece("stairs", Vector3(24, -4, 0.2), Vector3(4, 4, 8)))
	var tread: Variant = view.surface_anchor(Vector3(24.2, 4, 0.47), Vector3.DOWN, 1.0)
	check(tread is Vector3 and (tread as Vector3).is_equal_approx(Vector3(24, -1.75, 0)),
		"snapping across a riser uses the destination tread height (%s)" % str(tread))
	await despawn(studio)


func _test_geometry_palette_and_textures() -> void:
	section("Creation Studio: geometry palette and post-placement textures")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	var ctl := studio.get("controller") as MapEditController
	var view := studio.get_node("MapView") as MapEditorView
	var palette := ui.get("_palette_buttons") as Dictionary
	var variants_hidden := true
	for type: String in PieceCatalog.MATERIAL_VARIANTS:
		variants_hidden = variants_hidden and not palette.has(type) and PieceCatalog.has_type(type)
	check(variants_hidden and palette.has("floor") and palette.has("wall") and palette.has("ramp")
		and palette.has("stairs") and palette.has("wall_window") and palette.has("wall_half"),
		"the palette offers canonical shapes and retains distinct pieces and size presets")

	(palette["floor"] as Button).pressed.emit()
	var floor_id: String = studio.call("place_at", Vector3(2, 0, 2))
	(palette["wall"] as Button).pressed.emit()
	var wall_id: String = studio.call("place_at", Vector3(2, 0, 4))
	ctl.select(floor_id)
	var option := ui.find_child("TextureChoice", true, false) as OptionButton
	var paving := MapMaterials.ids().find("stone_paving") + 1
	check(option != null and option.get_item_metadata(paving) == "stone_paving"
		and option.get_item_icon(paving) == MapMaterials.swatch("stone_paving"),
		"the placed Floor offers a finish picker with texture swatches")
	if option == null:
		await despawn(studio)
		return
	var fingerprint := ctl.document.content_fingerprint()
	option.item_selected.emit(paving)
	var floor_mesh := view.node_for(floor_id).get_node("Body/Mesh") as MeshInstance3D
	check(ctl.document.get_piece(floor_id).get("material") == "stone_paving"
		and floor_mesh.material_override == MapMaterials.material("stone_paving")
		and option.selected == paving and ctl.document.content_fingerprint() == fingerprint,
		"changing texture updates the placed floor without changing gameplay geometry")

	ctl.select_many([floor_id, wall_id])
	option = ui.find_child("TextureChoice", true, false) as OptionButton
	check(option.get_item_text(option.selected) == "Mixed textures", "the picker shows when selected pieces have different finishes")
	var plaster := MapMaterials.ids().find("plaster_white") + 1
	option.item_selected.emit(plaster)
	check(ctl.document.get_piece(floor_id).get("material") == "plaster_white"
		and ctl.document.get_piece(wall_id).get("material") == "plaster_white" and option.selected == plaster,
		"one texture choice updates both placed pieces")
	check(ctl.undo() and ctl.document.get_piece(floor_id).get("material") == "stone_paving"
		and ctl.document.get_piece(wall_id).get("material") == ""
		and option.get_item_text(option.selected) == "Mixed textures",
		"undo restores both previous textures and the picker reflects the difference")
	check(ctl.redo() and option.selected == plaster, "redo restores the applied texture in the picker")

	var legacy := ctl.add_piece(_piece("floor_tile", Vector3(10, -0.2, 0)))
	var reopened := ctl.document.duplicate_document()
	var legacy_node := MapBuilder.build_piece(reopened.get_piece(legacy), MapBuilder.Mode.RUNTIME)
	var legacy_mesh := legacy_node.get_node("Body/Mesh") as MeshInstance3D
	check(reopened.get_piece(legacy).get("type") == "floor_tile"
		and legacy_mesh.material_override == MapMaterials.material("tile_terracotta")
		and reopened.get_piece(floor_id).get("material") == "plaster_white",
		"new finishes round trip and older floor types keep their original appearance")
	legacy_node.free()
	await despawn(studio)


func _edited(piece: Dictionary, position: Vector3, rotation: float) -> Dictionary:
	piece["position"] = position
	piece["rotation_y"] = rotation
	return piece


func _test_tactic_compatibility() -> void:
	section("Tactic compatibility after map edits")
	var maps := MapStorage.new(TEST_DIR)
	var tactics := TacticStorage.new(TEST_DIR.path_join("tactics"))
	var map := _arena("Compat map")
	var area := map.add_piece(_piece("callout", Vector3(-10, 0, -8), Vector3(8, 3, 8), 0.0, {"name": "Yard"}))
	var anchor := map.add_piece(_piece("tactical_anchor", Vector3(-10, 0, -8), Vector3.ZERO, 0.0, {"name": "Plant", "kind": "plant"}))
	check(maps.save(map) == OK, "the test map is saved")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	ui.confirm_dialog.hide()
	studio.set("storage", maps)
	studio.set("autosave", MapAutosave.new(TEST_DIR.path_join("studio_autosave")))
	studio.set("tactic_storage", tactics)
	check(bool(studio.call("load_map", maps.path_for(map.map_id))) and bool(studio.call("open_tactic_editor")), "the Tactical Play Creator opens on the saved map")
	var editor := studio.get("tactic_editor") as TacticEditor
	for i: int in TacticDocument.SLOT_COUNT:
		editor.selected_slot = i
		editor.edit_mode = TacticEditor.EditMode.SET_START
		editor.apply_point(Vector3(-4.0 + i * 2.0, 0, 11))
	editor.selected_slot = 0
	editor.edit_mode = TacticEditor.EditMode.ADD_WAYPOINT
	check(editor.apply_point(Vector3(10, 0, 6)).is_empty() and editor.apply_point(Vector3(-10.4, 0, -8.3)).is_empty(), "waypoints are added")
	var slot := editor.document.slots[0]
	check(slot.route[1].is_equal_approx(Vector3(-10, 0, -8)) and slot.anchor_of(1) == anchor,
		"a click near a tactical anchor snaps to it and records the anchor ID")
	check(slot.area_of(1) == area and slot.area_of(0).is_empty(), "waypoints record their callout area by ID, not by coordinates")
	editor.snap_to_anchors = false
	editor.selected_slot = 1
	editor.apply_point(Vector3(-10.4, 0, -8.3))
	check(editor.document.slots[1].route[0].is_equal_approx(Vector3(-10.4, 0, -8.3)) and editor.document.slots[1].anchor_of(0).is_empty(),
		"anchor snapping can be switched off")
	editor.document.display_name = "Yard take"
	check(editor.save_tactic().is_empty() and editor.document.map_content_version == 1, "the tactic is saved against content version 1")
	var path := tactics.path_for(editor.document.tactic_id)
	var raw := FileAccess.get_file_as_string(path)
	var stored := JSON.parse_string(raw) as Dictionary
	check(int(stored["format_version"]) == 2 and stored["players"][0]["waypoint_refs"][1]["anchor"] == anchor
		and stored["players"][0]["waypoint_refs"][1]["area"] == area, "format version 2 stores the area and anchor references")
	check(TacticCompatibility.scan(tactics, map, MapAnalysis.analyse(map, studio)).is_empty(), "an unchanged map reports no tactic problems")
	studio.call("close_tactic_editor")

	# Edit the map in the studio: remove the anchor, shrink the area, and cut off waypoint 1.
	var ctl := studio.get("controller") as MapEditController
	ctl.delete_piece(anchor)
	var shrunk := ctl.document.get_piece(area)
	shrunk["size"] = Vector3(2, 3, 2)
	shrunk["position"] = Vector3(-13, 0, -11)
	ctl.update_piece(shrunk)
	ctl.add_piece(_piece("building", Vector3(10, 0, 6), Vector3(6, 4, 6)))
	var hash_before := FileAccess.get_sha256(path)
	check(int(studio.call("save_map")) == OK and ctl.document.content_version == 2, "saving the edit raises the map content version")
	var issues: Array[Dictionary] = studio.get("tactic_issues")
	var codes: Array[String] = []
	for issue: Dictionary in issues:
		codes.append("%s:%d:%d" % [issue["code"], int(issue["slot"]), int(issue["step"])])
	check(codes.has("anchor_missing:1:2") and codes.has("area_left:1:2") and codes.has("unreachable:1:1"),
		"the editor reports the removed anchor, the area and the unreachable waypoint (%s)" % ", ".join(codes))
	check(ui.message_dialog.visible and ui.message_dialog.dialog_text.contains("Tactic \"Yard take\": player 1 step 1")
		and ui.message_dialog.dialog_text.contains("player 1 step 2"), "the warning names the tactic and the step")
	ui.message_dialog.hide()
	check(FileAccess.get_sha256(path) == hash_before, "the tactic file is not changed by the map edit")
	var report: Dictionary = studio.call("validation_report")
	check((report["tactic_warnings"] as Array).size() == issues.size(), "Validate lists the same tactic warnings")

	ctl.delete_piece(area)
	check(int(studio.call("save_map")) == OK, "a second edit is saved")
	ui.message_dialog.hide()
	check((studio.get("tactic_issues") as Array).any(func(issue: Dictionary) -> bool: return issue["code"] == "area_missing"),
		"removing a callout area a tactic uses is reported")
	check(FileAccess.get_sha256(path) == hash_before, "the tactic file is still untouched")

	check(bool(studio.call("open_tactic_editor")), "the Tactical Play Creator reopens on the edited map")
	editor = studio.get("tactic_editor") as TacticEditor
	check(editor.load_tactic(path).is_empty() and editor.document.display_name == "Yard take", "a tactic for an older map version still opens")
	var joined := "\n".join(editor.compatibility_warnings)
	check(joined.contains("map has changed") and joined.contains("player 1 step 1") and joined.contains("no longer exists")
		and joined.contains("reach"), "the Tactical Play Creator warns and names each broken step")
	check(FileAccess.get_sha256(path) == hash_before, "opening the tactic does not rewrite it")
	editor.selected_slot = 0
	editor.selected_point = 1
	editor.edit_mode = TacticEditor.EditMode.MOVE_POINT
	editor.apply_point(Vector3(4, 0, 0))
	editor.selected_point = 2
	editor.apply_point(Vector3(-10, 0, -8))
	editor.selected_slot = 1
	editor.selected_point = 1
	editor.apply_point(Vector3(-10.4, 0, -8.3))
	check(editor.save_tactic().is_empty() and FileAccess.get_sha256(path) != hash_before
		and editor.document.map_content_version == ctl.document.content_version, "saving in the creator is what updates the tactic")
	check(TacticCompatibility.scan(tactics, ctl.document, MapAnalysis.analyse(ctl.document, studio)).is_empty(), "the repaired tactic is compatible again")

	var other := _arena("Other map")
	check(str(tactics.load_path(path, other)["error"]).contains("different map"), "a tactic is still refused on a different map")
	var v1 := stored.duplicate(true)
	v1["format_version"] = 1
	v1.erase("map_content_version")
	for player: Dictionary in v1["players"]:
		player.erase("waypoint_refs")
		player.erase("start_area")
		player.erase("start_anchor")
	var migrated := TacticDocument.from_dict(v1)
	check(migrated != null and migrated.map_content_version == 0 and migrated.slots[0].route.size() == 2
		and migrated.slots[0].area_of(1).is_empty(), "a version 1 tactic loads with no references and an unknown content version")
	check(migrated != null and int(migrated.to_dict()["format_version"]) == 2, "a migrated tactic saves as version 2")
	await despawn(studio)


func _test_playtest_options() -> void:
	section("Playtest as either team, from any spawn")
	App.go_to(App.SCENE_CREATION_STUDIO)
	await wait_frames(3)
	var studio := tree.current_scene
	(studio.get_node("UI/StudioUI") as StudioUI).confirm_dialog.hide()
	var ctl := studio.get("controller") as MapEditController
	var doc := _arena("Spawn test")
	doc.add_piece(_piece("spawn_attack", Vector3(6, 0, 12)))
	doc.add_piece(_piece("spawn_defence", Vector3(-6, 0, -12), Vector3.ZERO, 180.0))
	doc.add_piece(_piece("callout", Vector3(-6, 0, -12), Vector3(4, 3, 4), 0.0, {"name": "Back Gate"}))
	ctl.set_document(doc)
	studio.call("_on_action", &"playtest_team", "defence")
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	check(ui.spawn_option.item_count == 2, "the spawn list follows the chosen team")
	studio.call("_on_action", &"playtest_spawn", 1)
	check(bool(studio.call("playtest")) and App.playtest_options == {"team": "defence", "spawn": 1}, "playtest carries the team and spawn")
	await wait_frames(3)
	var runtime := tree.current_scene
	var player := runtime.get_node("Player") as FirstPersonController
	check(player.global_position.distance_to(Vector3(-6, 0, -12)) < 0.5, "the player starts at the chosen defender spawn")
	await wait_frames(2)
	check((runtime.get_node("Hud") as SandboxHud).location_text() == "Back Gate", "the playtest HUD names the callout area the player is in")
	App.end_playtest()
	await wait_frames(3)
	var back := tree.current_scene
	(back.get_node("UI/StudioUI") as StudioUI).confirm_dialog.hide()
	check(str(back.get("playtest_team")) == "defence" and int(back.get("playtest_spawn")) == 1, "the editor remembers the playtest choice")
	check(bool(back.call("playtest", "attack", 1)), "playtest can be started as the other team")
	await wait_frames(3)
	player = tree.current_scene.get_node("Player") as FirstPersonController
	check(player.global_position.distance_to(Vector3(6, 0, 12)) < 0.5, "the player starts at the chosen attacker spawn")
	App.end_playtest()
	await wait_frames(3)
	(tree.current_scene.get("controller") as MapEditController).mark_saved()
	App.playtest_options = {}
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)


func _test_draw_navmesh_bot_playtest() -> void:
	section("Draw geometry → navmesh → bot playtest")
	App.go_to(App.SCENE_CREATION_STUDIO)
	await wait_frames(3)
	var studio := tree.current_scene
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	ui.confirm_dialog.hide()
	var ctl := studio.get("controller") as MapEditController
	var view := studio.get_node("MapView") as MapEditorView
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var doc := _arena("Bot playtest draft")
	for x: float in [-6.0, -3.0, 3.0, 6.0]:
		doc.add_piece(_piece("spawn_attack", Vector3(x, 0, 12)))
		doc.add_piece(_piece("spawn_defence", Vector3(x, 0, -12), Vector3.ZERO, 180.0))
	var hold_position := Vector3(10, 0, -10)
	doc.add_piece(_piece("ai_hold", hold_position, Vector3.ZERO, 0.0, {"site": "B"}))
	ctl.set_document(doc)
	ui.navmesh_check.button_pressed = true
	var from := Vector3(0, 0, 12)
	var to := Vector3(0, 0, -12)
	var original := studio.get("analysis") as MapAnalysis
	var direct := original.path_length(from, to)
	check(view.has_overlay() and absf(direct - 24.0) < 0.5, "bots start with a direct route across the open floor")

	studio.call("set_overhead", true)
	ui.tool_selected.emit(StudioUI.Tool.DRAW_WALL)
	studio.call("_begin_draw", camera.unproject_position(Vector3(-8, 0, 0)))
	studio.call("_finish_draw", camera.unproject_position(Vector3(8, 0, 0)))
	var wall_id := ctl.selected_id
	check(not view.has_overlay() and studio.get("analysis") == null, "drawing a wall immediately hides the stale overlay")
	var refreshed := await wait_until(func() -> bool: return view.has_overlay(), 2.0)
	var with_wall := studio.get("analysis") as MapAnalysis
	var detour := with_wall.path_length(from, to) if refreshed and with_wall != null else -1.0
	check(detour > direct + 3.0, "the overlay rebuilds and the wall forces a bot detour")
	ctl.undo()
	await wait_until(func() -> bool: return view.has_overlay(), 2.0)
	var undone := studio.get("analysis") as MapAnalysis
	check(undone != null and absf(undone.path_length(from, to) - direct) < 0.5,
		"undo reopens the direct route")
	ctl.redo()
	await wait_until(func() -> bool: return view.has_overlay(), 2.0)
	var redone := studio.get("analysis") as MapAnalysis
	check(redone != null and detour > 0.0 and absf(redone.path_length(from, to) - detour) < 0.5,
		"redo restores the detour")

	studio.call("_on_action", &"playtest_team", "defence")
	studio.call("_on_action", &"playtest_spawn", 1)
	ui.bot_playtest_check.button_pressed = true
	ui.playtest_button.pressed.emit()
	await wait_frames(3)
	var runtime := tree.current_scene
	var director := runtime.get("match_director") as MatchDirector
	check(director != null and director.squad != null and director.squad.bots.size() == 9
		and director.document.get_piece(wall_id).get("type") == "wall" and App.is_playtesting(),
		"Playtest starts a 5v5 bot match on the unsaved geometry")
	if director == null or director.squad == null:
		App.end_playtest()
		await wait_frames(3)
		return
	await wait_physics_frames(12)
	check(director.human_side() == MatchRules.SIDE_DEFENCE
		and director.player.global_position.distance_to(Vector3(-6, 0, -12)) < 0.5
		and director.squad.bots["bot_home_1"].global_position.distance_to(director.player.global_position) > 2.0,
		"the chosen defender spawn is reserved for the human")
	var runtime_map := director.level.navigation_region.get_navigation_map()
	var runtime_route := NavigationBuilder.path_length(runtime_map, from, to)
	check(runtime_route > direct + 3.0 and absf(runtime_route - detour) < 0.5,
		"the runtime bots use the same detour shown in the editor")
	director.state.tick(director.state.rules.freeze_time + 0.01)
	director.squad.physics_update(0.3)
	var uses_hold := director.squad.bots.values().any(func(bot: BotController) -> bool:
		return (director.state.side_of(bot.bot_id) == MatchRules.SIDE_DEFENCE
			and bot.goal_position.distance_to(hold_position) < 0.5))
	check(uses_hold, "a defender uses the hold point authored in the draft")

	var pause_hud := runtime.get_node("Hud") as SandboxHud
	check(pause_hud.editor_button.visible and director.hud.main_menu_button.text == "Return to Creation Studio",
		"the pause and match-end screens both point back to the editor")
	runtime.call("_on_practice_match_requested")
	await wait_frames(3)
	runtime = tree.current_scene
	director = runtime.get("match_director") as MatchDirector
	check(director != null and App.is_playtesting() and director.document.get_piece(wall_id).get("type") == "wall",
		"restarting the bot match retains the unsaved map and editor session")
	(runtime.get_node("Hud") as SandboxHud).editor_button.pressed.emit()
	await wait_frames(3)
	var restored := tree.current_scene
	var restored_ctl := restored.get("controller") as MapEditController
	check(App.current_scene_id == App.SCENE_CREATION_STUDIO and restored_ctl != null and restored_ctl.is_dirty()
		and restored_ctl.document.get_piece(wall_id).get("type") == "wall"
		and (restored.get_node("UI/StudioUI") as StudioUI).bot_playtest_check.button_pressed,
		"returning restores the unsaved wall and remembers the bot playtest setting")
	if restored_ctl != null:
		var restored_view := restored.get_node("MapView") as MapEditorView
		check(await wait_until(func() -> bool: return restored_view.has_overlay(), 2.0),
			"returning restores the navmesh display")
		check(restored_ctl.undo() and restored_ctl.document.get_piece(wall_id).is_empty()
			and restored_ctl.redo() and restored_ctl.document.get_piece(wall_id).get("type") == "wall",
			"the original draw stroke can still be undone and redone after the match")
		restored_ctl.mark_saved()
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)
