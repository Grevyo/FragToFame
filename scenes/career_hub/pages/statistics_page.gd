class_name CareerStatisticsPage
extends CareerPage


func get_page_title() -> String:
	return "Statistics"


func build_page() -> void:
	add_sample_notice("Development sample data — no match events have been recorded yet.")
	var s := DevSampleData.statistics_summary()

	var tiles := GridContainer.new()
	tiles.columns = 4
	tiles.add_theme_constant_override(&"h_separation", 18)
	tiles.add_theme_constant_override(&"v_separation", 18)
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tiles)
	UIFactory.stat_tile(tiles, "Rating", "%.2f" % s["rating"])
	UIFactory.stat_tile(tiles, "K/D", "%.2f" % s["kd"])
	UIFactory.stat_tile(tiles, "ADR", "%.1f" % s["adr"])
	UIFactory.stat_tile(tiles, "KAST", "%.1f%%" % s["kast"])
	UIFactory.stat_tile(tiles, "Headshot %", "%.1f%%" % s["hs_pct"])
	UIFactory.stat_tile(tiles, "Opening duels won", "%.1f%%" % s["opening_win_pct"])
	UIFactory.stat_tile(tiles, "Matches", str(s["matches"]))
	UIFactory.stat_tile(tiles, "Rounds", str(s["rounds"]))

	var card := UIFactory.card(self, "Recent matches")
	var rows: Array[PackedStringArray] = []
	for m: Dictionary in DevSampleData.recent_matches():
		rows.append(PackedStringArray([
			m["date"], m["opponent"], m["map"], m["score"], m["kda"],
			"%.1f" % m["adr"], "%.2f" % m["rating"],
		]))
	UIFactory.table(card, PackedStringArray(["Date", "Opponent", "Map", "Score", "K-D-A", "ADR", "Rating"]), rows)
