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
		bot.rng.seed = 3
		bot.throw_utility(again)
		await wait_until(func() -> bool: return not bot.is_throwing(), 15.0)
		times[String(preset)] = (Time.get_ticks_msec() - started_at) / 1000.0
	check(times["easy"] > times["hard"] and times["hard"] >= BotSkill.preset(&"hard").lineup_time * 0.75,
		"lining up takes time, longer for a low-skilled thrower (%.2f s against %.2f s)" % [times["easy"], times["hard"]])

	section("Every throw is different")
	var dice := RandomNumberGenerator.new()
	dice.seed = 5
	var normal := BotSkill.preset(&"normal")
	var slow := 0
	var snapped := 0
	var snap_spread := 0.0
	var steady_spread := 0.0
	var steady := 0
	var paced := 0.0
	var hurried := 0.0
	for i: int in 2000:
		var timing := normal.throw_timing(dice)
		paced += timing.x
		hurried += normal.throw_timing(dice, 0.5).x
		if timing.x >= normal.lineup_time + 0.5:
			slow += 1
		if timing.x <= 0.01:
			snapped += 1
			snap_spread += timing.y
		elif timing.x >= normal.lineup_time:
			steady += 1
			steady_spread += timing.y
	check(slow > 40 and snapped > 40, "some line-ups take half a second longer, some are snapped off (%d and %d of 2000)" % [slow, snapped])
	check(snapped > 0 and steady > 0 and snap_spread / snapped > steady_spread / steady * 2.0,
		"a snapped throw goes wider than a patient one (%.1f° against %.1f°)" % [snap_spread / maxf(snapped, 1), steady_spread / maxf(steady, 1)])
	check(hurried < paced * 0.7, "a call to throw fast shortens line-ups")
	var novice := BotSkill.from_abilities({"utility": 5, "composure": 30})
	var specialist := BotSkill.from_abilities({"utility": 96, "composure": 90})
	check(novice.lineup_time >= 5.0 and novice.lineup_time <= 10.0 and specialist.lineup_time < 0.7,
		"a novice takes %.1f s to line up, a specialist %.1f s" % [novice.lineup_time, specialist.lineup_time])

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


## Rifle rounds on an official map, one attack style at a time: each plays out the way it says.
func _test_official_execute() -> void:
	section("Attack styles on an official map")
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
	# A long round and a bomb nobody can plant: every style gets the same round to play out in.
	rules.round_time = 900.0
	rules.plant_time = 900.0
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
	(sandbox.get_node("Player") as FirstPersonController).input_enabled = false
	var attackers: Array[BotController] = []
	for id: String in squad.bots:
		squad.bots[id].enemies = []
		if director.state.side_of(id) == MatchRules.SIDE_ATTACK:
			attackers.append(squad.bots[id])
	# What each throw saw: [utility, bots released to push at that moment].
	var log: Array[Array] = []
	for bot: BotController in attackers:
		bot.weapons.utility_thrown.connect(func(item: StringName) -> void:
			log.append([item, squad.attack.released().size() if squad.attack != null else 0]))
	var spawns := director.level.spawn_points("attack")
	var sim := SimMap.for_map(map_id)
	Engine.time_scale = 4.0
	await wait_until(func() -> bool: return director.state.phase == MatchState.Phase.LIVE, 5.0)
	for style: AttackPlay.Style in [AttackPlay.Style.EXECUTE, AttackPlay.Style.EXECUTE_TOGETHER,
			AttackPlay.Style.SUPPORTED_ENTRY, AttackPlay.Style.DEFAULT, AttackPlay.Style.SPLIT, AttackPlay.Style.RUSH]:
		for index: int in attackers.size():
			var spawn: Array = spawns[index % spawns.size()]
			attackers[index].respawn_at((spawn[0] as Vector3) + Vector3(0.9 * floorf(float(index) / spawns.size()), 0, 0), float(spawn[1]))
			attackers[index].rng.seed = 40 + index
			for item: StringName in [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE]:
				if attackers[index].weapons.utility_count(item) == 0:
					attackers[index].weapons.give_utility(item)
		await wait_physics_frames(2)
		log.clear()
		squad.forced_style = style
		squad.plan_attack()
		var play := squad.attack
		var name := AttackPlay.STYLE_NAMES[style]
		if play == null:
			check(false, "%s: the attackers have a play" % name)
			continue
		var first_phase := play.lanes[0].phase
		var paired: Array[bool] = [false]
		var went := await wait_until(func() -> bool:
			for lane: AttackPlay.Lane in play.lanes:
				if lane.trader != null and lane.entry != null:
					paired[0] = true
			return play.is_going() and (log.size() > 0 or style == AttackPlay.Style.RUSH or style == AttackPlay.Style.DEFAULT
				or play.lanes.all(func(lane: AttackPlay.Lane) -> bool: return lane.throws.is_empty())), 60.0)
		var throws := ", ".join(log.map(func(entry: Array) -> String: return "%s@%d" % [String(entry[0]).trim_prefix("utl_"), entry[1]]))
		match style:
			AttackPlay.Style.EXECUTE:
				check(went and first_phase == AttackPlay.Phase.GATHER and log.size() >= 2 and log.back()[0] == EquipmentCatalog.FLASH
					and log.all(func(entry: Array) -> bool: return int(entry[1]) == 0),
					"execute: they gather, smoke, flash in last and only then go (%s)" % throws)
			AttackPlay.Style.EXECUTE_TOGETHER:
				check(went and not log.is_empty() and int(log[0][1]) > 0,
					"execute together: the first grenade flies with teammates already pushing (%s)" % throws)
			AttackPlay.Style.SUPPORTED_ENTRY:
				check(went and log.size() >= 2 and log[0][0] == EquipmentCatalog.FLASH
					and log.slice(1).any(func(entry: Array) -> bool: return int(entry[1]) >= 2 and int(entry[1]) < attackers.size()),
					"supported entry: a flash first, the entry pair goes while the supports keep throwing (%s)" % throws)
			AttackPlay.Style.DEFAULT:
				check(went and first_phase == AttackPlay.Phase.APPROACH and log.size() <= 1,
					"default: no gathering; at the entrance one flash at most, off the cuff (%s)" % throws)
			AttackPlay.Style.SPLIT:
				var entrances := play.lanes.map(func(lane: AttackPlay.Lane) -> String: return sim.name_of(lane.plan.entrance_id))
				check(went and play.lanes.size() == 2 and entrances[0] != entrances[1],
					"split: two groups take two lanes (%s) and push together (%s)" % [" and ".join(entrances), throws])
			AttackPlay.Style.RUSH:
				check(went and log.is_empty() and first_phase == AttackPlay.Phase.GO, "rush: straight in, no utility")
		if style != AttackPlay.Style.RUSH:
			check(paired[0], "%s: the first two in go as a pair (double peek)" % name)
	Engine.time_scale = 1.0
	squad.forced_style = -1
	app.set("last_match_result", null)
	await despawn(sandbox)
	await wait_frames(2)


func _official_with_graph() -> String:
	for id: String in OfficialMaps.ids():
		if SimMap.for_map(id) != null:
			return id
	return ""
