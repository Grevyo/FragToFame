extends TestSuite
## The human path to pro: visibility, trial invitations, trials, contract offers, signing and
## playable league series.

const TEST_ROOT: String = "user://tests/career_offers"
const PROFILE: Dictionary = {"first_name": "Ash", "last_name": "Vale", "nickname": "Kestrel",
	"nation_id": "gb", "preferred_role": &"entry", "difficulty": &"prospect", "age": 18}


func suite_name() -> String:
	return "Path to pro: trials, offers and league series (Milestone 14)"


func run() -> void:
	_test_rules()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_path(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _test_simulation_rules() -> void:
	section("Simulate match (dev): model")
	var lineup: Array[Dictionary] = [
		{"player_id": "h", "is_human": true, "abilities": {}},
		{"player_id": "a", "is_human": false, "abilities": {"aim": 70, "reaction": 80}},
	]
	check(is_equal_approx(CareerMatchSimulator.lineup_strength(lineup, {"h": 60}), 70.0),
		"humans count with their perceived rating, AI players with their abilities")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var legal := true
	var strong_wins := 0
	var rules := MatchRules.competitive(8)
	for i: int in 300:
		var score := CareerMatchSimulator.map_score(rng, 76.0, 64.0, 8)
		if maxi(score.x, score.y) != rules.winning_score(mini(score.x, score.y)):
			legal = false
		if score.x > score.y:
			strong_wins += 1
	check(legal, "every simulated map ends on a legal final score")
	check(strong_wins > 240 and strong_wins < 300, "the stronger side wins most maps but not all (%d of 300)" % strong_wins)


func _test_rules() -> void:
	_test_simulation_rules()
	section("Visibility and verdicts")
	var none: Array[float] = []
	check(is_equal_approx(CareerOffers.visibility(8, 1000, none), 14.0), "a standard start is visible to amateur organisations (14)")
	check(CareerOffers.visibility(2, 800, none) < CareerOffers.TIER_VISIBILITY[4], "a long grind starts unseen")
	var hot: Array[float] = [1.5, 1.4]
	var cold: Array[float] = [0.5, 0.6]
	check(CareerOffers.visibility(20, 1100, hot) > CareerOffers.visibility(20, 1100, cold), "recent form raises visibility")
	check(CareerOffers.would_consider(4, 15.0, 45) and not CareerOffers.would_consider(1, 15.0, 80),
		"top organisations need far more visibility")
	check(not CareerOffers.would_consider(2, 80.0, 40), "visibility alone is not enough without the level")
	check(CareerOffers.trial_passed(1.1, false) and CareerOffers.trial_passed(0.9, true) and not CareerOffers.trial_passed(0.8, true),
		"a trial needs a good rating, a little less in a win")


## Plays the pending fixture with a score and no telemetry. Returns the record_result message.
func _play(repo: CareerRepository, player_id: String, human_wins: bool) -> String:
	var fixture := repo.pending_fixture(player_id)
	if fixture == null:
		return "no pending fixture"
	var target := fixture.setup.rounds_to_win()
	var result := MatchResult.create(fixture.setup.fixture_id, target if human_wins else 2, 2 if human_wins else target,
		MatchResult.SOURCE_FPS_RUNTIME)
	result.map_id = fixture.setup.map_id
	return CareerFixtures.record_result(repo, player_id, result)


func _test_path(app: Node) -> void:
	section("Trial invitations")
	var problem: String = app.call("new_career", "Offers tests", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	var player_id := session.human_player_id
	check(repo.offers(player_id).is_empty(), "a new career starts with no offers")
	var dice := RandomNumberGenerator.new()
	dice.seed = 41
	var day := repo.current_day()
	var ran := true
	for attempt: int in 120:
		if not repo.offers(player_id, true).is_empty():
			break
		ran = CareerOffers.daily(repo, day, dice) and ran
	check(ran, "daily interest runs")
	var open := repo.offers(player_id, true)
	check(open.size() == 1 and str(open[0]["kind"]) == CareerOffers.KIND_TRIAL, "an organisation invites the prospect to a trial")
	if open.is_empty():
		return
	var trial := open[0]
	check(CareerOffers.would_consider(int(trial["tier"]), CareerOffers.visibility(repo.reputation(player_id),
		CareerDevelopment.current_elo(repo, player_id), repo.recent_ratings(player_id)), repo.perceived_rating(player_id)),
		"only an organisation whose tier can see the player invites them (tier %d)" % int(trial["tier"]))
	check(repo.news_on(day, WorldSimulation.HEADLINE).any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("trial")),
		"the invitation is a headline, so Continue stops for it")

	section("Trial match and contract offer")
	check(str(app.call("accept_career_offer", str(trial["id"]))).is_empty(), "accepting books the trial")
	var booked := repo.pending_fixture(player_id)
	check(booked != null and booked.setup.competition.begins_with(CareerOffers.TRIAL_COMPETITION)
		and booked.setup.home_team_id == str(trial["organisation_id"]) and booked.setup.home_lineup.size() == 5
		and str(booked.setup.home_lineup[0]["player_id"]) == player_id
		and booked.setup.away_lineup.size() == 5, "the trial plays alongside four of the organisation's starters")
	check(str(app.call("accept_career_offer", str(trial["id"]))) != "", "a booked trial cannot be accepted twice")
	var before_day := repo.current_day()
	check(_play(repo, player_id, true).is_empty(), "the trial result is saved")
	check(str(repo.offer(str(trial["id"]))["status"]) == "passed" and repo.current_day() == before_day + 1,
		"a convincing trial passes and the day moves on")
	# Other organisations may approach on the new day too; pick the contract offer itself.
	open = repo.offers(player_id, true).filter(func(o: Dictionary) -> bool:
		return str(o["kind"]) == CareerOffers.KIND_CONTRACT)
	check(open.size() == 1 and str(open[0]["organisation_id"]) == str(trial["organisation_id"])
		and int(open[0]["monthly_salary"]) >= 0, "the organisation follows up with a contract offer")
	if open.is_empty():
		return

	section("Contract talks")
	var talks := RandomNumberGenerator.new()
	talks.seed = 5
	var asked_before := int(open[0]["monthly_salary"])
	var first_talk := CareerOffers.negotiate(repo, player_id, str(open[0]["id"]), talks)
	var after_talk := int(repo.offer(str(open[0]["id"]))["monthly_salary"])
	check((bool(first_talk["ok"]) and after_talk > asked_before) or (not bool(first_talk["ok"]) and after_talk == asked_before),
		"asking for more either raises the offer or leaves it as it was (%s)" % first_talk["message"])
	var second_talk := CareerOffers.negotiate(repo, player_id, str(open[0]["id"]), talks)
	check(not bool(second_talk["ok"]) and str(second_talk["message"]).contains("final"), "an organisation only negotiates once")
	check(str(repo.offer(str(open[0]["id"]))["status"]) == "pending", "the offer stays open after talks")

	section("Signing")
	var org_id := str(trial["organisation_id"])
	var starters_before := repo.lineup(org_id).size()
	check(str(app.call("accept_career_offer", str(open[0]["id"]))).is_empty(), "signing the contract succeeds")
	var contract := repo.active_contract(player_id)
	check(contract != null and contract.organisation_id == org_id and not contract.is_substitute
		and contract.monthly_salary == after_talk, "the human is under contract as a starter, on the agreed salary")
	if contract != null:
		var balance_before := repo.player_balance(player_id)
		check(WorldFinance.monthly(repo, repo.current_day()) and repo.player_balance(player_id) == balance_before + contract.monthly_salary,
			"the human's salary is paid into their balance each month")
	var lineup := repo.lineup(org_id)
	check(lineup.size() == maxi(starters_before, 5) and lineup.any(func(p: Dictionary) -> bool: return bool(p["is_human"])),
		"the weakest AI starter makes room in the five")
	check(repo.offers(player_id, true).is_empty(), "other open offers are withdrawn")
	var visible_before := CareerOffers.daily(repo, repo.current_day(), dice) and repo.offers(player_id, true).is_empty()
	check(visible_before, "contracted players receive no new trial invitations")

	section("Playable league series")
	var ahead := repo.league_fixtures_between(repo.current_day(), repo.current_day() + 400, 100000)
	var due := ahead.filter(func(f: Dictionary) -> bool: return str(f["home_id"]) == org_id or str(f["away_id"]) == org_id)
	if due.is_empty() and not ahead.is_empty():
		# The trial organisation plays in no league this year (careers roll differently each
		# time): move the human to a league organisation so the series flow is still covered.
		org_id = str(ahead[0]["home_id"])
		repo.end_contract(contract.id, "terminated", repo.current_day())
		var league_contract := CareerRecords.ContractRecord.new()
		league_contract.id = "con_offers_league"
		league_contract.player_id = player_id
		league_contract.organisation_id = org_id
		league_contract.role = &"entry"
		league_contract.start_day = repo.current_day()
		league_contract.end_day = repo.current_day() + 800
		repo.sign_contract(league_contract)
		due = ahead.filter(func(f: Dictionary) -> bool: return str(f["home_id"]) == org_id or str(f["away_id"]) == org_id)
	check(not due.is_empty(), "the human's organisation has league series ahead")
	if due.is_empty():
		return
	var series: Dictionary = due[0]
	var stop := CareerCalendar.continue_until_event(repo, player_id, dice)
	for attempt: int in 20:
		if repo.pending_fixture(player_id) != null and repo.series_map_for_fixture(repo.pending_fixture(player_id).setup.fixture_id).size() > 0:
			break
		stop = CareerCalendar.continue_until_event(repo, player_id, dice)
	var map_one := repo.pending_fixture(player_id)
	check(map_one != null and str(stop["reason"]) == CareerCalendar.MATCH_DAY, "Continue stops on league match day")
	if map_one == null:
		return
	var series_map := repo.series_map_for_fixture(map_one.setup.fixture_id)
	var series_id := int(series_map.get("league_fixture_id", -1))
	check(series_id == int(series["id"]) and map_one.setup.home_team_id == org_id
		and map_one.setup.max_rounds == CareerLeagueMatches.MAX_ROUNDS
		and map_one.setup.home_lineup.any(func(p: Dictionary) -> bool: return str(p["player_id"]) == player_id),
		"map 1 of the series is the human's to play, with their organisation at home")
	check(CareerCalendar.advance_day(repo, player_id, dice) == CareerCalendar.BLOCKED_BY_FIXTURE, "the day waits for the series")
	var match_day := repo.current_day()
	var reputation_before := repo.reputation(player_id)
	check(_play(repo, player_id, true).is_empty() and repo.current_day() == match_day, "winning map 1 keeps the day")
	var map_two := repo.pending_fixture(player_id)
	check(map_two != null and int(repo.series_map_for_fixture(map_two.setup.fixture_id).get("map_number", 0)) == 2,
		"map 2 is booked straight away")
	check(_play(repo, player_id, true).is_empty(), "winning map 2 is saved")
	var scored := repo.league_fixture(series_id)
	var human_home := int(series_map["human_home"]) == 1
	check(scored["home_maps"] != null and (int(scored["home_maps"]) == 2 if human_home else int(scored["away_maps"]) == 2)
		and repo.current_day() == match_day + 1, "a 2–0 is published to the league table and the day moves on")
	check(repo.organisation_form(org_id) > 0, "the played series lifts the organisation's form")
	check(repo.reputation(player_id) >= reputation_before, "a played win can raise the human's reputation")

	section("Simulate match (dev)")
	var waited := 0
	while repo.pending_fixture(player_id) == null and waited < 20:
		CareerCalendar.continue_until_event(repo, player_id, dice)
		waited += 1
	var next_map := repo.pending_fixture(player_id)
	var next_series := repo.series_map_for_fixture(next_map.setup.fixture_id) if next_map != null else {}
	check(not next_series.is_empty(), "Continue reaches the next league match day")
	if next_series.is_empty():
		return
	var sim_day := repo.current_day()
	var rep_before := repo.reputation(player_id)
	var elo_before := CareerDevelopment.current_elo(repo, player_id)
	var outcome: Dictionary = app.call("simulate_career_fixture")
	var simulated_series := repo.league_fixture(int(next_series["league_fixture_id"]))
	check(bool(outcome["ok"]) and int(outcome["maps"]) >= 2 and simulated_series["home_maps"] != null,
		"one press simulates the whole series (%s)" % outcome["message"])
	check(repo.current_day() == sim_day + 1 and repo.pending_fixture(player_id) == null, "the day moves on afterwards")
	var sim_home := int(next_series["human_home"]) == 1
	var won := int(simulated_series["home_maps"] if sim_home else simulated_series["away_maps"]) == 2
	check(CareerDevelopment.current_elo(repo, player_id) == elo_before and (repo.reputation(player_id) >= rep_before if won
		else repo.reputation(player_id) <= rep_before),
		"a simulated series counts for the human's reputation like a played one (%d → %d, %s)" % [rep_before,
			repo.reputation(player_id), "won" if won else "lost"])
	check(repo.performance_totals(player_id).get("matches", 0) == 0 or int(repo.performance_totals(player_id)["matches"]) == 0,
		"simulated matches record no statistics")
	check(repo.fixture_by_id(next_map.setup.fixture_id).result.source == MatchResult.SOURCE_SIMULATION,
		"the stored result is marked as simulated")
	var strict := MatchResult.create("fix_unknown", 9, 3, MatchResult.SOURCE_SIMULATION)
	check(not CareerFixtures.record_result(repo, player_id, strict).is_empty(),
		"normal result saving still refuses simulated results")
	var none: Dictionary = app.call("simulate_career_fixture")
	check(not bool(none["ok"]), "there is nothing to simulate without a pending match")

	check(CareerFixtures.schedule(repo, player_id, MapTemplates.SANDBOX_ARENA_ID).is_empty() and repo.pending_fixture(player_id) != null,
		"an amateur match is scheduled")
	var amateur_elo := CareerDevelopment.current_elo(repo, player_id)
	var amateur_rep := repo.reputation(player_id)
	var amateur: Dictionary = app.call("simulate_career_fixture")
	var saved := repo.amateur_rating(player_id)
	check(bool(amateur["ok"]) and int(saved.get("last_change", 0)) != 0
		and CareerDevelopment.current_elo(repo, player_id) == amateur_elo + int(saved["last_change"]),
		"a simulated amateur match moves ELO (%+d)" % int(saved.get("last_change", 0)))
	var amateur_won := int(saved.get("last_change", 0)) > 0
	check(repo.reputation(player_id) == amateur_rep + (1 if amateur_won else 0),
		"and reputation, from the result alone (no performance rating)")


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
