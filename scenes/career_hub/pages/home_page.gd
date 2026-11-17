class_name CareerHomePage
extends CareerPage

var _fixture_card: VBoxContainer
var _fixture_status: Label
var offers_card: VBoxContainer
var offer_status: Label


func get_page_title() -> String:
	return "Home"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var me := session.human()
	var today := repo.current_day()

	var welcome := UIFactory.card(self, "Welcome, %s" % (me.nickname if me != null else "professional"))
	_fixture_card = UIFactory.card(self, "Your next match")
	_refresh_fixture_card()
	offers_card = UIFactory.card(self, "Offers")
	refresh_offers()

	if not session.warning.is_empty():
		welcome.add_child(UIFactory.label(session.warning, &"WarningLabel", true))

	var row := add_row()
	var status_card := UIFactory.card(row, "Career status")
	var contract := repo.active_contract(me.id) if me != null else null
	var team := "Free agent"
	if contract != null:
		team = "%s (%s)" % [repo.get_organisation(contract.organisation_id).name, CareerCatalog.role_name(contract.role)]
	var reputation := repo.reputation(me.id) if me != null else 0
	var profile := repo.human_profile(me.id) if me != null else {}
	var status_rows: Array[PackedStringArray] = [
		PackedStringArray(["Date", GameDate.format(today)]),
		PackedStringArray(["Team", team]),
		PackedStringArray(["Preferred role", CareerCatalog.role_name(me.preferred_role) if me != null else "—"]),
		PackedStringArray(["Reputation", "%s (%d)" % [CareerCatalog.reputation_label(reputation), reputation]]),
		PackedStringArray(["Difficulty", CareerCatalog.DIFFICULTY_NAMES.get(StringName(str(profile.get("difficulty", ""))), "—")]),
	]
	if me != null:
		var elo := CareerDevelopment.current_elo(repo, me.id)
		var saved := repo.amateur_rating(me.id)
		var change := int(saved.get("last_change", 0))
		var detail := "%d (%+d last match)" % [elo, change] if change != 0 else str(elo)
		status_rows.append(PackedStringArray(["Amateur ELO", detail]))
	UIFactory.key_value_grid(status_card, status_rows)

	var world_card := UIFactory.card(row, "The world")
	var world_rows: Array[PackedStringArray] = [
		PackedStringArray(["Template", repo.meta_value("database_name", "Legacy world")]),
		PackedStringArray(["Organisations", str(repo.organisation_count())]),
		PackedStringArray(["Active professionals", str(repo.player_count(false))]),
		PackedStringArray(["Free agents", str(repo.search_players({"free_agents": true, "limit": 100000}).size())]),
	]
	UIFactory.key_value_grid(world_card, world_rows)

	var news := UIFactory.card(self, "Latest news")
	CareerNewsPage.add_stories(news, repo.news(5, WorldSimulation.NOTABLE),
		"No notable news yet. Use Next day or Continue on the Calendar.")

	var top := UIFactory.card(self, "Top organisations")
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.organisations().slice(0, 6):
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		rows.append(PackedStringArray([org.name, CareerCatalog.region_name(org.region_id),
			CareerCatalog.tier_name(org.tier), str(entry["reputation"])]))
	UIFactory.table(top, PackedStringArray(["Organisation", "Region", "Tier", "Reputation"]), rows)


func _refresh_fixture_card() -> void:
	for child: Node in _fixture_card.get_children().slice(2):
		_fixture_card.remove_child(child)
		child.queue_free()
	var session := career()
	if session == null:
		return
	_fixture_status = UIFactory.label("", &"WarningLabel", true)
	var fixture := session.repo.pending_fixture(session.human_player_id)
	if App.has_unsaved_fixture_result():
		_fixture_card.add_child(UIFactory.label("Your finished match is waiting to be saved.", &"MutedLabel"))
		var retry := UIFactory.button("Retry saving result", &"AccentButton")
		retry.pressed.connect(func() -> void:
			var problem := App.retry_career_result()
			if problem.is_empty():
				App.open_career_hub()
			else:
				_fixture_status.text = problem)
		_fixture_card.add_child(retry)
	elif fixture == null:
		_fixture_card.add_child(UIFactory.label(
			"Schedule a 5v5 amateur matchmaking game. Results build your ELO and reputation, which "
			+ "organisations watch when deciding whom to invite to trials. The calendar advances after "
			+ "the final score is saved.", &"MutedLabel", true))
		var map_ids: Array[String] = []
		var map_option := OptionButton.new()
		map_option.tooltip_text = "Map for this fixture"
		for entry: Dictionary in OfficialMaps.listing():
			map_option.add_item("%s (official)" % entry["name"])
			map_ids.append(str(entry["map_id"]))
		map_option.add_item("Sandbox Arena (dev)")
		map_ids.append(MapTemplates.SANDBOX_ARENA_ID)
		_fixture_card.add_child(map_option)
		var schedule := UIFactory.button("Schedule amateur match", &"AccentButton")
		schedule.pressed.connect(func() -> void:
			var problem := App.schedule_career_fixture(map_ids[maxi(0, map_option.selected)])
			if problem.is_empty():
				_refresh_fixture_card()
			else:
				_fixture_status.text = problem)
		_fixture_card.add_child(schedule)
	else:
		var setup := fixture.setup
		_fixture_card.add_child(UIFactory.label("%s vs %s" % [setup.home_team_name, setup.away_team_name],
			&"CardTitleLabel", true))
		_fixture_card.add_child(UIFactory.label("%s · %s · MR%d · %s" % [setup.competition,
			GameDate.format(fixture.scheduled_day), setup.max_rounds, _map_name(setup.map_id)], &"MutedLabel", true))
		var play := UIFactory.button("Play fixture", &"AccentButton")
		play.pressed.connect(func() -> void: _fixture_status.text = App.start_career_fixture(setup.fixture_id))
		_fixture_card.add_child(play)
	_fixture_card.add_child(_fixture_status)


## Trial invitations and contract offers with Accept / Decline, plus a short history.
func refresh_offers() -> void:
	for child: Node in offers_card.get_children().slice(1):
		offers_card.remove_child(child)
		child.queue_free()
	var session := career()
	if session == null:
		return
	var repo := session.repo
	offer_status = UIFactory.label("", &"WarningLabel", true)
	var open := repo.offers(session.human_player_id, true)
	if open.is_empty():
		var signed := repo.active_contract(session.human_player_id) != null
		var seen := CareerOffers.visibility(repo.reputation(session.human_player_id),
			CareerDevelopment.current_elo(repo, session.human_player_id), repo.recent_ratings(session.human_player_id))
		offers_card.add_child(UIFactory.label("You are under contract." if signed else
			"No offers right now. Visibility %d / 100: tier 4 organisations look from %d, tier 3 from %d, tier 2 from %d, tier 1 from %d."
			% [roundi(seen), roundi(CareerOffers.TIER_VISIBILITY[4]), roundi(CareerOffers.TIER_VISIBILITY[3]),
				roundi(CareerOffers.TIER_VISIBILITY[2]), roundi(CareerOffers.TIER_VISIBILITY[1])], &"MutedLabel", true))
	for offer: Dictionary in open:
		var row := UIFactory.hbox(8)
		var trial := str(offer["kind"]) == CareerOffers.KIND_TRIAL
		var text := "%s · %s" % [offer["org_name"], CareerCatalog.tier_name(int(offer["tier"]))]
		if trial:
			text += " · trial invitation" if str(offer["status"]) == "pending" else " · trial booked (play it above)"
		else:
			text += " · %d-year contract, %d a month" % [int(offer["years"]), int(offer["monthly_salary"])]
		text += " · open until %s" % GameDate.format(int(offer["expires_day"]))
		var caption := UIFactory.label(text, &"", true)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		if str(offer["status"]) == "pending":
			var offer_id := str(offer["id"])
			var accept := UIFactory.button("Accept trial" if trial else "Sign", &"AccentButton")
			accept.pressed.connect(func() -> void: _answer_offer(offer_id, true))
			row.add_child(accept)
			var decline := UIFactory.button("Decline")
			decline.pressed.connect(func() -> void: _answer_offer(offer_id, false))
			row.add_child(decline)
		offers_card.add_child(row)
	offers_card.add_child(offer_status)


## Accepts or declines an offer and refreshes the cards. Returns "" or why not.
func _answer_offer(offer_id: String, accept: bool) -> String:
	var problem := App.accept_career_offer(offer_id) if accept else App.decline_career_offer(offer_id)
	if not problem.is_empty():
		offer_status.text = problem
		return problem
	_refresh_fixture_card()
	refresh_offers()
	return ""


func _map_name(map_id: String) -> String:
	for entry: Dictionary in OfficialMaps.listing():
		if str(entry["map_id"]) == map_id:
			return str(entry["name"])
	return "Sandbox Arena (development map)" if map_id == MapTemplates.SANDBOX_ARENA_ID else map_id
