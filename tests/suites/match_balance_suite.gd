extends TestSuite
## Balance harness (Milestone 21 stage H): the harness runs, is repeatable and reports every
## target. The targets themselves are checked over thousands of maps by tools/balance_harness.gd;
## a small sample here only guards the broad shape.

const MAPS: int = 28


func suite_name() -> String:
	return "Match balance harness"


func run() -> void:
	SimMap.clear_cache()
	section("A small balance sample")
	var maps: Array[String] = []
	for map_id: String in OfficialMaps.ids():
		if SimMap.for_map(map_id) != null:
			maps.append(map_id)
	check(maps.size() >= 2, "official maps have simulation graphs (%d)" % maps.size())
	var report := MatchBalance.run(maps, MAPS, 4)
	check(int(report["maps"]) == MAPS, "plays the maps asked for")
	var missing: Array[String] = []
	for key: String in MatchBalance.TARGETS:
		if not report.has(key):
			missing.append(key)
	check(missing.is_empty(), "reports every target metric (%s)" % [missing])
	check(float(report["attack_round_share"]) > 0.38 and float(report["attack_round_share"]) < 0.62,
		"neither side wins most rounds overall (%.2f)" % float(report["attack_round_share"]))
	check(float(report["rating_mean"]) > 0.8 and float(report["rating_mean"]) < 1.2
		and float(report["kills_per_round"]) > 0.45 and float(report["kills_per_round"]) < 0.9,
		"ratings and kills sit around the usual (%.2f, %.2f kpr)" % [float(report["rating_mean"]), float(report["kills_per_round"])])
	check((report["by_role"] as Dictionary).size() == MatchBalance.ROLES.size(), "every role is measured")
	check((report["per_map"] as Dictionary).size() == maps.size(), "every map's side balance is measured")
	var again := MatchBalance.run(maps, 6, 9)
	check(JSON.stringify(again) == JSON.stringify(MatchBalance.run(maps, 6, 9)), "the same seed gives the same report")
	var off := MatchBalance.misses({"attack_round_share": 0.9})
	check(off.size() == MatchBalance.TARGETS.size() and off[0].begins_with("attack_round_share"),
		"metrics off target are listed with their bands")
