class_name CareerHomePage
extends CareerPage

var _fixture_card: VBoxContainer
var _fixture_status: Label


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
	_fixture_card = UIFactory.card(self, "Amateur Matchmaking")
	_refresh_fixture_card()

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
			"Schedule a 5v5 career match. The calendar advances after its final score is saved.",
			&"MutedLabel", true))
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
		_fixture_card.add_child(UIFactory.label("%s · MR%d · Sandbox Arena (development map)" % [
			GameDate.format(fixture.scheduled_day), setup.max_rounds], &"MutedLabel", true))
		var play := UIFactory.button("Play fixture", &"AccentButton")
		play.pressed.connect(func() -> void: _fixture_status.text = App.start_career_fixture(setup.fixture_id))
		_fixture_card.add_child(play)
	_fixture_card.add_child(_fixture_status)
