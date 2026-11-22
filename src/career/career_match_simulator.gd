class_name CareerMatchSimulator
extends RefCounted
## DEVELOPMENT OPTION: resolves the player's pending career match without playing it, so days
## can be tested quickly. Each map goes through the same round-by-round [MatchEngine] as every
## simulated world series: AI players with their true abilities, the human with their perceived
## values (what the world believes about them), traits and morale. The engine's player lines
## are kept as simulated lines (`sim_player_map`), never as recorded match statistics.
##
## A simulated result carries [constant MatchResult.SOURCE_SIMULATION] and no telemetry, so it
## records no statistics or performance rating and changes no opinions. It does count like a
## played result (owner, 2026-11-17): amateur matches move ELO and reputation, league series
## move the human's reputation with their organisation's. League series simulate every
## remaining map; trials judge a win as a pass.

const MAX_MAPS: int = 5


## Strength of a lineup: AI abilities, human perceived rating ([param human_ratings] by id).
static func lineup_strength(lineup: Array[Dictionary], human_ratings: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for member: Dictionary in lineup:
		var id := str(member["player_id"])
		if bool(member.get("is_human", false)):
			total += float(human_ratings.get(id, 0))
			count += 1
			continue
		for value: Variant in (member.get("abilities", {}) as Dictionary).values():
			total += float(value)
			count += 1
	return total / count if count > 0 else 0.0


## A legal final score for one map of [param max_rounds]: the winner from the map chance, the
## loser's rounds closer to the winner's when the sides are even.
static func map_score(rng: RandomNumberGenerator, home_strength: float, away_strength: float, max_rounds: int) -> Vector2i:
	var chance := SeriesSimulator.map_win_chance(home_strength, away_strength)
	var closeness := 1.0 - absf(chance - 0.5) * 1.6
	var loser := clampi(roundi(rng.randf_range(0.25, 1.0) * closeness * (max_rounds - 1)), 0, max_rounds - 1)
	var winner := max_rounds + 1
	return Vector2i(winner, loser) if rng.randf() < chance else Vector2i(loser, winner)


## Simulates the pending match (and the rest of its league series). Returns {ok, message, maps}.
static func simulate_pending(repo: CareerRepository, player_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var dice := rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	var lines: PackedStringArray = []
	var series_id := -1
	# Rounds each player has played so far in this series (fatigue carries from map to map).
	var legs: Dictionary = {}
	for i: int in MAX_MAPS:
		var fixture := repo.pending_fixture(player_id)
		if fixture == null:
			break
		var series_map := repo.series_map_for_fixture(fixture.setup.fixture_id)
		var this_series := int(series_map.get("league_fixture_id", -1))
		if i > 0 and (series_map.is_empty() or this_series != series_id):
			break
		series_id = this_series
		var setup := fixture.setup
		var ratings: Dictionary = {}
		for lineup: Array[Dictionary] in [setup.home_lineup, setup.away_lineup]:
			for member: Dictionary in lineup:
				if bool(member.get("is_human", false)):
					ratings[str(member["player_id"])] = repo.perceived_rating(str(member["player_id"]))
		var home := lineup_strength(setup.home_lineup, ratings) + WorldSimulation.form_bonus(repo, setup.home_team_id)
		var away := lineup_strength(setup.away_lineup, ratings) + WorldSimulation.form_bonus(repo, setup.away_team_id)
		var played := engine_map(repo, setup, dice, legs, fixture.scheduled_day)
		var score: Vector2i = played["score"]
		if home <= 0.0 and away <= 0.0:
			score = map_score(dice, home, away, setup.max_rounds)
		var result := MatchResult.create(setup.fixture_id, score.x, score.y, MatchResult.SOURCE_SIMULATION)
		result.map_id = setup.map_id
		var problem := CareerFixtures.record_result(repo, player_id, result, true)
		if not problem.is_empty():
			return {"ok": false, "message": problem, "maps": lines.size()}
		if not _store_lines(repo, fixture, setup, played, score, this_series):
			return {"ok": false, "message": "Could not store the simulated lines.", "maps": lines.size()}
		lines.append("%s %d–%d %s" % [setup.home_team_name, score.x, score.y, setup.away_team_name])
	if lines.is_empty():
		return {"ok": false, "message": "There is no match to simulate.", "maps": 0}
	return {"ok": true, "message": "Simulated (dev): " + "; ".join(lines) + ".", "maps": lines.size()}


## One map of a career fixture through the match engine (home side starts on attack), with each
## side's history on the map from before [param day] and the rounds in [param legs] (player id ->
## rounds played earlier in the series, updated).
static func engine_map(repo: CareerRepository, setup: MatchSetup, dice: RandomNumberGenerator, legs: Dictionary = {},
		day: int = -1) -> Dictionary:
	var engine := MatchEngine.new(dice, setup.max_rounds)
	engine.sim_map = SimMap.for_map(setup.map_id)
	var home := MatchEngine.SimTeam.new()
	home.id = setup.home_team_id
	home.name = setup.home_team_name
	home.form = repo.organisation_form(setup.home_team_id)
	var away := MatchEngine.SimTeam.new()
	away.id = setup.away_team_id
	away.name = setup.away_team_name
	away.form = repo.organisation_form(setup.away_team_id)
	for member: Dictionary in setup.home_lineup:
		home.players.append(CareerSeriesEngine.sim_player(repo, member))
	for member: Dictionary in setup.away_lineup:
		away.players.append(CareerSeriesEngine.sim_player(repo, member))
	for team: MatchEngine.SimTeam in [home, away]:
		if day >= 0:
			CareerSeriesEngine.apply_history(repo, team, setup.map_id, day)
		for player: MatchEngine.SimPlayer in team.players:
			player.series_rounds = int(legs.get(player.id, 0))
	var played := engine.play_map(home, away)
	for team: MatchEngine.SimTeam in [home, away]:
		for player: MatchEngine.SimPlayer in team.players:
			legs[player.id] = player.series_rounds
	return played


static func _store_lines(repo: CareerRepository, fixture: CareerFixture, setup: MatchSetup, played: Dictionary, score: Vector2i,
		series_id: int) -> bool:
	var stats: Dictionary = played.get("players", {})
	for side: Array in [[setup.home_lineup, setup.home_team_id, score.x > score.y], [setup.away_lineup, setup.away_team_id, score.y > score.x]]:
		for member: Dictionary in side[0]:
			var line: Dictionary = stats.get(str(member["player_id"]), {})
			if line.is_empty():
				continue
			if not repo.insert_sim_line(fixture.scheduled_day, series_id, setup.fixture_id, 1, str(member["player_id"]),
					str(side[1]), line, bool(side[2]), setup.map_id):
				return false
	return true
