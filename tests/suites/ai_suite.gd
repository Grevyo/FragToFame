class_name AiSuite
extends TestSuite
## Milestone 6: aim model, skills, navmesh baking, bot navigation, perception, combat, teams.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Bot AI (Milestone 6)"


func run() -> void:
	_test_aim_model()
	_test_skills()
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
