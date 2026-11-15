class_name CombatSuite
extends TestSuite
## Milestone 4: weapons, spread, recoil, damage, health, hitscan, crouch, death/respawn, targets.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const STEP: float = 1.0 / 60.0


func suite_name() -> String:
	return "Combat (Milestone 4)"


func run() -> void:
	_test_catalog()
	_test_damage_model()
	_test_fire_cadence()
	_test_ammo_and_reload()
	_test_spread()
	_test_recoil()
	_test_health()
	_test_hitscan_math()
	_test_tally()
	await _test_sandbox_combat()


func _rifle() -> WeaponDefinition:
	return WeaponCatalog.get_definition(WeaponCatalog.VANTA_RIFLE)


func _pistol() -> WeaponDefinition:
	return WeaponCatalog.get_definition(WeaponCatalog.KESTREL_PISTOL)


## Runs [param steps] fixed steps; returns all shot offsets.
func _run_steps(state: WeaponState, steps: int, trigger: bool, motion: ShooterMotion,
		rng: RandomNumberGenerator) -> Array[Vector2]:
	var all: Array[Vector2] = []
	for i: int in steps:
		all.append_array(state.update(STEP, trigger, motion, rng))
	return all


func _test_catalog() -> void:
	section("Weapon catalog")
	check(WeaponCatalog.ids().size() == 3, "three sandbox weapons defined")
	var slots: Dictionary[int, bool] = {}
	for id: StringName in WeaponCatalog.ids():
		var d := WeaponCatalog.get_definition(id)
		check(d != null and d.id == id and not d.display_name.is_empty(), "'%s' loads with a name" % id)
		slots[d.slot] = true
		check(d.recoil_kick(0) == Vector2.ZERO or not d.recoil_pattern.is_empty(), "'%s' has a recoil pattern" % id)
		if d.is_automatic():
			check(d.recoil_pattern.size() >= d.magazine_size, "'%s' pattern covers a full magazine" % id)
		check(d.damage > 0.0 and d.fire_interval > 0.0 and d.magazine_size > 0, "'%s' has sane stats" % id)
	check(slots.size() == 3, "each weapon uses its own slot")
	check(WeaponCatalog.get_definition(&"nope") == null, "unknown weapon id returns null")
	check(WeaponCatalog.get_definition(WeaponCatalog.VANTA_RIFLE) == _rifle(), "definitions are cached/shared")
	check(is_equal_approx(_rifle().rounds_per_minute(), 600.0), "rifle fires 600 rpm")


func _test_damage_model() -> void:
	section("Damage model")
	var rifle := _rifle()
	check(DamageModel.damage_for(rifle, DamageModel.ZONE_CHEST, 0.0) == 34, "rifle chest at 0 m = 34")
	check(DamageModel.damage_for(rifle, DamageModel.ZONE_HEAD, 0.0) == 136, "rifle head at 0 m = 136 (one-shot)")
	check(DamageModel.damage_for(rifle, DamageModel.ZONE_LEGS, 0.0) == 26, "rifle legs at 0 m = 26")
	check(DamageModel.damage_for(rifle, DamageModel.ZONE_STOMACH, 0.0) > DamageModel.damage_for(rifle, DamageModel.ZONE_CHEST, 0.0),
		"stomach hits harder than chest")
	check(DamageModel.damage_for(rifle, DamageModel.ZONE_CHEST, 20.0) == 32, "rifle chest at 20 m = 32 (falloff)")
	check(DamageModel.damage_for(_pistol(), DamageModel.ZONE_HEAD, 0.0) >= 100, "pistol headshot is lethal up close")
	var smg := WeaponCatalog.get_definition(WeaponCatalog.WASP_SMG)
	check(DamageModel.damage_for(smg, DamageModel.ZONE_CHEST, 40.0) < DamageModel.damage_for(rifle, DamageModel.ZONE_CHEST, 40.0),
		"SMG loses more damage at range than the rifle")
	check(DamageModel.damage_for(smg, DamageModel.ZONE_LEGS, 10000.0) >= 1, "damage never drops below 1")


func _test_fire_cadence() -> void:
	section("Fire cadence")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var motion := ShooterMotion.new()
	var rifle := WeaponState.new(_rifle())
	var shots := _run_steps(rifle, 60, true, motion, rng).size()
	check(shots >= 10 and shots <= 11, "rifle fires 10–11 shots in 1 s held (got %d)" % shots)
	var pistol := WeaponState.new(_pistol())
	check(_run_steps(pistol, 60, true, motion, rng).size() == 1, "semi-auto pistol fires once while held")
	_run_steps(pistol, 2, false, motion, rng)
	check(_run_steps(pistol, 1, true, motion, rng).size() == 1, "pistol fires again after releasing the trigger")
	check(_run_steps(pistol, 1, false, motion, rng).is_empty() and _run_steps(pistol, 1, true, motion, rng).is_empty(),
		"pistol respects its fire interval on fast clicks")


func _test_ammo_and_reload() -> void:
	section("Ammo and reload")
	var rng := RandomNumberGenerator.new()
	var motion := ShooterMotion.new()
	var rifle := WeaponState.new(_rifle())
	var fired := _run_steps(rifle, 240, true, motion, rng).size()
	check(fired == 30 and rifle.ammo == 0, "a held trigger empties exactly one magazine")
	check(not rifle.is_reloading(), "holding an empty trigger does not auto-reload")
	_run_steps(rifle, 1, false, motion, rng)
	rifle.update(STEP, true, motion, rng)
	check(rifle.is_reloading() and rifle.reload_started_this_step, "pressing the trigger on empty starts a reload")
	check(_run_steps(rifle, 60, true, motion, rng).is_empty(), "cannot fire while reloading")
	_run_steps(rifle, int(_rifle().reload_time / STEP) + 2, false, motion, rng)
	check(rifle.ammo == 30 and rifle.reserve == 60, "reload refills the magazine from reserve (30 / 60)")

	var partial := WeaponState.new(_rifle())
	_run_steps(partial, 30, true, motion, rng)
	var left := partial.ammo
	check(left < 30 and partial.start_reload(), "manual reload starts on a partial magazine")
	check(not partial.start_reload(), "reload cannot be started twice")
	var started := partial.update(STEP, false, motion, rng)
	check(started.is_empty() and partial.reload_started_this_step, "manual reload is reported on the next step")
	_run_steps(partial, int(_rifle().reload_time / STEP) + 2, false, motion, rng)
	check(partial.ammo == 30 and partial.reserve == 90 - (30 - left), "partial reload only takes what it needs")
	check(not WeaponState.new(_rifle()).can_reload(), "a full magazine cannot be reloaded")
	partial.reserve = 0
	partial.ammo = 3
	check(not partial.start_reload(), "no reload without reserve ammo")
	partial.start_reload()
	partial.cancel_reload()
	check(not partial.is_reloading(), "reload can be cancelled")


func _test_spread() -> void:
	section("Spread")
	var rifle := WeaponState.new(_rifle())
	var still := ShooterMotion.new()
	var running := ShooterMotion.new()
	running.speed = ShooterMotion.REFERENCE_SPEED
	var walking := ShooterMotion.new()
	walking.speed = 2.9
	var crouched := ShooterMotion.new()
	crouched.crouched = true
	var air := ShooterMotion.new()
	air.airborne = true
	check(is_equal_approx(rifle.current_spread(still), _rifle().base_spread), "standing still uses base spread")
	check(rifle.current_spread(running) > rifle.current_spread(walking) and rifle.current_spread(walking) > rifle.current_spread(still),
		"running > walking > standing spread")
	check(rifle.current_spread(crouched) < rifle.current_spread(still), "crouching tightens spread")
	check(rifle.current_spread(air) > rifle.current_spread(running), "airborne is least accurate")
	var smg := WeaponState.new(WeaponCatalog.get_definition(WeaponCatalog.WASP_SMG))
	check(smg.current_spread(running) < rifle.current_spread(running), "SMG is more accurate on the move than the rifle")

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var worst_first := 0.0
	var worst_running := 0.0
	for i: int in 200:
		var fresh := WeaponState.new(_rifle())
		worst_first = maxf(worst_first, fresh.update(STEP, true, still, rng)[0].length())
		var moving := WeaponState.new(_rifle())
		worst_running = maxf(worst_running, moving.update(STEP, true, running, rng)[0].length())
	check(worst_first <= _rifle().base_spread + 0.0001, "first shot standing stays inside base spread (max %.3f°)" % worst_first)
	check(worst_running > 2.0, "running first shots scatter widely (max %.2f°)" % worst_running)

	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1234
	b.seed = 1234
	var sa := _run_steps(WeaponState.new(_rifle()), 30, true, running, a)
	var sb := _run_steps(WeaponState.new(_rifle()), 30, true, running, b)
	check(sa == sb and not sa.is_empty(), "same seed produces identical shots (deterministic)")

	var bloomed := WeaponState.new(_rifle())
	_run_steps(bloomed, 30, true, still, rng)
	check(bloomed.bloom > 0.0 and bloomed.current_spread(still) > _rifle().base_spread, "sustained fire blooms spread")
	_run_steps(bloomed, 120, false, still, rng)
	check(is_zero_approx(bloomed.bloom), "bloom recovers when not firing")


func _test_recoil() -> void:
	section("Recoil")
	var rng := RandomNumberGenerator.new()
	var still := ShooterMotion.new()
	var rifle := WeaponState.new(_rifle())
	var shots := _run_steps(rifle, 60, true, still, rng)
	check(shots[0].length() <= _rifle().base_spread + 0.0001, "first bullet has no recoil")
	check(rifle.recoil_offset.y > 5.0, "a 10-shot spray climbs over 5° (%.1f°)" % rifle.recoil_offset.y)
	check(shots[shots.size() - 1].y > shots[1].y, "later bullets land higher than early ones")
	_run_steps(rifle, 120, false, still, rng)
	check(rifle.recoil_offset.is_zero_approx(), "recoil fully recovers after 2 s")
	var again := _run_steps(rifle, 1, true, still, rng)
	check(again[0].length() <= _rifle().base_spread + 0.0001, "after recovery the pattern restarts")

	var pattern_a := WeaponState.new(_rifle())
	var pattern_b := WeaponState.new(_rifle())
	_run_steps(pattern_a, 90, true, still, rng)
	_run_steps(pattern_b, 90, true, still, rng)
	check(pattern_a.recoil_offset.is_equal_approx(pattern_b.recoil_offset), "recoil pattern is fixed (not random)")


func _test_health() -> void:
	section("Health")
	var health := Health.new()
	tree.root.add_child(health)
	var damaged_count: Array[int] = [0]
	var died_count: Array[int] = [0]
	health.damaged.connect(func(_i: DamageInfo) -> void: damaged_count[0] += 1)
	health.died.connect(func(_i: DamageInfo) -> void: died_count[0] += 1)
	var hit := DamageInfo.new()
	hit.amount = 30
	check(health.apply_damage(hit) == 30 and health.current == 70, "damage reduces health")
	var big := DamageInfo.new()
	big.amount = 136
	check(health.apply_damage(big) == 70 and big.applied == 70, "applied damage is clamped to remaining health")
	check(health.is_dead and died_count[0] == 1 and health.last_death == big, "lethal damage kills once")
	var extra := DamageInfo.new()
	extra.amount = 10
	check(health.apply_damage(extra) == 0 and damaged_count[0] == 2, "dead targets ignore further damage")
	health.revive()
	check(not health.is_dead and health.current == 100, "revive restores full health")
	health.kill()
	check(health.is_dead and health.last_death.cause == DamageInfo.CAUSE_WORLD, "kill() uses world damage")
	health.free()


func _test_hitscan_math() -> void:
	section("Hitscan direction")
	var basis := Basis.IDENTITY
	check(Hitscan.offset_direction(basis, Vector2.ZERO).is_equal_approx(Vector3.FORWARD), "zero offset = forward")
	check(Hitscan.offset_direction(basis, Vector2(5, 0)).x > 0.05, "positive yaw offset goes right")
	check(Hitscan.offset_direction(basis, Vector2(0, 5)).y > 0.05, "positive pitch offset goes up")
	var turned := Basis(Vector3.UP, PI / 2.0)
	check(Hitscan.offset_direction(turned, Vector2.ZERO).is_equal_approx(Vector3.LEFT), "offset is relative to the shooter")


func _test_tally() -> void:
	section("Combat tally")
	var tally := CombatTally.new()
	for i: int in 4:
		tally.record_shot()
	var head := DamageInfo.new()
	head.zone = DamageModel.ZONE_HEAD
	head.applied = 100
	tally.record_hit(head, true)
	check(is_equal_approx(tally.accuracy(), 0.25) and is_equal_approx(tally.headshot_rate(), 1.0), "accuracy and headshot rate")
	check(tally.kills == 1 and tally.damage == 100, "kills and damage recorded")


func _test_sandbox_combat() -> void:
	section("Sandbox combat (scene)")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(40)
	var player := sandbox.get_node("Player") as FirstPersonController
	var level := sandbox.get_node("Level") as SandboxLevel
	var hud := sandbox.get_node("Hud") as SandboxHud
	var effects := sandbox.get_node("Effects") as WeaponEffects
	var tally := sandbox.get("tally") as CombatTally
	check(level.dummies.size() == 4, "arena spawns 4 target dummies from map markers")
	var strafers := level.dummies.filter(func(d: TargetDummy) -> bool: return d.motion == TargetDummy.MOTION_STRAFE)
	check(strafers.size() == 1, "one dummy strafes")
	check(effects.viewmodel != null and effects.viewmodel.get_parent() == player.camera, "viewmodel attached to the camera")
	player.input_enabled = false
	var weapons := player.weapons
	check(weapons.current().definition.id == WeaponCatalog.VANTA_RIFLE, "player starts with the rifle")

	var dummy := level.dummies[0]
	dummy.respawn_delay = 0.4
	var chest := dummy.zone_position(DamageModel.ZONE_CHEST)
	player.face_point(chest)
	await _fire_one(weapons)
	var distance := player.head.global_position.distance_to(chest)
	var expected := DamageModel.damage_for(weapons.current().definition, DamageModel.ZONE_CHEST, distance)
	check(absi((100 - dummy.health.current) - expected) <= 1,
		"chest shot at %.1f m deals ~%d damage (dummy at %d)" % [distance, expected, dummy.health.current])
	check(tally.shots == 1 and tally.hits == 1, "training tally records the shot and hit")
	check(weapons.current().ammo == 29, "one round used")

	await wait_physics_frames(40)
	player.face_point(dummy.zone_position(DamageModel.ZONE_HEAD))
	await _fire_one(weapons)
	check(dummy.health.is_dead, "headshot eliminates the dummy")
	check(tally.kills == 1 and tally.headshots == 1, "kill and headshot recorded")
	check(hud.feed_count() >= 1, "kill feed shows the elimination")
	var hitboxes_off := dummy.hitboxes.all(func(h: Hitbox) -> bool: return h.collision_layer == 0)
	check(hitboxes_off, "eliminated dummy cannot be hit")
	var revived := await wait_until(func() -> bool: return not dummy.health.is_dead, 2.0)
	check(revived and dummy.health.current == 100, "dummy stands back up with full health")
	check(dummy.hitboxes.all(func(h: Hitbox) -> bool: return h.collision_layer == Hitscan.LAYER_HITBOXES),
		"revived dummy is hittable again")

	await wait_physics_frames(40)
	var impacts_before := effects.impact_count
	var hits_before := tally.hits
	player.face_point(Vector3(0, 3.0, -30))
	await _fire_one(weapons)
	check(effects.impact_count == impacts_before + 1 and tally.hits == hits_before, "wall shot leaves an impact mark, no hit")

	check(weapons.select_slot(2) and weapons.current().definition.id == WeaponCatalog.KESTREL_PISTOL, "slot 2 selects the pistol")
	weapons.trigger = true
	await wait_physics_frames(2)
	weapons.trigger = false
	check(weapons.current().ammo == weapons.current().definition.magazine_size, "cannot fire during the draw time")
	weapons.select_slot(1)
	check(weapons.current().ammo == 27, "rifle keeps its ammo across switches")

	weapons.trigger = true
	player.input_enabled = false
	check(not weapons.trigger, "disabling input releases the trigger")

	# Crouch, including being unable to stand under a low ceiling.
	player.wants_crouch = true
	await wait_physics_frames(15)
	check(player.is_crouched() and player.head.position.y < 1.1, "crouch lowers the eye height")
	check(is_equal_approx(player.current_height(), FirstPersonController.CROUCH_HEIGHT), "crouch shrinks the collision capsule")
	check(weapons.motion.crouched, "weapons know the player is crouched")
	var ceiling := BlockBuilder.make_box(level, Vector3(3, 0.3, 3),
		player.global_position + Vector3(0, 1.5, 0), Color.GRAY)
	await wait_physics_frames(2)
	player.wants_crouch = false
	await wait_physics_frames(15)
	check(player.is_crouched(), "cannot stand up under a low ceiling")
	ceiling.free()
	await wait_physics_frames(15)
	check(not player.is_crouched() and is_equal_approx(player.current_height(), FirstPersonController.STAND_HEIGHT),
		"stands up once there is room")

	# Death and respawn.
	sandbox.set("respawn_delay", 0.3)
	weapons.current().ammo = 3
	player.health.kill()
	await wait_frames(2)
	check(bool(sandbox.call("is_awaiting_respawn")) and hud.death_overlay.visible, "death shows the eliminated overlay")
	var respawned := await wait_until(func() -> bool: return not player.health.is_dead, 2.0)
	check(respawned and player.health.current == 100, "player respawns with full health")
	check(weapons.current().ammo == weapons.current().definition.magazine_size, "respawn refills ammo")
	check(not hud.death_overlay.visible, "death overlay hidden after respawn")
	await despawn(sandbox)


## Pulls the trigger for exactly one physics step (one rifle/pistol shot).
func _fire_one(weapons: WeaponController) -> void:
	await wait_physics_frames(1)
	weapons.trigger = true
	await wait_physics_frames(1)
	weapons.trigger = false
	await wait_physics_frames(1)
