class_name CareerCompetitionsPage
extends CareerPage
## Leagues and cups: standings, brackets, top performers, records and the calendar of series.
## Opens on {competition_id, year} when linked from a team or player; every team, player and
## series links onwards.

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
	var wanted := str(args.get("competition_id", ""))
	for idx: int in _definitions.size():
		_choice.add_item(_definitions[idx].name)
		if _definitions[idx].kind == "league" and _definitions[initial_index].kind != "league":
			initial_index = idx
	for idx: int in _definitions.size():
		if _definitions[idx].id == wanted:
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
	if args.has("year") and competition.id == str(args.get("competition_id", "")):
		for item: int in _year_choice.item_count:
			if _year_choice.get_item_id(item) == int(args["year"]):
				_year_choice.select(item)
	_year_choice.visible = true
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
		PackedStringArray(["Type", "Single round-robin league" if competition.kind == "league" else "Single-elimination cup"]),
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
	if season.is_empty():
		var notice := "Season schedule unavailable."
		if competition.kind == "cup":
			var invited := repo.cup_candidates(competition, start_day).size()
			notice = ("The %s draw is made when the edition starts." % competition.name if invited >= CareerCups.MIN_TEAMS
				else "%d of %d required organisations can enter this cup." % [invited, CareerCups.MIN_TEAMS])
		else:
			var eligible := CareerCompetitions.league_field(repo, competition, start_day).size()
			if eligible < CareerCompetitions.MIN_LEAGUE_TEAMS:
				notice = "%d of %d required organisations are eligible for this league." % [eligible, CareerCompetitions.MIN_LEAGUE_TEAMS]
		card.add_child(UIFactory.label(notice, &"MutedLabel", true))
		return
	if competition.kind == "cup":
		_show_cup(repo, competition, year)
		return

	var fixtures := repo.league_fixtures(competition.id, year)
	var record := repo.league_record(competition.id, year)
	var rows: Array[Array] = []
	if record.is_empty():
		var standings := CareerCompetitions.standings(repo.league_entrants(competition.id, year), fixtures)
		var standings_card := UIFactory.card(_detail, "Standings")
		standings_card.add_child(UIFactory.label("Prize pool %s, paid when the season ends." % CareerCatalog.format_money(
			WorldSeasons.PRIZE_POOL.get(competition.tier, WorldSeasons.PRIZE_POOL[4])), &"MutedLabel", true))
		for entry: Dictionary in standings:
			rows.append([cell_team(str(entry["organisation_id"]), str(entry["name"])), str(entry["won"]), str(entry["lost"]),
				"%+d" % int(entry["map_diff"])])
		link_table(standings_card, PackedStringArray(["Organisation", "Wins", "Losses", "Map diff"]), rows)
	else:
		var final_card := UIFactory.card(_detail, "Final standings · completed %s" % GameDate.format(int(record[0]["completed_day"])))
		for entry: Dictionary in record:
			rows.append([WorldSeasons.ordinal(int(entry["position"])), cell_team(str(entry["organisation_id"]), str(entry["name"])),
				str(entry["won"]), str(entry["lost"]), "%+d" % int(entry["map_diff"]), CareerCatalog.format_money(int(entry["prize"]))])
		link_table(final_card, PackedStringArray(["Pos", "Organisation", "Wins", "Losses", "Map diff", "Prize"]), rows)
	_add_performers(repo, competition.id, year)
	_add_history(repo, competition.id)
	_add_fixture_rounds(fixtures, repo.current_day())


## A cup edition: the bracket round by round, then the final placings once it is decided.
func _show_cup(repo: CareerRepository, competition: CareerRecords.CompetitionRecord, year: int) -> void:
	var seeded := repo.cup_seeds(competition.id, year)
	var fixtures := repo.league_fixtures(competition.id, year)
	var record := repo.league_record(competition.id, year)
	var names: Dictionary[String, String] = {}
	for entrant: Dictionary in repo.league_entrants(competition.id, year):
		names[str(entrant["organisation_id"])] = str(entrant["name"])
	var bracket_card := UIFactory.card(_detail, "Bracket")
	bracket_card.add_child(UIFactory.label("%d organisations, seeded by tier and reputation; top seeds get byes in a short field. Prize pool %s." % [
		seeded.size(), CareerCatalog.format_money(WorldSeasons.PRIZE_POOL.get(competition.tier, WorldSeasons.PRIZE_POOL[4]))],
		&"MutedLabel", true))
	var rounds := CareerCups.round_count(seeded.size())
	for round_number: int in range(1, rounds + 1):
		var rows: Array[Array] = []
		for fixture: Dictionary in fixtures:
			if int(fixture["round_number"]) != round_number:
				continue
			var score := "Awaiting result · %s" % GameDate.format(int(fixture["scheduled_day"])) if fixture["home_maps"] == null else (
				"%d – %d" % [int(fixture["home_maps"]), int(fixture["away_maps"])])
			rows.append([cell_team(str(fixture["home_id"]), names.get(str(fixture["home_id"]), "?")),
				cell_team(str(fixture["away_id"]), names.get(str(fixture["away_id"]), "?")),
				cell_link(score, &"series", {"series_id": int(fixture["id"])})])
		bracket_card.add_child(UIFactory.label(CareerCups.round_name(round_number, seeded.size()).to_upper(), &"SectionLabel"))
		if rows.is_empty():
			bracket_card.add_child(UIFactory.label("Drawn when the previous round is decided." if round_number > 1
				else "Every side has a bye.", &"MutedLabel", true))
		else:
			link_table(bracket_card, PackedStringArray(["Home", "Away", "Series score"]), rows)
	if not record.is_empty():
		var final_card := UIFactory.card(_detail, "Final placings · completed %s" % GameDate.format(int(record[0]["completed_day"])))
		var rows: Array[Array] = []
		for entry: Dictionary in record:
			rows.append([WorldSeasons.ordinal(int(entry["position"])), cell_team(str(entry["organisation_id"]), str(entry["name"])),
				str(entry["won"]), str(entry["lost"]), CareerCatalog.format_money(int(entry["prize"]))])
		link_table(final_card, PackedStringArray(["Pos", "Organisation", "Series won", "Series lost", "Prize"]), rows)
	_add_performers(repo, competition.id, year)
	_add_history(repo, competition.id)


## The season's best players in simulated series (average rating, at least four maps).
func _add_performers(repo: CareerRepository, competition_id: String, year: int) -> void:
	var best := repo.top_performers(competition_id, year, 4)
	if best.is_empty():
		return
	var card := UIFactory.card(_detail, "Top performers · simulated series")
	var rows: Array[Array] = []
	for entry: Dictionary in best:
		rows.append([cell_player(str(entry["player_id"]), str(entry["nickname"])), str(entry["org"]) if entry["org"] != null else "",
			str(int(entry["maps"])), "%d – %d" % [int(entry["kills"]), int(entry["deaths"])], "%.2f" % float(entry["rating"])])
	link_table(card, PackedStringArray(["Player", "Team", "Maps", "K – D", "Rating"]), rows)


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
		var rows: Array[Array] = []
		for fixture: Dictionary in by_round[selector.get_item_id(index)]:
			var score := "Awaiting result" if fixture["home_maps"] == null else (
				"%d – %d" % [int(fixture["home_maps"]), int(fixture["away_maps"])])
			rows.append([cell_team(str(fixture["home_id"]), str(fixture["home_name"])),
				cell_team(str(fixture["away_id"]), str(fixture["away_name"])),
				cell_link(score, &"series", {"series_id": int(fixture["id"])})])
		link_table(round_detail, PackedStringArray(["Home", "Away", "Series score"]), rows)
	selector.item_selected.connect(show_round)
	selector.select(default_index if default_index >= 0 else selector.item_count - 1)
	show_round.call(selector.selected)
