class_name BotUtilitySuite
extends TestSuite
## Milestone 7 B: bots solve grenade line-ups against the real map and throw them like a player,
## look away from their team's flashes, and take a site with utility in a match.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Bot utility (Milestone 7 B)"


func run() -> void:
	_test_pure()
	await _test_lineups()
	await _test_official_execute()


func _test_pure() -> void:
	section("Aim and site plans")
	var from := Vector3(1, 2, 3)
	var to := Vector3(-4, 6, -9)
	var angles := AimModel.angles_to(from, to)
	var direction := UtilityLineup.aim_direction(angles.x, angles.y)
	check(direction.distance_to((to - from).normalized()) < 0.001, "line-up angles turn back into the same view direction")
	check(UtilityLineup.miss_distance(EquipmentCatalog.SMOKE, Vector3(0, 1, 0), Vector3.ZERO) == 2.0,
		"a smoke on the wrong floor misses by double the height")
	check(SiteExecute.plan(null, "A") == null, "no site plan on a map without a simulation graph")
	var map_id := _official_with_graph()
	var map := SimMap.for_map(map_id)
	var doc := OfficialMaps.load_map(map_id)
	var take := SiteExecute.plan(map, "A", MapTactical.hints(doc, "ai_hold", "A"))
	check(take != null and not map.site_cluster("site_A").has(take.entrance_id) and map.neighbours(take.entrance_id).any(
		func(id: String) -> bool: return map.site_cluster("site_A").has(id)),
		"the take enters the site from a place next to it (%s)" % (map.name_of(take.entrance_id) if take != null else "none"))
	check(take != null and take.staging_id != "" and map.route(map.spawn("attack"), "site_A").has(take.staging_id),
		"attackers gather on their way in, before the entrance (%s)" % (map.name_of(take.staging_id) if take != null else "none"))
	check(take != null and not take.smokes.is_empty() and take.flash != Vector3.INF and take.flash.y > take.entrance.y + 2.0,
		"smokes are planned and the flash pops in the air over the entrance (%d smokes)" % (take.smokes.size() if take != null else 0))

	section("Flash warnings")
	var knowledge := TeamKnowledge.new()
	knowledge.warn_flash(Vector3(5, 2, 0), 1.5)
	check(knowledge.flash_to_avoid(Vector3.ZERO, 20.0) == Vector3.INF, "a flash far from going off is not looked away from yet")
	knowledge.advance(0.8)
	check(knowledge.flash_to_avoid(Vector3.ZERO, 20.0) == Vector3(5, 2, 0), "one about to go off is")
	check(knowledge.flash_to_avoid(Vector3(60, 0, 0), 20.0) == Vector3.INF, "only by teammates near it")
	knowledge.advance(1.5)
	check(knowledge.flashes.is_empty(), "a flash that has gone off is forgotten")


func _test_lineups() -> void:
	section("Line-ups against the map")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(5)
	var level := sandbox.get_node("Level") as SandboxLevel
	(sandbox.get_node("Player") as FirstPersonController).input_enabled = false
	level.build_navigation()
	await wait_physics_frames(8)
	var space := level.get_world_3d().direct_space_state
	var eye := Vector3(2, 1.6, 10)
	var target := Vector3(-6, 0.0, 4)
	var started := Time.get_ticks_msec()
	var lineup := UtilityLineup.solve(space, EquipmentCatalog.SMOKE, eye, target, 2.5)
	var took := Time.get_ticks_msec() - started
	check(lineup != null and lineup.error <= 2.5, "a smoke line-up is solved to land on the spot (miss %.2f m, %d ms)" % [
		lineup.error if lineup != null else INF, took])
	check(UtilityLineup.solve(space, EquipmentCatalog.SMOKE, eye, Vector3(0, 0, -40), 2.5) == null,
		"no line-up lands outside the map's walls")
	var flash := UtilityLineup.solve(space, EquipmentCatalog.FLASH, eye, Vector3(-2, 2.5, 2), 2.0)
	check(flash != null and absf(flash.seconds - float(EquipmentCatalog.params(EquipmentCatalog.FLASH)["fuse"])) < 0.05,
		"a flash line-up goes off in the air on its fuse")

	section("Bots throw line-ups")
	var bot := BotController.new()
	bot.setup("bot_thrower", "bot_thrower", &"away", BotSkill.preset(&"normal"), Color("8a3c3c"))
	level.add_child(bot)
	bot.respawn_at(eye - Vector3(0, BotController.STAND_EYE, 0), 0.0)
	await wait_physics_frames(4)
	check(not bot.throw_utility(lineup), "a bot without the grenade cannot throw it")
	bot.weapons.give_utility(EquipmentCatalog.SMOKE)
	var solved := UtilityLineup.solve(space, EquipmentCatalog.SMOKE, bot.head.global_position, target, 2.5, bot.weapons.exclude)
	var finished: Array[bool] = []
	bot.utility_finished.connect(func(_id: StringName, thrown: bool) -> void: finished.append(thrown))
	check(solved != null and bot.throw_utility(solved) and bot.is_throwing(), "a bot with a smoke takes it out to throw")
	Engine.time_scale = 2.0
	var landed := await wait_until(func() -> bool:
		return level.utility.smokes.any(func(smoke: UtilityField.Smoke) -> bool:
			return Vector2(smoke.centre.x - target.x, smoke.centre.z - target.z).length() <= 2.5), 10.0)
	Engine.time_scale = 1.0
	check(finished == [true] and not bot.is_throwing(), "it lines up and throws")
	check(landed, "the smoke blooms where the line-up said")
	check(not bot.weapons.current().definition.is_utility(), "and it has a gun back in its hands")

	section("Throwing skill")
	var spread: Dictionary[String, float] = {}
	for preset: StringName in [&"easy", &"hard"]:
		var skill := BotSkill.preset(preset)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var total := 0.0
		for i: int in 12:
			var result := UtilityLineup.simulate(space, EquipmentCatalog.SMOKE, eye, lineup.yaw + rng.randfn(0.0, skill.utility_error),
				lineup.pitch + rng.randfn(0.0, skill.utility_error), lineup.speed)
			total += UtilityLineup.miss_distance(EquipmentCatalog.SMOKE, result["position"] as Vector3, target)
		spread[String(preset)] = total / 12.0
	check(spread["easy"] > spread["hard"] * 1.5,
		"a low-skilled thrower's release lands further off the spot (%.1f m against %.1f m on average)" % [spread["easy"], spread["hard"]])
	var times: Dictionary[String, float] = {}
	for preset: StringName in [&"easy", &"hard"]:
		bot.skill = BotSkill.preset(preset)
		bot.respawn_at(eye - Vector3(0, BotController.STAND_EYE, 0), 0.0)
		await wait_physics_frames(3)
		bot.weapons.give_utility(EquipmentCatalog.SMOKE)
		var again := UtilityLineup.solve(space, EquipmentCatalog.SMOKE, bot.head.global_position, target, 2.5, bot.weapons.exclude)
		var started_at := Time.get_ticks_msec()
		bot.throw_utility(again)
		await wait_until(func() -> bool: return not bot.is_throwing(), 6.0)
		times[String(preset)] = (Time.get_ticks_msec() - started_at) / 1000.0
	check(times["easy"] > times["hard"] and times["hard"] >= BotSkill.preset(&"hard").lineup_time * 0.75,
		"lining up takes time, longer for a low-skilled thrower (%.2f s against %.2f s)" % [times["easy"], times["hard"]])

	section("Looking away from a teammate's flash")
	var knowledge := TeamKnowledge.new()
	bot.knowledge = knowledge
	var flash_at := bot.head.global_position + Vector3(0, 0, -8)
	bot.set_view(AimModel.angles_to(bot.head.global_position, flash_at))
	knowledge.warn_flash(flash_at, 0.6)
	await wait_until(func() -> bool:
		knowledge.advance(1.0 / 60.0)
		return false, 0.5)
	var off := AimModel.angle_between(bot.view_angles(), AimModel.angles_to(bot.head.global_position, flash_at))
	check(off > 100.0, "a bot turns its back on its own team's flash before it goes off (%.0f° away)" % off)
	await despawn(sandbox)


## A rifle round on an official map: the attacking bots gather, throw their utility and go in.
func _test_official_execute() -> void:
	section("A site take with utility")
	var app := tree.root.get_node("App")
	var map_id := _official_with_graph()
	var setup := MatchSetup.new()
	setup.fixture_id = "bot_utility_official"
	setup.home_team_id = "team_you"
	setup.home_team_name = "You"
	setup.away_team_id = "team_bots"
	setup.away_team_name = "Bots"
	setup.max_rounds = 2
	setup.map_id = map_id
	var rules := MatchRules.practice(2)
	rules.team_size = 5
	rules.freeze_time = 0.5
	rules.buy_time = 1.0
	rules.round_time = 115.0
	var map := OfficialMaps.load_map(map_id)
	app.set("pending_match_setup", setup)
	app.set("pending_match_rules", rules)
	app.set("pending_match_map", map)
	app.set("pending_match_options", {"opponents": "bots", "skill": "normal"})
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var director := sandbox.get("match_director") as MatchDirector
	var squad := director.squad if director != null else null
	if squad == null:
		check(false, "bots mode creates a BotSquad")
		await despawn(sandbox)
		return
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	# Nobody sees anyone, so the take plays out; attackers carry a rifle round's utility.
	var thrown: Array[StringName] = []
	for id: String in squad.bots:
		var bot := squad.bots[id]
		if director.state.side_of(id) == MatchRules.SIDE_ATTACK:
			for item: StringName in [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE]:
				bot.weapons.give_utility(item)
			bot.weapons.utility_thrown.connect(func(item: StringName) -> void: thrown.append(item))
		bot.enemies = []
	check(squad.execute != null and squad.execute_phase == BotSquad.Execute.GATHER,
		"the attackers plan a take of site %s from %s" % [squad.attack_site,
			SimMap.for_map(map_id).name_of(squad.execute.entrance_id) if squad.execute != null else "nowhere"])
	Engine.time_scale = 4.0
	var gathered := await wait_until(func() -> bool: return squad.execute_phase != BotSquad.Execute.GATHER, 30.0)
	check(gathered, 
		"they gather before the entrance")
	var went := await wait_until(func() -> bool: return squad.execute_phase == BotSquad.Execute.GO, 20.0)
	Engine.time_scale = 1.0
	check(went and thrown.has(EquipmentCatalog.SMOKE) and thrown.back() == EquipmentCatalog.FLASH,
		"they smoke, flash in last, then go (%s)" % ", ".join(thrown.map(
		func(item: StringName) -> String: return String(item))))
	app.set("last_match_result", null)
	await despawn(sandbox)
	await wait_frames(2)


func _official_with_graph() -> String:
	for id: String in OfficialMaps.ids():
		if SimMap.for_map(id) != null:
			return id
	return ""
