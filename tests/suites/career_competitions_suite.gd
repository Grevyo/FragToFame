extends TestSuite

const PROFILE: Dictionary = {"first_name": "Robin", "last_name": "Vale", "nickname": "Chevron",
	"nation_id": "gb", "preferred_role": &"rifler", "difficulty": &"standard", "age": 19}


func suite_name() -> String:
	return "Published league seasons (Milestone 13)"


func run() -> void:
	_test_schedule()
	_test_career()


func _test_schedule() -> void:
	section("Round-robin pairing")
	var entrants: Array[String] = ["alpha", "bravo", "charlie", "delta", "echo"]
	var fixtures := CareerCompetitions.round_robin(entrants, 31)
	var teams_by_round: Dictionary[int, Dictionary] = {}
	var pairs: Dictionary = {}
	var valid := true
	for fixture: Dictionary in fixtures:
		var round_number := int(fixture["round_number"])
		var home := str(fixture["home_id"])
		var away := str(fixture["away_id"])
		var pair := [home, away]
		pair.sort()
		if not teams_by_round.has(round_number):
			teams_by_round[round_number] = {}
		var used := teams_by_round[round_number]
		if home == away or used.has(home) or used.has(away) or pairs.has(pair):
			valid = false
		used[home] = true
		used[away] = true
		pairs[pair] = true
		if fixture["scheduled_day"] != 31 + (round_number - 1) * 7:
			valid = false
	check(valid and fixtures.size() == 10 and teams_by_round.size() == 5 and entrants.size() == 5,
		"five entrants have one meeting per pair, a rotating bye and published dates")
	var maximum: Array[String] = []
	for idx: int in 64:
		maximum.append("org_%d" % idx)
	var large := CareerCompetitions.round_robin(maximum, 365)
	check(large.size() == 2016 and large.back()["scheduled_day"] < 730,
		"a maximum-size league fits before the next anniversary")


func _test_career() -> void:
	section("Authored league seasons, scores and recovery")
	var root := "user://tests/career_competitions".path_join(Ids.generate("test"))
	var saves := CareerSaves.new(root)
	var session := saves.create_career("Competition test", PROFILE)
	check(session.is_ok(), "creates a career with the published league calendars")
	if not session.is_ok():
		return
	var repo := session.repo
	var pro_id := _competition_id(repo, "Northstar Pro Series")
	var west_id := _competition_id(repo, "Europe West Challenger League")
	var oceania_id := _competition_id(repo, "Oceania Challenger League")
	var cup_id := _competition_id(repo, "Vanguard Masters")
	var fixtures := repo.league_fixtures(pro_id, 1)
	var entrants := repo.league_entrants(pro_id, 1)
	check(fixtures.size() == 120 and entrants.size() == 16
		and repo.league_season(pro_id, 1).get("start_day") == GameDate.make(1, 2, 1),
		"the pro league opens in its authored month with all unique series")
	check(repo.league_entrants(west_id, 1).size() == 8 and repo.league_season(oceania_id, 1).is_empty()
		and repo.league_season(cup_id, 1).is_empty(), "the eligible regional league publishes and small fields and cups wait")
	if fixtures.is_empty():
		session.close()
		return
	var fixture := fixtures[0]
	var id := int(fixture["id"])
	check(CareerCompetitions.ensure_league_seasons(repo, 1) and repo.league_fixtures(pro_id, 1) == fixtures,
		"re-publishing preserves the locked schedule and fixture IDs")
	check(not CareerCompetitions.record_league_result(repo, id, 2, 1), "a future fixture cannot be resolved")
	repo.set_current_day(int(fixture["scheduled_day"]))
	check(not CareerCompetitions.record_league_result(repo, id, 1, 1)
		and not CareerCompetitions.record_league_result(repo, id, 3, 0)
		and not CareerCompetitions.record_league_result(repo, id, 2, -1)
		and not CareerCompetitions.record_league_result(repo, 0, 2, 0), "invalid BO3 scores and unknown fixture IDs are refused")
	check(CareerCompetitions.record_league_result(repo, id, 0, 2)
		and CareerCompetitions.record_league_result(repo, id, 0, 2)
		and not CareerCompetitions.record_league_result(repo, id, 2, 0), "series publication accepts retries and rejects conflicting scores")
	var standings := CareerCompetitions.standings(entrants, repo.league_fixtures(pro_id, 1))
	var home: Dictionary = {}
	for org: Dictionary in standings:
		if org["organisation_id"] == fixture["home_id"]:
			home = org
	check(standings[0]["organisation_id"] == fixture["away_id"] and standings[0]["won"] == 1
		and standings[0]["map_diff"] == 2 and home.get("lost") == 1 and home.get("map_diff") == -2,
		"the away win and map differential affect both teams exactly once")

	repo.set_current_day(GameDate.DAYS_PER_YEAR - 1)
	var player_id := session.human_player_id
	var map_id := "league_rollover_test_map"
	check(CareerFixtures.schedule(repo, player_id, map_id).is_empty(), "schedules the last amateur fixture of Year 1")
	var pending := repo.pending_fixture(player_id)
	if pending != null:
		var result := MatchResult.create(pending.setup.fixture_id, 6, 0, MatchResult.SOURCE_FPS_RUNTIME)
		result.map_id = map_id
		check(CareerFixtures.record_result(repo, player_id, result).is_empty()
			and repo.current_day() == GameDate.DAYS_PER_YEAR and repo.league_fixtures(pro_id, 2).size() == 120,
			"the first new-year day and its leagues are committed together")

	check(repo.db.execute("""CREATE TRIGGER block_test_league BEFORE INSERT ON league_fixture
		WHEN NEW.season_year = 3 BEGIN SELECT RAISE(ABORT, 'blocked league fixture'); END;"""),
		"installs a failing league write in the disposable save")
	check(not CareerCompetitions.ensure_league_seasons(repo, 3) and repo.league_season(pro_id, 3).is_empty()
		and repo.league_season(west_id, 3).is_empty() and repo.league_entrants(pro_id, 3).is_empty(),
		"a failed fixture write rolls back the edition and its entrants")
	var save_id := session.save_id
	session.close()
	session = saves.open_career(save_id)
	check(session.is_ok() and session.repo.league_years(pro_id) == [2, 1]
		and session.repo.league_fixture(id).get("away_maps") == 2 and session.repo.db.foreign_keys_are_valid(),
		"current and historic seasons, fixture identity and scores survive reopening")
	session.close()


func _competition_id(repo: CareerRepository, name: String) -> String:
	for competition: CareerRecords.CompetitionRecord in repo.competitions():
		if competition.name == name:
			return competition.id
	return ""
