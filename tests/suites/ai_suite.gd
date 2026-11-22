class_name AiSuite
extends TestSuite
## Milestone 6: aim model, skills, navmesh baking, bot navigation, perception, combat, teams.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


class MovementTestBot extends BotController:
	var direction: Vector3 = Vector3.ZERO

	func _navigate(_delta: float) -> Vector3:
		return direction


func suite_name() -> String:
	return "Bot AI (Milestone 6)"


func run() -> void:
	_test_aim_model()
	_test_skills()
	await _test_movement_parity()
	_test_roam_planner()
	await _test_sandbox_bots()
	await _test_world()
	_test_team_knowledge()
	await _test_player_like()


func _test_aim_model() -> void:
	section("Aim model")
	var skill := BotSkill.new()
	var aim := AimModel.new(skill)
	var step := aim.step(Vector2.ZERO, Vector2(90, 0), 0.1)
	check(step.x <= skill.turn_speed * 0.1 + 0.001 and step.x > 0.0, "turning is capped by turn speed (%.1f°)" % step.x)
	var view := Vector2.ZERO
	for i: int in 120:
		view = aim.step(view, Vector2(30, -10), 1.0 / 60.0)
	check(AimModel.angle_between(view, Vector2(30, -10)) < 0.5, "aim converges on the target direction")
	check(absf(aim.step(Vector2(170, 0), Vector2(-170, 0), 0.016).x) > 170.0, "aim turns the short way across ±180°")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	aim.acquire(60.0, rng)
	var initial := aim.error.length()
	check(initial > skill.initial_error * 0.5, "acquiring a target far off-centre adds error (%.1f°)" % initial)
	for i: int in 60:
		aim.step(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
	check(aim.error.length() < initial * 0.2, "aim error decays while tracking")
	var forward := AimModel.angles_to(Vector3.ZERO, Vector3(0, 0, -10))
	check(forward.is_equal_approx(Vector2.ZERO), "angles_to: straight ahead is 0,0")
	check(AimModel.angles_to(Vector3.ZERO, Vector3(-10, 0, 0)).x > 89.0, "angles_to: left is +90 yaw")
	check(AimModel.angles_to(Vector3.ZERO, Vector3(0, 10, -10)).y > 44.0, "angles_to: up is positive pitch")


func _test_skills() -> void:
	section("Bot skills")
	var easy := BotSkill.preset(&"easy")
	var normal := BotSkill.preset(&"normal")
	var hard := BotSkill.preset(&"hard")
	check(easy.reaction_time > normal.reaction_time and normal.reaction_time > hard.reaction_time, "reaction: easy > normal > hard")
	check(easy.initial_error > hard.initial_error and easy.recoil_control < hard.recoil_control, "hard bots aim and control recoil better")
	var rookie := BotSkill.from_abilities({"aim": 40, "reaction": 38, "spray_control": 35, "crosshair_placement": 42})
	var star := BotSkill.from_abilities({"aim": 92, "reaction": 90, "spray_control": 88, "crosshair_placement": 91})
	check(star.reaction_time < rookie.reaction_time and star.initial_error < rookie.initial_error
		and star.recoil_control > rookie.recoil_control, "career abilities map onto bot mechanics (star beats rookie)")
	var maxed := BotSkill.from_abilities({"aim": 100, "reaction": 100, "spray_control": 100, "crosshair_placement": 100})
	check(maxed.reaction_time >= 0.15 and maxed.initial_error >= 1.5 and maxed.recoil_control <= 0.92,
		"even perfect abilities keep human-like limits")
	check(BotSkill.from_abilities({}).label.begins_with("Rated"), "missing abilities fall back to average")


func _test_movement_parity() -> void:
	section("Player and bot movement parity")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	var player := sandbox.get_node("Player") as FirstPersonController
	var bot := MovementTestBot.new()
	bot.setup("bot_parity", "Movement parity", &"away", BotSkill.preset(&"hard"), Color.WHITE)
	sandbox.add_child(bot)
	var p_start := Vector3(-24, 0, 22)
	var b_start := Vector3(-24, 0, 24)
	player.input_enabled = false
	player.set_spawn(p_start, 0.0)
	player.respawn()
	bot.respawn_at(b_start, 0.0)
	player.weapons.set_loadout([WeaponCatalog.AK47])
	bot.weapons.set_loadout([WeaponCatalog.AK47])
	await wait_physics_frames(15)

	player.scripted_move = Vector2.RIGHT
	bot.direction = Vector3.RIGHT
	await wait_physics_frames(12)
	check(_same_movement(player, bot) and bot.horizontal_speed() > 0.0,
		"identical rifle input gives the player and hard bot the same acceleration")
	await wait_physics_frames(48)
	check(_same_movement(player, bot) and is_equal_approx(bot.horizontal_speed(), player.current_max_speed())
		and is_equal_approx(bot.weapons.motion.speed, ShooterMotion.REFERENCE_SPEED),
		"rifle mobility and full-run accuracy speed match")
	player.scripted_move = Vector2.LEFT
	bot.direction = Vector3.LEFT
	await wait_physics_frames(5)
	check(_same_movement(player, bot) and player.velocity.x < player.current_max_speed(),
		"opposing input slows both combatants at the same rate")

	player.scripted_walk = true
	bot.walk_requested = true
	await wait_physics_frames(65)
	check(_same_movement(player, bot) and is_equal_approx(bot.horizontal_speed(), player.current_max_speed()),
		"the bot's walk request uses the same cap as Shift")
	player.wants_crouch = true
	bot.wants_crouch = true
	await wait_physics_frames(30)
	check(_same_movement(player, bot) and player.is_crouched() and bot.weapons.motion.crouched
		and is_equal_approx(bot.current_height(), player.current_height())
		and is_equal_approx(bot.head.position.y, player.head.position.y)
		and is_equal_approx(bot.hitboxes[0].position.y, player.hitboxes[0].position.y)
		and is_equal_approx(bot.weapons.current_spread(), player.weapons.current_spread()),
		"crouch matches stance, hitbox height and weapon spread")

	player.scripted_walk = false
	player.scripted_move = Vector2.ZERO
	player.respawn()
	bot.direction = Vector3.ZERO
	bot.respawn_at(b_start, 0.0)
	await wait_physics_frames(15)
	player.scripted_jump = true
	bot.request_jump()
	await wait_physics_frames(8)
	check(_same_movement(player, bot) and bot.weapons.motion.airborne and bot.velocity.y > 0.0
		and bot.movement != player.movement, "both jump with the same physics and independent stamina")
	player.scripted_move = Vector2.RIGHT
	bot.direction = Vector3.RIGHT
	await wait_physics_frames(12)
	check(_same_movement(player, bot) and bot.velocity.x > 0.0,
		"air steering matches with the same input")
	await wait_physics_frames(27)
	check(_same_movement(player, bot) and bot.is_on_floor() and bot.movement.stamina > 0.0,
		"landing and its stamina cost match")

	await wait_physics_frames(60)
	var run_speed := player.current_max_speed()
	player.scripted_jump = true
	bot.request_jump()
	await wait_physics_frames(2)
	for i: int in 60:
		if player.is_on_floor():
			break
		await wait_physics_frames(1)
	player.scripted_jump = true
	bot.request_jump()
	await wait_physics_frames(2)
	check(not player.is_on_floor() and _same_movement(player, bot)
		and is_equal_approx(player.horizontal_speed(), run_speed),
		"the same landing-timed jump preserves rifle momentum for both combatants")

	bot.respawn_at(b_start, 0.0)
	check(bot.movement.stamina == 0.0 and bot.velocity == Vector3.ZERO and not bot.is_crouched(),
		"bot respawn clears locomotion state")
	await despawn(sandbox)


func _same_movement(player: FirstPersonController, bot: BotController) -> bool:
	return (player.velocity.is_equal_approx(bot.velocity)
		and absf(player.global_position.y - bot.global_position.y) < 0.001
		and is_equal_approx(player.movement.stamina, bot.movement.stamina))


func _test_roam_planner() -> void:
	section("Free-roam reasoning (RoamPlanner)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var here := Vector3.ZERO
	var near := RoamPoint.new(Vector3(2, 0, 0), &"site")
	var site := RoamPoint.new(Vector3(20, 0, 0), &"site")
	var corner := RoamPoint.new(Vector3(0, 0, 21), &"wander")
	var far := RoamPoint.new(Vector3(-90, 0, 0), &"site")
	var no_noise: Array[RoamNoise] = []
	check(is_inf(RoamPlanner.score_point(near, here, false, no_noise, 1.0)), "a point it is standing next to is never chosen")
	check(RoamPlanner.score_point(site, here, false, no_noise, 1.0) > RoamPlanner.score_point(corner, here, false, no_noise, 1.0),
		"a bombsite is more interesting than a random corner at the same distance")
	check(RoamPlanner.score_point(site, here, false, no_noise, 1.0) > RoamPlanner.score_point(far, here, false, no_noise, 1.0),
		"a comfortable distance beats crossing the whole map")
	check(RoamPlanner.score_point(site, here, true, no_noise, 1.0) < RoamPlanner.score_point(corner, here, false, no_noise, 1.0),
		"a recently visited site loses to somewhere new")
	var points: Array[RoamPoint] = [site, corner]
	var recent: Array[int] = [0]
	check(RoamPlanner.choose(points, here, recent, no_noise, 1.0, rng) == 1, "choose() tours: it skips where it just was")
	var shot: Array[RoamNoise] = [RoamNoise.new(Vector3(0, 0, 24), "other")]
	var empty_recent: Array[int] = []
	var investigate := 0
	var avoid := 0
	for i: int in 40:
		if RoamPlanner.choose(points, here, empty_recent, shot, 1.0, rng) == 1:
			investigate += 1
		if RoamPlanner.choose(points, here, empty_recent, shot, 0.3, rng) == 0:
			avoid += 1
	check(investigate == 40, "a healthy bot goes towards gunfire it heard (%d/40)" % investigate)
	check(avoid == 40, "a badly hurt bot keeps away from it (%d/40)" % avoid)
	check(RoamPlanner.should_walk(Vector3(0, 0, 18), shot) and not RoamPlanner.should_walk(Vector3(0, 0, -30), shot),
		"bots walk carefully near recent gunfire and run elsewhere")
	shot[0].age = RoamPlanner.NOISE_MEMORY
	check(not RoamPlanner.should_walk(Vector3(0, 0, 18), shot), "old gunfire is forgotten")
	check(RoamPlanner.hears(here, Vector3(0, 0, 40)) and not RoamPlanner.hears(here, Vector3(0, 0, 60)),
		"gunshots are heard within %.0f m" % RoamPlanner.HEARING_RADIUS)


func _test_sandbox_bots() -> void:
	section("Free-roam sandbox bots")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	var hud := sandbox.get_node("Hud") as SandboxHud
	var level := sandbox.get_node("Level") as SandboxLevel
	var player := sandbox.get_node("Player") as FirstPersonController
	var roster := sandbox.get_node("SandboxBots")
	var bots := roster.get("bots") as Array[BotController]
	check(bots.is_empty() and hud.remove_bots_button.disabled and level.navigation_region == null,
		"the sandbox starts empty and only bakes navigation when needed")
	sandbox.call("pause")
	hud.add_bot_button.pressed.emit()
	hud.add_bot_button.pressed.emit()
	await wait_physics_frames(8)
	check(bots.size() == 2 and not hud.remove_bots_button.disabled and level.navigation_region != null,
		"the pause menu adds two bots without starting a practice match")
	if bots.size() != 2:
		await despawn(sandbox)
		return
	var first := bots[0]
	var start := first.global_position
	check(not first.can_process() and start.distance_to(bots[1].global_position) > 0.7,
		"paused bots stay put and occupy separate spawns")
	var second := bots[1]
	check(first.enemies.has(player.health) and first.enemies.has(second.health)
		and player.health.is_enemy_of(first.team) and second.health.is_enemy_of(first.team)
		and not first.health.is_enemy_of(first.team),
		"free for all: every bot fights the human and the other bots, never itself")
	sandbox.call("resume")
	check(await wait_until(func() -> bool: return not (roster.call("interest_points") as Array).is_empty(), 3.0),
		"bots gather places of interest from the map once navigation is ready")
	check(await wait_until(func() -> bool: return first.global_position.distance_to(start) > 1.0, 6.0),
		"bots use map navigation to roam")
	# Bots now fight each other and may respawn (which resets their plan), so look for any living
	# bot that is roaming between fights.
	var roaming := func() -> bool:
		var points := roster.call("interest_points") as Array
		for bot: BotController in bots:
			var mind: Object = roster.call("mind_of", bot)
			if not bot.is_alive() or mind == null or int(mind.get("destination")) < 0 or not bot.has_goal:
				continue
			var chosen := points[int(mind.get("destination"))] as RoamPoint
			if bot.goal_position.distance_to(chosen.position) < 0.1 \
					and bot.goal_position.distance_to(player.global_position) > 1.0:
				return true
		return false
	check(await wait_until(roaming, 6.0),
		"bots head for interest points they chose, not the human's position")
	# Put the two bots face to face in the open, the human far behind cover: they fight each other.
	player.global_position = start + Vector3(0, 0, 40)
	var arena := Vector3(level.spawn_points("attack")[0][0] as Vector3)
	first.respawn_at(arena, 0.0)
	second.respawn_at(arena + Vector3(0, 0, -8), PI)
	var hurt := func() -> bool:
		return second.health.current < second.health.max_health or first.health.current < first.health.max_health
	check(await wait_until(hurt, 6.0), "two bots that see each other trade fire (free for all)")
	first.health.kill()
	check(not first.visible and not first.is_alive(), "a killed sandbox bot disappears")
	check(await wait_until(func() -> bool: return first.is_alive(), 4.0) and first.visible,
		"the bot respawns in free roam without a round restart")
	sandbox.call("pause")
	hud.remove_bots_button.pressed.emit()
	await wait_physics_frames(2)
	check(bots.is_empty() and roster.get_child_count() == 0 and hud.remove_bots_button.disabled,
		"Remove All clears the bots and updates the menu")
	await despawn(sandbox)


func _test_world() -> void:
	section("Navigation mesh")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(5)
	var level := sandbox.get_node("Level") as SandboxLevel
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	var region := level.build_navigation()
	check(region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 10,
		"navmesh baked from the map (%d polygons)" % region.navigation_mesh.get_polygon_count())
	await wait_physics_frames(8)
	var map := region.get_navigation_map()
	var spawn := Vector3(0, 0, 12)
	var platform := Vector3(14, 3, -5)
	var length := NavigationBuilder.path_length(map, spawn, platform, 1.0)
	check(length > spawn.distance_to(platform), "path to the raised platform exists and detours via ramp/stairs (%.1f m)" % length)
	check(NavigationBuilder.path_length(map, spawn, Vector3(-18, 0, -18)) > 0.0, "bombsite B is reachable")
	check(NavigationBuilder.path_length(map, spawn, Vector3(0, 0, -40), 1.0) < 0.0, "points outside the walls are unreachable")

	section("Bot navigation")
	Engine.time_scale = 4.0
	var walker := _spawn_bot(level, "bot_walker", &"away", Vector3(3, 0, 8), 0.0)
	await wait_physics_frames(2)
	walker.set_goal(Vector3(-18, 0, -18))
	var arrived := await wait_until(func() -> bool: return walker.at_goal(1.5), 8.0)
	check(arrived, "bot walks to bombsite B around obstacles (at %s)" % str(walker.global_position.snapped(Vector3.ONE * 0.1)))
	walker.set_goal(platform)
	var climbed := await wait_until(func() -> bool: return walker.at_goal(1.5), 8.0)
	check(climbed and walker.global_position.y > 2.5, "bot climbs onto the platform")
	walker.queue_free()
	Engine.time_scale = 1.0

	section("Bot perception and combat")
	var dummy := level.dummies[0]
	dummy.respawn_delay = 30.0
	var shooter := _spawn_bot(level, "bot_shooter", &"away", Vector3(2, 0, 10), 0.0)
	await wait_physics_frames(2)
	shooter.enemies = [dummy.health]
	await wait_physics_frames(8)
	check(shooter.target == dummy.health, "bot spots a target inside its view cone")
	check(shooter.weapons.current().shots_fired_total == 0, "bot does not fire before its reaction time")
	Engine.time_scale = 2.0
	var killed := await wait_until(func() -> bool: return dummy.health.is_dead, 6.0)
	Engine.time_scale = 1.0
	check(killed, "bot kills the target with its pistol")
	check(shooter.weapons.current().shots_fired_total >= 1, "shots came from the bot's WeaponController")

	# A target behind the west wall stays unseen.
	var hidden := TargetDummy.new()
	hidden.position = Vector3(-14, 0, -4)
	level.add_child(hidden)
	shooter.respawn_at(Vector3(-6, 0, -4), deg_to_rad(90.0))
	shooter.enemies = [hidden.health]
	await wait_physics_frames(40)
	check(shooter.target == null and hidden.health.current == 100, "no engagement without line of sight")

	section("Bots versus the player, teams")
	shooter.respawn_at(Vector3(0, 0, 0), deg_to_rad(180.0))
	player.respawn()
	player.set_team(&"home")
	shooter.enemies = [player.health]
	Engine.time_scale = 2.0
	var hurt := await wait_until(func() -> bool: return player.health.current < 100, 6.0)
	Engine.time_scale = 1.0
	check(hurt, "bot hits the player's hitboxes (player at %d HP)" % player.health.current)
	player.respawn()
	var mate := _spawn_bot(level, "bot_mate", &"home", Vector3(0, 0, 0), deg_to_rad(180.0))
	await wait_physics_frames(2)
	mate.enemies = [player.health]
	shooter.queue_free()
	await wait_physics_frames(60)
	check(mate.target == null and player.health.current == 100, "bots never target teammates")
	await despawn(sandbox)


func _test_team_knowledge() -> void:
	section("Team knowledge (Milestone 7 A)")
	var knowledge := TeamKnowledge.new()
	knowledge.places = [{"id": "near", "centre": Vector3(2, 0, 0), "site": ""},
		{"id": "far", "centre": Vector3(20, 0, 0), "site": "A"}, {"id": "away", "centre": Vector3(90, 0, 0), "site": ""}]
	var open := knowledge.uncleared_near(Vector3.ZERO, 40.0)
	check(open.size() == 2 and str(open[0]["id"]) == "near", "places in reach come nearest first, far ones left out")
	knowledge.mark_cleared("near")
	check(knowledge.is_cleared("near") and knowledge.uncleared_near(Vector3.ZERO, 40.0).size() == 1, "a cleared place is skipped")
	knowledge.advance(TeamKnowledge.CLEARED_SECONDS + 0.5)
	check(not knowledge.is_cleared("near"), "a cleared place needs checking again after a while")
	knowledge.report_enemy(Vector3(10, 0, 0))
	knowledge.report_enemy(Vector3(10.5, 0, 0))
	check(knowledge.sightings.size() == 1 and knowledge.enemy_near(Vector3(12, 0, 0), 5.0), "sightings merge and are found nearby")
	knowledge.advance(TeamKnowledge.SIGHTING_SECONDS + 0.5)
	check(knowledge.sightings.is_empty(), "old sightings are forgotten")
	knowledge.mark_cleared("far")
	knowledge.report_enemy(Vector3.ONE)
	knowledge.reset()
	check(knowledge.cleared.is_empty() and knowledge.sightings.is_empty() and knowledge.places.size() == 3,
		"a new round forgets everything but the places")
	var official := ""
	for map_id: String in OfficialMaps.ids():
		if SimMap.for_map(map_id) != null:
			official = map_id
			break
	var from_map := TeamKnowledge.from_sim_map(SimMap.for_map(official))
	var spawns_left_out := from_map.places.all(func(place: Dictionary) -> bool:
		return str(SimMap.for_map(official).nodes[place["id"]].get("kind", "")) != SimMap.KIND_SPAWN)
	check(official != "" and not from_map.places.is_empty() and spawns_left_out
		and from_map.places.all(func(place: Dictionary) -> bool: return place["centre"] is Vector3),
		"an official map's places load from its simulation graph, spawns left out (%s: %d)" % [official, from_map.places.size()])
	check(TeamKnowledge.from_sim_map(null).places.is_empty(), "a map without a graph gives no places")
	var easy := BotSkill.preset(&"easy")
	var hard := BotSkill.preset(&"hard")
	check(easy.strafe < hard.strafe and easy.peek < hard.peek, "harder bots strafe and peek more")
	var rookie := BotSkill.from_abilities({"utility": 30, "composure": 35, "game_sense": 35, "positioning": 35,
		"movement": 35, "teamwork": 35, "communication": 35})
	var veteran := BotSkill.from_abilities({"utility": 92, "composure": 90, "game_sense": 92, "positioning": 90,
		"movement": 90, "teamwork": 90, "communication": 90})
	check(rookie.utility_error > veteran.utility_error and rookie.lineup_time > veteran.lineup_time and veteran.lineup_time > 0.3,
		"utility usage: worse players throw wider and line up slower; nobody throws instantly")
	check(rookie.accurate_share > veteran.accurate_share and rookie.clearing < veteran.clearing
		and rookie.search_hold < veteran.search_hold and rookie.flash_lead < veteran.flash_lead
		and rookie.view_distance < veteran.view_distance,
		"discipline, angle clearing, patience, flash awareness and spotting range all come from abilities")


func _test_player_like() -> void:
	section("Bots move like players (Milestone 7 A)")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(5)
	var level := sandbox.get_node("Level") as SandboxLevel
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	level.build_navigation()
	await wait_physics_frames(8)
	var dummy := level.dummies[0]
	dummy.respawn_delay = 0.4
	var bot := BotController.new()
	bot.setup("bot_strafer", "bot_strafer", &"away", BotSkill.preset(&"hard"), Color("8a3c3c"))
	level.add_child(bot)
	bot.respawn_at(Vector3(2, 0, 10), 0.0)
	bot.rng.seed = 7
	await wait_physics_frames(2)
	var shot_speeds: Array[float] = []
	bot.weapons.shot_fired.connect(func(_o: Vector3, _e: Vector3, _r: Hitscan.Result) -> void:
		shot_speeds.append(bot.accuracy_speed()))
	var fastest: Array[float] = [0.0]
	bot.enemies = [dummy.health]
	Engine.time_scale = 2.0
	await wait_until(func() -> bool:
		if bot.target != null:
			fastest[0] = maxf(fastest[0], bot.accuracy_speed())
		return false, 5.0)
	Engine.time_scale = 1.0
	var limit := ShooterMotion.REFERENCE_SPEED * bot.skill.accurate_share + 0.05
	var slow := shot_speeds.filter(func(speed: float) -> bool: return speed <= limit).size()
	var distance := bot.global_position.distance_to(dummy.global_position)
	check(not shot_speeds.is_empty() and fastest[0] > 1.5,
		"a disciplined bot strafes between shots (top speed %.1f m/s, %d shots)" % [fastest[0], shot_speeds.size()])
	check(distance <= BotController.RUN_AND_GUN_DISTANCE or slow == shot_speeds.size(),
		"it counter-strafes: every shot at %d m is fired slow (%d of %d)" % [roundi(distance), slow, shot_speeds.size()])

	section("Holding the angle after losing sight")
	bot.enemies = []
	bot.respawn_at(Vector3(2, 0, 10), 0.0)
	await wait_physics_frames(2)
	bot.set("_last_known", Vector3(-2, 0, 4))
	bot.call("_lose_target", true)
	var held_at := bot.global_position
	await wait_physics_frames(30)
	check(bot.mode == BotController.Mode.SEARCH and bot.global_position.distance_to(held_at) < 0.3,
		"a bot that loses sight holds the angle first")
	var before := bot.global_position.distance_to(Vector3(-2, 0, 4))
	await wait_until(func() -> bool: return bot.global_position.distance_to(Vector3(-2, 0, 4)) < before - 1.0, 4.0)
	check(bot.global_position.distance_to(Vector3(-2, 0, 4)) < before - 1.0, "then follows up to where the enemy was")

	section("Clearing angles as a team")
	var knowledge := TeamKnowledge.new()
	var corner := Vector3(-6, 0, 6.5)
	knowledge.places = [{"id": "west", "centre": corner, "site": ""}]
	bot.knowledge = knowledge
	bot.skill.clearing = 1.0
	bot.mode = BotController.Mode.MOVE
	bot.respawn_at(Vector3(2, 0, 10), 0.0)
	await wait_physics_frames(2)
	bot.set_goal(Vector3(0, 0, 0))
	var cleared_from: Array[float] = [-1.0]
	await wait_until(func() -> bool:
		knowledge.advance(1.0 / 60.0)
		if knowledge.is_cleared("west") and cleared_from[0] < 0.0:
			cleared_from[0] = bot.global_position.distance_to(corner)
		return bot.at_goal(1.0), 8.0)
	check(cleared_from[0] > BotController.INSIDE_PLACE,
		"a bot on the move checks a place in sight and clears it for the team (from %.1f m)" % cleared_from[0])
	knowledge.report_enemy(Vector3(1, 0, 2))
	check(bot.target == null and bool(bot.call("_cautious")), "it walks quietly where a teammate just saw the enemy")
	await despawn(sandbox)


func _spawn_bot(level: SandboxLevel, id: String, team_key: StringName, at: Vector3, yaw: float) -> BotController:
	var bot := BotController.new()
	bot.setup(id, id, team_key, BotSkill.preset(&"normal"), Color("8a3c3c"))
	level.add_child(bot)
	bot.respawn_at(at, yaw)
	return bot
