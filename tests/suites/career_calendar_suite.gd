extends TestSuite
## Milestone 13: simulated organisation series and the day-by-day career calendar.

const TEST_ROOT: String = "user://tests/career_calendar"
const PROFILE: Dictionary = {"first_name": "Quinn", "last_name": "Marlow", "nickname": "Lattice",
	"nation_id": "gb", "preferred_role": &"support", "difficulty": &"standard", "age": 20}


func suite_name() -> String:
	return "Career calendar and simulated series (Milestone 13)"


func run() -> void:
	_test_simulator()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_calendar(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _test_simulator() -> void:
	section("Series simulation")
	check(is_equal_approx(SeriesSimulator.map_win_chance(70.0, 70.0), 0.5), "equal lineups are a coin flip per map")
	var edge := SeriesSimulator.map_win_chance(76.0, 70.0)
	check(edge > 0.7 and edge < 0.76, "a 6-point edge wins about 73%% of maps (%.2f)" % edge)
	check(SeriesSimulator.map_win_chance(99.0, 1.0) <= 1.0 - SeriesSimulator.MIN_MAP_CHANCE,
		"a huge gap still leaves the underdog a chance")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var valid := true
	for best_of: int in [1, 3, 5]:
		@warning_ignore("integer_division")
		var target := best_of / 2 + 1
		for i: int in 50:
			var score := SeriesSimulator.simulate(rng, 65.0, 62.0, best_of)
			if maxi(score.x, score.y) != target or mini(score.x, score.y) >= target:
				valid = false
	check(valid, "every simulated BO1, BO3 and BO5 ends exactly when one side reaches the target")
	var wins := 0
	for i: int in 400:
		if SeriesSimulator.simulate(rng, 78.0, 60.0, 3).x == 2:
			wins += 1
	check(wins > 360, "a tier-one lineup beats an amateur one in most BO3s (%d of 400)" % wins)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	check(SeriesSimulator.simulate(a, 70.0, 68.0, 5) == SeriesSimulator.simulate(b, 70.0, 68.0, 5),
		"the same dice give the same series")


func _test_calendar(app: Node) -> void:
	section("Advancing the calendar")
	var problem: String = app.call("new_career", "Calendar tests", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	var player_id := session.human_player_id
	var day_zero := repo.league_fixtures_between(0, 0, 1000)
	check(not day_zero.is_empty() and repo.current_day() == 0, "regional leagues open on day one")

	# A human under contract: that organisation's series are theirs to play, never simulated.
	var human_series := day_zero[0]
	var human_org := str(human_series["home_id"])
	var contract := CareerRecords.ContractRecord.new()
	contract.id = "con_calendar_test"
	contract.player_id = player_id
	contract.organisation_id = human_org
	contract.role = &"support"
	contract.start_day = 0
	contract.end_day = 400
	check(repo.sign_contract(contract) and repo.organisation_has_human(human_org), "the test human joins a league organisation")

	var dice := RandomNumberGenerator.new()
	dice.seed = 2026
	check(CareerCalendar.advance_day(repo, player_id, dice).is_empty() and repo.current_day() == 1, "advancing moves to day 2")
	var resolved := 0
	var valid := true
	for fixture: Dictionary in repo.league_fixtures_between(0, 0, 1000):
		if int(fixture["id"]) == int(human_series["id"]):
			check(fixture["home_maps"] == null, "the human organisation's series is left for them to play")
			continue
		if fixture["home_maps"] == null:
			valid = false
			continue
		resolved += 1
		if maxi(int(fixture["home_maps"]), int(fixture["away_maps"])) != 2:
			valid = false
	check(valid and resolved == day_zero.size() - 1, "every other series due that day gets a valid BO3 result (%d)" % resolved)
	var later := repo.league_fixtures_between(1, 400, 5000)
	check(later.all(func(f: Dictionary) -> bool: return f["home_maps"] == null), "series on later days are untouched")

	section("Calendar conflicts and atomic days")
	check(CareerFixtures.schedule(repo, player_id, MapTemplates.SANDBOX_ARENA_ID).is_empty(), "an amateur match is scheduled today")
	check(CareerCalendar.advance_day(repo, player_id) == CareerCalendar.BLOCKED_BY_FIXTURE and repo.current_day() == 1,
		"the day cannot pass while the player's match is unplayed")
	repo.db.execute("DELETE FROM league_series_map;")
	repo.db.execute("DELETE FROM career_fixture WHERE player_id = ? AND submission_id IS NULL;", [player_id])

	check(repo.db.execute("""CREATE TRIGGER block_calendar_score BEFORE UPDATE OF home_maps ON league_fixture
		WHEN NEW.scheduled_day = 7 BEGIN SELECT RAISE(ABORT, 'blocked series'); END;"""), "installs a failing series write")
	var before := repo.league_fixtures_between(1, 6, 5000).filter(func(f: Dictionary) -> bool: return f["home_maps"] != null).size()
	check(not CareerCalendar.advance_to(repo, 30, dice) and repo.current_day() == 1
		and repo.league_fixtures_between(1, 6, 5000).filter(func(f: Dictionary) -> bool: return f["home_maps"] != null).size() == before,
		"a failed series write rolls back the whole jump, date included")
	repo.db.execute("DROP TRIGGER block_calendar_score;")
	check(CareerCalendar.advance_to(repo, 30, dice) and repo.current_day() == 30, "a multi-day jump succeeds once unblocked")
	var unresolved := repo.unresolved_league_fixtures(30)
	check(unresolved.size() >= 2 and unresolved.all(func(f: Dictionary) -> bool:
			return str(f["home_id"]) == human_org or str(f["away_id"]) == human_org),
		"after a month only the human organisation's weekly series are still open (%d)" % unresolved.size())

	# The human's own league series are booked for them to play; release them so the page can
	# move the day on in this test.
	repo.db.execute("DELETE FROM league_series_map;")
	repo.db.execute("DELETE FROM career_fixture WHERE player_id = ? AND submission_id IS NULL;", [player_id])
	repo.end_contract(contract.id, "terminated", repo.current_day())

	section("Calendar page")
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"calendar")
	await wait_frames(1)
	var page := hub.get("current_page") as CareerCalendarPage
	check(page != null and page.advance_button != null, "the Calendar page offers moving to the next day")
	if page == null:
		return
	check(page.advance_day().is_empty() and repo.current_day() == 31, "the button advances the open career")
	await wait_frames(1)
	var labels := hub.find_children("*", "Label", true, false).map(func(n: Node) -> String: return (n as Label).text)
	check(labels.any(func(t: String) -> bool: return t.contains(GameDate.format(31))), "the hub shows the new date")


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
