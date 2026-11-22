extends TestSuite
## People over a match (Milestone 21 stage F): tilt, nerves in big rounds, fatigue over a series,
## and what a team and its players bring to a map from their history on it.

const MAP_ID: String = "map_f2f_kilnmarket"


func suite_name() -> String:
	return "People over a match"


func run() -> void:
	_test_tilt()
	_test_nerves()
	_test_fatigue()
	_test_history()
	_test_on_the_server()


func _player(skills: Dictionary = {}, traits: Dictionary = {}) -> MatchEngine.SimPlayer:
	var player := MatchEngine.SimPlayer.new()
	player.id = "p"
	for key: StringName in CareerCatalog.ABILITIES:
		player.skills[key] = 60
	for key: Variant in skills:
		player.skills[StringName(str(key))] = int(skills[key])
	player.traits = traits
	return player


func _team(name: String, level: float) -> MatchEngine.SimTeam:
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
		team.players.append(player)
	return team


func _test_tilt() -> void:
	section("Tilt")
	var hot := _player({}, {&"tr_hot_headed": 2})
	var calm := _player({}, {&"tr_calm": 2})
	var plain := _player()
	check(MatchEngine.tilt(plain) == 0.0, "no tilt before a bad run")
	for player: MatchEngine.SimPlayer in [hot, calm, plain]:
		player.bad_rounds = 4
	check(MatchEngine.tilt(hot) > MatchEngine.tilt(plain) and MatchEngine.tilt(plain) > MatchEngine.tilt(calm),
		"four rounds dying without a kill tilt a hot head most and a calm player least (%.1f, %.1f, %.1f)"
		% [MatchEngine.tilt(hot), MatchEngine.tilt(plain), MatchEngine.tilt(calm)])
	var composed := _player({"composure": 90})
	composed.bad_rounds = 4
	check(MatchEngine.tilt(composed) < MatchEngine.tilt(plain), "composure keeps a player level")
	var long := _player({"composure": 20}, {&"tr_hot_headed": 3})
	long.bad_rounds = 20
	check(MatchEngine.tilt(long) <= MatchEngine.TILT_CAP, "tilt has a limit")


func _test_nerves() -> void:
	section("Nerves in big rounds")
	var engine := MatchEngine.new(RandomNumberGenerator.new(), 8)
	var green := _player({"composure": 35})
	var veteran := _player({"composure": 35})
	veteran.experience = 1.0
	var ice := _player({"composure": 85})
	check(engine.nerves(green, false) == 0.0, "an ordinary round costs nobody")
	check(engine.nerves(green, true) > engine.nerves(veteran, true) and engine.nerves(veteran, true) > 0.0,
		"a match point shakes a shaky newcomer more than a shaky veteran (%.1f vs %.1f)"
		% [engine.nerves(green, true), engine.nerves(veteran, true)])
	check(engine.nerves(ice, true) == 0.0, "a composed player does not feel it")
	var plain := engine.nerves(green, true)
	engine.series_decider = true
	check(engine.nerves(green, true) > plain, "a match point on the deciding map weighs more")


func _test_fatigue() -> void:
	section("Fatigue over a series")
	var fresh := _player()
	var tired := _player()
	tired.series_rounds = 48
	var tired_steady := _player({"consistency": 90})
	tired_steady.series_rounds = 48
	check(MatchEngine.fatigue(fresh) == 0.0 and MatchEngine.fatigue(tired) > 0.0, "rounds played wear a player down")
	check(MatchEngine.fatigue(tired_steady) < MatchEngine.fatigue(tired), "consistent players tire less (%.1f vs %.1f)"
		% [MatchEngine.fatigue(tired_steady), MatchEngine.fatigue(tired)])
	var engine := MatchEngine.new(RandomNumberGenerator.new(), 8)
	var team := _team("F", 60.0)
	var before := engine.form_points(team.players[0], team, 5, 5, false)
	team.players[0].series_rounds = 48
	check(engine.form_points(team.players[0], team, 5, 5, false) < before, "fatigue costs form in the fights")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var played := MatchEngine.new(rng, 8)
	var home := _team("H", 60.0)
	played.play_map(home, _team("A", 60.0))
	var rounds := (played.rounds_log as Array).size()
	check(home.players[0].series_rounds == rounds, "every round played is counted (%d)" % rounds)
	played.play_map(home, _team("B", 60.0))
	check(home.players[0].series_rounds > rounds, "and carried into the next map of the series")


func _test_history() -> void:
	section("History on the map")
	check(CareerSeriesEngine.comfort(0, 0.0, 1.0) == 0.0, "no maps there, nothing carried in")
	check(CareerSeriesEngine.comfort(8, 1.3, 1.0) > 0.0 and CareerSeriesEngine.comfort(8, 0.8, 1.0) < 0.0,
		"a player who does well on a map carries it in; one who struggles there carries that")
	check(CareerSeriesEngine.comfort(1, 1.3, 1.0) < CareerSeriesEngine.comfort(8, 1.3, 1.0),
		"one good map is trusted less than eight")
	check(absf(CareerSeriesEngine.comfort(20, 3.0, 1.0)) <= CareerSeriesEngine.COMFORT_CAP, "comfort has a limit")
	var engine := MatchEngine.new(RandomNumberGenerator.new(), 8)
	var known := _team("K", 60.0)
	var stranger := _team("N", 60.0)
	known.familiarity = 1.0
	stranger.familiarity = 0.0
	check(engine.form_points(known.players[0], known, 5, 5, false) > engine.form_points(stranger.players[0], stranger, 5, 5, false),
		"a team that knows the map plays it better")


func _test_on_the_server() -> void:
	section("On the server")
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	if map == null:
		check(false, "the test map has a simulation graph")
		return
	var won := [0, 0]
	for seed_value: int in 6:
		var rng := RandomNumberGenerator.new()
		rng.seed = 300 + seed_value
		var engine := MatchEngine.new(rng, 8)
		engine.sim_map = map
		var known := _team("K", 62.0)
		var stranger := _team("N", 62.0)
		known.familiarity = 1.0
		stranger.familiarity = 0.0
		var score: Vector2i = engine.play_map(known, stranger)["score"]
		won[0] += score.x
		won[1] += score.y
	check(won[0] > won[1], "over six maps the team that knows the map wins more rounds (%d to %d)" % won)
