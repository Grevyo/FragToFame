extends TestSuite
## Same events as a played match (Milestone 21 stage E): a simulated map logs the FPS runtime's
## event stream, and every statistic comes from it through [MatchStatistics], the reducer a played
## match goes through.

const MAP_ID: String = "map_f2f_kilnmarket"
## Counters a played match and a simulated one must both produce.
const MUST_HAPPEN: Array[String] = ["kills", "assists", "headshot_kills", "first_shots", "first_hits", "opening_kills",
	"trade_kills", "traded_deaths", "clutch_attempts", "plants", "utility_thrown", "utility_damage", "enemies_flashed",
	"flash_assists"]


func suite_name() -> String:
	return "Simulated match events"


func run() -> void:
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	check(map != null, "the test map has a simulation graph")
	if map == null:
		return
	_test_stream(map)
	_test_duel_chain()


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


func _play(map: SimMap, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var engine := MatchEngine.new(rng, 8)
	engine.sim_map = map
	return engine.play_map(_team("H", 66.0), _team("A", 64.0))


## The played-match reducer run on [param played]'s events.
static func reduce(played: Dictionary) -> Dictionary[String, Dictionary]:
	var score: Vector2i = played["score"]
	var result := MatchResult.new()
	result.fixture_id = MatchEngine.SIM_FIXTURE
	result.home_score = score.x
	result.away_score = score.y
	result.rounds_played = score.x + score.y
	result.events.assign(played["events"] as Array)
	return MatchStatistics.calculate(result)


func _test_stream(map: SimMap) -> void:
	section("A simulated map logs a played match's events")
	var played := _play(map, 21)
	var events := played["events"] as Array
	check(not events.is_empty() and (events.front() as Dictionary)["type"] == "match_started"
		and (events.back() as Dictionary)["type"] == "match_ended", "the stream opens with match_started and closes with match_ended")
	var types: Dictionary[String, int] = {}
	var ordered := true
	var last_t := 0.0
	for event: Dictionary in events:
		types[str(event["type"])] = types.get(str(event["type"]), 0) + 1
		ordered = ordered and float(event["t"]) >= last_t
		last_t = float(event["t"])
	check(ordered, "event times only move forward")
	var score: Vector2i = played["score"]
	check(types.get("round_started", 0) == score.x + score.y and types.get("round_ended", 0) == score.x + score.y,
		"one round_started and one round_ended per round (%d rounds)" % (score.x + score.y))
	var missing: Array[String] = []
	for type: String in ["shot", "damage", "kill", "utility_thrown", "flashed", "bomb_planted"]:
		if types.get(type, 0) == 0:
			missing.append(type)
	check(missing.is_empty(), "shots, damage, kills, grenades, flashes and plants are all logged (missing: %s)" % [missing])

	var lines := reduce(played)
	var players := played["players"] as Dictionary
	var same := not lines.is_empty() and lines.size() == players.size()
	for id: String in lines:
		var line: Dictionary = (players[id] as Dictionary).duplicate(true)
		line.erase("rating")
		same = same and JSON.stringify(line, "", true) == JSON.stringify(lines[id], "", true)
	check(same, "every statistic is exactly what the played-match reducer makes of the stream")

	var kills_ok := true
	var shots_ok := true
	for id: String in lines:
		var kills := events.filter(func(e: Dictionary) -> bool: return e["type"] == "kill" and e["killer"] == id).size()
		var shots := events.filter(func(e: Dictionary) -> bool: return e["type"] == "shot" and e.get("player", "") == id).size()
		kills_ok = kills_ok and int(lines[id]["kills"]) <= kills
		shots_ok = shots_ok and int(lines[id]["shots"]) == shots
	check(kills_ok and shots_ok, "a player's kills and shots are their own kill and shot events")

	var totals := MatchStatistics.empty_counts()
	for seed_value: int in [21, 22, 23]:
		var lines_for := reduce(_play(map, seed_value)) if seed_value != 21 else lines
		for id: String in lines_for:
			for key: String in MatchStatistics.COUNTERS:
				totals[key] = int(totals[key]) + int(lines_for[id][key])
	var absent: Array[String] = []
	for key: String in MUST_HAPPEN:
		if int(totals[key]) == 0:
			absent.append(key)
	check(absent.is_empty(), "openings, trades, assists, flash assists, clutches and utility all show up (absent: %s)" % [absent])
	check(int(totals["hits"]) <= int(totals["shots"]) and int(totals["headshot_kills"]) <= int(totals["kills"])
		and int(totals["first_hits"]) <= int(totals["first_shots"]), "hits, headshots and first hits never exceed what they count from")
	var again := _play(map, 21)
	check(JSON.stringify(again["events"]) == JSON.stringify(events), "the same seed logs the same events")


func _test_duel_chain() -> void:
	section("A map without a simulation graph logs events too")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var engine := MatchEngine.new(rng, 8)
	var played := engine.play_map(_team("H", 66.0), _team("A", 64.0))
	var lines := reduce(played)
	check(not lines.is_empty(), "the duel chain's stream reduces like a played match's")
	var kills := 0
	var deaths := 0
	var damage := 0
	var trades := 0
	var assists := 0
	for id: String in lines:
		kills += int(lines[id]["kills"])
		deaths += int(lines[id]["deaths"])
		damage += int(lines[id]["damage"])
		trades += int(lines[id]["trade_kills"])
		assists += int(lines[id]["assists"])
		check(int((played["players"] as Dictionary)[id]["kills"]) == int(lines[id]["kills"]), "%s's line comes from the stream" % id)
	check(kills == deaths and damage >= 100 * deaths, "every kill is a death behind 100 damage (%d kills, %d damage)" % [kills, damage])
	check(trades > 0 and assists > 0, "the duel chain's trades and assists come through the reducer (%d trades, %d assists)" % [trades, assists])
