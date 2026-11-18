extends TestSuite
## The living world: development, opinion drift, retirements, rookies, the market, form,
## reputation, the news log and FM-style Continue.

const TEST_ROOT: String = "user://tests/world_simulation"
const PROFILE: Dictionary = {"first_name": "Rowan", "last_name": "Tide", "nickname": "Fathom",
	"nation_id": "ie", "preferred_role": &"rifler", "difficulty": &"standard", "age": 19}


func suite_name() -> String:
	return "Living world simulation (Milestone 14)"


func run() -> void:
	_test_development_rules()
	_test_market_rules()
	_test_form_and_reputation_rules()
	_test_finance_rules()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_world(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _truth(value: int, potential: int) -> Dictionary:
	var truth: Dictionary = {}
	for ability: StringName in CareerCatalog.ABILITIES:
		truth[ability] = value
	truth[CareerCatalog.POTENTIAL] = potential
	return truth


## Average overall after [param months] of development from a flat start.
func _grow(value: int, potential: int, age: int, months: int, rng: RandomNumberGenerator) -> float:
	var total := 0.0
	for sample: int in 40:
		var truth := _truth(value, potential)
		for month: int in months:
			truth.merge(WorldDevelopment.develop(truth, age, &"rifler", rng), true)
		total += WorldDevelopment.overall(truth)
	return total / 40.0


func _test_development_rules() -> void:
	section("Development and decline")
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	check(WorldDevelopment.overall(_truth(60, 90)) == 60, "overall ignores the hidden potential")
	var young := _grow(50, 75, 18, 12, rng)
	check(young > 55.0 and young < 70.0, "an 18-year-old with room to grow gains several points a year (%.1f)" % young)
	var capped := _grow(70, 70, 19, 12, rng)
	check(capped <= 70.5, "nobody grows past their potential (%.1f)" % capped)
	var prime := _grow(70, 74, 25, 12, rng)
	check(prime >= 70.0 and prime < young - 50.0 + 70.0, "a 25-year-old grows more slowly (%.1f)" % prime)
	var veteran := _grow(75, 75, 33, 12, rng)
	check(veteran < 74.0, "a 33-year-old declines (%.1f)" % veteran)
	var veteran_truth := _truth(75, 75)
	for month: int in 24:
		veteran_truth.merge(WorldDevelopment.develop(veteran_truth, 34, &"rifler", rng), true)
	check(int(veteran_truth[&"reaction"]) < int(veteran_truth[&"game_sense"]),
		"age takes reaction before game sense (%d vs %d)" % [veteran_truth[&"reaction"], veteran_truth[&"game_sense"]])

	var seen := _truth(40, 0)
	seen.erase(CareerCatalog.POTENTIAL)
	var truth := _truth(60, 70)
	for month: int in 60:
		seen.merge(WorldDevelopment.drift(seen, truth, 50, rng), true)
	check(WorldDevelopment.overall(seen) == 60, "the world's opinion catches up with the truth over time")
	check(WorldDevelopment.drift(truth.duplicate(), truth, 90, rng).is_empty(), "an accurate opinion does not move")

	var seen_rng := RandomNumberGenerator.new()
	seen_rng.seed = 12
	check(WorldDevelopment.confidence_after(40, 10, 66, seen_rng) > WorldDevelopment.confidence_after(40, 2, 66, seen_rng)
		and WorldDevelopment.confidence_after(40, 2, 66, seen_rng) > 40,
		"the more maps the world watches, the surer it gets")
	check(WorldDevelopment.confidence_after(70, 10, 66, seen_rng) == 70, "confidence does not grow past what a tier lets the world see")
	var stale := 60
	for month: int in 12:
		stale = WorldDevelopment.confidence_after(stale, 0, 66, seen_rng)
	check(stale < 60, "a player nobody watches becomes a stale read (60 → %d)" % stale)
	var watched_moves := 0
	var benched_moves := 0
	for trial: int in 40:
		watched_moves += WorldDevelopment.drift(_truth(40, 0), _truth(60, 70), 50, seen_rng, WorldDevelopment.exposure(10)).size()
		benched_moves += WorldDevelopment.drift(_truth(40, 0), _truth(60, 70), 50, seen_rng, WorldDevelopment.exposure(0)).size()
	check(watched_moves > benched_moves * 2, "opinions of players who play catch up faster than of benched ones")
	check(WorldDevelopment.retirement_chance(24, 70, true) == 0.0, "young professionals do not retire")
	check(WorldDevelopment.retirement_chance(33, 70, true) > WorldDevelopment.retirement_chance(30, 70, true),
		"retirement gets likelier with age")
	check(WorldDevelopment.retirement_chance(38, 80, true) >= 0.9, "almost everyone stops by 37")
	check(WorldDevelopment.retirement_chance(27, 40, false) > WorldDevelopment.retirement_chance(27, 40, true),
		"unsigned players who are not good enough give up sooner")

	var rookie := WorldRookies.roll_abilities(rng, &"sniper")
	var rookie_overall := WorldDevelopment.overall(rookie)
	check(rookie_overall > 25 and rookie_overall < 65 and int(rookie[CareerCatalog.POTENTIAL]) > rookie_overall,
		"a rookie is raw with room to grow (%d → %d)" % [rookie_overall, rookie[CareerCatalog.POTENTIAL]])


func _test_market_rules() -> void:
	section("Market decisions")
	check(WorldMarket.renewal_chance(24, 80, 1, false) > WorldMarket.renewal_chance(24, 80, 1, true),
		"starters are kept more often than substitutes")
	check(WorldMarket.renewal_chance(34, 80, 1, false) < WorldMarket.renewal_chance(26, 80, 1, false),
		"veterans are let go more often")
	check(WorldMarket.renewal_chance(25, 60, 1, false) < WorldMarket.renewal_chance(25, 78, 1, false),
		"a player well below the tier's level is rarely kept")
	check(WorldMarket.salary_for(1, 85) > WorldMarket.salary_for(1, 70) and WorldMarket.salary_for(1, 70) > WorldMarket.salary_for(3, 70),
		"salaries rise with rating and tier")
	check(WorldMarket.needed_role([&"igl", &"sniper"]) == &"entry", "an organisation looks for the first missing role")
	var pool: Array[Dictionary] = [
		{"rating": 70, "preferred_role": "rifler", "region_id": "na"},
		{"rating": 68, "preferred_role": "sniper", "region_id": "eu_west"},
	]
	check(WorldMarket.best_candidate(pool, &"sniper", "eu_west") == 1, "role fit and region outweigh a small rating gap")
	check(WorldMarket.best_candidate(pool, &"igl", "apac") == 0, "otherwise the best perceived player is chosen")
	check(WorldMarket.best_candidate([] as Array[Dictionary], &"igl", "na") == -1, "an empty pool signs nobody")

	section("Transfers between organisations")
	var july := GameDate.make(2, 7, 1)
	while GameDate.day_of_year(july) % WorldMarket.WINDOW_DAY_STEP != 0:
		july += 1
	check(WorldMarket.in_window(GameDate.make(2, 1, 8)) and WorldMarket.in_window(july)
		and not WorldMarket.in_window(july + 1) and not WorldMarket.in_window(GameDate.make(2, 4, 8)),
		"the January and July windows are recognised")
	var april := GameDate.make(2, 4, 1)
	while GameDate.day_of_year(april) % WorldMarket.WINDOW_DAY_STEP != 0:
		april += 1
	check(WorldMarket.is_market_day(april) and not WorldMarket.in_window(april) and not WorldMarket.is_market_day(april + 1),
		"the market also runs weekly outside the windows")
	check(WorldMarket.buy_chance(true, 0) > WorldMarket.buy_chance(false, 0) and WorldMarket.buy_chance(false, 0) > 0.0,
		"most moves happen in the windows, but the market never closes")
	check(WorldMarket.buy_chance(false, -60) > WorldMarket.buy_chance(false, 0) * 3.0
		and WorldMarket.buy_chance(true, -60) > WorldMarket.buy_chance(true, 0),
		"an organisation in poor form acts far more readily, even mid-season")
	var free: Array[Dictionary] = [
		{"id": "a", "rating": 60, "preferred_role": "igl", "region_id": "na"},
		{"id": "b", "rating": 66, "preferred_role": "entry", "region_id": "na"},
	]
	check(WorldMarket.free_agent_upgrade(free, 61, &"igl", "na") == 1 and WorldMarket.free_agent_upgrade(free, 63, &"igl", "na") == -1,
		"a free agent replaces a starter only when clearly better")
	check(WorldMarket.wants_move(3, 40, 2, 30) and WorldMarket.wants_move(2, 40, 2, 55) and not WorldMarket.wants_move(1, 80, 2, 99),
		"players move for a better tier or a bigger name in the same tier, never down")
	check(WorldMarket.sell_chance(90, false) > WorldMarket.sell_chance(600, false)
		and WorldMarket.sell_chance(600, true) < WorldMarket.sell_chance(600, false),
		"expiring players are easier to buy; a team's best player is harder")
	var market: Array[Dictionary] = [
		{"organisation_id": "org_buyer", "rating": 90, "preferred_role": "igl", "region_id": "na", "tier": 1, "org_reputation": 80},
		{"organisation_id": "org_big", "rating": 88, "preferred_role": "igl", "region_id": "na", "tier": 1, "org_reputation": 90},
		{"organisation_id": "org_small", "rating": 71, "preferred_role": "igl", "region_id": "na", "tier": 3, "org_reputation": 30},
		{"organisation_id": "org_small", "rating": 76, "preferred_role": "entry", "region_id": "eu_west", "tier": 3, "org_reputation": 30},
	]
	check(WorldMarket.upgrade_target(market, "org_buyer", 1, 80, 70, &"igl", "na") == 3,
		"the buyer takes the best upgrade that wants to come, not its own player or a bigger club's")
	check(WorldMarket.upgrade_target(market, "org_buyer", 1, 80, 72, &"igl", "na") == 3
		and WorldMarket.upgrade_target(market, "org_buyer", 1, 80, 73, &"igl", "na") == -1,
		"a target must be clearly better than the starter it replaces")


func _test_finance_rules() -> void:
	section("Finance rules")
	check(WorldFinance.opening_balance(1, 80) > WorldFinance.opening_balance(2, 80)
		and WorldFinance.opening_balance(2, 80) > WorldFinance.opening_balance(4, 80), "bigger tiers start richer")
	check(WorldFinance.monthly_income(1, 90) > WorldFinance.monthly_income(1, 60), "reputation brings sponsors and viewers")
	check(WorldFinance.transfer_fee(80, 25, 700) > WorldFinance.transfer_fee(70, 25, 700), "better players cost more")
	check(WorldFinance.transfer_fee(75, 20, 700) > WorldFinance.transfer_fee(75, 31, 700), "youth costs more than age")
	check(WorldFinance.transfer_fee(75, 25, 60) < WorldFinance.transfer_fee(75, 25, 700), "an expiring contract is cheap to buy out")
	check(WorldFinance.transfer_fee(41, 33, 10) >= 1000, "every fee is at least a token amount")
	check(WorldFinance.can_afford(100000, 70000, 9000) and not WorldFinance.can_afford(80000, 70000, 9000),
		"a buyer keeps three months of the new salary after the fee")
	check(WorldFinance.affordable_salary(1000000, 12000, 1) == 12000 and WorldFinance.affordable_salary(30000, 12000, 1) < 12000
		and WorldFinance.affordable_salary(-5000, 12000, 1) == WorldGenerator.TIER_PROFILE[1][3],
		"tight budgets offer less, never below the tier minimum")
	check(CareerCatalog.format_money(950) == "$950" and CareerCatalog.format_money(12500) == "$13k"
		and CareerCatalog.format_money(2400) == "$2.4k" and CareerCatalog.format_money(-1250000) == "-$1.25m", "money reads naturally")


func _test_form_and_reputation_rules() -> void:
	section("Form and reputation from results")
	check(WorldSimulation.next_form(0, 1.0) == 40 and WorldSimulation.next_form(40, -1.0) == -16,
		"a sweep lifts form; a loss after it drops it")
	check(WorldSimulation.next_form(100, 1.0) == 100, "form is capped")
	check(is_equal_approx(WorldSimulation.expected_score(50, 50), 0.5), "equal reputations are an even contest")
	var upset := WorldSimulation.reputation_change(30, 80, true, 1)
	var expected_win := WorldSimulation.reputation_change(80, 30, true, 1)
	check(upset > 5.0 and expected_win > 0.0 and expected_win < 1.0, "an upset earns much more than a favourite's win (%.2f vs %.2f)" % [upset, expected_win])
	check(WorldSimulation.reputation_change(50, 50, true, 1) > WorldSimulation.reputation_change(50, 50, true, 4),
		"top-tier results matter more")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var total := 0
	for i: int in 1000:
		total += WorldSimulation.stochastic_round(0.3, rng)
	check(total > 240 and total < 360, "small changes add up fairly (%d of ~300)" % total)


func _test_world(app: Node) -> void:
	section("A year of the living world")
	var problem: String = app.call("new_career", "World tests", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	var player_id := session.human_player_id
	check(repo.db.user_version() == CareerSchema.CURRENT_VERSION, "the save has the living-world tables")
	var players_before := repo.player_count(false)
	var truths_before := repo.all_abilities()
	var ages: Dictionary[String, int] = {}
	for found: Dictionary in repo.ai_players():
		ages[str(found["id"])] = GameDate.age(int(found["birth_day"]), 0)
	var org_reputation_before: Dictionary[String, int] = {}
	for entry: Dictionary in repo.organisations():
		org_reputation_before[(entry["organisation"] as CareerRecords.OrganisationRecord).id] = int(entry["reputation"])

	# The human joins an organisation on a short deal so its expiry is a headline.
	# An organisation with no league series in its first weeks, so the contract is the first event.
	var human_org := ""
	for entry: Dictionary in repo.organisations():
		var candidate := (entry["organisation"] as CareerRecords.OrganisationRecord).id
		if repo.due_series_for(candidate, 25).is_empty():
			human_org = candidate
			break
	var contract := CareerRecords.ContractRecord.new()
	contract.id = "con_world_test"
	contract.player_id = player_id
	contract.organisation_id = human_org
	contract.role = &"rifler"
	contract.is_substitute = true
	contract.start_day = 0
	contract.end_day = 20
	check(repo.sign_contract(contract), "the test human signs a short contract")

	var dice := RandomNumberGenerator.new()
	dice.seed = 2027
	var human_form := repo.organisation_form(human_org)
	var started := Time.get_ticks_msec()
	var first := CareerCalendar.continue_until_event(repo, player_id, dice)
	check(bool(first["ok"]) and int(first["days"]) == 20 and str(first["reason"]).contains("contract")
		and repo.active_contract(player_id) == null,
		"Continue runs until the human's contract expires (%d days: %s)" % [first["days"], first["reason"]])
	check(repo.organisation_form(human_org) == human_form, "the human organisation's series were left for them, so no simulated form")

	check(CareerFixtures.schedule(repo, player_id, MapTemplates.SANDBOX_ARENA_ID).is_empty(), "an amateur match is scheduled")
	var blocked := CareerCalendar.continue_until_event(repo, player_id, dice)
	check(not bool(blocked["ok"]) and int(blocked["days"]) == 0 and str(blocked["reason"]) == CareerCalendar.BLOCKED_BY_FIXTURE,
		"Continue refuses while the player's match is due")
	repo.db.execute("DELETE FROM career_fixture WHERE player_id = ? AND submission_id IS NULL;", [player_id])

	var quiet := CareerCalendar.continue_until_event(repo, player_id, dice)
	check(bool(quiet["ok"]) and int(quiet["days"]) >= 1 and int(quiet["days"]) <= CareerCalendar.CONTINUE_LIMIT,
		"Continue stops at the next event or after a month (%d days: %s)" % [quiet["days"], quiet["reason"]])

	check(CareerCalendar.advance_to(repo, GameDate.DAYS_PER_YEAR, dice) and repo.current_day() == GameDate.DAYS_PER_YEAR,
		"a full year passes (%d ms)" % (Time.get_ticks_msec() - started))

	section("What changed")
	var kinds: Dictionary[String, int] = {}
	for story: Dictionary in repo.news(100000):
		kinds[str(story["kind"])] = kinds.get(str(story["kind"]), 0) + 1
	check(kinds.get(WorldSimulation.NEWS_SIGNING, 0) > 0, "organisations signed players (%d stories)" % kinds.get(WorldSimulation.NEWS_SIGNING, 0))
	check(kinds.get(WorldSimulation.NEWS_TRANSFER, 0) > 0,
		"organisations bought players from each other (%d)" % kinds.get(WorldSimulation.NEWS_TRANSFER, 0))
	var off_day: int = repo.db.scalar("SELECT COUNT(*) FROM world_news WHERE kind = ? AND (day % 365) % 7 <> 0;", [WorldSimulation.NEWS_TRANSFER], 0)
	check(off_day == 0, "transfers happen on the weekly market days")
	var in_windows := 0
	var off_window := 0
	for story: Dictionary in repo.news(100000):
		if str(story["kind"]) == WorldSimulation.NEWS_TRANSFER:
			if WorldMarket.in_window(int(story["day"])):
				in_windows += 1
			else:
				off_window += 1
	check(in_windows > off_window and off_window > 0,
		"most transfers happen in the windows, some during the season (%d in, %d out)" % [in_windows, off_window])
	check(kinds.get(WorldSimulation.NEWS_RELEASE, 0) + kinds.get(WorldSimulation.NEWS_CONTRACT, 0) > 0,
		"contracts were renewed or let go")
	check(kinds.get(WorldSimulation.NEWS_NEW_YEAR, 0) == 1 and kinds.get(WorldSimulation.NEWS_ROOKIES, 0) == 1,
		"the new year made headlines with its rookie class")
	var retired := int(repo.db.scalar("SELECT COUNT(*) FROM player WHERE status = 'retired';", [], 0))
	var rookies := int(repo.db.scalar("SELECT COUNT(*) FROM player WHERE created_day = ? AND is_human = 0;", [GameDate.DAYS_PER_YEAR], 0))
	check(retired > 0 and rookies >= WorldSimulation.MIN_ROOKIES and rookies >= retired,
		"veterans retired and rookies replaced them (%d out, %d in)" % [retired, rookies])
	check(int(repo.db.scalar("""SELECT COUNT(*) FROM contract c JOIN player p ON p.id = c.player_id
		WHERE c.status = 'active' AND p.status = 'retired';""", [], 0)) == 0, "retired players hold no contracts")
	check(repo.player_count(false) >= players_before - 5, "the world keeps its size (%d → %d)" % [players_before, repo.player_count(false)])
	var short := repo.organisations_short_of_starters().filter(func(o: Dictionary) -> bool: return int(o["starters"]) < 4)
	check(short.size() <= 2, "almost every organisation fields a starting five (%d short)" % short.size())

	var truths_after := repo.all_abilities()
	var young_gain := 0.0
	var young_count := 0
	var old_change := 0.0
	var old_count := 0
	for id: String in truths_before:
		if not truths_after.has(id) or not ages.has(id):
			continue
		var change := WorldDevelopment.overall(truths_after[id]) - WorldDevelopment.overall(truths_before[id])
		if ages[id] <= 19:
			young_gain += change
			young_count += 1
		elif ages[id] >= 31:
			old_change += change
			old_count += 1
	check(young_count > 0 and young_gain / young_count > 1.0, "teenagers improved over the year (%+.1f avg)" % (young_gain / maxi(young_count, 1)))
	check(old_count > 0 and old_change / old_count < 0.0, "veterans declined (%+.1f avg)" % (old_change / maxi(old_count, 1)))
	check(int(repo.db.scalar("SELECT COUNT(*) FROM player_ability_history;", [], 0)) > 0, "monthly development is kept as history")
	check(repo.abilities(player_id).is_empty(), "the human still has no simulated abilities")

	var formed := int(repo.db.scalar("SELECT COUNT(*) FROM organisation_form WHERE value <> 0;", [], 0))
	check(formed > 5, "simulated results gave organisations form (%d)" % formed)
	var moved := 0
	for entry: Dictionary in repo.organisations():
		var org_id := (entry["organisation"] as CareerRecords.OrganisationRecord).id
		if int(entry["reputation"]) != org_reputation_before.get(org_id, -1):
			moved += 1
	check(moved > 5, "reputations rose and fell with results (%d organisations)" % moved)

	section("Money over the year")
	var org_count := repo.organisation_count()
	check(int(repo.db.scalar("SELECT COUNT(*) FROM organisation_finance;", [], 0)) == org_count, "every organisation has finances")
	var incomes := int(repo.db.scalar("SELECT COUNT(*) FROM finance_ledger WHERE kind = 'income';", [], 0))
	check(incomes == org_count * 12, "income arrived on the first of each month (%d entries)" % incomes)
	check(int(repo.db.scalar("SELECT COUNT(*) FROM finance_ledger WHERE kind = 'wages';", [], 0)) > 0
		and int(repo.db.scalar("SELECT COUNT(*) FROM finance_ledger WHERE kind = 'prize';", [], 0)) > 0,
		"wages were paid and series wins earned prize money")
	var paid := int(repo.db.scalar("SELECT COALESCE(SUM(amount), 0) FROM finance_ledger WHERE kind = 'fee_paid';", [], 0))
	var received := int(repo.db.scalar("SELECT COALESCE(SUM(amount), 0) FROM finance_ledger WHERE kind = 'fee_received';", [], 0))
	check(paid < 0 and paid == -received, "every transfer fee left one organisation and reached another (%s)" % CareerCatalog.format_money(received))
	check(int(repo.db.scalar("""SELECT COUNT(*) FROM organisation_finance f WHERE f.balance <> (SELECT SUM(amount)
		FROM finance_ledger l WHERE l.organisation_id = f.organisation_id);""", [], 0)) == 0,
		"every balance equals the sum of its ledger")
	var in_debt := int(repo.db.scalar("SELECT COUNT(*) FROM organisation_finance WHERE balance < 0;", [], 0))
	var by_tier: PackedStringArray = []
	for tier: int in [1, 2, 3, 4]:
		by_tier.append("T%d %s" % [tier, CareerCatalog.format_money(int(repo.db.scalar("""SELECT COALESCE(ROUND(AVG(f.balance)), 0)
			FROM organisation_finance f JOIN organisation o ON o.id = f.organisation_id WHERE o.tier = ?;""", [tier], 0)))])
	check(in_debt * 5 <= org_count, "most organisations stay solvent (%d of %d in debt; average %s)" % [in_debt, org_count, ", ".join(by_tier)])
	check(repo.news(100000).any(func(n: Dictionary) -> bool:
			return str(n["kind"]) == WorldSimulation.NEWS_TRANSFER and str(n["headline"]).contains("$")),
		"transfer stories name the fee")

	section("News and Continue on the Calendar page")
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"news")
	await wait_frames(1)
	var news_page := hub.get("current_page") as CareerNewsPage
	check(news_page != null, "the hub has a News page")
	hub.call("show_page", &"calendar")
	await wait_frames(1)
	var page := hub.get("current_page") as CareerCalendarPage
	check(page != null and page.continue_button != null and page.advance_button != null,
		"the Calendar page offers Next day and Continue")
	if page == null:
		return
	var before_day := repo.current_day()
	var outcome := page.continue_on()
	check(bool(outcome["ok"]) and repo.current_day() == before_day + int(outcome["days"]), "Continue moves the open career on")
	await wait_frames(1)
	check(page.status_label.text.contains(str(outcome["reason"])), "the page says why it stopped")

	section("Top bar: Continue and Holiday")
	var human_id := (app.get("career") as CareerSession).human_player_id
	var top_day := repo.current_day()
	var top := hub.call("continue_on") as Dictionary
	check(repo.current_day() == top_day + int(top["days"]) and not (hub.get("status_label") as Label).text.is_empty(),
		"the top-bar Continue moves the career on and says why it stopped")
	var week_start := repo.current_day()
	var week := hub.call("go_on_holiday", 7, false) as Dictionary
	check(int(week["days"]) <= 7 and repo.current_day() == week_start + int(week["days"])
		and (int(week["days"]) == 7 or repo.pending_fixture(human_id) != null),
		"a one-week holiday runs seven days unless your match stops it (%s)" % week["reason"])
	var inbox_start := repo.current_day()
	var inbox := CareerCalendar.holiday(repo, human_id, 0, false)
	var stopped_on := repo.news_on(repo.current_day(), WorldSimulation.HEADLINE)
	check(int(inbox["days"]) > 0 and repo.current_day() - inbox_start <= CareerCalendar.HOLIDAY_INBOX_LIMIT
		and (not stopped_on.is_empty() or str(inbox["reason"]).contains(CareerCalendar.MATCH_DAY)),
		"a holiday until the next inbox message stops on a headline (%s)" % inbox["reason"])
	var year_end := GameDate.make(GameDate.year_of(repo.current_day()) + 1, 1, 1) - 1
	var to_year_end := CareerCalendar.holiday(repo, human_id, -1, false)
	check(repo.current_day() == year_end or str(to_year_end["reason"]).contains(CareerCalendar.MATCH_DAY),
		"a holiday to the end of the year lands on 31 December (%s)" % GameDate.format(repo.current_day()))


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
