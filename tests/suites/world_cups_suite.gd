extends TestSuite
## Cups, promotion and relegation, offers to contracted humans and each save's own start.

const TEST_ROOT: String = "user://tests/world_cups"
const PROFILE: Dictionary = {"first_name": "Ines", "last_name": "Varga", "nickname": "Quill",
	"nation_id": "hu", "preferred_role": &"rifler", "difficulty": &"standard", "age": 21}


func suite_name() -> String:
	return "Cups, promotion and life under contract (Milestones 13–14)"


func run() -> void:
	_test_bracket_rules()
	_test_contract_rules()
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


func _test_bracket_rules() -> void:
	section("Cup brackets")
	check(CareerCups.bracket_size(6) == 8 and CareerCups.bracket_size(16) == 16 and CareerCups.round_count(6) == 3,
		"brackets grow to the next power of two")
	check(CareerCups.bracket_order(8) == [1, 8, 4, 5, 2, 7, 3, 6], "seed 1 meets the last seed; 1 and 2 only meet in the final")
	var seeded: Array[String] = ["a", "b", "c", "d", "e", "f"]
	var first := CareerCups.first_round(seeded, 10)
	var slots := CareerCups.slots(seeded)
	check(first.size() == 2 and slots[0] == "a" and slots[1].is_empty() and slots[4] == "b" and slots[5].is_empty(),
		"a six-team field gives the top two seeds byes")
	check(CareerCups.round_name(1, 16) == "Round of 16" and CareerCups.round_name(3, 16) == "Semi-finals"
		and CareerCups.round_name(4, 16) == "Final", "rounds are named by how many sides are left")
	var fixtures: Array[Dictionary] = []
	for fixture: Dictionary in first:
		fixtures.append(fixture.merged({"home_maps": 2, "away_maps": 0}))
	var state := CareerCups.bracket(seeded, fixtures)
	var rounds: Array = state["rounds"]
	check(rounds.size() == 2 and (rounds[1] as Array).size() == 4 and str(state["champion"]).is_empty(),
		"after round one the semi-finals are known and nobody has won yet")
	check(int(state["eliminated"].size()) == 2, "the beaten sides are out in round one")


func _test_contract_rules() -> void:
	section("Life under contract rules")
	var none: Array[float] = []
	var slump: Array[float] = [0.7, 0.8, 0.75]
	var fine: Array[float] = [1.1, 0.9, 1.0]
	check(CareerHumanContracts.wants_to_keep(3, 61, none, false, 0.9) and not CareerHumanContracts.wants_to_keep(3, 40, none, false, 0.0),
		"organisations renew a human at their level and let a weak one go")
	check(not CareerHumanContracts.wants_to_keep(3, 70, slump, false, 0.0) and not CareerHumanContracts.wants_to_keep(3, 70, fine, true, 0.9),
		"a slump or a seat on the bench can cost a renewal")
	check(CareerHumanContracts.should_bench(slump, 0.1) and not CareerHumanContracts.should_bench(fine, 0.1)
		and not CareerHumanContracts.should_bench([0.5, 0.5] as Array[float], 0.1), "only a real slump over three matches risks a starting place")


func _test_career(app: Node) -> void:
	section("Every save starts differently")
	var problem: String = app.call("new_career", "Cup tests A", PROFILE)
	check(problem.is_empty(), "creates a disposable career (%s)" % problem)
	if not problem.is_empty():
		return
	var first_signature := _signature((app.get("career") as CareerSession).repo)
	app.call("close_career")
	problem = app.call("new_career", "Cup tests B", PROFILE)
	check(problem.is_empty(), "creates a second career from the same database")
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	check(_signature(repo) != first_signature, "two careers from one database start with different tiers and form")
	var start_moves := int(repo.db.scalar("SELECT COUNT(*) FROM organisation_move WHERE reason = 'Start of this world';", [], 0))
	check(start_moves >= 2 and start_moves % 2 == 0, "some organisations start a tier up or down (%d moves)" % start_moves)
	var sizes := _tier_sizes(repo)
	check(sizes == _original_sizes(repo), "every tier keeps its size")

	section("A cup is played to the end")
	var cup_id := str(repo.db.scalar("SELECT id FROM competition WHERE name = 'Vanguard Masters';", [], ""))
	var cup := repo.league_season(cup_id, 1)
	check(not cup.is_empty() and repo.cup_seeds(cup_id, 1).size() == 16 and repo.league_fixtures(cup_id, 1).size() == 8,
		"the cup is drawn with sixteen seeds and eight first-round series")
	if cup.is_empty():
		return
	var dice := RandomNumberGenerator.new()
	dice.seed = 404
	var end_day := int(cup["start_day"]) + CareerCups.DAYS_BETWEEN_ROUNDS * 4 + 2
	check(CareerCalendar.advance_to(repo, end_day, dice), "the calendar runs through the cup")
	var record := repo.league_record(cup_id, 1)
	var fixtures := repo.league_fixtures(cup_id, 1)
	var per_round: Dictionary[int, int] = {}
	for fixture: Dictionary in fixtures:
		per_round[int(fixture["round_number"])] = per_round.get(int(fixture["round_number"]), 0) + 1
	check(per_round == {1: 8, 2: 4, 3: 2, 4: 1}, "each round halves the field (%s)" % str(per_round))
	check(record.size() == 16 and int(record[0]["won"]) == 4 and int(record[1]["won"]) == 3,
		"the cup closes with the champion and runner-up on top")
	check(repo.news(2000).any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("in the final")),
		"the cup winner makes the news")

	section("Promotion and relegation")
	var promoted := int(repo.db.scalar("SELECT COUNT(*) FROM organisation_move WHERE reason LIKE 'Promoted after finishing%';", [], 0))
	var relegated := int(repo.db.scalar("SELECT COUNT(*) FROM organisation_move WHERE reason LIKE 'Relegated after%';", [], 0))
	check(promoted >= 1 and relegated == promoted, "finished leagues promote and relegate in pairs (%d up)" % promoted)
	check(_tier_sizes(repo) == sizes, "tiers keep their sizes after the swaps")
	var open_id := str(repo.db.scalar("SELECT id FROM competition WHERE name = 'Europe West Open';", [], ""))
	var bottom := repo.weakest_in_tier(4, "eu_west", [] as Array[String])
	var other := repo.weakest_in_tier(4, "", [bottom] as Array[String])
	var season := {"competition_id": open_id, "season_year": 1, "name": "Europe West Open", "tier": 4, "region_id": "eu_west"}
	var table: Array[Dictionary] = [
		{"organisation_id": bottom, "name": "Winner", "won": 4, "lost": 0, "map_diff": 8, "_out": 99},
		{"organisation_id": other, "name": "Runner-up", "won": 3, "lost": 1, "map_diff": 4, "_out": 4},
	]
	check(not bottom.is_empty() and WorldSeasons.close_cup(repo, season, table, repo.current_day())
		and repo.get_organisation(bottom).tier == 3 and _tier_sizes(repo) == sizes,
		"a tier 4 open winner moves up to tier 3 and a tier 3 side makes room")

	section("Offers to a contracted human")
	var player_id := session.human_player_id
	var seller_id := ""
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if org.tier == 3 and int(entry["roster_size"]) >= 5:
			seller_id = org.id
	var today := repo.current_day()
	var contract := CareerRecords.ContractRecord.new()
	contract.id = "con_cup_tests"
	contract.player_id = player_id
	contract.organisation_id = seller_id
	contract.role = &"rifler"
	contract.start_day = today - 200
	contract.end_day = today + 500
	check(repo.sign_contract(contract), "the human plays for a tier 3 organisation")
	var seen: Dictionary = {}
	for ability: StringName in CareerCatalog.ABILITIES:
		seen[ability] = 74
	repo.set_perceived(player_id, seen, 60, today)
	repo.set_reputation(player_id, 96, today)
	var human := repo.get_player(player_id)
	for attempt: int in 600:
		if repo.offers(player_id, true).any(func(o: Dictionary) -> bool: return str(o["kind"]) == CareerHumanContracts.KIND_TRANSFER):
			break
		CareerHumanContracts.daily(repo, human, repo.active_contract(player_id), today, dice)
	var bids := repo.offers(player_id, true).filter(func(o: Dictionary) -> bool:
		return str(o["kind"]) == CareerHumanContracts.KIND_TRANSFER)
	check(bids.size() == 1 and int(bids[0]["tier"]) < 3 and int(bids[0]["fee"]) > 0,
		"a higher-tier organisation bids for a visible human")
	if bids.is_empty():
		return
	var seller_before := repo.organisation_balance(seller_id)
	var answer := CareerOffers.accept(repo, player_id, str(bids[0]["id"]))
	var moved_to := repo.active_contract(player_id)
	check(answer.is_empty() and moved_to != null and moved_to.organisation_id == str(bids[0]["organisation_id"])
		and repo.organisation_balance(seller_id) == seller_before + int(bids[0]["fee"]),
		"accepting moves the human and pays the fee to their old organisation (%s)" % answer)

	section("Renewal and release")
	var notice_day := moved_to.end_day - CareerHumanContracts.RENEWAL_NOTICE
	check(CareerHumanContracts.daily(repo, human, moved_to, notice_day, dice) and repo.offers(player_id, true).any(
		func(o: Dictionary) -> bool: return str(o["kind"]) == CareerHumanContracts.KIND_RENEWAL),
		"a valued human is offered a renewal before the contract ends")
	var renewal: Dictionary = repo.offers(player_id, true).filter(func(o: Dictionary) -> bool:
		return str(o["kind"]) == CareerHumanContracts.KIND_RENEWAL)[0]
	check(CareerOffers.accept(repo, player_id, str(renewal["id"])).is_empty()
		and repo.active_contract(player_id).end_day == moved_to.end_day + int(renewal["years"]) * GameDate.DAYS_PER_YEAR,
		"accepting a renewal extends the contract")
	for ability: StringName in CareerCatalog.ABILITIES:
		seen[ability] = 30
	repo.set_perceived(player_id, seen, 60, repo.current_day())
	var extended := repo.active_contract(player_id)
	var last_notice := extended.end_day - CareerHumanContracts.RENEWAL_NOTICE
	check(CareerHumanContracts.daily(repo, human, extended, last_notice, dice) and repo.news_on(last_notice, WorldSimulation.HEADLINE).any(
		func(n: Dictionary) -> bool: return str(n["headline"]).contains("will not renew")),
		"a human below the organisation's level is told they will be released")

	section("Benched and recalled")
	check(repo.set_contract_substitute(extended.id, true) and not repo.organisation_has_human_starter(extended.organisation_id),
		"a benched human's organisation is simulated without them")
	for ability: StringName in CareerCatalog.ABILITIES:
		seen[ability] = 90
	repo.set_perceived(player_id, seen, 60, repo.current_day())
	for attempt: int in 40:
		if not repo.active_contract(player_id).is_substitute:
			break
		CareerHumanContracts.monthly(repo, repo.current_day(), dice)
	check(not repo.active_contract(player_id).is_substitute and repo.organisation_has_human_starter(extended.organisation_id)
		and repo.lineup(extended.organisation_id).size() == CareerFixtures.TEAM_SIZE,
		"a strong benched human wins their place back")


func _signature(repo: CareerRepository) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		parts.append("%s:%d:%d" % [org.id, org.tier, repo.organisation_form(org.id)])
	parts.sort()
	return ",".join(parts)


func _tier_sizes(repo: CareerRepository) -> Dictionary:
	var sizes: Dictionary = {}
	for entry: Dictionary in repo.organisations():
		var tier := (entry["organisation"] as CareerRecords.OrganisationRecord).tier
		sizes[tier] = int(sizes.get(tier, 0)) + 1
	return sizes


## Tier sizes before the save's start moves (each org's first recorded from_tier).
func _original_sizes(repo: CareerRepository) -> Dictionary:
	var sizes: Dictionary = {}
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		var tier := org.tier
		var first: Variant = repo.db.scalar("SELECT from_tier FROM organisation_move WHERE organisation_id = ? ORDER BY id LIMIT 1;", [org.id])
		if first != null:
			tier = int(first)
		sizes[tier] = int(sizes.get(tier, 0)) + 1
	return sizes


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
