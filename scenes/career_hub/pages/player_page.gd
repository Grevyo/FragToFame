class_name CareerPlayerPage
extends CareerPage
## One player's pages: Overview (profile and scouting), Stats, Maps, Career and News, with a
## Compare button. Opened from any player name ({player_id, tab}).

const TABS: Array[Array] = [["overview", "Overview"], ["stats", "Stats"], ["maps", "Maps"],
	["career", "Career"], ["news", "News"]]
## Form windows on the Stats tab (label, days back; 0 = all time).
const FORM_WINDOWS: Array[Array] = [["Last 30 days", 30], ["Last 90 days", 90], ["Last year", 365], ["All time", 0]]

var player: CareerRecords.PlayerRecord
## The scouting card (Overview tab, AI professionals only).
var scouting_card: VBoxContainer


func get_page_title() -> String:
	return player.display_name() if player != null else "Player"


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	player = repo.get_player(str(args.get("player_id", "")))
	if player == null:
		var missing := UIFactory.card(self, "Pick a player")
		missing.add_child(UIFactory.label("Open a player from Players, a squad, a table or a match report.", &"MutedLabel", true))
		missing.add_child(link("Browse players", &"players", {}))
		return
	_header(repo)
	var tab := str(args.get("tab", "overview"))
	add_tabs(TABS, tab)
	match tab:
		"stats":
			_stats(repo)
		"maps":
			_maps(repo)
		"career":
			_career(repo)
		"news":
			var talks := UIFactory.card(self, "Interviews")
			var said: Array[Dictionary] = []
			var stories: Array[Dictionary] = []
			for story: Dictionary in repo.news_about(player.id, "", 60):
				if str(story["kind"]) == WorldSimulation.NEWS_INTERVIEW:
					said.append(story)
				else:
					stories.append(story)
			story_table(talks, said, "Has not spoken to the press yet." if not player.is_human
				else "Your own interviews are not part of the game yet.")
			var card := UIFactory.card(self, "In the news")
			story_table(card, stories, "No stories about this player yet.")
		_:
			_overview()


func _header(repo: CareerRepository) -> void:
	var row := add_row(12)
	var contract := repo.active_contract(player.id)
	if contract != null:
		var org := repo.get_organisation(contract.organisation_id)
		if org != null:
			row.add_child(team_link(org.id, org.name))
			row.add_child(UIFactory.label("· %s%s" % [CareerCatalog.role_name(contract.role),
				" (bench)" if contract.is_substitute else ""], &"MutedLabel"))
	else:
		row.add_child(UIFactory.label("Free agent" if player.status == "active" else player.status.capitalize(), &"MutedLabel"))
	row.add_child(UIFactory.expand_spacer())
	row.add_child(UIFactory.label("Rating %d · Reputation %d" % [repo.perceived_rating(player.id), repo.reputation(player.id)],
		&"AccentLabel"))
	var compare := UIFactory.button("Compare…")
	var player_id := player.id
	compare.pressed.connect(func() -> void: go(&"compare", {"a": player_id}))
	row.add_child(compare)


func _overview() -> void:
	var session := career()
	if not player.is_human and player.status == "active":
		_build_scouting(session)
	_person(session.repo)
	PlayerView.build(self, session.repo, player.id)


## Who they are: personality, drive, goal, mood and relationships (AI professionals).
func _person(repo: CareerRepository) -> void:
	var person := repo.person(player.id)
	var bonds := repo.relationships_of(player.id, 8)
	if person.is_empty() and bonds.is_empty():
		return
	var row := add_row()
	if not person.is_empty():
		var card := UIFactory.card(row, "The person")
		card.add_child(UIFactory.label(" · ".join(PersonVoice.descriptors(person)), &"AccentLabel", true))
		var happiness := int(person["happiness"])
		var wants := int(person["wants_move"]) == 1
		var goal := PersonVoice.goal_text(str(person["goal"])) + (" (achieved %s)" % GameDate.format(int(person["goal_done_day"]))
			if person["goal_done_day"] != null else "")
		UIFactory.key_value_grid(card, [PackedStringArray(["Background", str(person["background"])]),
			PackedStringArray(["Driven by", PersonVoice.drive_text(str(person["drive"]))]),
			PackedStringArray(["Career goal", goal]),
			PackedStringArray(["Mood", "%s (%s)" % [PersonVoice.mood_word(happiness, wants), person["mood_reason"]]
				if not str(person["mood_reason"]).is_empty() else PersonVoice.mood_word(happiness, wants)]),
			PackedStringArray(["Speaks", PersonVoice.tone(person).capitalize()])] as Array[PackedStringArray])
	var people := UIFactory.card(row, "Relationships")
	if bonds.is_empty():
		people.add_child(UIFactory.label("No strong feelings either way yet.", &"MutedLabel", true))
		return
	var rows: Array[Array] = []
	for bond: Dictionary in bonds:
		rows.append([cell_player(str(bond["other_id"]), str(bond["nickname"])), PersonVoice.bond_word(int(bond["strength"])),
			"%+d" % int(bond["strength"])])
	link_table(people, PackedStringArray(["With", "Relationship", "Strength"]), rows)


func _stats(repo: CareerRepository) -> void:
	var card := UIFactory.card(self, "Simulated series")
	card.add_child(UIFactory.label("Maps the match engine simulated round by round. Separate from the statistics of matches you play.",
		&"MutedLabel", true))
	var rows: Array[PackedStringArray] = []
	var today := repo.current_day()
	for window: Array in FORM_WINDOWS:
		var days := int(window[1])
		var form := repo.sim_form(player.id, today - days if days > 0 else 0)
		var maps := int(form["maps"])
		rows.append(PackedStringArray([str(window[0]), str(maps), str(int(form["won"])),
			"%.2f" % float(form["rating"]) if maps > 0 else "—",
			"%d – %d" % [int(form["kills"]), int(form["deaths"])], str(int(form["assists"])),
			str(int(form["opening_kills"])), str(int(form["clutch_wins"]))]))
	UIFactory.table(card, PackedStringArray(["Period", "Maps", "Won", "Rating", "K – D", "Assists", "Openings", "Clutches"]), rows)
	var recorded := UIFactory.card(self, "Recorded matches")
	var totals := repo.performance_totals(player.id)
	var matches := int(totals.get("matches", 0))
	if matches == 0:
		recorded.add_child(UIFactory.label("No matches played in the FPS yet.", &"MutedLabel"))
		return
	UIFactory.key_value_grid(recorded, [PackedStringArray(["Matches", str(matches)]),
		PackedStringArray(["Kills – deaths", "%d – %d" % [int(totals.get("kills", 0)), int(totals.get("deaths", 0))]]),
		PackedStringArray(["F2F performance rating", "%.2f" % MatchStatistics.rating(totals)])] as Array[PackedStringArray])
	recorded.add_child(link("Full statistics", &"statistics", {}))


func _maps(repo: CareerRepository) -> void:
	var summary := UIFactory.card(self, "By map")
	var map_rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.player_map_stats(player.id):
		map_rows.append(PackedStringArray([map_name(str(entry["map_id"])), str(int(entry["maps"])),
			"%d%%" % roundi(100.0 * float(entry["won"]) / maxf(float(entry["maps"]), 1.0)), "%.2f" % float(entry["rating"]),
			"%d – %d" % [int(entry["kills"]), int(entry["deaths"])]]))
	if map_rows.is_empty():
		summary.add_child(UIFactory.label("No simulated maps yet.", &"MutedLabel"))
	else:
		UIFactory.table(summary, PackedStringArray(["Map", "Played", "Won", "Rating", "K – D"]), map_rows)
	var recent := UIFactory.card(self, "Recent maps")
	var rows: Array[Array] = []
	for line: Dictionary in repo.player_lines(player.id, 40):
		var score := "—"
		if line["home_rounds"] != null:
			var home := int(line["at_home"]) == 1
			score = "%d–%d" % [int(line["home_rounds"]) if home else int(line["away_rounds"]),
				int(line["away_rounds"]) if home else int(line["home_rounds"])]
		var opponent: Variant = "Your match" if line["opponent_id"] == null else cell_team(str(line["opponent_id"]),
			str(line["opponent_name"]))
		var report: Variant = score if line["series_id"] == null else cell_link(score, &"series", {"series_id": int(line["series_id"])})
		rows.append([GameDate.format(int(line["day"])), str(line["competition_name"]) if line["competition_name"] != null else "",
			opponent, map_name(str(line["map_id"])) if line["map_id"] != null else "", report,
			"%d – %d – %d" % [int(line["kills"]), int(line["deaths"]), int(line["assists"])], "%.2f" % float(line["rating"])])
	if rows.is_empty():
		recent.add_child(UIFactory.label("No simulated maps yet.", &"MutedLabel"))
	else:
		link_table(recent, PackedStringArray(["Date", "Competition", "Opponent", "Map", "Score", "K – D – A", "Rating"]), rows)


func _career(repo: CareerRepository) -> void:
	var clubs := UIFactory.card(self, "Contracts")
	var rows: Array[Array] = []
	var history := repo.contract_history(player.id)
	history.reverse()
	for contract: CareerRecords.ContractRecord in history:
		var org := repo.get_organisation(contract.organisation_id)
		rows.append([GameDate.format(contract.start_day), GameDate.format(contract.end_day),
			cell_team(contract.organisation_id, org.name if org != null else contract.organisation_id),
			CareerCatalog.role_name(contract.role), CareerCatalog.format_money(contract.monthly_salary), contract.status.capitalize()])
	if rows.is_empty():
		clubs.add_child(UIFactory.label("Never signed for an organisation.", &"MutedLabel"))
	else:
		link_table(clubs, PackedStringArray(["From", "Until", "Organisation", "Role", "Salary", "Status"]), rows)
	var honours := UIFactory.card(self, "Honours")
	var honour_rows: Array[Array] = []
	for honour: Dictionary in repo.honours(player.id):
		honour_rows.append([str(int(honour["season_year"])), WorldSeasons.ordinal(int(honour["position"])),
			cell_link(str(honour["competition_name"]), &"competitions", {"competition_id": str(honour["competition_id"]),
				"year": int(honour["season_year"])}), cell_team(str(honour["organisation_id"]), str(honour["org_name"]))])
	if honour_rows.is_empty():
		honours.add_child(UIFactory.label("No honours yet.", &"MutedLabel"))
	else:
		link_table(honours, PackedStringArray(["Year", "Finish", "Competition", "With"]), honour_rows)


func _build_scouting(session: CareerSession) -> void:
	scouting_card = UIFactory.card(self, "Scouting report")
	var subject_id := player.id
	var report := session.repo.last_scout_report(session.human_player_id, subject_id)
	if not report.is_empty():
		scouting_card.add_child(UIFactory.label("Last report · %s · confidence +%d" % [
			GameDate.format(int(report["day"])), int(report["change"])], &"MutedLabel", true))
	if not session.repo.development_today(session.human_player_id, CareerDevelopment.SCOUTING).is_empty():
		scouting_card.add_child(UIFactory.label("Today's scouting report is complete.", &"MutedLabel", true))
		return
	var scout := UIFactory.button("Scout player", &"AccentButton")
	var status := UIFactory.label("", &"WarningLabel", true)
	scouting_card.add_child(scout)
	scouting_card.add_child(status)
	scout.pressed.connect(func() -> void:
		var problem := CareerDevelopment.scout(session.repo, session.human_player_id, subject_id)
		if not problem.is_empty():
			status.text = problem
			return
		var hub := hub_node()
		if hub != null:
			hub.call("refresh"))
