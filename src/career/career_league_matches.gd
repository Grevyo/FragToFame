class_name CareerLeagueMatches
extends RefCounted
## Playable league series for an organisation with a human under contract. When a series is due
## the human's next map is scheduled as a career fixture; each saved map either books the next
## map the same day or, once one side reaches the best-of target, publishes the series score and
## feeds form and reputation exactly like a simulated series. The human's side is always the
## fixture's home team (the FPS runtime plays the human at home); [code]human_home[/code]
## records which side that is in the league table.

## Maps a series is played on, in order (map selection and veto are planned).
const MAP_POOL: Array[String] = [OfficialMaps.DEFAULT_ID]
## League maps are MR8 (first to 9; overtime per [MatchRules]). Configurable per competition with M19.
const MAX_ROUNDS: int = 8


## Daily: books the first map of the oldest due series for every contracted human with no
## pending match. Returns false if a write failed.
static func schedule_due(repo: CareerRepository, day: int) -> bool:
	for human: CareerRecords.PlayerRecord in repo.human_players():
		var contract := repo.active_contract(human.id)
		if contract == null or repo.pending_fixture(human.id) != null:
			continue
		var due := repo.due_series_for(contract.organisation_id, day)
		if due.is_empty():
			continue
		var series := due[0]
		var maps := repo.series_maps(int(series["id"]))
		if not _schedule_map(repo, human, contract.organisation_id, series, maps.size() + 1, day):
			return false
	return true


## Saves one played map (inside the result transaction). Sets [code]finished[0][/code] to true
## when the series is decided; otherwise the next map is booked for the same day.
static func record_map(repo: CareerRepository, fixture: CareerFixture, series_map: Dictionary,
		finished: Array[bool]) -> bool:
	var series := repo.league_fixture(int(series_map["league_fixture_id"]))
	if series.is_empty():
		return false
	@warning_ignore("integer_division")
	var target := int(series["best_of"]) / 2 + 1
	var human_home := int(series_map["human_home"]) == 1
	var own := 0
	var other := 0
	for played: Dictionary in repo.series_maps(int(series["id"])):
		var map_fixture := repo.fixture_by_id(str(played["career_fixture_id"]))
		if map_fixture == null or map_fixture.result == null:
			continue
		var result := map_fixture.result
		if result.home_score > result.away_score:
			own += 1
		else:
			other += 1
	if own < target and other < target:
		finished.append(false)
		var human := repo.get_player(fixture.player_id)
		var org_id := fixture.setup.home_team_id
		return _schedule_map(repo, human, org_id, _named(repo, series), own + other + 1, fixture.scheduled_day)
	finished.append(true)
	var score := Vector2i(own, other) if human_home else Vector2i(other, own)
	if not CareerCompetitions.record_league_result(repo, int(series["id"]), score.x, score.y):
		return false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var competition := repo.get_competition(str(series["competition_id"]))
	return WorldSimulation.apply_series(repo, str(series["home_id"]), str(series["away_id"]), score,
		int(series["best_of"]), competition.tier if competition != null else 4, repo.current_day(), rng, true)


static func _schedule_map(repo: CareerRepository, human: CareerRecords.PlayerRecord, org_id: String,
		series: Dictionary, map_number: int, day: int) -> bool:
	var human_home := str(series["home_id"]) == org_id
	var opponent_id := str(series["away_id"]) if human_home else str(series["home_id"])
	var setup := MatchSetup.new()
	setup.fixture_id = Ids.generate("fix")
	setup.competition = "%s · Map %d of BO%d" % [series["competition_name"], map_number, int(series["best_of"])]
	setup.home_team_id = org_id
	setup.home_team_name = str(series["home_name"] if human_home else series["away_name"])
	setup.away_team_id = opponent_id
	setup.away_team_name = str(series["away_name"] if human_home else series["home_name"])
	setup.max_rounds = MAX_ROUNDS
	setup.map_id = MAP_POOL[(map_number - 1) % MAP_POOL.size()]
	setup.home_lineup.assign(repo.lineup(org_id))
	if not setup.home_lineup.any(func(p: Dictionary) -> bool: return str(p["player_id"]) == human.id):
		# A human on the bench still plays their own organisation's matches in this slice.
		if setup.home_lineup.size() >= CareerFixtures.TEAM_SIZE:
			setup.home_lineup.resize(CareerFixtures.TEAM_SIZE - 1)
		setup.home_lineup.push_front(repo.match_player(human.id, human.nickname, human.preferred_role, true))
	setup.away_lineup.assign(repo.lineup(opponent_id))
	var fixture := CareerFixture.new()
	fixture.player_id = human.id
	fixture.scheduled_day = day
	fixture.setup = setup
	return repo.insert_fixture(fixture) and repo.insert_series_map(int(series["id"]), map_number, setup.fixture_id, human_home)


## Adds the names [method _schedule_map] needs to a bare league fixture row.
static func _named(repo: CareerRepository, series: Dictionary) -> Dictionary:
	var named := series.duplicate()
	var competition := repo.get_competition(str(series["competition_id"]))
	named["competition_name"] = competition.name if competition != null else "League"
	named["home_name"] = repo.get_organisation(str(series["home_id"])).name
	named["away_name"] = repo.get_organisation(str(series["away_id"])).name
	return named
