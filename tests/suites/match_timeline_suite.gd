extends TestSuite
## Match view (Milestone 21 stage G): every simulated map's round-by-round story (plans, buys,
## kill feed, economy, scoreboard), stored with the map and read back for the match view.

const MAP_ID: String = "map_f2f_kilnmarket"
const TEST_ROOT: String = "user://tests/match_timeline"


func suite_name() -> String:
	return "Match view timelines"


func run() -> void:
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	check(map != null, "the test map has a simulation graph")
	if map == null:
		return
	_test_planned(map)
	_test_duel_chain()
	_test_storage(map)


func _team(name: String, level: float) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = name
	team.name = name
	var roles: Array[StringName] = [&"igl", &"sniper", &"entry", &"lurker", &"support"]
	for i: int in 5:
		var player := MatchEngine.SimPlayer.new()
		player.id = "%s_%d" % [name, i]
		player.name = "Player %s%d" % [name, i]
		player.role = roles[i]
		for key: StringName in CareerCatalog.ABILITIES:
			player.skills[key] = roundi(level)
		team.players.append(player)
	return team


func _play(map: SimMap, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var engine := MatchEngine.new(rng, 8)
	engine.sim_map = map
	return engine.play_map(_team("H", 66.0), _team("A", 64.0))


func _test_planned(map: SimMap) -> void:
	section("A map's round-by-round story")
	var flashed := 0
	var headshots := 0
	var unnamed: Array[String] = []
	for seed_value: int in [31, 32]:
		var played := _play(map, seed_value)
		var timeline := played["timeline"] as Dictionary
		var score: Vector2i = played["score"]
		var rounds := timeline["rounds"] as Array
		if seed_value == 31:
			check(int(timeline["format_version"]) == MatchTimeline.FORMAT_VERSION and str(timeline["map_id"]) == MAP_ID,
				"the timeline names its format and map")
			check(rounds.size() == score.x + score.y and (timeline["score"] as Array) == [score.x, score.y],
				"one entry per round, ending on the final score (%d–%d)" % [score.x, score.y])
			var last := rounds.back() as Dictionary
			check((last["score"] as Array) == [score.x, score.y], "the running score ends where the map did")
			var deaths := 0
			for line: Array in timeline["scoreboard"] as Array:
				deaths += int(line[1])
			var feed := 0
			var plans_ok := true
			var eco_ok := true
			for round_data: Dictionary in rounds:
				feed += (round_data["kills"] as Array).size()
				plans_ok = plans_ok and (round_data["plans"] as Array).size() == 2 and (round_data["buys"] as Array).size() == 2
				eco_ok = eco_ok and (round_data["eco"] as Array).size() == 10
			check(feed == deaths, "the kill feed holds every death on the scoreboard (%d)" % deaths)
			check(plans_ok, "every round shows both leaders' plans and buys")
			check(eco_ok, "every round shows each player's money and kit")
			check((timeline["players"] as Array).size() == 10 and str((timeline["players"] as Array)[0]["name"]) == "Player H0",
				"players are listed by name")
			var pistol := (rounds[0]["eco"] as Array)[0] as Array
			var category := str(WeaponCatalog.DATA.get(StringName(str(pistol[1])), {}).get("category", ""))
			check(category == "secondary", "the pistol round's kit is a pistol (%s)" % MatchTimeline.weapon_name(str(pistol[1])))
		for round_data: Dictionary in rounds:
			for kill: Array in round_data["kills"] as Array:
				if int(kill[5]) >= 0:
					flashed += 1
				if bool(kill[4]):
					headshots += 1
				var name := MatchTimeline.weapon_name(str(kill[3]))
				if name == str(kill[3]) and not unnamed.has(name):
					unnamed.append(name)
	check(headshots > 0 and flashed > 0, "the feed marks headshots and kills on flashed players (%d, %d)" % [headshots, flashed])
	check(unnamed.is_empty(), "every weapon in the feed has a name (%s)" % [unnamed])
	check(MatchTimeline.how_text("defused") == "bomb defused", "round endings read as words")


func _test_duel_chain() -> void:
	section("A map without a simulation graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var played := MatchEngine.new(rng, 8).play_map(_team("H", 66.0), _team("A", 64.0))
	var timeline := played["timeline"] as Dictionary
	var score: Vector2i = played["score"]
	var rounds := timeline["rounds"] as Array
	check(rounds.size() == score.x + score.y, "the duel chain has a round-by-round story too")
	check(rounds.all(func(r: Dictionary) -> bool: return (r["buys"] as Array).size() == 2 and not r.has("eco")),
		"with team buys, and no per-player economy")


func _test_storage(map: SimMap) -> void:
	section("Kept with the map")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	var path := TEST_ROOT + "/timeline.db"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var repo := CareerRepository.new()
	check(repo.open(path).is_empty(), "a career database opens at the current schema")
	var timeline := _play(map, 31)["timeline"] as Dictionary
	var league := CareerRepository.league_timeline_key(7, 2)
	var own := CareerRepository.career_timeline_key("fix_abc")
	check(repo.insert_sim_timeline(league, 10, timeline) and repo.insert_sim_timeline(own, 10, timeline), "timelines are stored")
	var back := repo.sim_timeline(league)
	# JSON numbers come back as floats: compare both sides after the same trip.
	var sent := JSON.stringify(JSON.parse_string(JSON.stringify(timeline["rounds"])))
	check(not back.is_empty() and JSON.stringify(back["rounds"]) == sent, "and read back as they were")
	check(repo.sim_timeline("L0:0").is_empty() and not repo.has_sim_timeline("L0:0"), "a map without one reads as none")
	check(repo.prune_sim_timelines(50) and not repo.has_sim_timeline(league) and repo.has_sim_timeline(own),
		"old world timelines are dropped; the human's own are kept")
	repo.close()
