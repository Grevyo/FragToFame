extends SceneTree
## Runs the match engine's balance harness ([MatchBalance]) and prints the report against its
## targets. Exits 1 when a metric is off target.
##   <godot> --headless --path <project> --script res://tools/balance_harness.gd -- --maps=2000 --seed=1
## Options: --maps=N (default 1000), --seed=N (default 1), --map=<map id> (repeatable; default
## every official map with a simulation graph), --duel (the duel chain, maps without a graph).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var count := 1000
	var seed_value := 1
	var maps: Array[String] = []
	var duel := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--maps="):
			count = int(argument.substr(7))
		elif argument.begins_with("--seed="):
			seed_value = int(argument.substr(7))
		elif argument.begins_with("--map="):
			maps.append(argument.substr(6))
		elif argument == "--duel":
			duel = true
	if duel:
		maps = [""]
	elif maps.is_empty():
		for map_id: String in OfficialMaps.ids():
			if SimMap.for_map(map_id) != null:
				maps.append(map_id)
	var started := Time.get_ticks_msec()
	var report := MatchBalance.run(maps, count, seed_value)
	print("Balance harness: %d maps in %.1f s (seed %d)" % [count, (Time.get_ticks_msec() - started) / 1000.0, seed_value])
	for key: String in MatchBalance.TARGETS:
		var band: Vector2 = MatchBalance.TARGETS[key]
		var value := float(report.get(key, NAN))
		var mark := "ok " if value >= band.x and value <= band.y else "OFF"
		print("  %s %-24s %8.3f   (%.2f–%.2f)" % [mark, key, value, band.x, band.y])
	print("  mean rounds per map: %.2f" % float(report["mean_rounds"]))
	print("Attack round share by map:")
	var sides := report["per_map"] as Dictionary
	var endings := report["map_endings"] as Dictionary
	for map_id: String in sides:
		var how: Dictionary = endings.get(map_id if map_id != "duel chain" else "", {})
		var total := 0
		for key: String in how:
			total += int(how[key])
		var parts: PackedStringArray = []
		for key: String in ["eliminated", "detonated", "defused", "time"]:
			parts.append("%s %.0f%%" % [key, 100.0 * int(how.get(key, 0)) / maxf(total, 1.0)])
		print("  %-24s %.3f   %s" % [map_id, float(sides[map_id]), "  ".join(parts)])
	print("By role (per round):")
	var roles := report["by_role"] as Dictionary
	for role: String in roles:
		var line := roles[role] as Dictionary
		print("  %-8s kpr %.2f  adr %5.1f  rating %.2f  openings %.3f  utility dmg %4.1f" % [role, float(line["kpr"]),
			float(line["adr"]), float(line["rating"]), float(line["opening"]), float(line["utility_damage"])])
	var misses := MatchBalance.misses(report)
	print("All metrics on target." if misses.is_empty() else "Off target:\n  " + "\n  ".join(misses))
	quit(0 if misses.is_empty() else 1)
