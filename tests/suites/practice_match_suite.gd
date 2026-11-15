class_name PracticeMatchSuite
extends TestSuite
## Milestone 5 (scene): a full practice match in the FPS runtime — buying, kills, plant and
## detonation, half-time switch, death without mid-round respawn, defuse, match end.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Practice match (Milestone 5)"


func run() -> void:
	var app := tree.root.get_node("App")
	var setup := MatchSetup.new()
	setup.fixture_id = "practice_test"
	setup.home_team_id = "team_you"
	setup.home_team_name = "You"
	setup.away_team_id = "team_targets"
	setup.away_team_name = "Targets"
	setup.max_rounds = 2
	var rules := MatchRules.practice(2)
	rules.team_size = 2
	rules.freeze_time = 0.4
	rules.round_time = 2.5
	rules.round_end_delay = 0.4
	rules.bomb_timer = 1.0
	rules.plant_time = 0.3
	rules.defuse_time = 0.4
	var map := MapTemplates.sandbox_arena()
	setup.map_id = map.map_id
	app.set("pending_match_setup", setup)
	app.set("pending_match_rules", rules)
	app.set("pending_match_map", map)

	section("Practice match: setup")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	check(not bool(app.call("has_pending_match")), "runtime consumed the pending match")
	var director := sandbox.get("match_director") as MatchDirector
	check(director != null, "match director created")
	if director == null:
		await despawn(sandbox)
		return
	var state := director.state
	var player := sandbox.get_node("Player") as FirstPersonController
	var level := sandbox.get_node("Level") as SandboxLevel
	var sandbox_hud := sandbox.get_node("Hud") as SandboxHud
	player.input_enabled = false
	check(level.dummies.is_empty(), "no training dummies in match mode")
	check(director.combatants.size() == 2, "two passive combatants spawned")
	check(state.phase == MatchState.Phase.FREEZE and state.round_number == 1, "round 1 freeze time")
	check(player.frozen, "player is frozen during freeze time")
	check(player.weapons.loadout_ids() == [WeaponCatalog.KESTREL_PISTOL], "player starts with the pistol only")
	check(director.human_side() == MatchRules.SIDE_ATTACK and state.bomb_carrier_id == MatchDirector.HUMAN_ID,
		"player attacks first and carries the bomb")
	var defence_spawn := level.spawn_points("defence")[0][0] as Vector3
	var any_dummy: TargetDummy = director.combatants.values()[0]
	check(any_dummy.global_position.distance_to(defence_spawn) < 4.0, "combatants stand at the defence spawns")

	section("Practice match: buying")
	check(director.can_open_buy_menu(), "buy menu available at spawn during freeze")
	director.open_buy_menu()
	check(director.is_buy_menu_open() and director.hud.buy_buttons().size() == ShopCatalog.item_ids().size(),
		"buy menu lists every shop item")
	check(director.try_buy(ShopCatalog.ARMOUR_VEST) == "" and player.health.armour == 100, "buying a vest equips armour")
	check(director.try_buy(WeaponCatalog.VANTA_RIFLE) == "not enough money", "cannot afford the rifle on round 1")
	director.close_buy_menu()
	player.input_enabled = false
	check(not director.is_buy_menu_open(), "buy menu closes")

	section("Practice match: round 1 elimination")
	var live := await wait_until(func() -> bool: return state.phase == MatchState.Phase.LIVE, 2.0)
	check(live and not player.frozen, "round goes live and the player can move")
	for dummy: TargetDummy in director.combatants.values():
		_shoot(dummy.health, WeaponCatalog.KESTREL_PISTOL)
	check(state.phase == MatchState.Phase.ROUND_END and state.teams[MatchState.HOME].score == 1,
		"eliminating the defenders wins round 1")
	check(director.hud.banner_text().contains("ATTACKERS WIN"), "round result banner shown")
	check(director.human().money == 900 - 650 + 2 * 300 + rules.win_rewards[MatchRules.REASON_ELIMINATION],
		"money: start − vest + 2 kills + win reward")

	section("Practice match: round 2 plant and detonation")
	var round_two := await wait_until(func() -> bool: return state.round_number == 2 and state.phase == MatchState.Phase.LIVE, 3.0)
	check(round_two, "round 2 starts and goes live")
	check(player.health.armour == 100, "surviving player keeps the vest")
	player.global_position = Vector3(-18, 0.05, -18)
	await wait_physics_frames(4)
	check(MapZones.bombsite_at(level.document, player.global_position) == "B", "player stands on bombsite B")
	check(director.hud.hint_text().contains("plant"), "plant hint shown on the site")
	var money_before := director.human().money
	director.interact_held = true
	await wait_physics_frames(3)
	check(director.plant_progress > 0.0 and player.frozen, "holding interact plants (player frozen)")
	var planted := await wait_until(func() -> bool: return state.is_bomb_planted, 2.0)
	director.interact_held = false
	check(planted and director.bomb != null and director.bomb.planted, "bomb planted and placed in the world")
	check(director.human().money == money_before + rules.plant_bonus, "plant bonus paid")
	var detonated := await wait_until(func() -> bool: return state.phase == MatchState.Phase.ROUND_END, 3.0)
	check(detonated and state.last_round_reason == MatchRules.REASON_DETONATED and state.teams[MatchState.HOME].score == 2,
		"detonation wins round 2")

	section("Practice match: half time, death, defuse, end")
	var round_three := await wait_until(func() -> bool: return state.round_number == 3, 3.0)
	check(round_three and director.human_side() == MatchRules.SIDE_DEFENCE, "sides switch at half time")
	check(director.human().money == rules.start_money and player.health.armour == 0, "money and armour reset at half time")
	check(player.global_position.distance_to(defence_spawn) < 3.0, "player respawns at the defence spawn")
	await wait_until(func() -> bool: return state.phase == MatchState.Phase.LIVE, 2.0)
	player.health.kill()
	await wait_frames(2)
	check(state.teams[MatchState.AWAY].score == 1 and state.last_round_reason == MatchRules.REASON_ELIMINATION,
		"dying alone on defence loses the round")
	check(not bool(sandbox.call("is_awaiting_respawn")) and sandbox_hud.death_overlay.visible,
		"no mid-round respawn in a match; death message shown")
	var round_four := await wait_until(func() -> bool: return state.round_number == 4 and state.phase == MatchState.Phase.LIVE, 3.0)
	check(round_four and not player.health.is_dead, "player is back for round 4")
	var carrier := state.bomb_carrier_id
	var near := player.global_position + Vector3(0.8, 0, 0)
	check(state.plant_bomb(carrier, near), "a combatant plant is simulated next to the player")
	await wait_physics_frames(2)
	check(director.bomb != null and director.hud.hint_text().contains("defuse"), "defuse hint shown near the bomb")
	director.interact_held = true
	var finished := await wait_until(func() -> bool: return state.phase == MatchState.Phase.MATCH_END, 2.0)
	director.interact_held = false
	check(finished and state.teams[MatchState.HOME].score == 3, "defusing wins the deciding round (3–1)")
	var result := app.get("last_match_result") as MatchResult
	check(result != null and result.home_score == 3 and result.away_score == 1 and result.validate() == "",
		"a valid MatchResult is produced")
	check(director.hud.end_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"match-end screen shown with a free cursor")
	check(director.hud.play_again_button.pressed.get_connections().size() > 0, "play again is wired")
	await despawn(sandbox)


## Applies one lethal-or-not hit from the local player to [param target].
func _shoot(target: Health, weapon: StringName) -> void:
	var info := DamageInfo.new()
	info.amount = 200
	info.zone = DamageModel.ZONE_HEAD
	info.weapon_id = weapon
	info.source_id = MatchDirector.HUMAN_ID
	target.apply_damage(info)
