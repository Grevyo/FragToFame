class_name MatchTimeline
extends RefCounted
## A simulated map's round-by-round story for the match view, built from its event stream and the
## engine's round log. Pure career-layer data; stored as JSON with the map ([CareerRepository]).
##
## {"format_version", "map_id", "teams": [{id, name}, {id, name}] (engine order: team 0 started on
## attack), "players": [{id, name, team}], "score": [team 0, team 1], "scoreboard": [[kills,
## deaths, assists, adr, kast %, rating] per player], "rounds": [{"n", "winner", "how", "attack",
## "seconds", "score": [a, b], "buys": [team 0 call, team 1 call], "plans": [{kind, site}, {kind,
## site}] (planned maps only), "kills": [[seconds into the round, killer, victim, weapon id,
## headshot, flasher or -1]], "bomb": [[seconds, "planted"|"defused", player]], "eco": [[money,
## weapon id, armour 0|1|2 (2: helmet), grenades] per player] (planned maps only)}]}.
## Players are referred to by their index in "players".

const FORMAT_VERSION: int = 1


static func build(map_id: String, teams: Array[MatchEngine.SimTeam], events: Array[Dictionary], rounds_log: Array[Dictionary],
		stats: Dictionary) -> Dictionary:
	var players: Array[Dictionary] = []
	var index: Dictionary[String, int] = {}
	var board: Array[Array] = []
	for team_index: int in teams.size():
		for player: MatchEngine.SimPlayer in teams[team_index].players:
			index[player.id] = players.size()
			players.append({"id": player.id, "name": player.name, "team": team_index})
			var line: Dictionary = stats.get(player.id, {})
			var rounds := maxf(float(line.get("rounds", 0)), 1.0)
			board.append([int(line.get("kills", 0)), int(line.get("deaths", 0)), int(line.get("assists", 0)),
				roundi(float(line.get("damage", 0)) / rounds), roundi(100.0 * float(line.get("kast_rounds", 0)) / rounds),
				snappedf(float(line.get("rating", 0.0)), 0.01)])
	var rounds: Array[Dictionary] = []
	var score: Array[int] = [0, 0]
	var current: Dictionary = {}
	var started := 0.0
	var blind: Dictionary[int, Array] = {}
	for event: Dictionary in events:
		var t := float(event.get("t", 0.0))
		match str(event.get("type", "")):
			"round_started":
				started = t
				blind.clear()
				current = {"n": int(event["round"]), "attack": int(event.get("attack_team", 0)), "kills": [], "bomb": []}
			"flashed":
				var victim := int(index.get(str(event.get("victim", "")), -1))
				if victim >= 0:
					blind[victim] = [int(index.get(str(event.get("player", "")), -1)), t + float(event.get("seconds", 0.0))]
			"kill":
				var killer := int(index.get(str(event.get("killer", "")), -1))
				var victim := int(index.get(str(event.get("victim", "")), -1))
				var flasher := -1
				if blind.has(victim) and t <= float(blind[victim][1]) and int(blind[victim][0]) >= 0 \
						and int(players[int(blind[victim][0])]["team"]) != int(players[victim]["team"]):
					flasher = int(blind[victim][0])
				(current["kills"] as Array).append([snappedf(t - started, 0.1), killer, victim, str(event.get("weapon", "")),
					bool(event.get("headshot", false)), flasher])
			"bomb_planted", "bomb_defused":
				(current["bomb"] as Array).append([snappedf(t - started, 0.1), "planted" if event["type"] == "bomb_planted" else "defused",
					int(index.get(str(event.get("player", "")), -1))])
			"round_ended":
				var winner := int(event.get("winner_team", 0))
				score[winner] += 1
				current["winner"] = winner
				current["how"] = str(event.get("reason", ""))
				current["seconds"] = snappedf(t - started, 0.1)
				current["score"] = [score[0], score[1]]
				var logged: Dictionary = rounds_log[rounds.size()] if rounds.size() < rounds_log.size() else {}
				current["buys"] = logged.get("buys", [])
				if logged.has("eco"):
					current["eco"] = logged["eco"]
				if logged.has("plans"):
					var plans: Array = []
					for plan: Dictionary in logged["plans"] as Array:
						plans.append({"kind": str(plan.get("kind", "")), "site": str(plan.get("site", ""))})
					current["plans"] = plans
				rounds.append(current)
	var team_list: Array[Dictionary] = []
	for team: MatchEngine.SimTeam in teams:
		team_list.append({"id": team.id, "name": team.name})
	return {"format_version": FORMAT_VERSION, "map_id": map_id, "teams": team_list, "players": players, "score": score,
		"scoreboard": board, "rounds": rounds}


## Display name of a weapon or grenade id from a timeline.
static func weapon_name(id: String) -> String:
	if id.is_empty():
		return "—"
	if EquipmentCatalog.DATA.has(StringName(id)):
		return str(EquipmentCatalog.DATA[StringName(id)].get("name", id))
	return WeaponCatalog.recorded_name(StringName(id))


## How a round ended, for people.
static func how_text(how: String) -> String:
	return {"eliminated": "eliminated", "defused": "bomb defused", "detonated": "bomb exploded", "time": "time ran out"}.get(how, how)
