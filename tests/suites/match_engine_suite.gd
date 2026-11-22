extends TestSuite
## The round-by-round match engine and how its series feed the career world.

const TEST_ROOT: String = "user://tests/match_engine"
const PROFILE: Dictionary = {"first_name": "Mara", "last_name": "Quist", "nickname": "Tally",
	"nation_id": "se", "preferred_role": &"entry", "difficulty": &"standard", "age": 20}


func suite_name() -> String:
	return "Round-by-round match engine (Milestone 14)"


func run() -> void:
	_test_engine()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_career(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _team(name: String, level: float, rng: RandomNumberGenerator, traits: Dictionary = {}) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = name
	team.name = name
	var roles: Array[StringName] = [&"igl", &"sniper", &"entry", &"rifler", &"support"]
	for i: int in 5:
		var player := MatchEngine.SimPlayer.new()
		player.id = "%s_%d" % [name, i]
		player.name = player.id
		player.role = roles[i]
		player.traits = traits.duplicate()
		for key: StringName in CareerCatalog.ABILITIES:
			player.skills[key] = clampi(roundi(rng.randfn(level, 4.0)), 1, 99)
		team.players.append(player)
	return team


func _test_engine() -> void:
	section("A map, round by round")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var engine := MatchEngine.new(rng, 8)
	var home := _team("H", 70.0, rng)
	var away := _team("A", 70.0, rng)
	var played := engine.play_map(home, away)
	var score: Vector2i = played["score"]
	var high := maxi(score.x, score.y)
	var low := mini(score.x, score.y)
	check(high == MatchEngine.winner_score(low, 8), "the map ends with a legal score (%d–%d)" % [score.x, score.y])
	check((played["rounds"] as Array).size() == score.x + score.y, "every round is logged")
	var home_kills := 0
	var away_deaths := 0
	var ratings := 0.0
	for player: MatchEngine.SimPlayer in home.players:
		home_kills += int(played["players"][player.id]["kills"])
	for player: MatchEngine.SimPlayer in away.players:
		away_deaths += int(played["players"][player.id]["deaths"])
	for id: String in played["players"]:
		ratings += float(played["players"][id]["rating"])
	check(home_kills == away_deaths, "every kill is someone's death (%d)" % home_kills)
	check(played["players"].has(str(played["mvp"])) and ratings / 10.0 > 0.6 and ratings / 10.0 < 1.4,
		"players get lines and ratings, and the map has an MVP")
	check(MatchEngine.winner_score(8, 8) == 12 and MatchEngine.winner_score(11, 8) == 15, "overtime follows the competitive rule")

	var replay_a := RandomNumberGenerator.new()
	replay_a.seed = 99
	var replay_b := RandomNumberGenerator.new()
	replay_b.seed = 99
	var first := MatchEngine.new(replay_a, 8).play_map(_team("H", 70.0, replay_a), _team("A", 66.0, replay_a))
	var second := MatchEngine.new(replay_b, 8).play_map(_team("H", 70.0, replay_b), _team("A", 66.0, replay_b))
	check(first["score"] == second["score"] and first["mvp"] == second["mvp"], "the same dice replay the same map")

	section("Skill matters, but it is not a foregone conclusion")
	var even := 0
	var gap := 0
	var close := 0
	for i: int in 160:
		var level_a := _team("A", 68.0, rng)
		var level_b := _team("B", 68.0, rng)
		var result: Vector2i = engine.play_map(level_a, level_b)["score"]
		if result.x > result.y:
			even += 1
		if absi(result.x - result.y) <= 3:
			close += 1
		var strong := _team("S", 78.0, rng)
		var weak := _team("W", 63.0, rng)
		var mismatch: Vector2i = engine.play_map(strong, weak)["score"]
		if mismatch.x > mismatch.y:
			gap += 1
	check(even > 50 and even < 110, "even sides split their maps (%d of 160)" % even)
	check(close > 30, "many even maps are close (%d of 160 within three rounds)" % close)
	check(gap > 130 and gap < 160, "a much stronger side usually wins, but not always (%d of 160)" % gap)

	section("Personality on the server")
	var clutch_rng := RandomNumberGenerator.new()
	clutch_rng.seed = 5
	var clutch_engine := MatchEngine.new(clutch_rng, 8)
	var cold := 0
	var hot := 0
	for i: int in 120:
		var plain: Dictionary = clutch_engine.play_map(_team("P", 70.0, clutch_rng), _team("O", 70.0, clutch_rng))["players"]
		var clutchers: Dictionary = clutch_engine.play_map(_team("C", 70.0, clutch_rng, {&"tr_clutch_player": 3}),
			_team("O", 70.0, clutch_rng))["players"]
		for id: String in plain:
			if id.begins_with("P"):
				cold += int(plain[id]["clutch_wins"])
		for id: String in clutchers:
			if id.begins_with("C"):
				hot += int(clutchers[id]["clutch_wins"])
	check(hot > cold, "clutch players win more clutches (%d vs %d)" % [hot, cold])
	var steady_spread := _spread(clutch_engine, clutch_rng, {&"tr_steady": 3})
	var streaky_spread := _spread(clutch_engine, clutch_rng, {&"tr_streaky": 3})
	check(streaky_spread > steady_spread, "streaky players swing more than steady ones (%.2f vs %.2f)" % [streaky_spread, steady_spread])
	check(CareerSeriesEngine.next_morale(0.0, 1.5, true, {}) > 0.0 and CareerSeriesEngine.next_morale(0.0, 0.6, false, {}) < 0.0
		and absf(CareerSeriesEngine.next_morale(0.0, 0.6, false, {&"tr_calm": 3})) < absf(CareerSeriesEngine.next_morale(0.0, 0.6, false, {})),
		"morale follows performance, and calm players take it less to heart")
	var empty := MatchEngine.SimTeam.new()
	check(engine.play_map(_team("H", 60.0, rng), empty)["score"] == Vector2i(9, 0), "a side with nobody to field forfeits")


## Standard deviation of one team's ratings across maps.
func _spread(engine: MatchEngine, rng: RandomNumberGenerator, traits: Dictionary) -> float:
	var values: Array[float] = []
	for i: int in 60:
		var team := _team("T", 70.0, rng, traits)
		var lines: Dictionary = engine.play_map(team, _team("O", 70.0, rng))["players"]
		for player: MatchEngine.SimPlayer in team.players:
			values.append(float(lines[player.id]["rating"]))
	var mean := 0.0
	for value: float in values:
		mean += value
	mean /= values.size()
	var total := 0.0
	for value: float in values:
		total += (value - mean) * (value - mean)
	return sqrt(total / values.size())


func _test_career(app: Node) -> void:
	section("Simulated series in a career")
	var problem: String = app.call("new_career", "Engine tests", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var repo := (app.get("career") as CareerSession).repo
	var first_day := int(repo.db.scalar("SELECT MIN(scheduled_day) FROM league_fixture;", [], 0))
	var dice := RandomNumberGenerator.new()
	dice.seed = 31
	check(CareerCalendar.advance_to(repo, first_day + 1, dice), "the first series day passes")
	var played := repo.db.rows("SELECT * FROM league_fixture WHERE scheduled_day = ? AND home_maps IS NOT NULL;", [first_day])
	check(not played.is_empty(), "series were played (%d)" % played.size())
	if played.is_empty():
		return
	var series := played[0]
	var maps := repo.sim_maps(int(series["id"]))
	check(maps.size() == int(series["home_maps"]) + int(series["away_maps"]), "every map of the series is stored with its score")
	var home_maps := 0
	for map: Dictionary in maps:
		if int(map["home_rounds"]) > int(map["away_rounds"]):
			home_maps += 1
	check(home_maps == int(series["home_maps"]) and maps.all(func(m: Dictionary) -> bool: return m["mvp_name"] != null),
		"the maps add up to the series score and each has an MVP")
	var lines := int(repo.db.scalar("SELECT COUNT(*) FROM sim_player_map WHERE league_fixture_id = ?;", [int(series["id"])], 0))
	check(lines == maps.size() * 10, "every player has a line for every map (%d)" % lines)
	var moved := int(repo.db.scalar("SELECT COUNT(*) FROM player_morale WHERE value <> 0;", [], 0))
	check(moved > 0, "morale moved for the players who played (%d)" % moved)
	var someone := str(repo.db.scalar("SELECT player_id FROM sim_player_map WHERE league_fixture_id = ? LIMIT 1;", [int(series["id"])], ""))
	var form := repo.sim_form(someone, 0)
	check(int(form["maps"]) >= 1 and float(form["rating"]) > 0.0, "a player's simulated form adds up their lines")
	var unmapped := int(repo.db.scalar("SELECT COUNT(*) FROM sim_player_map WHERE map_id = '';", [], -1))
	check(unmapped == 0, "every simulated line records its map")
	var map_id := str(maps[0]["map_id"])
	var known := repo.team_map_history(str(series["home_id"]), map_id, 0)
	check(int(known["on_map"]) >= 1 and int(known["maps"]) >= int(known["on_map"]), "a team's history counts the maps it played (%s)" % known)
	var ids: Array[String] = [someone]
	var history := repo.player_map_history(ids, map_id, 0)
	check(history.has(someone) and int(history[someone]["maps"]) >= 1, "a player's history on a map is read back")
	var key := CareerRepository.league_timeline_key(int(series["id"]), 1)
	check(repo.has_sim_timeline(key), "each map of a world series keeps its round-by-round story")
	var hub := spawn_scene("res://scenes/career_hub/career_hub.tscn")
	if hub != null:
		await wait_frames(2)
		var opened: bool = hub.call("navigate", &"match_view", {"key": key})
		await wait_frames(1)
		var page := hub.get("current_page") as CareerPage
		check(opened and page != null and page.get_page_title() != "Round by round" and page.get_child_count() > 2,
			"the match view shows the map round by round (%d cards)" % (page.get_child_count() if page != null else 0))
		await despawn(hub)

	section("A month of the engine")
	var month_end := first_day + 40
	check(CareerCalendar.advance_to(repo, month_end, dice), "the calendar runs a busy month")
	var faded := int(repo.db.scalar("SELECT MAX(ABS(value)) FROM player_morale;", [], 0))
	check(faded <= 20, "morale stays within its range (largest %d)" % faded)
	var opinions := int(repo.db.scalar("""SELECT COUNT(*) FROM player_perceived pp JOIN player_ability pa
		ON pa.player_id = pp.player_id AND pa.ability = pp.ability
		WHERE pp.ability IN ('aim', 'reaction', 'crosshair_placement') AND ABS(pp.value - pa.value) > ?;""",
		[CareerSeriesEngine.OPINION_LIMIT + 30], 0))
	check(opinions == 0, "opinion follows form but never runs far from the truth")
	var top := repo.top_performers(str(series["competition_id"]), int(series["season_year"]), 1)
	check(not top.is_empty() and float(top[0]["rating"]) >= float(top[top.size() - 1]["rating"]),
		"the competition lists its top performers")


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
