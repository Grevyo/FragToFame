class_name CareerCompetitions
extends RefCounted
## Publishes round-robin league seasons from the fixed definitions in a career. The league calendar
## and organisation series belong to the career host and have no dependency on an FPS scene.

const LEAGUE_BEST_OF: int = 3
const DAYS_BETWEEN_ROUNDS: int = 7


static func ensure_league_seasons(repo: CareerRepository, year: int) -> bool:
	if year < 1:
		return false
	return repo.transaction(func() -> bool:
		for competition: CareerRecords.CompetitionRecord in repo.competitions():
			if competition.kind != "league" or not repo.league_season(competition.id, year).is_empty():
				continue
			var start_day := GameDate.make(year, competition.start_month, 1)
			var entrants := repo.eligible_organisations(competition, start_day)
			if entrants.size() < competition.team_count:
				continue
			entrants.resize(competition.team_count)
			var fixtures := round_robin(entrants, start_day)
			if not repo.insert_league_season(competition.id, year, start_day, LEAGUE_BEST_OF, entrants, fixtures):
				return false
		return true)


## The circle method gives every pair one meeting and every team at most one match per round.
## Odd fields have a rotating bye. Long calendars fit within one year of their start date.
static func round_robin(entrants: Array[String], start_day: int) -> Array[Dictionary]:
	var fixtures: Array[Dictionary] = []
	var rotation: Array[String] = entrants.duplicate()
	if rotation.size() % 2 != 0:
		rotation.append("")
	var rounds := rotation.size() - 1
	var spacing := mini(DAYS_BETWEEN_ROUNDS, floori(float(GameDate.DAYS_PER_YEAR - 1) / maxi(rounds - 1, 1)))
	@warning_ignore("integer_division")
	var pairs_per_round := rotation.size() / 2
	for round_index: int in rounds:
		for pair: int in pairs_per_round:
			var first := rotation[pair]
			var second := rotation[rotation.size() - 1 - pair]
			if first.is_empty() or second.is_empty():
				continue
			var swap_sides := (round_index + pair) % 2 != 0
			fixtures.append({
				"round_number": round_index + 1,
				"scheduled_day": start_day + round_index * spacing,
				"home_id": second if swap_sides else first,
				"away_id": first if swap_sides else second,
			})
		rotation.insert(1, rotation.pop_back())
	return fixtures


## Future match or simulation hosts can publish one final series score. A matching retry succeeds.
static func record_league_result(repo: CareerRepository, fixture_id: int, home_maps: int, away_maps: int) -> bool:
	return repo.transaction(func() -> bool:
		var fixture := repo.league_fixture(fixture_id)
		if fixture.is_empty() or int(fixture["scheduled_day"]) > repo.current_day():
			return false
		@warning_ignore("integer_division")
		var target := int(fixture["best_of"]) / 2 + 1
		if (mini(home_maps, away_maps) < 0 or mini(home_maps, away_maps) >= target
				or maxi(home_maps, away_maps) != target):
			return false
		if fixture["home_maps"] != null:
			return int(fixture["home_maps"]) == home_maps and int(fixture["away_maps"]) == away_maps
		return repo.store_league_score(fixture_id, home_maps, away_maps))


## Standings are derived from accepted results so a duplicate submission cannot double-count.
static func standings(entrants: Array[Dictionary], fixtures: Array[Dictionary]) -> Array[Dictionary]:
	var totals: Dictionary[String, Dictionary] = {}
	for entrant: Dictionary in entrants:
		totals[str(entrant["organisation_id"])] = entrant.merged({"won": 0, "lost": 0, "map_diff": 0})
	for fixture: Dictionary in fixtures:
		if fixture["home_maps"] == null:
			continue
		var home := totals[str(fixture["home_id"])]
		var away := totals[str(fixture["away_id"])]
		var difference := int(fixture["home_maps"]) - int(fixture["away_maps"])
		home["map_diff"] += difference
		away["map_diff"] -= difference
		if difference > 0:
			home["won"] += 1
			away["lost"] += 1
		else:
			away["won"] += 1
			home["lost"] += 1
	var table := totals.values()
	table.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["won"] != b["won"]:
			return a["won"] > b["won"]
		if a["map_diff"] != b["map_diff"]:
			return a["map_diff"] > b["map_diff"]
		return a["organisation_id"] < b["organisation_id"])
	return table
