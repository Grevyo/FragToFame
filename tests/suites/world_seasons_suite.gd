extends TestSuite
## Season endings (records, prizes, rewards, honours) and spending a human's own money.

const TEST_ROOT: String = "user://tests/world_seasons"
const PROFILE: Dictionary = {"first_name": "Noor", "last_name": "Ashby", "nickname": "Cinder",
	"nation_id": "nl", "preferred_role": &"support", "difficulty": &"standard", "age": 21}


func suite_name() -> String:
	return "Season records, prizes and spending (Milestone 14)"


func run() -> void:
	_test_rules()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_career(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _test_rules() -> void:
	section("Prize rules")
	for entrants: int in [2, 4, 8, 16]:
		var shares := WorldSeasons.prize_shares(entrants)
		var total := 0.0
		var ordered := true
		for i: int in shares.size():
			total += shares[i]
			if i > 0 and shares[i] > shares[i - 1] + 0.0001:
				ordered = false
		check(shares.size() == entrants and is_equal_approx(total, 1.0) and ordered,
			"a %d-team pool is fully paid out, best place first" % entrants)
	check(WorldSeasons.prize_for(1, 16, 1) > WorldSeasons.prize_for(2, 16, 1) and WorldSeasons.prize_for(1, 16, 17) == 0,
		"top tiers pay more; there is no prize outside the table")
	check(WorldSeasons.ordinal(1) == "1st" and WorldSeasons.ordinal(2) == "2nd" and WorldSeasons.ordinal(3) == "3rd"
		and WorldSeasons.ordinal(11) == "11th" and WorldSeasons.ordinal(22) == "22nd", "positions read naturally")


func _test_career(app: Node) -> void:
	section("A season ends")
	var problem: String = app.call("new_career", "Season tests", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	var player_id := session.human_player_id
	# The season that finishes first.
	var finishing: Dictionary = {}
	for row: Dictionary in repo.db.rows("""SELECT competition_id, season_year, MAX(scheduled_day) AS last_day
			FROM league_fixture GROUP BY competition_id, season_year ORDER BY last_day LIMIT 1;"""):
		finishing = row
	check(not finishing.is_empty(), "the career has a league season")
	if finishing.is_empty():
		return
	var competition_id := str(finishing["competition_id"])
	var year := int(finishing["season_year"])
	var last_day := int(finishing["last_day"])
	var dice := RandomNumberGenerator.new()
	dice.seed = 77
	check(CareerCalendar.advance_to(repo, last_day, dice) and repo.league_record(competition_id, year).is_empty(),
		"the season is still open on its final match day")
	check(CareerCalendar.advance_to(repo, last_day + 1, dice), "the final series are played")
	var record := repo.league_record(competition_id, year)
	var entrants := repo.league_entrants(competition_id, year)
	check(record.size() == entrants.size() and int(record[0]["position"]) == 1, "the final table is stored as the season record")
	if record.is_empty():
		return
	var ordered := true
	for i: int in range(1, record.size()):
		if int(record[i]["won"]) > int(record[i - 1]["won"]) or int(record[i]["prize"]) > int(record[i - 1]["prize"]):
			ordered = false
	check(ordered, "positions follow wins and prizes follow positions")
	var competition := repo.get_competition(competition_id)
	var pool: int = WorldSeasons.PRIZE_POOL[competition.tier]
	var paid := 0
	for row: Dictionary in record:
		paid += int(row["prize"])
	check(absi(paid - pool) <= 100 * record.size(), "the whole prize pool is paid out (%s)" % CareerCatalog.format_money(paid))
	var champion_id := str(record[0]["organisation_id"])
	check(int(repo.db.scalar("""SELECT COUNT(*) FROM finance_ledger WHERE organisation_id = ? AND kind = 'prize'
		AND amount = ? AND day = ?;""", [champion_id, int(record[0]["prize"]), last_day + 1], 0)) == 1,
		"the champion receives its prize")
	var squad := repo.roster(champion_id)
	check(not squad.is_empty() and squad.all(func(e: Dictionary) -> bool:
			return repo.honours((e["player"] as CareerRecords.PlayerRecord).id).any(func(h: Dictionary) -> bool:
				return str(h["competition_id"]) == competition_id and int(h["position"]) == 1)),
		"every player in the champion squad earns an honour")
	check(repo.news(1000).any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("win the")),
		"the champions make the news")
	check(CareerCalendar.advance_to(repo, last_day + 2, dice) and repo.league_record(competition_id, year).size() == record.size(),
		"a season is only closed once")

	section("A human in the winning squad")
	repo.db.execute("DELETE FROM player_honour WHERE competition_id = ? AND season_year = ?;", [competition_id, year])
	repo.db.execute("DELETE FROM league_record WHERE competition_id = ? AND season_year = ?;", [competition_id, year])
	var contract := CareerRecords.ContractRecord.new()
	contract.id = "con_seasons_test"
	contract.player_id = player_id
	contract.organisation_id = champion_id
	contract.role = &"support"
	contract.is_substitute = true
	contract.start_day = repo.current_day()
	contract.end_day = repo.current_day() + 400
	check(repo.sign_contract(contract), "the human joins the champions")
	var balance_before := repo.player_balance(player_id)
	var reputation_before := repo.reputation(player_id)
	check(WorldSeasons.close_finished(repo, repo.current_day(), dice), "the season closes again for the test")
	var bonus := repo.player_balance(player_id) - balance_before
	check(bonus > 0 and bonus == roundi(int(record[0]["prize"]) * WorldSeasons.SQUAD_BONUS_SHARE / repo.roster(champion_id).size()),
		"the human receives a share of the prize (%s)" % CareerCatalog.format_money(bonus))
	check(repo.honours(player_id).size() == 1 and repo.reputation(player_id) == reputation_before + WorldSeasons.PLAYER_PODIUM_REPUTATION[0],
		"and an honour and reputation")
	check(repo.news_on(repo.current_day(), WorldSimulation.HEADLINE).any(func(n: Dictionary) -> bool:
			return str(n["headline"]).contains("your organisation finished 1st")), "the human's finish is a headline")
	repo.end_contract(contract.id, "terminated", repo.current_day())

	section("Spending your own money")
	repo.add_player_money(player_id, -repo.player_balance(player_id), repo.current_day(), "expense", "Test: empty the balance")
	check(CareerSpending.hire(repo, player_id, "coach") != "" and repo.services(player_id).is_empty(),
		"a coach cannot be hired without the first month's fee")
	repo.add_player_money(player_id, 20000, repo.current_day(), "bonus", "Test funds")
	var funds := repo.player_balance(player_id)
	check(CareerSpending.hire(repo, player_id, "coach").is_empty()
		and repo.player_balance(player_id) == funds - int(CareerSpending.SERVICES["coach"][1]), "hiring a coach pays the first month")
	check(CareerSpending.hire(repo, player_id, "coach") != "", "a service cannot be hired twice")
	var focus := &"utility"
	var seen_before := int(repo.perceived(player_id).get(focus, 0))
	check(CareerDevelopment.train(repo, player_id, focus).is_empty()
		and int(repo.perceived(player_id)[focus]) == mini(seen_before + CareerSpending.COACH_TRAINING_GAIN, 100),
		"with a coach, training raises the attribute by 2")
	check(CareerSpending.hire(repo, player_id, "pr_agent").is_empty(), "a PR agent is hired")
	var rep_before := repo.reputation(player_id)
	var month_funds := repo.player_balance(player_id)
	check(CareerSpending.monthly(repo, repo.current_day()) and repo.player_balance(player_id) == month_funds - 1000
		and repo.reputation(player_id) == mini(rep_before + 1, maxi(rep_before, CareerSpending.PR_REPUTATION_CAP)),
		"each month the services are charged and the PR agent lifts reputation")
	var camp_seen := repo.perceived(player_id)
	check(CareerSpending.buy_bootcamp(repo, player_id).is_empty()
		and CareerSpending.BOOTCAMP_ABILITIES.all(func(a: StringName) -> bool:
			return int(repo.perceived(player_id)[a]) == mini(int(camp_seen[a]) + 1, 99)), "a bootcamp raises its attributes")
	check(CareerSpending.buy_bootcamp(repo, player_id).contains("days"), "bootcamps have a cooldown")
	repo.add_player_money(player_id, -repo.player_balance(player_id), repo.current_day(), "expense", "Test: spend it all")
	check(CareerSpending.monthly(repo, repo.current_day()) and repo.services(player_id).is_empty()
		and repo.news_on(repo.current_day(), WorldSimulation.HEADLINE).any(func(n: Dictionary) -> bool:
			return str(n["headline"]).contains("could not pay")), "services you cannot pay for end, with a headline")
	check(int(repo.db.scalar("""SELECT COUNT(*) FROM player_finance f WHERE f.balance <> (SELECT SUM(amount)
		FROM finance_ledger l WHERE l.player_id = f.player_id);""", [], 0)) == 0, "the human's balance equals their ledger")

	section("Profile spending card")
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"profile")
	await wait_frames(1)
	var page := hub.get("current_page") as CareerProfilePage
	check(page != null and page.spending_status != null, "the Profile page offers spending")
	if page != null:
		check(not page.spend("coach", true).is_empty(), "the page reports why a service cannot be hired")


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
