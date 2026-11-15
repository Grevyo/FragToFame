extends TestSuite
## Pure coverage for round counters and the independent F2F rating.

func suite_name() -> String:
	return "Detailed match statistics (Milestone 11)"


func run() -> void:
	var result := MatchResult.create("telemetry_test", 2, 0, MatchResult.SOURCE_FPS_RUNTIME)
	result.events = [
		{"type": "match_started", "fixture_id": result.fixture_id, "lineup": {"a": 0, "b": 0, "c": 1, "d": 1, "e": 1}},
		{"type": "round_started", "round": 1},
		{"type": "shot", "player": "a", "weapon": "rifle", "round": 1},
		{"type": "damage", "player": "a", "victim": "c", "hp": 45, "weapon": "rifle", "round": 1},
		{"type": "shot", "player": "b", "weapon": "pistol", "round": 1},
		{"type": "damage", "player": "b", "victim": "c", "hp": 55, "weapon": "pistol", "round": 1},
		{"type": "kill", "killer": "b", "victim": "c", "headshot": true, "weapon": "pistol", "round": 1, "t": 1.0},
		{"type": "shot", "player": "a", "weapon": "rifle", "round": 1},
		{"type": "kill", "killer": "d", "victim": "b", "weapon": "pistol", "round": 1, "t": 3.0},
		{"type": "shot", "player": "a", "weapon": "rifle", "round": 1},
		{"type": "damage", "player": "a", "victim": "d", "hp": 100, "weapon": "rifle", "round": 1},
		{"type": "kill", "killer": "a", "victim": "d", "weapon": "rifle", "round": 1, "t": 5.0},
		{"type": "shot", "player": "a", "weapon": "rifle", "round": 1},
		{"type": "damage", "player": "a", "victim": "e", "hp": 100, "weapon": "rifle", "round": 1},
		{"type": "kill", "killer": "a", "victim": "e", "weapon": "rifle", "round": 1, "t": 6.0},
		{"type": "round_ended", "round": 1, "winner_team": 0},
		{"type": "shot", "player": "a", "weapon": "rifle", "round": 1},
		{"type": "round_started", "round": 2},
		{"type": "bomb_planted", "player": "a", "round": 2},
		{"type": "round_ended", "round": 2, "winner_team": 0},
		{"type": "match_ended", "round": 2},
	]

	var lines := MatchStatistics.calculate(result)
	check(lines.size() == 5, "records every participant as part of the match")
	if lines.is_empty():
		return
	var a := lines["a"]
	var b := lines["b"]
	var c := lines["c"]
	check(a["kills"] == 2 and b["kills"] == 1 and b["deaths"] == 1 and a["assists"] == 1,
		"K/D/A credits one eligible damage assist")
	check(a["damage"] == 245 and a["shots"] == 4 and a["hits"] == 3 and a["first_hits"] == 1
		and (a["weapons"]["rifle"] as Dictionary).get("shots") == 4,
		"counts misses, first-shot hits and health damage, excluding post-round fire")
	check(b["headshot_kills"] == 1 and b["opening_kills"] == 1 and c["opening_deaths"] == 1,
		"records headshot and opening kills separately")
	check(a["trade_kills"] == 1,
		"credits the teammate who trades a death in the five-second window")
	check(b["traded_deaths"] == 1 and c["traded_deaths"] == 1
		and a["kast_rounds"] == 2 and b["kast_rounds"] == 2 and c["kast_rounds"] == 2,
		"trade credit contributes to KAST even for a player who died")
	check(a["clutch_attempts"] == 1 and a["clutch_wins"] == 1 and a["clutches"]["2"]["wins"] == 1
		and a["plants"] == 1, "records a 1v2 clutch win and objective actions")
	var doubled := a.duplicate()
	for counter: String in MatchStatistics.COUNTERS:
		doubled[counter] = 2 * int(a[counter])
	check(MatchStatistics.rating(a) == MatchStatistics.rating(doubled), "F2F rating normalises for match length")
	check(MatchStatistics.rating(MatchStatistics.empty_counts()) == 0.0, "empty counts are safe to rate")
	result.home_score = 1
	result.away_score = 1
	check(MatchStatistics.calculate(result).is_empty(), "rejects events that disagree with the final score")
