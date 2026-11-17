class_name CareerCups
extends RefCounted
## Single-elimination cups. An edition invites organisations ([method CareerRepository.cup_candidates]),
## seeds them by tier and reputation and plays a bracket sized to the next power of two: the top
## seeds get byes when the field is short. Cup series live in the same tables as league series,
## so simulation, the human's playable series, form, reputation and series prize money work the
## same way. Each round's series are created once both sides are known; the final closes the
## edition through [WorldSeasons] (record, prizes, honours and, for tier 4 opens, promotion).

## A cup needs at least this many organisations to run.
const MIN_TEAMS: int = 4
## Cup rounds start on this day of the month so they do not land on league days (1st, 8th, ...).
const START_DAY_OF_MONTH: int = 4
const DAYS_BETWEEN_ROUNDS: int = 7


## Publishes every cup edition of [param year] that is not published yet (inside the caller's
## transaction).
static func ensure_cup_seasons(repo: CareerRepository, year: int) -> bool:
	for competition: CareerRecords.CompetitionRecord in repo.competitions():
		if competition.kind != "cup" or not repo.league_season(competition.id, year).is_empty():
			continue
		var start_day := GameDate.make(year, competition.start_month, START_DAY_OF_MONTH)
		var seeded := repo.cup_candidates(competition, start_day)
		if seeded.size() < MIN_TEAMS:
			continue
		if not repo.insert_league_season(competition.id, year, start_day, CareerCompetitions.LEAGUE_BEST_OF, seeded,
				first_round(seeded, start_day)) or not repo.insert_cup_seeds(competition.id, year, seeded):
			return false
	return true


## Smallest power of two that holds [param teams].
static func bracket_size(teams: int) -> int:
	var size := 2
	while size < teams:
		size *= 2
	return size


## Seed numbers in bracket order: seed 1 meets the last seed, and seeds 1 and 2 can only meet in
## the final.
static func bracket_order(size: int) -> Array[int]:
	var order: Array[int] = [1]
	while order.size() < size:
		var next: Array[int] = []
		var total := order.size() * 2 + 1
		for seed: int in order:
			next.append(seed)
			next.append(total - seed)
		order = next
	return order


## Bracket slots for [param seeded] organisations ("" is a bye).
static func slots(seeded: Array[String]) -> Array[String]:
	var list: Array[String] = []
	for seed: int in bracket_order(bracket_size(seeded.size())):
		list.append(seeded[seed - 1] if seed <= seeded.size() else "")
	return list


static func first_round(seeded: Array[String], start_day: int) -> Array[Dictionary]:
	var fixtures: Array[Dictionary] = []
	var list := slots(seeded)
	for pair: int in range(0, list.size(), 2):
		if not list[pair].is_empty() and not list[pair + 1].is_empty():
			fixtures.append({"round_number": 1, "scheduled_day": start_day, "home_id": list[pair], "away_id": list[pair + 1]})
	return fixtures


static func round_count(teams: int) -> int:
	var rounds := 0
	var size := bracket_size(teams)
	while size > 1:
		size >>= 1
		rounds += 1
	return rounds


## "Final", "Semi-finals", "Quarter-finals", "Round of 16" ...
static func round_name(round_number: int, teams: int) -> String:
	var remaining := bracket_size(teams) >> (round_number - 1)
	match remaining:
		2:
			return "Final"
		4:
			return "Semi-finals"
		8:
			return "Quarter-finals"
	return "Round of %d" % remaining


## Works out the bracket from the stored series: {rounds: Array of Array[String] (the sides alive
## at the start of each round), champion: String, eliminated: {org_id: round lost in}}.
static func bracket(seeded: Array[String], fixtures: Array[Dictionary]) -> Dictionary:
	var by_pair: Dictionary[String, Dictionary] = {}
	for fixture: Dictionary in fixtures:
		by_pair[_pair_key(int(fixture["round_number"]), str(fixture["home_id"]), str(fixture["away_id"]))] = fixture
	var alive := slots(seeded)
	var rounds: Array = [alive]
	var eliminated: Dictionary[String, int] = {}
	var round_number := 1
	while alive.size() > 1:
		var next: Array[String] = []
		for pair: int in range(0, alive.size(), 2):
			next.append(_winner(alive[pair], alive[pair + 1], by_pair.get(_pair_key(round_number, alive[pair], alive[pair + 1]), {}),
				round_number, eliminated))
		if next.has("?"):
			break
		alive = next
		rounds.append(alive)
		round_number += 1
	return {"rounds": rounds, "champion": alive[0] if alive.size() == 1 else "", "eliminated": eliminated}


## Daily: creates the series of rounds whose sides are now known and closes finished cups.
static func progress(repo: CareerRepository, day: int) -> bool:
	for season: Dictionary in repo.open_cup_seasons():
		var competition_id := str(season["competition_id"])
		var year := int(season["season_year"])
		var seeded := repo.cup_seeds(competition_id, year)
		var fixtures := repo.league_fixtures(competition_id, year)
		var state := bracket(seeded, fixtures)
		if not str(state["champion"]).is_empty():
			if not WorldSeasons.close_cup(repo, season, final_table(repo, competition_id, year, seeded, fixtures, state), day):
				return false
			continue
		if not _schedule_next(repo, season, state, fixtures, day):
			return false
	return true


## Final placings: champion, runner-up, then by the round each side went out in, series
## record and seed. Rows look like league standings ({organisation_id, name, won, lost, map_diff}).
static func final_table(repo: CareerRepository, competition_id: String, year: int, seeded: Array[String],
		fixtures: Array[Dictionary], state: Dictionary) -> Array[Dictionary]:
	var names: Dictionary[String, String] = {}
	for entrant: Dictionary in repo.league_entrants(competition_id, year):
		names[str(entrant["organisation_id"])] = str(entrant["name"])
	var rows: Array[Dictionary] = []
	for org_id: String in seeded:
		rows.append({"organisation_id": org_id, "name": names.get(org_id, org_id), "won": 0, "lost": 0, "map_diff": 0,
			"_seed": seeded.find(org_id), "_out": 99 if org_id == str(state["champion"]) else int(state["eliminated"].get(org_id, 0))})
	var index: Dictionary[String, Dictionary] = {}
	for row: Dictionary in rows:
		index[str(row["organisation_id"])] = row
	for fixture: Dictionary in fixtures:
		if fixture["home_maps"] == null:
			continue
		var difference := int(fixture["home_maps"]) - int(fixture["away_maps"])
		var home: Dictionary = index[str(fixture["home_id"])]
		var away: Dictionary = index[str(fixture["away_id"])]
		home["map_diff"] += difference
		away["map_diff"] -= difference
		home["won" if difference > 0 else "lost"] += 1
		away["lost" if difference > 0 else "won"] += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["_out"] != b["_out"]:
			return a["_out"] > b["_out"]
		if a["won"] != b["won"]:
			return a["won"] > b["won"]
		if a["map_diff"] != b["map_diff"]:
			return a["map_diff"] > b["map_diff"]
		return a["_seed"] < b["_seed"])
	return rows


static func _schedule_next(repo: CareerRepository, season: Dictionary, state: Dictionary, fixtures: Array[Dictionary], day: int) -> bool:
	var rounds: Array = state["rounds"]
	var round_number := rounds.size()
	var alive: Array[String] = []
	alive.assign(rounds[round_number - 1])
	var existing: Dictionary[String, bool] = {}
	for fixture: Dictionary in fixtures:
		existing[_pair_key(int(fixture["round_number"]), str(fixture["home_id"]), str(fixture["away_id"]))] = true
	var planned := int(season["start_day"]) + (round_number - 1) * DAYS_BETWEEN_ROUNDS
	for pair: int in range(0, alive.size(), 2):
		var home := alive[pair]
		var away := alive[pair + 1]
		if home.is_empty() or away.is_empty() or existing.has(_pair_key(round_number, home, away)):
			continue
		if not repo.insert_league_fixture(str(season["competition_id"]), int(season["season_year"]), round_number,
				maxi(planned, day + 1), home, away):
			return false
	return true


## The side that goes through: the other side of a bye, a decided series' winner, or "?" while
## the series is unplayed.
static func _winner(home: String, away: String, fixture: Dictionary, round_number: int, eliminated: Dictionary[String, int]) -> String:
	if home.is_empty() or away.is_empty():
		return away if home.is_empty() else home
	if fixture.is_empty() or fixture["home_maps"] == null:
		return "?"
	var home_won := int(fixture["home_maps"]) > int(fixture["away_maps"])
	if str(fixture["home_id"]) != home:
		home_won = not home_won
	eliminated[away if home_won else home] = round_number
	return home if home_won else away


static func _pair_key(round_number: int, first: String, second: String) -> String:
	return "%d|%s|%s" % [round_number, mini_string(first, second), second if first < second else first]


static func mini_string(first: String, second: String) -> String:
	return first if first < second else second
