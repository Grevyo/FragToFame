class_name CareerSeriesPage
extends CareerPage
## A match report for one series ({series_id}): both teams, map scores, MVPs, moments and every
## player's line, all linked.

var series: Dictionary = {}


func get_page_title() -> String:
	if series.is_empty():
		return "Match report"
	return "%s vs %s" % [series["home_name"], series["away_name"]]


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	series = repo.series_detail(int(args.get("series_id", 0)))
	if series.is_empty():
		var missing := UIFactory.card(self, "Match report")
		missing.add_child(UIFactory.label("Open a series from a team's matches, a player's maps or the Calendar.", &"MutedLabel", true))
		return
	var played := series["home_maps"] != null
	var head := UIFactory.card(self, "%s · %s" % [series["competition_name"], GameDate.format(int(series["scheduled_day"]))])
	var row := UIFactory.hbox(16)
	head.add_child(row)
	row.add_child(team_link(str(series["home_id"]), str(series["home_name"])))
	row.add_child(UIFactory.label("%d – %d" % [int(series["home_maps"]), int(series["away_maps"])] if played else "vs",
		&"HeaderLabel"))
	row.add_child(team_link(str(series["away_id"]), str(series["away_name"])))
	head.add_child(UIFactory.label("BO%d · %s" % [int(series["best_of"]), CareerCatalog.tier_name(int(series["tier"]))],
		&"MutedLabel"))
	head.add_child(link("Competition", &"competitions", {"competition_id": str(series["competition_id"]),
		"year": int(series["season_year"])}))
	if not played:
		_preview(repo)
		return
	var maps := repo.sim_maps(int(series["id"]))
	if maps.is_empty():
		if not _own_maps(repo, head):
			head.add_child(UIFactory.label("This series was played before round-by-round reports were kept, or in the FPS.",
				&"MutedLabel", true))
		return
	var lines := repo.series_lines(int(series["id"]))
	for map: Dictionary in maps:
		_map_card(map, lines)


func _map_card(map: Dictionary, lines: Array[Dictionary]) -> void:
	var number := int(map["map_number"])
	var card := UIFactory.card(self, "Map %d · %s · %d – %d" % [number, map_name(str(map["map_id"])),
		int(map["home_rounds"]), int(map["away_rounds"])])
	var key := CareerRepository.league_timeline_key(int(series["id"]), number)
	if career().repo.has_sim_timeline(key):
		card.add_child(link("Round by round", &"match_view", {"key": key}))
	if map["mvp_id"] != null:
		var mvp := UIFactory.hbox(6)
		mvp.add_child(UIFactory.label("MVP", &"SectionLabel"))
		mvp.add_child(player_link(str(map["mvp_id"]), str(map["mvp_name"])))
		card.add_child(mvp)
	for side: Array in [[str(series["home_id"]), str(series["home_name"])], [str(series["away_id"]), str(series["away_name"])]]:
		var rows: Array[Array] = []
		for line: Dictionary in lines:
			if int(line["map_number"]) != number or str(line["organisation_id"]) != str(side[0]):
				continue
			rows.append([cell_player(str(line["player_id"]), str(line["nickname"])), str(int(line["kills"])),
				str(int(line["deaths"])), str(int(line["assists"])), "%.0f" % (float(line["damage"]) / maxf(float(line["rounds"]), 1.0)),
				"%d%%" % roundi(100.0 * float(line["kast_rounds"]) / maxf(float(line["rounds"]), 1.0)),
				str(int(line["opening_kills"])), str(int(line["clutch_wins"])), "%.2f" % float(line["rating"])])
		card.add_child(UIFactory.label(str(side[1]).to_upper(), &"SectionLabel"))
		link_table(card, PackedStringArray(["Player", "K", "D", "A", "ADR", "KAST", "Open", "Clutch", "Rating"]), rows)
	var moments := str(map["highlights"]).strip_edges()
	if not moments.is_empty():
		card.add_child(UIFactory.label("MOMENTS", &"SectionLabel"))
		for moment: String in moments.split("\n"):
			card.add_child(UIFactory.label("· " + moment, &"", true))


## The human's series: a link to the round-by-round story of each map that was simulated.
## Returns false when none was.
func _own_maps(repo: CareerRepository, parent: Control) -> bool:
	var found := false
	for booked: Dictionary in repo.series_maps(int(series["id"])):
		var key := CareerRepository.career_timeline_key(str(booked["career_fixture_id"]))
		if repo.has_sim_timeline(key):
			parent.add_child(link("Map %d · round by round" % int(booked["map_number"]), &"match_view", {"key": key}))
			found = true
	return found


## An upcoming series: both line-ups as the world sees them.
func _preview(repo: CareerRepository) -> void:
	var row := add_row()
	for side: Array in [[str(series["home_id"]), str(series["home_name"])], [str(series["away_id"]), str(series["away_name"])]]:
		var card := UIFactory.card(row, str(side[1]))
		var rows: Array[Array] = []
		for entry: Dictionary in repo.roster(str(side[0])):
			var contract := entry["contract"] as CareerRecords.ContractRecord
			if contract.is_substitute:
				continue
			var player := entry["player"] as CareerRecords.PlayerRecord
			rows.append([cell_player(player.id, player.nickname), CareerCatalog.role_name(contract.role), str(entry["rating"])])
		link_table(card, PackedStringArray(["Player", "Role", "Rating"]), rows)
