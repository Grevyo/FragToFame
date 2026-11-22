class_name CareerMatchViewPage
extends CareerPage
## Round by round ({key}): a simulated map's scoreboard, then every round with both leaders'
## plans, the buys, the kill feed (weapon, headshot, flash) and each player's kit and money.

var timeline: Dictionary = {}


func get_page_title() -> String:
	if timeline.is_empty():
		return "Round by round"
	var teams := timeline["teams"] as Array
	return "%s vs %s" % [teams[0]["name"], teams[1]["name"]]


func build_page() -> void:
	if add_no_career_notice():
		return
	timeline = career().repo.sim_timeline(str(args.get("key", "")))
	if timeline.is_empty():
		var missing := UIFactory.card(self, "Round by round")
		missing.add_child(UIFactory.label("No round-by-round story is kept for this map. World series keep theirs for "
			+ "%d days; your own simulated matches keep theirs for good." % CareerSeriesEngine.TIMELINE_DAYS, &"MutedLabel", true))
		return
	var teams := timeline["teams"] as Array
	var score := timeline["score"] as Array
	var head := UIFactory.card(self, map_name(str(timeline["map_id"])) if not str(timeline["map_id"]).is_empty() else "Simulated map")
	var row := UIFactory.hbox(16)
	head.add_child(row)
	row.add_child(team_link(str(teams[0]["id"]), str(teams[0]["name"])))
	row.add_child(UIFactory.label("%d – %d" % [int(score[0]), int(score[1])], &"HeaderLabel"))
	row.add_child(team_link(str(teams[1]["id"]), str(teams[1]["name"])))
	head.add_child(UIFactory.label("%s started on attack." % teams[0]["name"], &"MutedLabel"))
	_scoreboard()
	for round_data: Dictionary in timeline["rounds"] as Array:
		_round_card(round_data)


func _player_name(index: int) -> String:
	var players := timeline["players"] as Array
	return str(players[index]["name"]) if index >= 0 and index < players.size() else "—"


func _team_name(index: int) -> String:
	return str((timeline["teams"] as Array)[index]["name"])


func _scoreboard() -> void:
	var card := UIFactory.card(self, "Scoreboard")
	var players := timeline["players"] as Array
	var board := timeline["scoreboard"] as Array
	for team: int in 2:
		var rows: Array[Array] = []
		for i: int in players.size():
			if int(players[i]["team"]) != team:
				continue
			var line := board[i] as Array
			rows.append([cell_player(str(players[i]["id"]), str(players[i]["name"])), str(int(line[0])), str(int(line[1])),
				str(int(line[2])), str(int(line[3])), "%d%%" % int(line[4]), "%.2f" % float(line[5])])
		card.add_child(UIFactory.label(_team_name(team).to_upper(), &"SectionLabel"))
		link_table(card, PackedStringArray(["Player", "K", "D", "A", "ADR", "KAST", "Rating"]), rows)


func _round_card(round_data: Dictionary) -> void:
	var winner := int(round_data["winner"])
	var score := round_data["score"] as Array
	var card := UIFactory.card(self, "Round %d · %s · %s · %d – %d" % [int(round_data["n"]), _team_name(winner),
		MatchTimeline.how_text(str(round_data["how"])), int(score[0]), int(score[1])])
	var attack := int(round_data["attack"])
	var buys := round_data.get("buys", []) as Array
	var plans := round_data.get("plans", []) as Array
	var calls: PackedStringArray = []
	for team: int in 2:
		var call := "%s (%s)" % [_team_name(team), "attack" if team == attack else "defence"]
		if team < plans.size():
			var plan := plans[team] as Dictionary
			call += ": " + str(plan["kind"]).capitalize() + ("" if str(plan["site"]).is_empty() else " " + _site(str(plan["site"])))
		if team < buys.size():
			call += " · %s buy" % str(buys[team])
		calls.append(call)
	card.add_child(UIFactory.label(" | ".join(calls), &"MutedLabel", true))
	var feed: Array[Array] = []
	for kill: Array in round_data["kills"] as Array:
		var how: String = MatchTimeline.weapon_name(str(kill[3])) + (" · headshot" if bool(kill[4]) else "")
		if int(kill[5]) >= 0:
			how += " · flashed by " + _player_name(int(kill[5]))
		feed.append([_clock(float(kill[0])), cell_player(_id(int(kill[1])), _player_name(int(kill[1]))), how,
			cell_player(_id(int(kill[2])), _player_name(int(kill[2])))])
	for bomb: Array in round_data.get("bomb", []) as Array:
		feed.append([_clock(float(bomb[0])), cell_player(_id(int(bomb[2])), _player_name(int(bomb[2]))), "bomb " + str(bomb[1]), ""])
	feed.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	if not feed.is_empty():
		link_table(card, PackedStringArray(["Time", "Player", "How", "Victim"]), feed)
	var eco := round_data.get("eco", []) as Array
	if not eco.is_empty():
		var rows: Array[Array] = []
		for i: int in eco.size():
			var kit := eco[i] as Array
			rows.append([cell_player(_id(i), _player_name(i)), _team_name(int((timeline["players"] as Array)[i]["team"])),
				"$%d" % int(kit[0]), MatchTimeline.weapon_name(str(kit[1])), ["none", "kevlar", "kevlar + helmet"][int(kit[2])],
				str(int(kit[3]))])
		link_table(card, PackedStringArray(["Player", "Team", "Money", "Weapon", "Armour", "Grenades"]), rows)


func _id(index: int) -> String:
	var players := timeline["players"] as Array
	return str(players[index]["id"]) if index >= 0 and index < players.size() else ""


## Seconds into the round as m:ss (zero-padded so the feed sorts by time).
static func _clock(seconds: float) -> String:
	var whole := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]


func _site(site_id: String) -> String:
	return site_id.trim_prefix("site_").to_upper() if site_id.begins_with("site_") else site_id
