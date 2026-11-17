class_name CareerCompetitionsPage
extends CareerPage

var _definitions: Array[CareerRecords.CompetitionRecord] = []
var _choice: OptionButton
var _year_choice: OptionButton
var _detail: VBoxContainer


func get_page_title() -> String:
	return "Competitions"


func build_page() -> void:
	if add_no_career_notice():
		return
	_definitions = career().repo.competitions()
	if _definitions.is_empty():
		add_child(UIFactory.label("This world database has no competitions.", &"MutedLabel"))
		return

	var selectors := add_row(12)
	_choice = OptionButton.new()
	_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(_choice)
	var initial_index := 0
	for idx: int in _definitions.size():
		_choice.add_item(_definitions[idx].name)
		if _definitions[idx].kind == "league" and _definitions[initial_index].kind != "league":
			initial_index = idx
	_year_choice = OptionButton.new()
	selectors.add_child(_year_choice)
	_detail = UIFactory.vbox(18)
	add_child(_detail)
	_choice.item_selected.connect(_select_competition)
	_year_choice.item_selected.connect(func(_idx: int) -> void: _show_season())
	_choice.select(initial_index)
	_select_competition(initial_index)


func _select_competition(index: int) -> void:
	var repo := career().repo
	var competition := _definitions[index]
	var current_year := GameDate.year_of(repo.current_day())
	var published_years := repo.league_years(competition.id)
	_year_choice.clear()
	_year_choice.add_item("Year %d" % current_year, current_year)
	for year: int in published_years:
		if year != current_year:
			_year_choice.add_item("Year %d" % year, year)
	_year_choice.select(0)
	_year_choice.visible = competition.kind == "league"
	_show_season()


func _show_season() -> void:
	for child: Node in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var repo := career().repo
	var competition := _definitions[_choice.selected]
	var year := _year_choice.get_selected_id()
	var start_day := GameDate.make(year, competition.start_month, 1)
	var season := repo.league_season(competition.id, year)
	var region := "International" if competition.is_international() else CareerCatalog.region_name(competition.region_id)
	var card := UIFactory.card(_detail, competition.name)
	var info: Array[PackedStringArray] = [
		PackedStringArray(["Type", "Single round-robin league" if competition.kind == "league" else "Cup"]),
		PackedStringArray(["Region", region]),
		PackedStringArray(["Tier", CareerCatalog.tier_name(competition.tier)]),
		PackedStringArray(["Teams", str(competition.team_count)]),
	]
	if season.is_empty():
		info.append(PackedStringArray(["Start month", GameDate.MONTH_NAMES[competition.start_month - 1]]))
	else:
		info.append(PackedStringArray(["Opening day", GameDate.format(int(season["start_day"]))]))
		info.append(PackedStringArray(["Format", "BO%d" % int(season["best_of"])]))
	UIFactory.key_value_grid(card, info)
	if competition.kind == "cup":
		card.add_child(UIFactory.label("Cup scheduling is pending.", &"MutedLabel", true))
		return
	if season.is_empty():
		var eligible := repo.eligible_organisations(competition, start_day).size()
		var notice := "Season schedule unavailable."
		if eligible < competition.team_count:
			notice = "%d of %d required organisations are eligible for this league." % [eligible, competition.team_count]
		card.add_child(UIFactory.label(notice, &"MutedLabel", true))
		return

	var fixtures := repo.league_fixtures(competition.id, year)
	var record := repo.league_record(competition.id, year)
	var rows: Array[PackedStringArray] = []
	if record.is_empty():
		var standings := CareerCompetitions.standings(repo.league_entrants(competition.id, year), fixtures)
		var standings_card := UIFactory.card(_detail, "Standings")
		standings_card.add_child(UIFactory.label("Prize pool %s, paid when the season ends." % CareerCatalog.format_money(
			WorldSeasons.PRIZE_POOL.get(competition.tier, WorldSeasons.PRIZE_POOL[4])), &"MutedLabel", true))
		for entry: Dictionary in standings:
			rows.append(PackedStringArray([str(entry["name"]), str(entry["won"]), str(entry["lost"]),
				"%+d" % int(entry["map_diff"])]))
		UIFactory.table(standings_card, PackedStringArray(["Organisation", "Wins", "Losses", "Map diff"]), rows)
	else:
		var final_card := UIFactory.card(_detail, "Final standings · completed %s" % GameDate.format(int(record[0]["completed_day"])))
		for entry: Dictionary in record:
			rows.append(PackedStringArray([WorldSeasons.ordinal(int(entry["position"])), str(entry["name"]), str(entry["won"]),
				str(entry["lost"]), "%+d" % int(entry["map_diff"]), CareerCatalog.format_money(int(entry["prize"]))]))
		UIFactory.table(final_card, PackedStringArray(["Pos", "Organisation", "Wins", "Losses", "Map diff", "Prize"]), rows)
	_add_history(repo, competition.id)
	_add_fixture_rounds(fixtures, repo.current_day())


## Past podiums of a competition (season records).
func _add_history(repo: CareerRepository, competition_id: String) -> void:
	var podiums := repo.league_podiums(competition_id)
	if podiums.is_empty():
		return
	var card := UIFactory.card(_detail, "Season records")
	var by_year: Dictionary[int, PackedStringArray] = {}
	var years: Array[int] = []
	for entry: Dictionary in podiums:
		var year := int(entry["season_year"])
		if not by_year.has(year):
			by_year[year] = PackedStringArray([GameDate.format_year(GameDate.make(year, 1, 1)), "", "", ""])
			years.append(year)
		by_year[year][int(entry["position"])] = str(entry["name"])
	var rows: Array[PackedStringArray] = []
	for year: int in years:
		rows.append(by_year[year])
	UIFactory.table(card, PackedStringArray(["Season", "Champion", "Runner-up", "Third"]), rows)


func _add_fixture_rounds(fixtures: Array[Dictionary], today: int) -> void:
	if fixtures.is_empty():
		return
	var card := UIFactory.card(_detail, "League calendar")
	var selector := OptionButton.new()
	card.add_child(selector)
	var by_round: Dictionary[int, Array] = {}
	var default_index := -1
	for fixture: Dictionary in fixtures:
		var round_number := int(fixture["round_number"])
		if not by_round.has(round_number):
			by_round[round_number] = []
			var day := int(fixture["scheduled_day"])
			selector.add_item("Round %d  ·  %s" % [round_number, GameDate.format(day)], round_number)
			if default_index == -1 and day >= today:
				default_index = selector.item_count - 1
		by_round[round_number].append(fixture)
	var round_detail := UIFactory.vbox(0)
	card.add_child(round_detail)
	var show_round := func(index: int) -> void:
		for child: Node in round_detail.get_children():
			round_detail.remove_child(child)
			child.queue_free()
		var rows: Array[PackedStringArray] = []
		for fixture: Dictionary in by_round[selector.get_item_id(index)]:
			var score := "Awaiting result" if fixture["home_maps"] == null else (
				"%d – %d" % [int(fixture["home_maps"]), int(fixture["away_maps"])])
			rows.append(PackedStringArray([str(fixture["home_name"]), str(fixture["away_name"]), score]))
		UIFactory.table(round_detail, PackedStringArray(["Home", "Away", "Series score"]), rows)
	selector.item_selected.connect(show_round)
	selector.select(default_index if default_index >= 0 else selector.item_count - 1)
	show_round.call(selector.selected)
