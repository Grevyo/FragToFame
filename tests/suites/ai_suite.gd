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
	await _test_world()


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
	player.weapons.set_loadout([WeaponCatalog.VANTA_RIFLE])
	bot.weapons.set_loadout([WeaponCatalog.VANTA_RIFLE])
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
	bot.respawn_at(b_start, 0.0)
	check(bot.movement.stamina == 0.0 and bot.velocity == Vector3.ZERO and not bot.is_crouched(),
		"bot respawn clears locomotion state")
	await despawn(sandbox)


func _same_movement(player: FirstPersonController, bot: BotController) -> bool:
	return (player.velocity.is_equal_approx(bot.velocity)
		and absf(player.global_position.y - bot.global_position.y) < 0.001
		and is_equal_approx(player.movement.stamina, bot.movement.stamina))


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


func _spawn_bot(level: SandboxLevel, id: String, team_key: StringName, at: Vector3, yaw: float) -> BotController:
	var bot := BotController.new()
	bot.setup(id, id, team_key, BotSkill.preset(&"normal"), Color("8a3c3c"))
	level.add_child(bot)
	bot.respawn_at(at, yaw)
	return bot
