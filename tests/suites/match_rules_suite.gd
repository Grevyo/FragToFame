class_name MatchRulesSuite
extends TestSuite
## Milestone 5 (pure logic): armour, shop, rounds, economy, bomb, sides, overtime, result.

const HUMAN: String = "ply_human"


func suite_name() -> String:
	return "Match rules (Milestone 5)"


func run() -> void:
	_test_armour()
	_test_weapon_loadout_api()
	_test_round_flow_and_timers()
	_test_economy_and_buying()
	_test_bomb()
	_test_halves_and_result()
	_test_overtime()
	_test_event_log()


## A 2v2 match: home = human + h2, away = a1 + a2. Home attacks first.
func _make_match(mr: int = 3) -> MatchState:
	var setup := MatchSetup.new()
	setup.fixture_id = "fix_test"
	setup.home_team_id = "team_home"
	setup.home_team_name = "Home"
	setup.away_team_id = "team_away"
	setup.away_team_name = "Away"
	setup.max_rounds = mr
	setup.map_id = "map_test"
	var rules := MatchRules.practice(mr)
	rules.freeze_time = 1.0
	rules.round_time = 10.0
	rules.buy_time = 2.0
	rules.round_end_delay = 1.0
	rules.bomb_timer = 5.0
	var state := MatchState.new(setup, rules)
	state.add_player(HUMAN, "You", MatchState.HOME, true)
	state.add_player("h2", "Home 2", MatchState.HOME)
	state.add_player("a1", "Away 1", MatchState.AWAY)
	state.add_player("a2", "Away 2", MatchState.AWAY)
	return state


func _go_live(state: MatchState) -> void:
	state.tick(state.rules.freeze_time + 0.01)


func _finish_round_end(state: MatchState) -> void:
	state.tick(state.rules.round_end_delay + 0.01)


## Wins the current round for [param team_index] by eliminating the other team.
func _win_round(state: MatchState, team_index: int) -> void:
	if state.phase == MatchState.Phase.FREEZE:
		_go_live(state)
	var killer: String = state.teams[team_index].player_ids[0]
	for id: String in state.teams[1 - team_index].player_ids:
		state.record_kill(id, killer, WeaponCatalog.VANTA_RIFLE, false)
	_finish_round_end(state)


func _test_armour() -> void:
	section("Armour")
	var rifle := WeaponCatalog.get_definition(WeaponCatalog.VANTA_RIFLE)
	check(DamageModel.armour_split(34, rifle.armour_penetration, DamageModel.ZONE_CHEST, 0, false) == [34, 0],
		"no armour: full damage")
	var chest := DamageModel.armour_split(34, rifle.armour_penetration, DamageModel.ZONE_CHEST, 100, false)
	check(chest[0] == 27 and chest[1] == 4, "vest: rifle chest 34 → 27 health, 4 armour (%s)" % str(chest))
	check(DamageModel.armour_split(136, rifle.armour_penetration, DamageModel.ZONE_HEAD, 100, false)[0] == 136,
		"vest without helmet does not protect the head")
	check(DamageModel.armour_split(136, rifle.armour_penetration, DamageModel.ZONE_HEAD, 100, true)[0] == 106,
		"helmet reduces a rifle headshot to 106 (still lethal)")
	var pistol := WeaponCatalog.get_definition(WeaponCatalog.KESTREL_PISTOL)
	check(DamageModel.armour_split(120, pistol.armour_penetration, DamageModel.ZONE_HEAD, 100, true)[0] == 60,
		"helmet saves you from a pistol headshot")
	check(DamageModel.armour_split(26, rifle.armour_penetration, DamageModel.ZONE_LEGS, 100, true)[1] == 0,
		"legs are never protected")
	check(DamageModel.armour_split(34, 1.0, DamageModel.ZONE_CHEST, 100, true) == [34, 0], "world damage ignores armour")

	var health := Health.new()
	tree.root.add_child(health)
	health.armour = 3
	var hit := DamageInfo.new()
	hit.amount = 34
	hit.zone = DamageModel.ZONE_CHEST
	hit.armour_penetration = rifle.armour_penetration
	health.apply_damage(hit)
	check(health.armour == 0 and hit.armour_damage == 3 and health.current == 73, "armour points cannot go negative")
	health.free()


func _test_weapon_loadout_api() -> void:
	section("Weapon loadout")
	var weapons := WeaponController.new()
	weapons.set_loadout([WeaponCatalog.DEFAULT_SECONDARY])
	check(weapons.loadout_ids() == [WeaponCatalog.KESTREL_PISTOL], "match loadout starts with the sidearm")
	check(weapons.give_weapon(WeaponCatalog.WASP_SMG) and weapons.current().definition.id == WeaponCatalog.WASP_SMG,
		"buying a primary equips it")
	weapons.give_weapon(WeaponCatalog.VANTA_RIFLE)
	check(weapons.loadout_ids() == [WeaponCatalog.VANTA_RIFLE, WeaponCatalog.KESTREL_PISTOL],
		"a new primary replaces the old one (rifle, pistol)")
	check(weapons.draw_remaining > 0.0, "newly given weapon has a draw time")
	check(not weapons.give_weapon(&"nope"), "unknown weapon is rejected")
	weapons.free()


func _test_round_flow_and_timers() -> void:
	section("Round flow")
	var state := _make_match()
	check(state.phase == MatchState.Phase.WAITING, "match waits until started")
	state.start()
	check(state.phase == MatchState.Phase.FREEZE and state.round_number == 1, "round 1 starts in freeze time")
	check(state.teams[MatchState.HOME].side == MatchRules.SIDE_ATTACK, "home attacks first")
	check(state.bomb_carrier_id == HUMAN, "the human attacker carries the bomb")
	check(state.get_player(HUMAN).loadout() == [WeaponCatalog.KESTREL_PISTOL], "everyone starts with a pistol")
	check(not state.record_kill("a1", HUMAN, WeaponCatalog.KESTREL_PISTOL, false), "no kills during freeze time")
	_go_live(state)
	check(state.phase == MatchState.Phase.LIVE, "freeze ends and the round goes live")
	state.tick(state.rules.round_time)
	check(state.phase == MatchState.Phase.ROUND_END and state.last_round_reason == MatchRules.REASON_TIME,
		"round clock running out ends the round")
	check(state.last_round_winner == MatchState.AWAY, "time running out (no plant) is a defence win")
	_finish_round_end(state)
	check(state.phase == MatchState.Phase.FREEZE and state.round_number == 2, "next round starts after the delay")

	_go_live(state)
	state.record_kill("a1", HUMAN, WeaponCatalog.KESTREL_PISTOL, true)
	check(state.phase == MatchState.Phase.LIVE, "round continues while both teams have players")
	state.record_kill("a2", "h2", WeaponCatalog.KESTREL_PISTOL, false)
	check(state.phase == MatchState.Phase.ROUND_END and state.last_round_winner == MatchState.HOME
		and state.last_round_reason == MatchRules.REASON_ELIMINATION, "eliminating the defence wins for attack")
	check(state.get_player(HUMAN).kills == 1 and state.get_player("a1").deaths == 1, "kills and deaths counted")
	check(state.record_kill("a1", HUMAN, WeaponCatalog.KESTREL_PISTOL, false) == false,
		"kills on already-dead players are ignored")
	_finish_round_end(state)

	_go_live(state)
	state.record_kill(HUMAN, "a1", WeaponCatalog.KESTREL_PISTOL, false)
	state.record_kill("h2", "", &"", false)
	check(state.last_round_winner == MatchState.AWAY and state.last_round_reason == MatchRules.REASON_ELIMINATION,
		"eliminating the attack (no plant) wins for defence; world deaths count")


func _test_economy_and_buying() -> void:
	section("Economy and buying")
	var state := _make_match()
	state.start()
	var human := state.get_player(HUMAN)
	check(human.money == state.rules.start_money, "everyone starts with the start money")
	check(state.can_buy(HUMAN), "buying allowed in freeze time")
	check(state.buy(HUMAN, WeaponCatalog.VANTA_RIFLE) == "not enough money", "cannot buy what you cannot afford")
	check(state.buy(HUMAN, ShopCatalog.ARMOUR_VEST) == "" and human.armour == 100 and human.money == 250,
		"vest bought: 900 − 650 = 250")
	check(state.buy(HUMAN, ShopCatalog.ARMOUR_VEST) == "already owned", "cannot buy the same armour twice")
	check(state.buy(HUMAN, ShopCatalog.DEFUSE_KIT) == "not available to your side", "attackers cannot buy kits")
	check(state.buy(HUMAN, &"nope") == "unknown item", "unknown items rejected")
	check(state.buy("a1", ShopCatalog.DEFUSE_KIT) == "" and state.get_player("a1").has_kit, "defenders can buy kits")
	check(is_equal_approx(state.defuse_duration("a1"), state.rules.defuse_time_with_kit), "kit shortens the defuse")
	_go_live(state)
	state.tick(state.rules.buy_time + 0.01)
	check(not state.can_buy(HUMAN) and state.buy(HUMAN, WeaponCatalog.KESTREL_PISTOL) == "buying is closed",
		"buy window closes after the buy time")

	# Kill rewards and round rewards.
	var before := human.money
	state.record_kill("a1", HUMAN, WeaponCatalog.WASP_SMG, false)
	check(human.money == before + ShopCatalog.kill_reward(WeaponCatalog.WASP_SMG), "SMG kill pays its reward")
	var h2_money := state.get_player("h2").money
	state.record_kill("h2", "h2", &"", false)
	check(state.get_player("h2").money == h2_money, "suicides pay nothing")
	var a2_money := state.get_player("a2").money
	var human_money := human.money
	state.record_kill("a2", HUMAN, WeaponCatalog.KESTREL_PISTOL, false)
	check(human.money == human_money + 300 + state.rules.win_rewards[MatchRules.REASON_ELIMINATION],
		"winners get the elimination reward")
	check(state.get_player("a2").money == a2_money + state.rules.loss_bonus[0], "losers get the first loss bonus")
	_finish_round_end(state)
	check(human.armour == 100, "surviving keeps armour")
	check(state.get_player("h2").armour == 0 and state.get_player("h2").loadout() == [WeaponCatalog.KESTREL_PISTOL],
		"dying loses gear")
	check(not state.get_player("a1").has_kit, "dead defender loses the kit")

	# Loss bonus ladder.
	var away := state.teams[MatchState.AWAY]
	_win_round(state, MatchState.HOME)
	check(away.loss_streak == 2, "consecutive losses build the streak")
	var a1 := state.get_player("a1")
	var a1_before := a1.money
	_go_live(state)
	for id: String in ["a1", "a2"]:
		state.record_kill(id, HUMAN, WeaponCatalog.KESTREL_PISTOL, false)
	check(a1.money == a1_before + state.rules.loss_bonus_for(3), "third loss pays the third bonus")
	check(state.rules.loss_bonus_for(99) == state.rules.loss_bonus[state.rules.loss_bonus.size() - 1], "loss bonus caps")
	_finish_round_end(state)
	_go_live(state)
	human.money = state.rules.max_money - 10
	state.record_kill("a1", HUMAN, WeaponCatalog.KESTREL_PISTOL, false)
	check(human.money == state.rules.max_money, "money is capped")


func _test_bomb() -> void:
	section("Bomb")
	var state := _make_match()
	state.start()
	_go_live(state)
	check(not state.plant_bomb("h2", Vector3.ZERO), "only the carrier can plant")
	state.tick(state.rules.round_time - 1.0)
	var human_money := state.get_player(HUMAN).money
	check(state.plant_bomb(HUMAN, Vector3(1, 0, 2)), "carrier plants")
	check(state.is_bomb_planted and is_equal_approx(state.bomb_time_left, state.rules.bomb_timer), "bomb timer starts")
	check(state.get_player(HUMAN).money == human_money + state.rules.plant_bonus
		and state.get_player("h2").money == state.rules.start_money + state.rules.plant_bonus, "whole attack team gets the plant bonus")
	check(not state.plant_bomb(HUMAN, Vector3.ZERO), "cannot plant twice")
	state.tick(2.0)
	check(state.phase == MatchState.Phase.LIVE, "the round clock no longer matters once planted")
	state.record_kill(HUMAN, "a1", WeaponCatalog.KESTREL_PISTOL, false)
	state.record_kill("h2", "a1", WeaponCatalog.KESTREL_PISTOL, false)
	check(state.phase == MatchState.Phase.LIVE, "eliminating attackers after the plant does not end the round")
	check(not state.defuse_bomb(HUMAN), "attackers cannot defuse")
	check(state.defuse_bomb("a1") and state.last_round_reason == MatchRules.REASON_DEFUSED
		and state.last_round_winner == MatchState.AWAY, "defuse wins for defence")
	_finish_round_end(state)

	_go_live(state)
	state.plant_bomb(HUMAN, Vector3.ZERO)
	state.tick(state.rules.bomb_timer + 0.1)
	check(state.last_round_reason == MatchRules.REASON_DETONATED and state.last_round_winner == MatchState.HOME,
		"detonation wins for attack")
	_finish_round_end(state)

	_go_live(state)
	state.record_kill(HUMAN, "a1", WeaponCatalog.KESTREL_PISTOL, false, Vector3(5, 0, 5))
	check(state.is_bomb_dropped and state.bomb_carrier_id == "" and state.bomb_position == Vector3(5, 0, 5),
		"carrier death drops the bomb where they died")
	check(not state.pick_up_bomb("a1"), "defenders cannot pick up the bomb")
	check(state.pick_up_bomb("h2") and state.bomb_carrier_id == "h2", "a teammate picks it up")
	check(state.plant_bomb("h2", Vector3.ZERO), "the new carrier can plant")


func _test_halves_and_result() -> void:
	section("Halves and result")
	var state := _make_match(3)
	var switched: Array[int] = [0]
	state.sides_switched.connect(func() -> void: switched[0] += 1)
	var ended: Array[MatchResult] = []
	state.match_ended.connect(func(r: MatchResult) -> void: ended.append(r))
	state.start()
	state.get_player(HUMAN).money = 5000
	for i: int in 3:
		_win_round(state, MatchState.AWAY)
	check(switched[0] == 1 and state.teams[MatchState.HOME].side == MatchRules.SIDE_DEFENCE, "sides switch after MR rounds")
	check(state.get_player(HUMAN).money == state.rules.start_money, "money resets at half time")
	check(state.round_label().contains("2nd half"), "round label shows the 2nd half")
	check(state.match_winner() == -1, "0–3 is not over in MR3")
	_win_round(state, MatchState.AWAY)
	check(state.phase == MatchState.Phase.MATCH_END and state.match_winner() == MatchState.AWAY, "first to MR+1 wins")
	check(ended.size() == 1, "match_ended emitted once")
	var result := ended[0]
	check(result.home_score == 0 and result.away_score == 4 and result.validate() == "", "result is a valid 0–4")
	check(result.source == MatchResult.SOURCE_FPS_RUNTIME and result.map_id == "map_test" and result.fixture_id == "fix_test",
		"result carries fixture, map and source")
	state.tick(100.0)
	check(state.phase == MatchState.Phase.MATCH_END and state.round_number == 4, "nothing happens after the match ends")


func _test_overtime() -> void:
	section("Overtime")
	var state := _make_match(2)
	state.rules.overtime_max_rounds = 2
	state.start()
	_win_round(state, MatchState.HOME)
	_win_round(state, MatchState.HOME)
	_win_round(state, MatchState.AWAY)
	_win_round(state, MatchState.AWAY)
	check(state.phase == MatchState.Phase.FREEZE and state.is_overtime(), "2–2 in MR2 goes to overtime")
	check(state.get_player(HUMAN).money == state.rules.overtime_start_money, "overtime money")
	var side_before := state.teams[MatchState.HOME].side
	check(state.round_label().contains("Overtime 1"), "round label shows overtime")
	_win_round(state, MatchState.HOME)
	_win_round(state, MatchState.AWAY)
	check(state.teams[MatchState.HOME].side != side_before, "sides switch at overtime half")
	_win_round(state, MatchState.HOME)
	check(state.match_winner() == -1, "4–3 is not yet an overtime win")
	_win_round(state, MatchState.AWAY)
	check(state.match_winner() == -1 and state.round_label().contains("Overtime 2"), "4–4 goes to a second overtime")
	_win_round(state, MatchState.HOME)
	_win_round(state, MatchState.HOME)
	check(state.match_winner() == -1, "6–4 is not yet a win (block needs 3 of 4)")
	_win_round(state, MatchState.HOME)
	check(state.phase == MatchState.Phase.MATCH_END and state.result().home_score == 7 and state.result().away_score == 4,
		"winning 3 of the 4-round overtime block ends it 7–4")
	check(state.result().validate() == "", "overtime result validates")


func _test_event_log() -> void:
	section("Event log")
	var state := _make_match(1)
	state.start()
	_go_live(state)
	state.buy(HUMAN, WeaponCatalog.KESTREL_PISTOL)
	state.plant_bomb(HUMAN, Vector3.ZERO)
	state.record_kill("a1", HUMAN, WeaponCatalog.KESTREL_PISTOL, true)
	var types: Array[String] = []
	for entry: Dictionary in state.events:
		types.append(str(entry["type"]))
	for expected: String in ["match_started", "round_started", "bomb_planted", "kill"]:
		check(types.has(expected), "event log records '%s'" % expected)
	var kill: Dictionary = state.events[types.find("kill")]
	check(kill["headshot"] == true and kill["round"] == 1 and kill.has("t"), "events carry round, time and details")
