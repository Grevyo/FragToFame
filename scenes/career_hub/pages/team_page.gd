class_name CareerTeamPage
extends CareerPage
## One organisation's pages: Overview, Squad, Matches, Finances and History. Opened from any
## team name ({org_id}), or as "My Team" (the human's organisation). Every player, opponent and
## series links onwards.

const TABS: Array[Array] = [["overview", "Overview"], ["squad", "Squad"], ["matches", "Matches"],
	["finances", "Finances"], ["history", "History"]]

var org: CareerRecords.OrganisationRecord


func get_page_title() -> String:
	return org.name if org != null else ("My Team" if str(args.get("_page", "")) == "my_team" else "Team")


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	var org_id := str(args.get("org_id", ""))
	if org_id.is_empty() and str(args.get("_page", "")) == "my_team":
		var contract := repo.active_contract(career().human_player_id)
		if contract == null:
			var card := UIFactory.card(self, "No team yet")
			card.add_child(UIFactory.label("You are a free agent. Trials and offers arrive in your Inbox; Teams lists every organisation.",
				&"MutedLabel", true))
			card.add_child(link("Browse teams", &"teams", {}))
			return
		org_id = contract.organisation_id
		args["org_id"] = org_id
	org = repo.get_organisation(org_id)
	if org == null:
		var missing := UIFactory.card(self, "Pick a team")
		missing.add_child(UIFactory.label("Open a team from Teams, a table or a match.", &"MutedLabel", true))
		missing.add_child(link("Browse teams", &"teams", {}))
		return
	_header(repo)
	var tab := str(args.get("tab", "overview"))
	add_tabs(TABS, tab)
	match tab:
		"squad":
			_squad(repo)
		"matches":
			_matches(repo)
		"finances":
			_finances(repo)
		"history":
			_history(repo)
		_:
			_overview(repo)


func _header(repo: CareerRepository) -> void:
	var row := add_row(12)
	for tile: Array in [["Tier", CareerCatalog.tier_name(org.tier)], ["Region", CareerCatalog.region_name(org.region_id)],
			["Reputation", str(repo.organisation_reputation(org.id))], ["Form", CareerNewsPage.form_label(repo.organisation_form(org.id))]]:
		UIFactory.stat_tile(row, str(tile[0]), str(tile[1]))


func _overview(repo: CareerRepository) -> void:
	var row := add_row()
	var starting := UIFactory.card(row, "Starting five")
	var lines: Array[Array] = []
	for entry: Dictionary in repo.roster(org.id):
		var contract := entry["contract"] as CareerRecords.ContractRecord
		if contract.is_substitute:
			continue
		var player := entry["player"] as CareerRecords.PlayerRecord
		lines.append([cell_player(player.id, player.nickname + ("  (you)" if player.is_human else "")),
			CareerCatalog.role_name(contract.role), str(entry["rating"])])
	link_table(starting, PackedStringArray(["Player", "Role", "Rating"]), lines)
	starting.add_child(link("Full squad", &"team", {"org_id": org.id, "tab": "squad"}))
	var next_card := UIFactory.card(row, "Next series")
	_series_table(repo, next_card, repo.organisation_series(org.id, 5, true), true)
	var recent := UIFactory.card(self, "Recent results")
	_series_table(repo, recent, repo.organisation_series(org.id, 6), false)
	recent.add_child(link("All matches", &"team", {"org_id": org.id, "tab": "matches"}))
	var news := UIFactory.card(self, "In the news")
	_news(repo.news_about("", org.id, 8), news)
	var practice := UIFactory.button("Practice match vs %s (MR3, bots)" % org.short_name)
	var org_id := org.id
	practice.pressed.connect(func() -> void: App.start_practice_against(org_id))
	add_child(practice)


func _squad(repo: CareerRepository) -> void:
	var card := UIFactory.card(self, "Squad")
	card.add_child(UIFactory.label("Ratings are perceived (what the world believes). Form is the last 90 days of simulated maps.",
		&"MutedLabel", true))
	var rows: Array[Array] = []
	var today := repo.current_day()
	for entry: Dictionary in repo.roster(org.id):
		var player := entry["player"] as CareerRecords.PlayerRecord
		var contract := entry["contract"] as CareerRecords.ContractRecord
		var form := repo.sim_form(player.id, today - 90)
		rows.append([cell_player(player.id, player.nickname + ("  (you)" if player.is_human else "")),
			CareerCatalog.role_name(contract.role) + (" · bench" if contract.is_substitute else ""), str(player.age(today)),
			CareerCatalog.nation_name(player.nation_id), str(entry["rating"]),
			"%.2f (%d maps)" % [float(form["rating"]), int(form["maps"])] if int(form["maps"]) > 0 else "—",
			"%+d" % repo.morale(player.id), CareerCatalog.format_money(contract.monthly_salary), GameDate.format(contract.end_day)])
	link_table(card, PackedStringArray(["Player", "Role", "Age", "Nation", "Rating", "Form", "Morale", "Salary", "Contract until"]), rows)


func _matches(repo: CareerRepository) -> void:
	var upcoming := UIFactory.card(self, "Upcoming")
	_series_table(repo, upcoming, repo.organisation_series(org.id, 10, true), true)
	var played := UIFactory.card(self, "Results")
	_series_table(repo, played, repo.organisation_series(org.id, 40), false)


func _finances(repo: CareerRepository) -> void:
	var row := add_row(12)
	UIFactory.stat_tile(row, "Balance", CareerCatalog.format_money(repo.organisation_balance(org.id)))
	UIFactory.stat_tile(row, "Monthly income", CareerCatalog.format_money(WorldFinance.monthly_income(org.tier,
		repo.organisation_reputation(org.id))))
	UIFactory.stat_tile(row, "Monthly wages", CareerCatalog.format_money(repo.wage_bill(org.id)))
	var card := UIFactory.card(self, "Ledger")
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.ledger(org.id, false, 30):
		rows.append(PackedStringArray([GameDate.format(int(entry["day"])), str(entry["kind"]).capitalize(),
			str(entry["note"]), CareerCatalog.format_money(int(entry["amount"]))]))
	UIFactory.table(card, PackedStringArray(["Date", "Kind", "Note", "Amount"]), rows)


func _history(repo: CareerRepository) -> void:
	var finishes := UIFactory.card(self, "Season finishes")
	var rows: Array[Array] = []
	for entry: Dictionary in repo.organisation_records(org.id):
		rows.append([str(int(entry["season_year"])), cell_link(str(entry["competition_name"]), &"competitions",
			{"competition_id": str(entry["competition_id"]), "year": int(entry["season_year"])}),
			WorldSeasons.ordinal(int(entry["position"])), "%d–%d" % [int(entry["won"]), int(entry["lost"])],
			CareerCatalog.format_money(int(entry["prize"]))])
	if rows.is_empty():
		finishes.add_child(UIFactory.label("No completed seasons yet.", &"MutedLabel"))
	else:
		link_table(finishes, PackedStringArray(["Year", "Competition", "Finish", "Series", "Prize"]), rows)
	var moves := UIFactory.card(self, "Promotions and relegations")
	var move_rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.organisation_moves(org.id):
		move_rows.append(PackedStringArray([GameDate.format(int(entry["day"])), "Tier %d → %d" % [int(entry["from_tier"]),
			int(entry["to_tier"])], str(entry["reason"])]))
	if move_rows.is_empty():
		moves.add_child(UIFactory.label("Always in this tier.", &"MutedLabel"))
	else:
		UIFactory.table(moves, PackedStringArray(["Date", "Move", "Why"]), move_rows)
	var info := UIFactory.card(self, "Club")
	UIFactory.key_value_grid(info, [PackedStringArray(["Short name", org.short_name]),
		PackedStringArray(["Founded", GameDate.format_year(org.founded_day)]), PackedStringArray(["ID", org.id])] as Array[PackedStringArray])


## A table of series with the opponent and the report linked.
func _series_table(_repo: CareerRepository, card: VBoxContainer, fixtures: Array[Dictionary], upcoming: bool) -> void:
	if fixtures.is_empty():
		card.add_child(UIFactory.label("None.", &"MutedLabel"))
		return
	var rows: Array[Array] = []
	for fixture: Dictionary in fixtures:
		var home := str(fixture["home_id"]) == org.id
		var opponent_id := str(fixture["away_id"]) if home else str(fixture["home_id"])
		var opponent := str(fixture["away_name"]) if home else str(fixture["home_name"])
		var result := ""
		if not upcoming:
			var own := int(fixture["home_maps"]) if home else int(fixture["away_maps"])
			var other := int(fixture["away_maps"]) if home else int(fixture["home_maps"])
			result = "%s %d–%d" % ["W" if own > other else "L", own, other]
		rows.append([GameDate.format(int(fixture["scheduled_day"])), str(fixture["competition_name"]),
			cell_team(opponent_id, ("vs " if home else "@ ") + opponent),
			cell_link(result if not upcoming else "Preview", &"series", {"series_id": int(fixture["id"])})])
	link_table(card, PackedStringArray(["Date", "Competition", "Opponent", "Result"]), rows)


func _news(stories: Array[Dictionary], card: VBoxContainer) -> void:
	if stories.is_empty():
		card.add_child(UIFactory.label("Nothing yet.", &"MutedLabel"))
		return
	var rows: Array[PackedStringArray] = []
	for story: Dictionary in stories:
		rows.append(PackedStringArray([GameDate.format(int(story["day"])), str(story["headline"])]))
	UIFactory.table(card, PackedStringArray(["Date", "Story"]), rows)
