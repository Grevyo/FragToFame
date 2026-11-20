extends TestSuite
## Utility (frag, flashbang, smoke, incendiary) and the knife: data, rules, statistics, grenade
## flight and every effect in the FPS runtime.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const HUMAN: String = "h1"


func suite_name() -> String:
	return "Utility and knife"


func run() -> void:
	_test_catalog()
	_test_flash_maths()
	_test_rules()
	_test_statistics()
	await _test_runtime()


func _test_catalog() -> void:
	section("Equipment data")
	var knife := WeaponCatalog.get_definition(EquipmentCatalog.KNIFE)
	check(knife != null and knife.is_melee() and not knife.is_firearm() and knife.slot == 3, "the knife is a melee weapon in slot 3")
	var all_utility := EquipmentCatalog.UTILITY.all(func(id: StringName) -> bool:
		var definition := WeaponCatalog.get_definition(id)
		return definition != null and definition.is_utility() and definition.slot == EquipmentCatalog.UTILITY_SLOT \
			and ShopCatalog.kind(id) == ShopCatalog.KIND_UTILITY and ShopCatalog.price(id) > 0)
	check(EquipmentCatalog.UTILITY.size() == 4 and all_utility, "four kinds of utility, each in the shop and slot 4")
	check(EquipmentCatalog.carry_limit(EquipmentCatalog.FLASH) == 2 and EquipmentCatalog.carry_limit(EquipmentCatalog.SMOKE) == 1,
		"two flashbangs, one of everything else")
	check(WeaponCatalog.ids().size() == 10 and not WeaponCatalog.ids().has(EquipmentCatalog.KNIFE),
		"the firearm list is unchanged")
	check(WeaponCatalog.recorded_name(EquipmentCatalog.FRAG) == "Frag grenade", "utility has names for the kill feed and stats")
	check(ShopCatalog.kill_reward(EquipmentCatalog.KNIFE) > ShopCatalog.kill_reward(WeaponCatalog.AK47),
		"a knife kill pays more than a rifle kill")
	var velocity := GrenadeFlight.throw_velocity(Vector3.FORWARD, 10.0, Vector3(2, 0, 0))
	check(velocity.y > 0.5 and velocity.x > 1.9, "throws leave above the crosshair and carry the thrower's speed")


func _test_flash_maths() -> void:
	section("Flash blindness")
	var params := EquipmentCatalog.params(EquipmentCatalog.FLASH)
	var at := Vector3(0, 1.6, -4)
	var eye := Vector3(0, 1.6, 0)
	var facing := UtilityField.flash_seconds(params, at, eye, Vector3.FORWARD)
	var sideways := UtilityField.flash_seconds(params, at, eye, Vector3.RIGHT)
	var away := UtilityField.flash_seconds(params, at, eye, Vector3.BACK)
	check(is_equal_approx(facing, float(params["max_blind"])), "looking at a close flash blinds fully (%.2f s)" % facing)
	check(facing > sideways and sideways > away and away > 0.0, "turning away helps (%.2f / %.2f / %.2f s)" % [facing, sideways, away])
	var far := UtilityField.flash_seconds(params, Vector3(0, 1.6, -18), eye, Vector3.FORWARD)
	check(far < facing and far > 0.0, "a distant flash blinds for less (%.2f s)" % far)
	check(UtilityField.flash_seconds(params, Vector3(0, 1.6, -40), eye, Vector3.FORWARD) == 0.0, "out of range does nothing")


func _test_rules() -> void:
	section("Utility in the match rules")
	var state := _state()
	state.start()
	var human := state.get_player(HUMAN)
	human.money = 6000
	check(state.buy(HUMAN, EquipmentCatalog.FLASH) == "" and state.buy(HUMAN, EquipmentCatalog.FLASH) == "", "buys two flashbangs")
	check(not state.buy(HUMAN, EquipmentCatalog.FLASH).is_empty(), "a third flashbang is refused")
	check(state.buy(HUMAN, EquipmentCatalog.SMOKE) == "" and state.buy(HUMAN, EquipmentCatalog.FRAG) == "", "adds a smoke and a frag")
	check(not state.buy(HUMAN, EquipmentCatalog.FIRE).is_empty(), "a fifth piece of utility is refused")
	check(human.loadout() == [WeaponCatalog.G17, EquipmentCatalog.KNIFE, EquipmentCatalog.FLASH, EquipmentCatalog.FLASH,
		EquipmentCatalog.SMOKE, EquipmentCatalog.FRAG], "the loadout carries the pistol, knife and utility")
	_go_live(state)
	state.record_throw(HUMAN, EquipmentCatalog.FLASH)
	check(human.utility_count(EquipmentCatalog.FLASH) == 1 and _has_event(state, "utility_thrown"), "a throw uses one up and is logged")
	state.record_flash(HUMAN, "a1", 2.5)
	check(_has_event(state, "flashed"), "a flash on an enemy is logged")
	var reward_before := human.money
	state.record_kill("a1", HUMAN, EquipmentCatalog.KNIFE, false)
	check(human.money - reward_before == ShopCatalog.kill_reward(EquipmentCatalog.KNIFE), "knife kills pay the knife reward")
	state.record_kill("a2", HUMAN, WeaponCatalog.G17, false)
	_finish_round(state)
	check(human.utility == [EquipmentCatalog.FLASH, EquipmentCatalog.SMOKE, EquipmentCatalog.FRAG],
		"a survivor keeps unused utility into the next round")
	_go_live(state)
	state.record_kill(HUMAN, "a1", WeaponCatalog.G17, false)
	_finish_round(state)
	check(human.utility.is_empty() and human.loadout() == [WeaponCatalog.G17, EquipmentCatalog.KNIFE], "dying loses utility")


func _test_statistics() -> void:
	section("Utility statistics")
	var result := MatchResult.create("utility_stats", 1, 0, MatchResult.SOURCE_FPS_RUNTIME)
	result.events = [
		{"type": "match_started", "fixture_id": result.fixture_id, "lineup": {"a": 0, "b": 0, "c": 1, "d": 1}},
		{"type": "round_started", "round": 1},
		{"type": "utility_thrown", "player": "a", "item": "utl_flash", "round": 1, "t": 1.0},
		{"type": "flashed", "player": "a", "victim": "c", "seconds": 3.0, "enemy": true, "round": 1, "t": 2.0},
		{"type": "flashed", "player": "a", "victim": "b", "seconds": 3.0, "enemy": false, "round": 1, "t": 2.0},
		{"type": "kill", "killer": "b", "victim": "c", "weapon": "wpn_g17", "round": 1, "t": 3.5},
		{"type": "utility_thrown", "player": "a", "item": "utl_frag", "round": 1, "t": 4.0},
		{"type": "damage", "player": "a", "victim": "d", "hp": 60, "weapon": "utl_frag", "utility": true, "round": 1, "t": 5.6},
		{"type": "damage", "player": "b", "victim": "d", "hp": 40, "weapon": "wpn_g17", "round": 1, "t": 6.0},
		{"type": "kill", "killer": "b", "victim": "d", "weapon": "wpn_g17", "round": 1, "t": 6.0},
		{"type": "round_ended", "round": 1, "winner_team": 0},
		{"type": "match_ended", "round": 1},
	]
	var lines := MatchStatistics.calculate(result)
	if lines.is_empty():
		check(false, "the utility match reduces")
		return
	var a := lines["a"]
	check(a["utility_thrown"] == 2 and a["enemies_flashed"] == 1, "counts throws and enemies flashed (not teammates)")
	check(a["flash_assists"] == 1 and a["kast_rounds"] == 1, "a flash assist counts toward KAST")
	check(a["utility_damage"] == 60 and a["damage"] == 60 and a["hits"] == 0 and a["assists"] == 1,
		"frag damage counts as damage and toward assists, never as a bullet hit")


func _test_runtime() -> void:
	section("Utility and knife in the FPS runtime (scene)")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(30)
	var player := sandbox.get_node("Player") as FirstPersonController
	var level := sandbox.get_node("Level") as SandboxLevel
	var hud := sandbox.get_node("Hud") as SandboxHud
	var effects := sandbox.get_node("Effects") as WeaponEffects
	var field := level.utility
	player.input_enabled = false
	var weapons := player.weapons
	check(field != null and UtilityField.find(player) == field, "every level has a utility field")
	for dummy: TargetDummy in level.dummies:
		dummy.respawn_delay = 60.0
		dummy.motion = TargetDummy.MOTION_STATIC

	# Knife: a slash from the front, a stab from behind.
	var dummy := level.dummies[0]
	var forward := -dummy.global_basis.z
	check(weapons.select_slot(3) and weapons.current().definition.is_melee(), "slot 3 is the knife")
	player.set_spawn(dummy.global_position + forward * 1.1, 0.0)
	player.face_point(dummy.zone_position(DamageModel.ZONE_CHEST))
	await wait_physics_frames(30)
	await _press(weapons, false)
	var slash := int(EquipmentCatalog.params(EquipmentCatalog.KNIFE)["light"]["damage"])
	check(dummy.health.current == 100 - slash, "a slash from the front deals %d (dummy at %d)" % [slash, dummy.health.current])
	player.set_spawn(dummy.global_position - forward * 1.1, 0.0)
	player.face_point(dummy.zone_position(DamageModel.ZONE_CHEST))
	await wait_physics_frames(65)
	await _press(weapons, true)
	check(dummy.health.is_dead, "a stab in the back kills")

	# Grenade flight is deterministic.
	var space := player.get_world_3d().direct_space_state
	var start := player.head.global_position
	var throw := GrenadeFlight.throw_velocity(-player.head.global_basis.z, EquipmentCatalog.THROW_SPEED_FULL, Vector3.ZERO)
	var first := GrenadeFlight.predict(space, start, throw, 6.0, weapons.exclude)
	var second := GrenadeFlight.predict(space, start, throw, 6.0, weapons.exclude)
	check(first.size() > 10 and first == second, "the same throw always takes the same path (%d steps)" % first.size())
	var lob := GrenadeFlight.predict(space, start, GrenadeFlight.throw_velocity(Vector3(0, 0, -1), EquipmentCatalog.THROW_SPEED_LOB, Vector3.ZERO), 8.0)
	var landed := lob[lob.size() - 1]
	check(landed.y < start.y - 1.0 and landed.distance_to(start) < 12.0,
		"a lob comes to rest on the floor nearby (%s from %s, %d steps)" % [landed, start, lob.size()])

	# Throwing from the hand.
	weapons.give_utility(EquipmentCatalog.SMOKE)
	weapons.give_utility(EquipmentCatalog.FLASH)
	weapons.give_utility(EquipmentCatalog.FLASH)
	check(weapons.utility_counts() == {EquipmentCatalog.FLASH: 2, EquipmentCatalog.SMOKE: 1}, "carries two flashes and a smoke")
	weapons.select_slot(1)
	check(weapons.select_slot(EquipmentCatalog.UTILITY_SLOT) and weapons.current().definition.id == EquipmentCatalog.FLASH,
		"slot 4 picks the first utility")
	check(weapons.select_slot(EquipmentCatalog.UTILITY_SLOT) and weapons.current().definition.id == EquipmentCatalog.SMOKE,
		"slot 4 again moves on to the smoke")
	await wait_physics_frames(1)
	check(effects.utility_model != null, "the grenade is shown in the hand")
	player.face_point(player.head.global_position + Vector3(0, 0.3, -5))
	await wait_physics_frames(40)
	weapons.trigger = true
	await wait_physics_frames(3)
	check(field.grenades.is_empty() and weapons.is_throw_readied(), "holding the button readies the throw")
	weapons.trigger = false
	await wait_physics_frames(2)
	check(field.grenades.size() == 1 and weapons.utility_count(EquipmentCatalog.SMOKE) == 0, "letting go throws it")
	check(weapons.current().definition.id == WeaponCatalog.AK47, "the last smoke thrown returns to the rifle")
	await wait_physics_frames(5)
	check(hud.utility_text().contains("Flashbang"), "the HUD lists the utility carried (%s)" % hud.utility_text())
	field.clear()

	# Smoke blocks sight once it has bloomed, but not bullets.
	var floor_point := player.global_position + Vector3(0, 0, -8)
	field.throw(EquipmentCatalog.SMOKE, floor_point + Vector3(0, 0.3, 0), Vector3.ZERO, "test", &"")
	var eye_a := floor_point + Vector3(0, 1.6, 6)
	var eye_b := floor_point + Vector3(0, 1.6, -6)
	check(not field.blocks_sight(eye_a, eye_b), "no smoke before it pops")
	var bloomed := await wait_until(func() -> bool: return field.blocks_sight(eye_a, eye_b), 4.0)
	check(bloomed and field.smokes.size() == 1, "the smoke blocks the view through it")
	check(not field.blocks_sight(eye_a + Vector3(12, 0, 0), eye_b + Vector3(12, 0, 0)), "a line beside the cloud is clear")
	await wait_seconds(1.0)
	check(field.smoke_cover(floor_point + Vector3(0, 1.5, 0)) > 0.5, "inside the cloud the view is covered")
	# Fire under the smoke never lights; fire beside it does, and a new smoke puts it out.
	field.throw(EquipmentCatalog.FIRE, floor_point + Vector3(0, 0.5, 0), Vector3.ZERO, "test", &"")
	await wait_physics_frames(20)
	check(field.fires.is_empty(), "an incendiary landing in smoke fizzles")
	field.clear()

	# Frag: damage falls with distance; walls block it.
	var target := level.dummies[1]
	var target_feet := target.global_position
	field.throw(EquipmentCatalog.FRAG, target_feet + Vector3(1.5, 0.2, 0), Vector3.ZERO, "test", &"")
	await wait_physics_frames(120)
	var frag_damage := 100 - target.health.current
	check(frag_damage > 30 and frag_damage < 100, "a frag 1.5 m away hurts (%d)" % frag_damage)
	var shielded := level.dummies[2]
	var wall := BlockBuilder.make_box(level, Vector3(0.4, 3.0, 3.0), shielded.global_position + Vector3(1.0, 1.5, 0), Color.GRAY)
	await wait_physics_frames(2)
	field.throw(EquipmentCatalog.FRAG, shielded.global_position + Vector3(1.8, 0.2, 0), Vector3.ZERO, "test", &"")
	await wait_physics_frames(120)
	check(shielded.health.current == 100, "a wall between the blast and the target stops it")

	# Flash: blinds someone looking at it; not through a wall.
	player.set_spawn(shielded.global_position + Vector3(4.0, 0, 0), 0.0)
	await wait_physics_frames(5)
	player.face_point(shielded.global_position + Vector3(0.4, 1.0, 0))
	field.throw(EquipmentCatalog.FLASH, shielded.global_position + Vector3(0.4, 1.0, 0), Vector3.ZERO, "test", &"")
	await wait_physics_frames(110)
	check(player.blind_amount() == 0.0, "a flash behind a wall never blinds")
	wall.free()
	await wait_physics_frames(2)
	var flashes: Array[float] = []
	field.combatant_flashed.connect(func(_by: String, _victim: String, seconds: float) -> void: flashes.append(seconds))
	field.throw(EquipmentCatalog.FLASH, player.head.global_position + (-player.head.global_basis.z) * 3.0, Vector3.ZERO, "test", &"")
	await wait_physics_frames(110)
	check(player.blind_amount() > 0.9 and not flashes.is_empty(), "looking at a flash blinds (%.1f s)" % (flashes[0] if not flashes.is_empty() else 0.0))
	await wait_frames(2)
	check(hud.vision().x > 0.9, "the screen goes white")
	var cleared := await wait_until(func() -> bool: return player.blind_amount() == 0.0, 7.0)
	check(cleared, "sight comes back")

	# Incendiary: burns the floor and anyone standing in it.
	var burning := level.dummies[3]
	field.throw(EquipmentCatalog.FIRE, burning.global_position + Vector3(0, 0.6, 0), Vector3.ZERO, "test", &"")
	await wait_physics_frames(90)
	check(field.fires.size() == 1 and field.fires[0].patches.size() >= 8, "the fire spreads over the floor (%d patches)" % (field.fires[0].patches.size() if not field.fires.is_empty() else 0))
	check(field.is_burning(burning.global_position), "the target stands in the fire")
	check(burning.health.current < 100, "fire burns the target (%d)" % burning.health.current)
	field.throw(EquipmentCatalog.SMOKE, burning.global_position + Vector3(0, 0.3, 0), Vector3.ZERO, "test", &"")
	var out := await wait_until(func() -> bool: return field.fires.is_empty(), 4.0)
	check(out, "a smoke puts the fire out")
	field.clear()
	check(not field.is_active(), "clearing removes every grenade, smoke and fire")
	await despawn(sandbox)


## Presses and releases the knife's left (or right) button for one swing.
func _press(weapons: WeaponController, heavy: bool) -> void:
	await wait_physics_frames(1)
	if heavy:
		weapons.secondary_trigger = true
	else:
		weapons.trigger = true
	await wait_physics_frames(1)
	weapons.trigger = false
	weapons.secondary_trigger = false
	await wait_physics_frames(2)


func _state() -> MatchState:
	var setup := MatchSetup.new()
	setup.fixture_id = "utility_rules"
	setup.max_rounds = 3
	var state := MatchState.new(setup, MatchRules.competitive())
	state.add_player(HUMAN, "Human", MatchState.HOME, true)
	state.add_player("a1", "A1", MatchState.AWAY)
	state.add_player("a2", "A2", MatchState.AWAY)
	return state


func _go_live(state: MatchState) -> void:
	while state.phase == MatchState.Phase.FREEZE:
		state.tick(0.5)


func _finish_round(state: MatchState) -> void:
	while state.phase == MatchState.Phase.ROUND_END:
		state.tick(0.5)


func _has_event(state: MatchState, type: String) -> bool:
	return state.events.any(func(event: Dictionary) -> bool: return event.get("type") == type)
