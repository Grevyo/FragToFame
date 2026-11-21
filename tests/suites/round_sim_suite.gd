extends TestSuite
## Players in places (Milestone 21 stage C): simulated rounds where players walk the map, meet,
## and fight burst by burst with their own weapons, damage, headshots, crossfires and trades.

const MAP_ID: String = "map_f2f_kilnmarket"


func suite_name() -> String:
	return "Round simulation"


func run() -> void:
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	check(map != null, "the test map has a simulation graph")
	if map == null:
		return
	_test_bookkeeping(map)
	_test_skill(map)
	_test_rounds(map)
	_test_weapons()


func _team(name: String, level: float, skills: Dictionary = {}) -> MatchEngine.SimTeam:
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
		for key: Variant in skills:
			player.skills[StringName(str(key))] = int(skills[key])
		team.players.append(player)
	return team


func _play(map: SimMap, home: MatchEngine.SimTeam, away: MatchEngine.SimTeam, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var engine := MatchEngine.new(rng, 8)
	engine.sim_map = map
	return engine.play_map(home, away)


func _test_bookkeeping(map: SimMap) -> void:
	section("A map played on the map")
	var home := _team("H", 65.0)
	var away := _team("A", 65.0)
	var played := _play(map, home, away, 3)
	var rounds := played["rounds"] as Array
	var kills := [0, 0]
	var deaths := [0, 0]
	var damage := 0
	var assists := 0
	var trades := 0
	var headshots := 0
	var plants := 0
	var defuses := 0
	for index: int in 2:
		for player: MatchEngine.SimPlayer in ([home, away][index] as MatchEngine.SimTeam).players:
			kills[index] += int(player.counts["kills"])
			deaths[index] += int(player.counts["deaths"])
			damage += int(player.counts["damage"])
			assists += int(player.counts["assists"])
			trades += int(player.counts["trade_kills"])
			headshots += int(player.counts["headshot_kills"])
			plants += int(player.counts["plants"])
			defuses += int(player.counts["defuses"])
			if player.id.ends_with("_0"):
				check(int(player.counts["hits"]) <= int(player.counts["shots"]) and int(player.counts["headshot_kills"]) <= int(player.counts["kills"]),
					"shots, hits and headshots add up for %s" % player.id)
	check(kills[0] == deaths[1] and kills[1] == deaths[0], "every kill is someone's death (%d and %d)" % kills)
	check(damage >= 100 * (deaths[0] + deaths[1]) and damage <= 100 * (deaths[0] + deaths[1]) + 100 * 10 * rounds.size(),
		"damage is real: at least 100 per death, never more than the health in play")
	var planted := rounds.filter(func(e: Dictionary) -> bool: return e.has("at_plant")).size()
	var defused := rounds.filter(func(e: Dictionary) -> bool: return e["how"] == "defused").size()
	check(plants == planted and defuses == defused, "plants and defuses match the rounds (%d plants, %d defuses)" % [plants, defuses])
	var ends_ok := true
	for entry: Dictionary in rounds:
		ends_ok = ends_ok and str(entry["how"]) in ["eliminated", "defused", "detonated", "time"] and float(entry.get("seconds", 0.0)) > 0.0
	check(ends_ok, "every round ends a real way, at a time")
	check(assists > 0 and trades > 0 and headshots > 0, "damage carries over (assists), deaths get traded, headshots kill")
	var again := _play(map, _team("H", 65.0), _team("A", 65.0), 3)
	check(JSON.stringify(again["rounds"]) == JSON.stringify(rounds), "the same seed plays the same map")


func _test_skill(map: SimMap) -> void:
	section("Who wins the fights")
	var strong := 0
	var total := 0
	for seed_value: int in 4:
		var played := _play(map, _team("S", 80.0), _team("W", 50.0), 40 + seed_value)
		var score: Vector2i = played["score"]
		strong += score.x
		total += score.x + score.y
	check(float(strong) / total > 0.7, "a far better team wins most rounds (%d of %d)" % [strong, total])
	var sharp := _team("Aim", 60.0, {"aim": 85, "crosshair_placement": 85})
	var dull := _team("Low", 60.0, {"aim": 40, "crosshair_placement": 40})
	_play(map, sharp, dull, 9)
	var ratio := func(team: MatchEngine.SimTeam) -> float:
		var hs := 0
		var k := 0
		for player: MatchEngine.SimPlayer in team.players:
			hs += int(player.counts["headshot_kills"])
			k += int(player.counts["kills"])
		return float(hs) / maxf(k, 1.0)
	check(float(ratio.call(sharp)) > float(ratio.call(dull)), "aim and crosshair placement land more headshots (%.2f vs %.2f)"
		% [ratio.call(sharp), ratio.call(dull)])
	# Holders: the same attack against defenders who hold angles well or badly.
	var holders_won := [0, 0]
	for variant: int in 2:
		var level := 75 if variant == 0 else 45
		for seed_value: int in 3:
			var played := _play(map, _team("T", 62.0), _team("D", 62.0, {"crosshair_placement": level, "positioning": level, "game_sense": level}),
				70 + seed_value)
			for entry: Dictionary in played["rounds"] as Array:
				if int(entry["attackers"]) == 0 and int(entry["winner"]) == 1:
					holders_won[variant] += 1
	check(holders_won[0] > holders_won[1], "defenders who hold angles well win more defence rounds (%d vs %d)" % holders_won)


func _test_rounds(map: SimMap) -> void:
	section("How rounds play out")
	var times: Dictionary[String, Array] = {"rush": [], "default": []}
	var hows: Dictionary[String, int] = {}
	var attack_wins := 0
	var total := 0
	for seed_value: int in 6:
		var played := _play(map, _team("H", 65.0), _team("A", 65.0), 100 + seed_value)
		for entry: Dictionary in played["rounds"] as Array:
			total += 1
			hows[str(entry["how"])] = int(hows.get(str(entry["how"]), 0)) + 1
			if int(entry["winner"]) == int(entry["attackers"]):
				attack_wins += 1
			var kind := str((entry["plans"] as Array)[int(entry["attackers"])]["kind"])
			if entry.has("at_plant") and times.has(kind):
				times[kind].append(float(entry["seconds"]))
	check(hows.has("detonated") and hows.has("defused") and hows.has("eliminated") and hows.has("time"),
		"rounds end every way a round can (%s)" % hows)
	# Over the whole map pool (single maps lean one way or the other; balancing them is stage H).
	var pool_wins := 0
	var pool_total := 0
	for map_id: String in OfficialMaps.ids():
		var pool_map := SimMap.for_map(map_id)
		if pool_map == null:
			continue
		for seed_value: int in 2:
			var played := _play(pool_map, _team("H", 65.0), _team("A", 65.0), 200 + seed_value)
			for entry: Dictionary in played["rounds"] as Array:
				pool_total += 1
				if int(entry["winner"]) == int(entry["attackers"]):
					pool_wins += 1
	var share := float(pool_wins) / maxf(pool_total, 1.0)
	check(share > 0.38 and share < 0.62, "attack and defence are both winnable between even teams over the map pool (%.2f)" % share)
	var average := func(list: Array) -> float:
		var sum := 0.0
		for value: Variant in list:
			sum += float(value)
		return sum / maxf(list.size(), 1.0)
	if not times["rush"].is_empty() and not times["default"].is_empty():
		check(float(average.call(times["rush"])) < float(average.call(times["default"])),
			"rushed rounds are over sooner than defaults (%.0f s vs %.0f s)" % [average.call(times["rush"]), average.call(times["default"])])


func _test_weapons() -> void:
	section("Weapons")
	var ak := RoundSim.gun(WeaponCatalog.AK47)
	var m4 := RoundSim.gun(WeaponCatalog.M4A1)
	var head := func(weapon: Dictionary) -> int:
		return DamageModel.armour_split(roundi(float(weapon["damage"]) * DamageModel.zone_multiplier(DamageModel.ZONE_HEAD)),
			float(weapon["penetration"]), DamageModel.ZONE_HEAD, 100, true)[0]
	check(int(head.call(ak)) >= 100 and int(head.call(m4)) < 100,
		"the game's own numbers: an AK-47 headshot kills through a helmet, an M4A1's does not (%d, %d)" % [head.call(ak), head.call(m4)])
	check(int(ak["burst"]) > int(RoundSim.gun(WeaponCatalog.L118A1)["burst"]) and float(RoundSim.gun(WeaponCatalog.L118A1)["spread"]) < float(ak["spread"]),
		"a rifle fires more per burst than a bolt-action, which is the more accurate at range")
