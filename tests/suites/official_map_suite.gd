extends TestSuite
## Milestone 16: the official maps. Every one must load as an ordinary map document, validate
## with no errors or warnings, bake a navmesh, give defenders the first contact at each site and
## let bots from every spawn reach both sites. Kilnmarket, the default, also hosts a full bot
## round (plant and defuse), previews an authored tactic and keeps its tuned route timings.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"
const TEST_DIR: String = "user://tests/official_map"
const ATTACK: String = "Attackers from spawn"
const DEFENCE: String = "Defenders from spawn"


func suite_name() -> String:
	return "Official maps (Milestone 16)"


func run() -> void:
	check(OfficialMaps.ids().size() >= 3 and OfficialMaps.listing().size() == OfficialMaps.ids().size(),
		"every registered official map loads (%d)" % OfficialMaps.listing().size())
	for map_id: String in OfficialMaps.ids():
		var official := OfficialMaps.load_map(map_id)
		check(official != null, "%s loads from res://data/maps/official" % map_id)
		if official == null:
			continue
		var analysis: MapAnalysis = await _test_document(official)
		if analysis != null and map_id == OfficialMaps.DEFAULT_ID:
			await _test_kilnmarket_timings(analysis)
		await _test_bots_reach_sites(official)
	var doc := OfficialMaps.load_map(OfficialMaps.DEFAULT_ID)
	if doc == null:
		return
	await _test_bot_round(doc)
	await _test_tactic_preview()
	await _test_map_select()
	var dir := DirAccess.open(TEST_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)


func _test_document(doc: MapDocument) -> MapAnalysis:
	section("%s: document, validation and timings" % doc.name)
	check(OfficialMaps.is_official(doc.map_id) and doc.map_id.begins_with("map_f2f_") and not doc.name.is_empty()
		and not doc.name.contains("Dev"), "it has a stable official ID and an original name")
	var raw := JSON.parse_string(FileAccess.get_file_as_string(OfficialMaps.path_for(doc.map_id))) as Dictionary
	check(raw["format"] == MapDocument.FORMAT and int(raw["format_version"]) == MapDocument.FORMAT_VERSION,
		"it is a normal map document in the current format")
	check(doc.content_version >= 1 and doc.content_hash == doc.content_fingerprint(), "its content version matches its content")
	check(MapDocument.from_json(doc.to_json()) != null and doc.pieces.size() > 120, "it round-trips through the editor's save format (%d pieces)" % doc.pieces.size())
	check(doc.pieces_of_type("spawn_attack").size() == 5 and doc.pieces_of_type("spawn_defence").size() == 5, "five spawns per team")
	check(doc.pieces_of_type("bombsite").size() == 2 and doc.pieces_of_type("buy_zone").size() == 2, "two bombsites and two buy zones")
	var names: Dictionary[String, bool] = {}
	for area: Dictionary in MapTactical.areas(doc):
		names[str(area["props"]["name"])] = true
	check(names.size() >= 20 and names.size() == MapTactical.areas(doc).size(), "full, uniquely named callout areas (%d)" % names.size())
	var plants_ok := true
	for site: Dictionary in doc.pieces_of_type("bombsite"):
		var inside := 0
		for anchor: Dictionary in MapTactical.anchors(doc, "plant"):
			if MapZones.contains(site, anchor["position"] as Vector3):
				inside += 1
		plants_ok = plants_ok and inside >= 2 and MapTactical.hints(doc, "ai_hold", str(site["props"]["site"])).size() >= 2
	check(plants_ok and MapTactical.anchors(doc, "default").size() >= 3 and MapTactical.anchors(doc, "utility").size() >= 3,
		"plant spots on both sites, default positions, utility spots and hold hints")
	var slopes_ok := true
	for piece: Dictionary in doc.pieces:
		if PieceCatalog.kind(str(piece["type"])) in ["stairs", "ramp"]:
			var size: Vector3 = piece["size"]
			slopes_ok = slopes_ok and rad_to_deg(atan2(size.y, size.z)) <= MapAnalysis.bot_slope_limit()
	check(slopes_ok, "every stair and ramp is shallow enough for bots (%.0f° or less)" % MapAnalysis.bot_slope_limit())
	check(not doc.lighting.is_empty() and not doc.pieces_of_kind("light").is_empty() and doc.layers.size() > 3,
		"it uses the editor's lighting, lights and layers")

	var host := Node3D.new()
	tree.root.add_child(host)
	var report := MapAnalysis.full_validation(doc, host)
	check((report["errors"] as Array).is_empty(), "MapValidator passes with no errors (%s)" % str(report["errors"]))
	check((report["warnings"] as Array).is_empty(), "no warnings, including unreachable areas (%s)" % str(report["warnings"]))
	var analysis := report["analysis"] as MapAnalysis
	check(analysis != null and analysis.polygon_count() > 200, "a navmesh is baked (%d polygons)" % analysis.polygon_count())
	var stranded: Array[String] = []
	for piece: Dictionary in doc.pieces:
		if (PieceCatalog.kind(str(piece["type"])) in ["anchor", "hint"] or str(piece["type"]).begins_with("spawn_")) 				and not analysis.is_reachable(piece["position"] as Vector3):
			stranded.append("%s %s" % [piece["type"], piece["id"]])
	check(stranded.is_empty(), "every spawn, anchor and AI hint is on reachable navmesh (%s)" % ", ".join(stranded))

	print(analysis.timing_text())
	var site_a := float(analysis.timing("Site A", DEFENCE)["seconds"])
	var site_b := float(analysis.timing("Site B", DEFENCE)["seconds"])
	var first_a := INF
	var first_b := INF
	for entry: Dictionary in analysis.timings:
		if entry["group"] == ATTACK and str(entry["label"]).contains("entrance A"):
			first_a = minf(first_a, float(entry["seconds"]))
		if entry["group"] == ATTACK and str(entry["label"]).contains("entrance B"):
			first_b = minf(first_b, float(entry["seconds"]))
	check(site_a > 0.0 and site_b > 0.0 and site_a + 2.0 < first_a and site_b + 2.0 < first_b,
		"defenders reach both sites at least 2 s before attackers reach any entrance (A %.1f vs %.1f, B %.1f vs %.1f)" % [site_a, first_a, site_b, first_b])
	check(absf(site_a - site_b) < 1.5, "defenders reach the two sites evenly (%.1f s vs %.1f s)" % [site_a, site_b])
	host.queue_free()
	await wait_frames(1)
	return analysis


## Kilnmarket's tuned layout: the long and short A routes, even sides, rotations and mid.
func _test_kilnmarket_timings(analysis: MapAnalysis) -> void:
	section("Kilnmarket: route timings")
	var site_a := float(analysis.timing("Site A", DEFENCE)["seconds"])
	var site_b := float(analysis.timing("Site B", DEFENCE)["seconds"])
	var gate := float(analysis.timing("Kiln Gate (entrance A)", ATTACK)["seconds"])
	var potter := float(analysis.timing("Potter's Door (entrance A)", ATTACK)["seconds"])
	var culvert := float(analysis.timing("Culvert Mouth (entrance B)", ATTACK)["seconds"])
	check(potter + 1.5 < gate, "the long A approach takes longer than the secondary route (%.1f s vs %.1f s)" % [gate, potter])
	check(absf(site_a - site_b) < 1.5 and absf(culvert - potter) < 2.0, "the two sides are timed evenly")
	var rotation := float(analysis.timing("Site A ↔ Site B")["seconds"])
	var crossing := float(analysis.timing("Kiln Gate (entrance A) ↔ Culvert Mouth (entrance B)", "Crossings")["seconds"])
	check(rotation > 8.0 and rotation < crossing, "rotations are faster than the attacker crossing but not instant (%.1f s vs %.1f s)" % [rotation, crossing])
	var mid_attack := float(analysis.timing("Dogleg (mid)", ATTACK)["seconds"])
	var mid_defence := float(analysis.timing("Dogleg (mid)", DEFENCE)["seconds"])
	check(mid_attack > 0.0 and mid_defence > 0.0 and absf(mid_attack - mid_defence) < 3.0, "mid is contested (%.1f s vs %.1f s)" % [mid_attack, mid_defence])

	check(App.map_by_id(OfficialMaps.DEFAULT_ID) != null and App.map_by_id(MapTemplates.SANDBOX_ARENA_ID) != null
		and App.map_by_id("map_missing") == null, "fixtures resolve the official map by ID; the Sandbox Arena stays available")


func _test_bots_reach_sites(doc: MapDocument) -> void:
	section("%s: bots from each spawn reach both sites" % doc.name)
	var level := SandboxLevel.new()
	tree.root.add_child(level)
	level.load_map(doc, false)
	var region := level.build_navigation()
	check(region.navigation_mesh.get_polygon_count() > 200, "the runtime bakes the map's navmesh")
	var map := level.get_world_3d().navigation_map
	var probe: Vector3 = doc.pieces_of_type("spawn_attack")[0]["position"]
	var synced := func() -> bool:
		return NavigationServer3D.map_get_iteration_id(map) > 0 			and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0
	await wait_until(synced, 4.0)
	var bots: Array[BotController] = []
	var starts: Array[Array] = []
	for team: String in ["attack", "defence"]:
		for spawn: Array in level.spawn_points(team):
			var bot := BotController.new()
			bot.setup("reach_%d" % bots.size(), "Runner", &"runners", BotSkill.preset(&"normal"), Color.WHITE)
			level.add_child(bot)
			bot.collision_mask = Hitscan.LAYER_WORLD
			bot.collision_layer = 0
			bots.append(bot)
			starts.append(spawn)
	check(bots.size() == 10, "one bot per spawn")
	Engine.time_scale = 6.0
	for site: Dictionary in doc.pieces_of_type("bombsite"):
		var letter := str(site["props"]["site"])
		for i: int in bots.size():
			bots[i].respawn_at(starts[i][0] as Vector3, float(starts[i][1]))
			bots[i].set_goal(NavigationServer3D.map_get_closest_point(map, site["position"] as Vector3))
		var arrived := await wait_until(func() -> bool:
			return bots.all(func(bot: BotController) -> bool: return MapZones.bombsite_at(doc, bot.global_position) == letter), 25.0)
		var inside := bots.filter(func(bot: BotController) -> bool: return MapZones.bombsite_at(doc, bot.global_position) == letter).size()
		check(arrived, "all ten bots walk from their spawn into site %s (%d/10)" % [letter, inside])
	Engine.time_scale = 1.0
	level.queue_free()
	await wait_frames(2)


func _test_bot_round(doc: MapDocument) -> void:
	section("A full bot round: plant and defuse")
	var app := tree.root.get_node("App")
	var setup := MatchSetup.new()
	setup.fixture_id = "official_map_round"
	setup.home_team_id = "team_you"
	setup.home_team_name = "You"
	setup.away_team_id = "team_bots"
	setup.away_team_name = "Bots"
	setup.max_rounds = 3
	setup.map_id = doc.map_id
	var rules := MatchRules.practice(3)
	rules.team_size = 3
	rules.freeze_time = 0.5
	rules.buy_time = 2.0
	rules.round_time = 80.0
	rules.round_end_delay = 0.5
	rules.bomb_timer = 40.0
	rules.plant_time = 1.0
	rules.defuse_time = 3.0
	rules.defuse_time_with_kit = 2.0
	app.set("pending_match_setup", setup)
	app.set("pending_match_rules", rules)
	app.set("pending_match_map", doc)
	app.set("pending_match_options", {"opponents": "bots", "skill": "normal"})
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var director := sandbox.get("match_director") as MatchDirector
	check(director != null and director.squad != null and director.level.document.map_id == doc.map_id,
		"a practice match starts on the official map")
	if director == null or director.squad == null:
		await despawn(sandbox)
		return
	var hud := sandbox.get_node("Hud") as SandboxHud
	check(hud.select_practice_map(OfficialMaps.DEFAULT_ID) and hud.selected_practice_map_id() == OfficialMaps.DEFAULT_ID
		and hud.select_practice_map(MapTemplates.SANDBOX_ARENA_ID), "the pause menu offers Kilnmarket and the Sandbox Arena for practice")
	var sun := sandbox.get_node("Sun") as DirectionalLight3D
	check(is_equal_approx(sun.light_energy, float(doc.lighting["sun_energy"])), "the map's lighting is applied in the runtime")
	var state := director.state
	var squad := director.squad
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	check(MapZones.is_in_buy_zone(doc, "attack", player.global_position), "the human spawns inside the attackers' buy zone")
	await wait_frames(2)
	check(hud.location_text() == "Caravan Gate", "the HUD names the callout area (%s)" % hud.location_text())
	# Blind the bots so the round is decided by objectives: the human dies, a teammate takes the
	# bomb and plants, the defenders retake and defuse.
	var blind: Array[Health] = []
	for bot: BotController in squad.bots.values():
		bot.enemies = blind
	var log: Array[String] = []
	state.bomb_picked_up.connect(func(id: String) -> void: log.append("pickup:" + id))
	state.bomb_planted.connect(func(id: String) -> void: log.append("plant:" + id))
	state.bomb_defused.connect(func(id: String) -> void: log.append("defuse:" + id))
	Engine.time_scale = 6.0
	check(await wait_until(func() -> bool: return state.phase == MatchState.Phase.LIVE, 4.0), "the round goes live")
	await wait_physics_frames(3)
	var holding := 0
	for id: String in squad.bots:
		var bot := squad.bots[id]
		if state.side_of(id) == MatchRules.SIDE_DEFENCE and bot.has_goal:
			for hold: Dictionary in doc.pieces_of_type("ai_hold"):
				if Vector2(bot.goal_position.x - (hold["position"] as Vector3).x, bot.goal_position.z - (hold["position"] as Vector3).z).length() < 1.0:
					holding += 1
	check(holding == 3, "defending bots head for the map's hold hints (%d/3)" % holding)
	player.health.kill()
	var round_over := func() -> bool: return state.round_number >= 2 or state.phase != MatchState.Phase.LIVE
	await wait_until(func() -> bool: return state.is_bomb_planted or round_over.call(), 30.0)
	check(log.any(func(entry: String) -> bool: return entry.begins_with("plant:bot_home")),
		"a bot carries the bomb to a site and plants (%s)" % ", ".join(log))
	check(not MapZones.bombsite_at(doc, state.bomb_position).is_empty(), "the bomb is planted inside a bombsite")
	await wait_until(round_over, 30.0)
	check(log.any(func(entry: String) -> bool: return entry.begins_with("defuse:bot_away"))
		and state.last_round_reason == MatchRules.REASON_DEFUSED,
		"the defenders retake and defuse, completing the round (%s, %s)" % [", ".join(log), state.last_round_reason])
	Engine.time_scale = 1.0
	app.set("last_match_result", null)
	await despawn(sandbox)
	await wait_frames(2)


func _test_tactic_preview() -> void:
	section("An authored tactic previews on the map")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	(studio.get_node("UI/StudioUI") as StudioUI).confirm_dialog.hide()
	studio.set("tactic_storage", TacticStorage.new(TEST_DIR))
	check(bool(studio.call("load_official", OfficialMaps.DEFAULT_ID)) and bool(studio.call("open_tactic_editor")),
		"the Tactical Play Creator opens on the official map without saving a copy")
	var editor := studio.get("tactic_editor") as TacticEditor
	if editor == null:
		await despawn(studio)
		return
	var doc := OfficialMaps.load_map(OfficialMaps.DEFAULT_ID)
	var spawns := MapBuilder.spawn_points(doc, "attack")
	var hold := Vector3.ZERO
	for anchor: Dictionary in MapTactical.anchors(doc, "default"):
		if anchor["props"]["name"] == "Dogleg hold":
			hold = anchor["position"]
	for i: int in TacticDocument.SLOT_COUNT:
		editor.selected_slot = i
		editor.edit_mode = TacticEditor.EditMode.SET_START
		editor.apply_point(spawns[i][0] as Vector3)
		editor.edit_mode = TacticEditor.EditMode.ADD_WAYPOINT
		editor.apply_point((spawns[i][0] as Vector3) + Vector3(0, 0, -5))
	editor.selected_slot = 0
	check(editor.apply_point(hold + Vector3(0.4, 0, 0.3)).is_empty() and editor.document.slots[0].route[1].is_equal_approx(hold),
		"a waypoint snaps to the map's tactical anchor")
	check(MapTactical.area_name(doc, editor.document.slots[0].area_of(1)) == "Spice Row"
		and MapTactical.area_name(doc, editor.document.slots[0].start_area) == "Caravan Gate", "steps record the callout areas they are in")
	editor.document.display_name = "Spice Row default"
	check(editor.save_tactic().is_empty() and editor.document.map_id == OfficialMaps.DEFAULT_ID, "the tactic is saved against the official map")
	Engine.time_scale = 6.0
	check(editor.start_preview().is_empty(), "the preview starts")
	var preview := editor.preview
	var finished := await wait_until(func() -> bool:
		return preview.completed[0] == 2 and preview.completed.slice(1).all(func(count: int) -> bool: return count == 1), 20.0)
	check(finished, "five bots run the authored routes to the end (%s)" % str(preview.statuses))
	Engine.time_scale = 1.0
	editor.stop_preview()
	var path := editor.store.path_for(editor.document.tactic_id)
	var reopened := editor.store.load_path(path, doc)
	check(reopened["tactic"] != null and (reopened["warnings"] as Array).is_empty(), "the saved tactic is current for the shipped map")
	await despawn(studio)


func _test_map_select() -> void:
	section("FPS Sandbox map select")
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)
	(tree.current_scene.get("sandbox_button") as Button).pressed.emit()
	await wait_frames(3)
	var select := tree.current_scene
	check(App.current_scene_id == App.SCENE_MAP_SELECT and select.get("map_buttons") != null,
		"FPS Sandbox on the main menu opens the map select screen")
	var buttons: Dictionary = select.get("map_buttons")
	check(buttons.has(OfficialMaps.DEFAULT_ID) and buttons.has(MapTemplates.SANDBOX_ARENA_ID),
		"it lists Kilnmarket and the Sandbox Arena")
	var storage := MapStorage.new(TEST_DIR)
	var mine := MapTemplates.blank()
	mine.name = "My test map"
	storage.save(mine)
	select.set("storage", storage)
	select.call("refresh")
	buttons = select.get("map_buttons")
	check(buttons.has(mine.map_id) and (buttons[mine.map_id] as Button).text.contains("My test map"), "it lists maps saved in the Creation Studio")
	check(not bool(select.call("play", "map_missing")) and App.current_scene_id == App.SCENE_MAP_SELECT, "an unreadable map stays on the screen")
	(buttons[OfficialMaps.DEFAULT_ID] as Button).pressed.emit()
	await wait_frames(3)
	var runtime := tree.current_scene
	var level := runtime.get_node("Level") as SandboxLevel
	check(App.current_scene_id == App.SCENE_FPS_SANDBOX and level.document.map_id == OfficialMaps.DEFAULT_ID
		and runtime.get("match_director") == null, "choosing Kilnmarket loads it in the FPS Sandbox for free roam")
	var player := runtime.get_node("Player") as FirstPersonController
	check(MapZones.is_in_buy_zone(level.document, "attack", player.global_position), "the player starts at an attacker spawn")
	App.go_to(App.SCENE_MAP_SELECT)
	await wait_frames(3)
	tree.current_scene.set("storage", storage)
	check(bool(tree.current_scene.call("play", mine.map_id)), "a saved map can be chosen")
	await wait_frames(3)
	check((tree.current_scene.get_node("Level") as SandboxLevel).document.map_id == mine.map_id, "the saved map loads")
	App.go_to(App.SCENE_FPS_SANDBOX)
	await wait_frames(3)
	check((tree.current_scene.get_node("Level") as SandboxLevel).document.map_id == MapTemplates.SANDBOX_ARENA_ID,
		"the choice is used once; the runtime falls back to the Sandbox Arena")
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)
	storage.delete_map(mine.map_id)
