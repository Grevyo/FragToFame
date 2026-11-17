class_name CareerMatchSimulator
extends RefCounted
## DEVELOPMENT OPTION: resolves the player's pending career match without playing it, so days
## can be tested quickly. It uses the same model as every simulated world series
## ([SeriesSimulator]): each side's strength is the mean ability of its lineup (AI players' true
## abilities; human players' perceived values, i.e. what the world believes about them) plus the
## organisation's form, and the map goes to the home side with the logistic map-win chance.
##
## A simulated result carries [constant MatchResult.SOURCE_SIMULATION] and no telemetry, so it
## records no statistics and never moves the human's ELO or reputation (only played games do).
## League series simulate every remaining map; trials judge a win as a pass.

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
		var score := map_score(dice, home, away, setup.max_rounds)
		var result := MatchResult.create(setup.fixture_id, score.x, score.y, MatchResult.SOURCE_SIMULATION)
		result.map_id = setup.map_id
		var problem := CareerFixtures.record_result(repo, player_id, result, true)
		if not problem.is_empty():
			return {"ok": false, "message": problem, "maps": lines.size()}
		lines.append("%s %d–%d %s" % [setup.home_team_name, score.x, score.y, setup.away_team_name])
	if lines.is_empty():
		return {"ok": false, "message": "There is no match to simulate.", "maps": 0}
	return {"ok": true, "message": "Simulated (dev): " + "; ".join(lines) + ".", "maps": lines.size()}
