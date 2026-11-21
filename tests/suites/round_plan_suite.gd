extends TestSuite
## Round plans (Milestone 21 stage B): the in-game leader's attack strategies, defence setups and
## mid-round calls on a real map's simulation graph, and the match engine logging them.

const MAP_ID: String = "map_f2f_kilnmarket"


func suite_name() -> String:
	return "Round plans"


func run() -> void:
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	check(map != null, "the test map has a simulation graph")
	if map == null:
		return
	_test_places(map)
	_test_defence(map)
	_test_attack(map)
	_test_choices(map)
	_test_calls(map)
	_test_engine(map)


func _team(name: String, level: float, aggression: float = 1.0) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = name
	team.name = name
	var roles: Array[StringName] = [&"igl", &"sniper", &"entry", &"lurker", &"support"]
	for i: int in 5:
		var player := MatchEngine.SimPlayer.new()
		player.id = "%s_%d" % [name, i]
		player.name = player.id
		player.role = roles[i]
		for key: StringName in CareerCatalog.ABILITIES:
			player.skills[key] = roundi(level)
		player.aggression = aggression * (1.7 if roles[i] == &"entry" else 1.0)
		team.players.append(player)
	team.tactics = level
	team.utility = level
	team.coordination = level
	return team


func _planner(map: SimMap, team: MatchEngine.SimTeam, seed_value: int = 1) -> RoundPlanner:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return RoundPlanner.new(map, team, rng)


func _situation(buy: StringName = &"full") -> RoundPlanner.Situation:
	var situation := RoundPlanner.Situation.new()
	situation.buy = buy
	situation.round_index = 3
	return situation


func _test_places(map: SimMap) -> void:
	section("Places on the map")
	var planner := _planner(map, _team("T", 60.0))
	var ok := true
	for site: String in map.sites():
		var ways := planner.approaches(site)
		var cluster := map.site_cluster(site)
		ok = ok and not ways.is_empty() and not ways.any(func(p: String) -> bool: return cluster.has(p)) \
			and planner.holds(site)[0] in cluster
	check(ok, "every site has ways in from outside it and places to hold on it")
	var rotator := planner.rotator_spot()
	check(not rotator.is_empty() and map.distance(map.spawn("defence"), rotator) < map.distance(map.spawn("attack"), rotator)
		and map.sites().all(func(s: String) -> bool: return not map.site_cluster(s).has(rotator)),
		"the rotator waits between the sites on the defenders' half (%s)" % map.name_of(rotator))


func _test_defence(map: SimMap) -> void:
	section("Defence setups")
	var team := _team("D", 60.0)
	var planner := _planner(map, team)
	var plan := planner.plan_defence(_situation(), team.players)
	var everyone := team.players.all(func(p: MatchEngine.SimPlayer) -> bool:
		return plan.spots.has(p.id) and not (plan.routes[p.id] as Array).is_empty())
	var each_site := map.sites().all(func(s: String) -> bool: return plan.players_at(map, s) >= 1)
	check(plan.kind == RoundPlan.STANDARD or plan.kind == RoundPlan.AGGRESSIVE, "with nothing seen yet there is no stack (%s)" % plan.kind)
	check(everyone and each_site, "every defender has a place and a way there, and both sites are held")
	check(plan.with_job(RoundPlan.ROTATOR).size() <= 1 and plan.with_job(RoundPlan.ANCHOR).size() >= 2, "anchors on the sites, at most one rotator")
	# Five attacks in a row on A: a leader who reads it stacks A.
	for i: int in 5:
		planner.learn_defence("site_A")
	var weights := planner.defence_weights(_situation())
	check(weights[RoundPlan.STACK] > weights[RoundPlan.STANDARD], "a one-sided attack makes a stack the stronger read")
	var stacked := 0
	for i: int in 20:
		var next := planner.plan_defence(_situation(), team.players)
		if next.kind == RoundPlan.STACK:
			stacked += 1
			if stacked == 1:
				check(next.site == "site_A" and next.players_at(map, "site_A") >= 3 and next.players_at(map, "site_B") >= 1,
					"a stack puts most of the team on the read site and still leaves the other held")
	check(stacked > 0, "the leader does stack after the read (%d of 20)" % stacked)


func _test_attack(map: SimMap) -> void:
	section("Attack plans")
	var team := _team("A", 60.0)
	var planner := _planner(map, team, 4)
	var seen_kinds: Dictionary[StringName, bool] = {}
	var routes_ok := true
	var lurk_ok := true
	var split_ok := true
	for i: int in 40:
		var plan := planner.plan_attack(_situation(), team.players)
		seen_kinds[plan.kind] = true
		for player: MatchEngine.SimPlayer in team.players:
			var walk := plan.routes.get(player.id, []) as Array
			routes_ok = routes_ok and not walk.is_empty() and walk[0] == map.spawn("attack") and walk.back() == plan.spots[player.id]
		var lurkers := plan.with_job(RoundPlan.LURK)
		if plan.kind != RoundPlan.RUSH:
			lurk_ok = lurk_ok and lurkers == ["A_3"]
		if plan.kind == RoundPlan.SPLIT and planner.approaches(plan.site).size() >= 2:
			var lanes: Dictionary[String, bool] = {}
			for id: String in plan.spots:
				if plan.jobs[id] != RoundPlan.LURK:
					lanes[plan.spots[id]] = true
			split_ok = split_ok and lanes.size() >= 2
		if i == 0:
			check(plan.hit_at > 0.0 and plan.hit_at <= 80.0, "the hit lands inside the round (%s at %.0f s)" % [plan.kind, plan.hit_at])
	check(routes_ok, "every attacker walks a real route from spawn to their place")
	check(lurk_ok, "the lurker plays alone on the other side unless the team rushes")
	check(split_ok, "a split comes through at least two ways in")
	check(seen_kinds.size() >= 3, "an even team mixes its plans (%s)" % [seen_kinds.keys()])


func _test_choices(map: SimMap) -> void:
	section("What decides the call")
	var hot := _team("H", 50.0, 1.6)
	var calm := _team("C", 75.0, 0.7)
	var hot_eco := _planner(map, hot).attack_weights(_situation(&"eco"), 5)
	var calm_full := _planner(map, calm).attack_weights(_situation(&"full"), 5)
	check(hot_eco[RoundPlan.RUSH] > hot_eco[RoundPlan.DEFAULT] and hot_eco[RoundPlan.RUSH] > hot_eco[RoundPlan.EXECUTE],
		"an aggressive team on an eco rushes")
	check(calm_full[RoundPlan.DEFAULT] > calm_full[RoundPlan.RUSH] and calm_full[RoundPlan.EXECUTE] > calm_full[RoundPlan.RUSH],
		"a tactical team on a full buy plays default and executes, not rushes")
	var level := _situation()
	level.own_score = 5
	level.their_score = 5
	var behind := _situation()
	behind.own_score = 2
	behind.their_score = 8
	var planner := _planner(map, _team("S", 60.0))
	var even := planner.attack_weights(level, 5)
	var losing := planner.attack_weights(behind, 5)
	check(losing[RoundPlan.RUSH] > even[RoundPlan.RUSH] and losing[RoundPlan.FAKE] > even[RoundPlan.FAKE],
		"far behind with few rounds to spare, the leader gambles more")
	var fresh := planner.attack_weights(level, 5)[RoundPlan.EXECUTE]
	var plan := RoundPlan.new()
	plan.kind = RoundPlan.EXECUTE
	plan.site = "site_A"
	for i: int in 3:
		planner.learn_attack(plan, false, {"site_A": 3, "site_B": 1}, false)
	var beaten := planner.attack_weights(level, 5)[RoundPlan.EXECUTE]
	var sites := planner.site_weights(RoundPlan.EXECUTE)
	check(beaten < fresh, "an execute that keeps losing is called less")
	check(sites["site_B"] > sites["site_A"], "the site where more defenders were found is avoided")
	var tactician := _team("T", 80.0)
	var novice := _team("N", 40.0)
	var picks := [_spread(map, tactician), _spread(map, novice)]
	check(int(picks[0]) < int(picks[1]), "a sharp leader settles on the best plan more consistently (%d vs %d kinds over 30 rounds)" % picks)


func _spread(map: SimMap, team: MatchEngine.SimTeam) -> int:
	var planner := _planner(map, team, 9)
	var kinds: Dictionary[StringName, int] = {}
	for i: int in 30:
		var kind := planner.plan_attack(_situation(&"eco"), team.players).kind
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	var most := 0
	for kind: StringName in kinds:
		most = maxi(most, kinds[kind])
	return 30 - most


func _test_calls(map: SimMap) -> void:
	section("Calls during the round")
	var team := _team("D", 60.0)
	var planner := _planner(map, team)
	var plan := planner.plan_defence(_situation(), team.players)
	var rotator_id := plan.with_job(RoundPlan.ROTATOR)
	var anchor_b := ""
	for id: String in plan.with_job(RoundPlan.ANCHOR):
		if planner._site_of(plan.spots[id]) == "site_B":
			anchor_b = id
	var by_id: Dictionary[String, MatchEngine.SimPlayer] = {}
	for player: MatchEngine.SimPlayer in team.players:
		by_id[player.id] = player
	var two_on_a: Dictionary[String, int] = {"site_A": 2}
	var contact_both: Dictionary[String, int] = {"site_A": 4, "site_B": 1}
	if not rotator_id.is_empty():
		check(planner.rotation_for(plan, by_id[rotator_id[0]], two_on_a, "") == "site_A", "the rotator goes on first contact")
	if not anchor_b.is_empty():
		check(planner.rotation_for(plan, by_id[anchor_b], two_on_a, "") == "" and planner.rotation_for(plan, by_id[anchor_b], contact_both, "") == "",
			"the other site's anchor holds on light contact and while their own site has contact")
		check(planner.rotation_for(plan, by_id[anchor_b], {} as Dictionary[String, int], "site_A") == "site_A", "after a plant everyone goes to the bomb")
	check(planner.retake_or_save(4, 1, 30.0, 40.0, true, 4000) == &"retake", "four against one with time: retake")
	check(planner.retake_or_save(2, 2, 6.0, 60.0, false, 4000) == &"save", "no time to reach and defuse: save")
	check(planner.retake_or_save(1, 4, 30.0, 20.0, true, 6000) == &"save", "one against four with money for next round: save")
	check(planner.attack_should_save(1, 4, 10.0, 80.0) and not planner.attack_should_save(5, 3, 60.0, 40.0),
		"a lone attacker with no time saves; a full team with time plays on")
	var attack := _planner(map, _team("A", 60.0))
	var default_plan := RoundPlan.new()
	default_plan.kind = RoundPlan.DEFAULT
	default_plan.site = "site_A"
	check(attack.call_hit(default_plan, {"site_A": 3, "site_B": 0} as Dictionary[String, int]) == "site_B",
		"a default is called where the map control found the fewest defenders")


func _test_engine(map: SimMap) -> void:
	section("The engine plays the plans")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var engine := MatchEngine.new(rng, 8)
	engine.sim_map = map
	var played := engine.play_map(_team("H", 65.0), _team("A", 65.0))
	var rounds := played["rounds"] as Array
	var logged := true
	var kinds: Dictionary[String, bool] = {}
	for entry: Dictionary in rounds:
		var plans := entry.get("plans", []) as Array
		var attackers := int(entry["attackers"])
		logged = logged and plans.size() == 2 and map.sites().has(str(entry.get("site", ""))) \
			and str(plans[attackers]["side"]) == "attack" and str(plans[1 - attackers]["side"]) == "defence" \
			and (plans[0]["spots"] as Dictionary).size() == 5 and (plans[1]["spots"] as Dictionary).size() == 5
		if logged:
			kinds[str(plans[attackers]["kind"])] = true
	check(logged and not rounds.is_empty(), "every round logs both teams' plans and the attacked site")
	check(kinds.size() >= 2, "plans change over the map (%s)" % [kinds.keys()])
	var again := RandomNumberGenerator.new()
	again.seed = 21
	var replay := MatchEngine.new(again, 8)
	replay.sim_map = map
	var second := replay.play_map(_team("H", 65.0), _team("A", 65.0))
	check(JSON.stringify(second["rounds"]) == JSON.stringify(rounds), "the same seed calls the same plans")
	var plain := MatchEngine.new(RandomNumberGenerator.new(), 8).play_map(_team("H", 65.0), _team("A", 65.0))
	check(not ((plain["rounds"] as Array)[0] as Dictionary).has("plans"), "without a map graph rounds are played without plans")
