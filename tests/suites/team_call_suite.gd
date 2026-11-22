class_name TeamCallSuite
extends TestSuite
## Milestone 7 D: mid-round calls. The AI leader reads the round (save, take the other site,
## regroup; defence regroups outside a fallen site), a human makes the same calls from the call
## menu, and the bots obey a call the same way whoever made it.
## Milestone 7 E: the team buys on its leader's call, with drops for teammates.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Team calls and economy (Milestone 7 D, E)"


func run() -> void:
	_test_menu()
	_test_leader_reads()
	_test_team_buy()
	_test_drops()
	await _test_calls_in_match()


func _test_menu() -> void:
	section("Call menu")
	var letters: Array[String] = ["A", "B"]
	var attack := TeamCall.menu(MatchRules.SIDE_ATTACK, letters).map(func(call: TeamCall) -> String: return call.label())
	var defence := TeamCall.menu(MatchRules.SIDE_DEFENCE, letters).map(func(call: TeamCall) -> String: return call.label())
	check(attack == ["Execute A", "Execute B", "Hold", "Regroup", "Save"], "attack calls: %s" % ", ".join(attack))
	check(defence == ["Rotate A", "Rotate B", "Hold", "Regroup", "Save"], "defence calls: %s" % ", ".join(defence))
	check(TeamCall.make(TeamCall.Kind.HOLD, "A").site == "" and TeamCall.make(TeamCall.Kind.REGROUP, "B").label() == "Regroup for B",
		"a hold has no site; a regroup names where")


func _leader(map: SimMap, side: StringName) -> BotTactics:
	var ids: Array[String] = ["p1", "p2", "p3", "p4", "p5"]
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	var tactics := BotTactics.create(map, ids, [], 55.0, dice)
	tactics.plan_round(side, RoundPlanner.Situation.new(), ids)
	return tactics


func _test_leader_reads() -> void:
	section("The AI leader reads the round")
	var map := SimMap.for_map(_official_with_graph())
	if map == null:
		check(false, "an official map has a simulation graph")
		return
	var site_a := "site_A"
	var site_b := "site_B"
	var metres: Dictionary[String, float] = {site_a: 30.0, site_b: 60.0}
	var none: Dictionary[String, int] = {}
	var leader := _leader(map, MatchRules.SIDE_ATTACK)
	leader.plan.kind = RoundPlan.EXECUTE
	leader.plan.site = site_a
	check(leader.adapt_attack("A", true, false, none, 5, 5, 80.0, metres, 0, true) == null, "five against five with time: carry on")
	var save := leader.adapt_attack("A", true, true, none, 1, 4, 60.0, metres, 0, true)
	check(save != null and save.kind == TeamCall.Kind.SAVE, "one against four: save (%s)" % (save.reason if save != null else "no call"))
	check(leader.adapt_attack("A", true, true, none, 1, 4, 60.0, metres, 0, true) == null, "a call is made once a round")
	var late := _leader(map, MatchRules.SIDE_ATTACK)
	var far := late.adapt_attack("A", true, false, none, 5, 5, 8.0, metres, 0, true)
	check(far != null and far.kind == TeamCall.Kind.SAVE, "too far from the site with the clock nearly out: save")
	check(late.adapt_attack("A", true, false, none, 5, 5, 8.0, metres, 0, true) == null, "no second save")

	var stacked := _leader(map, MatchRules.SIDE_ATTACK)
	stacked.plan.kind = RoundPlan.EXECUTE
	stacked.plan.site = site_a
	var seen: Dictionary[String, int] = {site_a: 3}
	var turn := stacked.adapt_attack("A", true, false, seen, 5, 5, 80.0, metres, 0, true)
	check(turn != null and turn.kind == TeamCall.Kind.EXECUTE and turn.site == "B",
		"three seen on A before the push: execute B instead (%s)" % (turn.label() if turn != null else "no call"))
	var committed := _leader(map, MatchRules.SIDE_ATTACK)
	committed.plan.kind = RoundPlan.EXECUTE
	committed.plan.site = site_a
	check(committed.adapt_attack("A", true, true, seen, 5, 5, 80.0, metres, 0, true) == null, "once the push is on, no turning back")
	var rushing := _leader(map, MatchRules.SIDE_ATTACK)
	rushing.plan.kind = RoundPlan.RUSH
	rushing.plan.site = site_a
	check(rushing.adapt_attack("A", true, false, seen, 5, 5, 80.0, metres, 0, true) == null, "a rush does not turn")

	var door := _leader(map, MatchRules.SIDE_ATTACK)
	var regroup := door.adapt_attack("A", true, true, none, 3, 4, 80.0, metres, 2, true)
	check(regroup != null and regroup.kind == TeamCall.Kind.REGROUP and regroup.site == "A",
		"two lost at the door, three left: regroup (%s)" % (regroup.label() if regroup != null else "no call"))
	var inside := _leader(map, MatchRules.SIDE_ATTACK)
	check(inside.adapt_attack("A", true, true, none, 3, 4, 80.0, metres, 2, false) == null, "a push already on the site plays on")
	check(inside.adapt_attack("A", true, true, none, 4, 4, 80.0, metres, 1, true) == null, "one lost: play on")

	var defence := _leader(map, MatchRules.SIDE_DEFENCE)
	var fallen := defence.adapt_defence(site_b, 3)
	check(fallen != null and fallen.kind == TeamCall.Kind.REGROUP and fallen.site == "B",
		"defence: B has fallen, three left: regroup to retake together")
	check(_leader(map, MatchRules.SIDE_DEFENCE).adapt_defence(site_b, 1) == null and defence.adapt_defence("", 3) == null,
		"a last defender does not call a regroup; nothing fallen, nothing called")


## Bot ID -> carried gear for [method BotTactics.team_buy], everyone with [param money].
static func _carried(moneys: Array[int]) -> Dictionary[String, Dictionary]:
	var carried: Dictionary[String, Dictionary] = {}
	for index: int in moneys.size():
		carried["p%d" % (index + 1)] = {"money": moneys[index], "primary": "", "secondary": String(WeaponCatalog.DEFAULT_SECONDARY),
			"armour": 0, "helmet": false, "kit": false, "utility": []}
	return carried


static func _is_primary(item: StringName) -> bool:
	if ShopCatalog.kind(item) != ShopCatalog.KIND_WEAPON:
		return false
	return WeaponCatalog.get_definition(item).category == WeaponDefinition.CATEGORY_PRIMARY


static func _items(orders: Array[Dictionary], id: String) -> Array[StringName]:
	var items: Array[StringName] = []
	for order: Dictionary in orders:
		if str(order["for"]) == id:
			items.append(order["item"] as StringName)
	return items


func _test_team_buy() -> void:
	section("The team buys on the leader's call")
	var map := SimMap.for_map(_official_with_graph())
	if map == null:
		return
	var leader := _leader(map, MatchRules.SIDE_ATTACK)
	var roles := leader.team.players.map(func(player: MatchEngine.SimPlayer) -> String: return String(player.role))
	check(roles == ["igl", "entry", "support", "rifler", "lurker"], "sandbox bots get a leader, an entry and support (%s)" % ", ".join(roles))
	var pistol := leader.team_buy(_carried([800, 800, 800, 800, 800]), MatchRules.SIDE_ATTACK, true, 800.0, 0)
	check(leader.buy_call == &"pistol" and not pistol.any(func(order: Dictionary) -> bool: return _is_primary(order["item"] as StringName)),
		"pistol round: a pistol-round buy, no rifles")
	var full := leader.team_buy(_carried([6000, 6000, 6000, 6000, 6000]), MatchRules.SIDE_ATTACK, false, 6000.0, 0)
	check(leader.buy_call == &"full" and range(1, 6).all(func(n: int) -> bool:
		return _items(full, "p%d" % n).has(WeaponCatalog.AK47) and _items(full, "p%d" % n).has(ShopCatalog.ARMOUR_VEST_HELMET)),
		"full buy: everyone a rifle, vest and helmet")
	var support := _items(full, "p3")
	var entry := _items(full, "p2")
	check(support.has(EquipmentCatalog.SMOKE) and entry.has(EquipmentCatalog.FLASH),
		"each buys utility for their role (support: %s; entry: %s)" % [", ".join(support), ", ".join(entry)])
	leader.team_buy(_carried([1800, 1800, 1800, 1800, 1800]), MatchRules.SIDE_ATTACK, false, 5000.0, 0)
	check(leader.buy_call == &"eco", "short of money against a full buy: eco")
	leader.team_buy(_carried([2400, 2400, 2400, 2400, 2400]), MatchRules.SIDE_ATTACK, false, 5000.0, 3)
	check(leader.buy_call == &"force", "after a losing run with some money: force")
	var defence := _leader(map, MatchRules.SIDE_DEFENCE)
	var kits := defence.team_buy(_carried([7000, 7000, 7000, 7000, 7000]), MatchRules.SIDE_DEFENCE, false, 6000.0, 0)
	var kit_count := kits.filter(func(order: Dictionary) -> bool: return order["item"] == ShopCatalog.DEFUSE_KIT).size()
	check(kit_count >= 1 and kit_count <= 2 and _items(kits, "p1").has(WeaponCatalog.M4A1), "defenders: rifles and one or two kits")


func _test_drops() -> void:
	section("Drops")
	var map := SimMap.for_map(_official_with_graph())
	if map == null:
		return
	var leader := _leader(map, MatchRules.SIDE_ATTACK)
	var orders := leader.team_buy(_carried([9000, 9000, 9000, 9000, 400]), MatchRules.SIDE_ATTACK, false, 6000.0, 0)
	var drop := orders.filter(func(order: Dictionary) -> bool: return str(order["buyer"]) != str(order["for"]))
	check(leader.buy_call == &"full" and drop.size() == 1 and str(drop[0]["for"]) == "p5" and drop[0]["item"] == WeaponCatalog.AK47,
		"four rich, one broke: a teammate drops the broke player a rifle")
	var setup := MatchSetup.new()
	setup.fixture_id = "drops"
	var state := MatchState.new(setup, MatchRules.practice(2))
	state.add_player("a", "A", MatchState.HOME)
	state.add_player("b", "B", MatchState.HOME)
	state.add_player("c", "C", MatchState.AWAY)
	state.start()
	state.get_player("a").money = 4000
	state.get_player("b").money = 0
	check(state.buy_for("a", "b", WeaponCatalog.AK47) == "" and state.get_player("b").primary == WeaponCatalog.AK47
		and state.get_player("a").money == 4000 - ShopCatalog.price(WeaponCatalog.AK47) and state.get_player("a").primary == &"",
		"buy_for: the buyer pays, the teammate gets the rifle")
	check(state.buy_for("a", "c", WeaponCatalog.AK47) != "" and state.buy_for("a", "b", ShopCatalog.ARMOUR_VEST) != ""
		and state.buy_for("b", "a", WeaponCatalog.AK47) != "", "no drops for opponents, of armour, or without the money")


func _test_calls_in_match() -> void:
	section("Calls in a match")
	var app := tree.root.get_node("App")
	var map_id := _official_with_graph()
	var setup := MatchSetup.new()
	setup.fixture_id = "team_calls"
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
	rules.round_time = 900.0
	rules.plant_time = 900.0
	app.set("pending_match_setup", setup)
	app.set("pending_match_rules", rules)
	app.set("pending_match_map", OfficialMaps.load_map(map_id))
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
	for bot: BotController in squad.bots.values():
		bot.enemies = []
	var state := director.state
	Engine.time_scale = 4.0
	await wait_until(func() -> bool: return state.phase == MatchState.Phase.LIVE, 5.0)
	check(director.human_side() == MatchRules.SIDE_ATTACK and director.can_call(), "the player attacks and can call")
	check(squad.tactics[MatchState.AWAY].buy_call == &"pistol" and squad.tactics[MatchState.HOME].buy_call == &"pistol",
		"both bot teams buy on their leader's pistol-round call")

	# The menu: Z opens it, a number makes the call.
	var open := InputEventAction.new()
	open.action = InputActions.TEAM_CALL
	open.pressed = true
	director._unhandled_input(open)
	check(director.hud.is_call_menu_open() and director.hud.call_menu_text().begins_with("1  Execute A"),
		"Z opens the call menu (%s)" % director.hud.call_menu_text().replace("\n", " / "))
	var three := InputEventKey.new()
	three.physical_keycode = KEY_3
	three.pressed = true
	director._input(three)
	var mine: Array[BotController] = []
	for id: String in squad.bots:
		if state.get_player(id).team == MatchState.HOME:
			mine.append(squad.bots[id])
	check(not director.hud.is_call_menu_open() and squad.attack_hold.size() == mine.size()
		and director.hud.call_text().begins_with("You: Hold"), "3 calls Hold: every teammate holds (%s)" % director.hud.call_text())
	var held_at: Dictionary[String, Vector3] = squad.attack_hold.duplicate()
	await wait_seconds(1.5)
	check(mine.all(func(bot: BotController) -> bool: return _flat(bot.global_position, held_at[bot.bot_id]) < 2.5),
		"holding teammates stay where they were")

	check(director.make_call(1) and squad.attack_site == "B" and squad.attack != null and squad.attack.site == "B"
		and squad.attack_hold.is_empty(), "Execute B: the team's play goes for B from where it is")
	check(director.make_call(3) and squad.attack != null and squad.attack.site == "B"
		and squad.attack.lanes[0].phase != AttackPlay.Phase.GO, "Regroup: back to the gathering spot before going again")
	check(director.make_call(4) and squad.attack_saving, "Save: the team gives the round up")
	var spawn := director.level.spawn_point("attack")[0] as Vector3
	await wait_seconds(0.3)
	check(mine.all(func(bot: BotController) -> bool: return not bot.has_goal or _flat(bot.goal_position, spawn) < 6.0),
		"saving teammates head back towards their spawn")

	# The defending bots' calls (as their leader or a human would make them).
	var defence := MatchState.AWAY
	var defenders: Array[BotController] = []
	for id: String in squad.bots:
		if state.get_player(id).team == defence:
			defenders.append(squad.bots[id])
	check(squad.issue_call(defence, TeamCall.make(TeamCall.Kind.ROTATE, "A"))
		and defenders.all(func(bot: BotController) -> bool: return squad.rotations.get(bot.bot_id, "") == "site_A"),
		"Rotate A: every defender goes to A")
	await wait_seconds(0.3)
	var site_a := SimMap.for_map(map_id).nodes["site_A"]["centre"] as Vector3
	check(defenders.all(func(bot: BotController) -> bool: return _flat(bot.goal_position, site_a) < 16.0),
		"rotating defenders head for A")
	check(squad.issue_call(defence, TeamCall.make(TeamCall.Kind.HOLD)) and squad.rotations.is_empty() and squad.defence_hold,
		"Hold: rotations are called off and the set-up holds")
	check(squad.issue_call(defence, TeamCall.make(TeamCall.Kind.REGROUP, "B")) and squad.regroup_site == "B",
		"Regroup for B: the defenders gather to retake B")
	await wait_seconds(0.3)
	var take := SiteExecute.plan(SimMap.for_map(map_id), "B", [], "", SimMap.for_map(map_id).spawn("defence"))
	check(take != null and defenders.all(func(bot: BotController) -> bool: return _flat(bot.goal_position, take.staging) < 3.0),
		"regrouping defenders gather outside B")
	check(squad.calls.size() == 7 and not squad.issue_call(defence, TeamCall.make(TeamCall.Kind.ROTATE, "Z")),
		"every call is logged; a call for no site does not apply")
	Engine.time_scale = 1.0
	app.set("last_match_result", null)
	await despawn(sandbox)
	await wait_frames(2)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _official_with_graph() -> String:
	for id: String in OfficialMaps.ids():
		if SimMap.for_map(id) != null:
			return id
	return ""
