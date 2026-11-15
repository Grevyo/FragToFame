class_name CareerStatisticsPage
extends CareerPage


func get_page_title() -> String:
	return "Statistics"


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	var player_id := career().human_player_id
	var counts := repo.performance_totals(player_id)
	if int(counts.get("matches", 0)) == 0:
		var empty := UIFactory.card(self, "No recorded match statistics")
		empty.add_child(UIFactory.label("Complete an amateur fixture from Career Home to record your first match.",
			&"MutedLabel", true))
		return

	var tiles := GridContainer.new()
	tiles.columns = 4
	tiles.add_theme_constant_override(&"h_separation", 18)
	tiles.add_theme_constant_override(&"v_separation", 18)
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tiles)
	UIFactory.stat_tile(tiles, "F2F rating", "%.2f" % MatchStatistics.rating(counts))
	UIFactory.stat_tile(tiles, "K/D", "—" if int(counts["deaths"]) == 0 else "%.2f" % _ratio(counts, "kills", "deaths"))
	UIFactory.stat_tile(tiles, "ADR", "%.1f" % _ratio(counts, "damage", "rounds"))
	UIFactory.stat_tile(tiles, "KAST", "%.1f%%" % (100.0 * _ratio(counts, "kast_rounds", "rounds")))
	UIFactory.stat_tile(tiles, "Accuracy", "%.1f%%" % (100.0 * _ratio(counts, "hits", "shots")))
	UIFactory.stat_tile(tiles, "First-shot accuracy", "%.1f%%" % (100.0 * _ratio(counts, "first_hits", "first_shots")))
	UIFactory.stat_tile(tiles, "Headshot kills", "%.1f%%" % (100.0 * _ratio(counts, "headshot_kills", "kills")))
	UIFactory.stat_tile(tiles, "Recorded matches", "%d · %d rounds" % [counts["matches"], counts["rounds"]])

	var impact := UIFactory.card(self, "Round impact")
	UIFactory.key_value_grid(impact, [
		PackedStringArray(["Opening duels won / lost", "%d / %d" % [counts["opening_kills"], counts["opening_deaths"]]]),
		PackedStringArray(["Trade kills / deaths traded", "%d / %d" % [counts["trade_kills"], counts["traded_deaths"]]]),
		PackedStringArray(["Clutches won / attempted", "%d / %d" % [counts["clutch_wins"], counts["clutch_attempts"]]]),
		PackedStringArray(["Bombs planted / defused", "%d / %d" % [counts["plants"], counts["defuses"]]]),
	])

	var history := repo.recent_performance(player_id)
	_build_history(history)
	if not history.is_empty():
		_build_latest_weapons(history[0]["counts"] as Dictionary)


func _build_history(history: Array[Dictionary]) -> void:
	var card := UIFactory.card(self, "Recent matches")
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in history:
		var fixture := entry["fixture"] as CareerFixture
		var counts := entry["counts"] as Dictionary
		rows.append(PackedStringArray([
			GameDate.format(fixture.scheduled_day), fixture.setup.away_team_name,
			"%d – %d" % [fixture.result.home_score, fixture.result.away_score],
			"%d-%d-%d" % [counts["kills"], counts["deaths"], counts["assists"]],
			"%.1f" % _ratio(counts, "damage", "rounds"), "%.2f" % float(entry["rating"]),
		]))
	UIFactory.table(card, PackedStringArray(["Date", "Opponent", "Score", "K-D-A", "ADR", "Rating"]), rows)


func _build_latest_weapons(counts: Dictionary) -> void:
	var weapons := counts["weapons"] as Dictionary
	if weapons.is_empty():
		return
	var card := UIFactory.card(self, "Last match by weapon")
	var rows: Array[PackedStringArray] = []
	for id: String in weapons:
		var stats := weapons[id] as Dictionary
		var definition := WeaponCatalog.get_definition(StringName(id))
		var label := definition.display_name if definition != null else id
		rows.append(PackedStringArray([label, str(stats["shots"]), str(stats["hits"]), str(stats["kills"])]))
	UIFactory.table(card, PackedStringArray(["Weapon", "Shots", "Hits", "Kills"]), rows)


static func _ratio(counts: Dictionary, numerator: String, denominator: String) -> float:
	return MatchStatistics.ratio(float(counts[numerator]), float(counts[denominator]))
