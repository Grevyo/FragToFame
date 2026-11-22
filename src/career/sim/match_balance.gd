class_name MatchBalance
extends RefCounted
## Balance harness for the match engine (Milestone 21 stage H): plays many headless maps between
## sample teams and checks the results against [constant TARGETS] (side balance, round and score
## distributions, rating spread, upsets, stat ranges by role). Pure career-layer code; run it from
## [code]tools/balance_harness.gd[/code] for thousands of maps, or small from the tests.
##
## Sample teams are built here, not drawn from a save: five players with the five match roles,
## abilities spread around a team level and leaning on each role's focus, a few traits. The level
## gap between the two teams is drawn so even, close and lopsided matches all appear.

const ROLES: Array[StringName] = [&"igl", &"sniper", &"entry", &"lurker", &"support"]
## Ability spread within a team (points either side of the player's level).
const ABILITY_SPREAD: float = 8.0
## Spread of a player's level around the team's.
const PLAYER_SPREAD: float = 5.0
## Points a role's focus abilities sit above the player's level.
const FOCUS_POINTS: float = 6.0
## Team levels are drawn from this range; the gap to the opponent from [constant MAX_GAP].
const LEVEL_RANGE: Vector2 = Vector2(40.0, 85.0)
const MAX_GAP: float = 20.0
## A level gap at least this big makes the weaker team's win an upset.
const UPSET_GAP: float = 8.0
const TRAITS: Array[StringName] = [&"tr_calm", &"tr_hot_headed", &"tr_clutch_player", &"tr_aggressive", &"tr_team_player",
	&"tr_lone_wolf", &"tr_risk_taker", &"tr_cautious", &"tr_pressure_prone", &"tr_steady", &"tr_streaky", &"tr_utility_expert"]

## Targets: metric -> [low, high]. Fractions are 0..1; per-round values per player.
## worst_map_side_gap: the furthest any map's attack round share is from half. blowout_share
## counts only evenly matched teams (level gap under 2).
const TARGETS: Dictionary[String, Vector2] = {
	"attack_round_share": Vector2(0.44, 0.56),
	"worst_map_side_gap": Vector2(0.0, 0.08),
	"pistol_attack_share": Vector2(0.35, 0.65),
	"rounds_share": Vector2(0.75, 0.95),
	"overtime_share": Vector2(0.03, 0.2),
	"close_share": Vector2(0.2, 0.6),
	"blowout_share": Vector2(0.03, 0.35),
	"even_favourite_share": Vector2(0.4, 0.65),
	"upset_share": Vector2(0.05, 0.3),
	"rating_mean": Vector2(0.95, 1.05),
	"rating_sd": Vector2(0.15, 0.45),
	"rating_low": Vector2(0.0, 0.7),
	"rating_high": Vector2(1.4, 3.0),
	"kills_per_round": Vector2(0.55, 0.8),
	"adr": Vector2(60.0, 90.0),
	"headshot_share": Vector2(0.25, 0.65),
	"flash_assist_share": Vector2(0.04, 0.15),
	"traded_death_share": Vector2(0.15, 0.35),
	"eliminated_share": Vector2(0.45, 0.85),
	"bomb_share": Vector2(0.1, 0.45),
	"time_share": Vector2(0.0, 0.15),
	"entry_opening_rate": Vector2(0.12, 0.35),
	"support_utility_damage": Vector2(2.0, 20.0),
	"sniper_kpr_vs_mean": Vector2(0.95, 1.35),
}


## Plays [param count] maps from [param seed_value], rotating through [param map_ids] (an empty
## id plays the duel chain). Returns the report: every metric in [constant TARGETS] plus "maps",
## "per_map" ({map_id: attack round share}) and "by_role" ({role: {kpr, adr, rating, opening,
## utility_damage}}).
static func run(map_ids: Array[String], count: int, seed_value: int, rounds_per_half: int = 8) -> Dictionary:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	var tally := _Tally.new()
	for i: int in count:
		var map_id := map_ids[i % map_ids.size()] if not map_ids.is_empty() else ""
		var level := dice.randf_range(LEVEL_RANGE.x, LEVEL_RANGE.y)
		var gap := dice.randf_range(-MAX_GAP, MAX_GAP) * dice.randf()
		var home := sample_team(dice, "H%d" % i, level)
		var away := sample_team(dice, "A%d" % i, clampf(level + gap, 20.0, 95.0))
		var engine_dice := RandomNumberGenerator.new()
		engine_dice.seed = dice.randi()
		var engine := MatchEngine.new(engine_dice, rounds_per_half)
		engine.sim_map = SimMap.for_map(map_id) if not map_id.is_empty() else null
		tally.add(map_id, engine.play_map(home, away), [home, away], gap, rounds_per_half)
	return tally.report()


## Metrics of [param report] outside [constant TARGETS], as readable lines (empty: all on target).
static func misses(report: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for key: String in TARGETS:
		var band := TARGETS[key]
		var value := float(report.get(key, NAN))
		if is_nan(value) or value < band.x or value > band.y:
			lines.append("%s = %.3f (target %.2f–%.2f)" % [key, value, band.x, band.y])
	return lines


## A sample team around [param level] with the five match roles.
static func sample_team(dice: RandomNumberGenerator, id: String, level: float) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = id
	team.name = id
	team.form = dice.randi_range(-2, 2)
	team.chemistry = dice.randf_range(-2.0, 2.0)
	for index: int in ROLES.size():
		var player := MatchEngine.SimPlayer.new()
		player.id = "%s_%d" % [id, index]
		player.name = player.id
		player.role = ROLES[index]
		var own := level + dice.randfn(0.0, PLAYER_SPREAD)
		var focus: Array = CareerCatalog.ROLE_FOCUS.get(player.role, [])
		for key: StringName in CareerCatalog.ABILITIES:
			var value := own + dice.randf_range(-ABILITY_SPREAD, ABILITY_SPREAD) + (FOCUS_POINTS if focus.has(key) else 0.0)
			player.skills[key] = clampi(roundi(value), 1, 100)
		if dice.randf() < 0.5:
			player.traits[TRAITS[dice.randi() % TRAITS.size()]] = dice.randi_range(1, 3)
		player.morale = dice.randf_range(-1.0, 1.0)
		player.experience = clampf((level - 40.0) / 50.0 + dice.randf_range(-0.2, 0.2), 0.0, 1.0)
		team.players.append(player)
	return team


## Running sums over the maps played.
class _Tally extends RefCounted:
	var maps := 0
	var half := 8
	var rounds := 0
	var attack_wins := 0
	var pistols := 0
	var pistol_attack_wins := 0
	var overtime := 0
	var close := 0
	var blowout := 0
	var even_maps := 0
	var even_favourite_wins := 0
	var lopsided := 0
	var upsets := 0
	var endings: Dictionary[String, int] = {}
	var per_map: Dictionary[String, Vector2i] = {}
	## map -> how rounds ended there ({how: count}).
	var map_endings: Dictionary[String, Dictionary] = {}
	var ratings: Array[float] = []
	var kills := 0
	var damage := 0.0
	var headshots := 0
	var flash_assists := 0
	var traded := 0
	var deaths := 0
	var player_rounds := 0
	var by_role: Dictionary[StringName, Dictionary] = {}

	func add(map_id: String, played: Dictionary, teams: Array[MatchEngine.SimTeam], gap: float, rounds_per_half: int) -> void:
		maps += 1
		half = rounds_per_half
		var score: Vector2i = played["score"]
		var total := score.x + score.y
		rounds += total
		if total > half * 2:
			overtime += 1
		var margin := absi(score.x - score.y)
		if margin <= 3:
			close += 1
		if margin >= half - 2 and absf(gap) < 2.0:
			blowout += 1
		# Gap is away minus home: positive means team 1 is stronger.
		var stronger_won := (score.y > score.x) == (gap > 0.0)
		if absf(gap) < 2.0:
			even_maps += 1
			if stronger_won:
				even_favourite_wins += 1
		elif absf(gap) >= UPSET_GAP:
			lopsided += 1
			if not stronger_won:
				upsets += 1
		var side := per_map.get(map_id, Vector2i.ZERO) as Vector2i
		for index: int in (played["rounds"] as Array).size():
			var round_data := (played["rounds"] as Array)[index] as Dictionary
			var attack := int(round_data.get("attackers", 0))
			var won := int(round_data["winner"]) == attack
			attack_wins += int(won)
			side += Vector2i(int(won), 1)
			if index == 0 or index == half:
				pistols += 1
				pistol_attack_wins += int(won)
			var how := str(round_data.get("how", ""))
			endings[how] = endings.get(how, 0) + 1
			var at_map: Dictionary = map_endings.get(map_id, {})
			at_map[how] = int(at_map.get(how, 0)) + 1
			map_endings[map_id] = at_map
		per_map[map_id] = side
		var stats := played["players"] as Dictionary
		for team: MatchEngine.SimTeam in teams:
			for player: MatchEngine.SimPlayer in team.players:
				var line: Dictionary = stats.get(player.id, {})
				var played_rounds := int(line.get("rounds", total))
				ratings.append(float(line.get("rating", 0.0)))
				kills += int(line.get("kills", 0))
				damage += float(line.get("damage", 0))
				headshots += int(line.get("headshot_kills", 0))
				flash_assists += int(line.get("flash_assists", 0))
				traded += int(line.get("traded_deaths", 0))
				deaths += int(line.get("deaths", 0))
				player_rounds += played_rounds
				var role: Dictionary = by_role.get(player.role, {"rounds": 0, "kills": 0, "damage": 0.0, "rating": 0.0, "lines": 0,
					"opening": 0, "utility_damage": 0.0})
				role["rounds"] = int(role["rounds"]) + played_rounds
				role["kills"] = int(role["kills"]) + int(line.get("kills", 0))
				role["damage"] = float(role["damage"]) + float(line.get("damage", 0))
				role["rating"] = float(role["rating"]) + float(line.get("rating", 0.0))
				role["lines"] = int(role["lines"]) + 1
				role["opening"] = int(role["opening"]) + int(line.get("opening_kills", 0))
				role["utility_damage"] = float(role["utility_damage"]) + float(line.get("utility_damage", 0))
				by_role[player.role] = role

	func report() -> Dictionary:
		var mean := 0.0
		for value: float in ratings:
			mean += value
		mean /= maxf(ratings.size(), 1.0)
		var variance := 0.0
		for value: float in ratings:
			variance += (value - mean) * (value - mean)
		var sorted := ratings.duplicate()
		sorted.sort()
		var all_rounds := maxf(rounds, 1.0)
		var kpr := kills / maxf(player_rounds, 1.0)
		var roles: Dictionary = {}
		for role: StringName in by_role:
			var line := by_role[role]
			var role_rounds := maxf(float(line["rounds"]), 1.0)
			roles[str(role)] = {"kpr": float(line["kills"]) / role_rounds, "adr": float(line["damage"]) / role_rounds,
				"rating": float(line["rating"]) / maxf(float(line["lines"]), 1.0),
				"opening": float(line["opening"]) / role_rounds, "utility_damage": float(line["utility_damage"]) / role_rounds}
		var sides: Dictionary = {}
		for map_id: String in per_map:
			sides[map_id if not map_id.is_empty() else "duel chain"] = float(per_map[map_id].x) / maxf(per_map[map_id].y, 1.0)
		var worst_gap := 0.0
		for map_id: String in sides:
			worst_gap = maxf(worst_gap, absf(float(sides[map_id]) - 0.5))
		var bombs: int = endings.get("defused", 0) + endings.get("detonated", 0)
		return {
			"maps": maps,
			"attack_round_share": attack_wins / all_rounds,
			"worst_map_side_gap": worst_gap,
			"pistol_attack_share": pistol_attack_wins / maxf(pistols, 1.0),
			"mean_rounds": rounds / maxf(maps, 1.0),
			"rounds_share": rounds / maxf(maps, 1.0) / maxf(half * 2.0, 1.0),
			"overtime_share": overtime / maxf(maps, 1.0),
			"close_share": close / maxf(maps, 1.0),
			"blowout_share": blowout / maxf(even_maps, 1.0),
			"even_favourite_share": even_favourite_wins / maxf(even_maps, 1.0),
			"upset_share": upsets / maxf(lopsided, 1.0),
			"rating_mean": mean,
			"rating_sd": sqrt(variance / maxf(ratings.size(), 1.0)),
			"rating_low": float(sorted[int(sorted.size() * 0.02)]) if not sorted.is_empty() else 0.0,
			"rating_high": float(sorted[int(sorted.size() * 0.98)]) if not sorted.is_empty() else 0.0,
			"kills_per_round": kpr,
			"adr": damage / maxf(player_rounds, 1.0),
			"headshot_share": headshots / maxf(kills, 1.0),
			"flash_assist_share": flash_assists / maxf(kills, 1.0),
			"traded_death_share": traded / maxf(deaths, 1.0),
			"eliminated_share": endings.get("eliminated", 0) / all_rounds,
			"bomb_share": bombs / all_rounds,
			"time_share": endings.get("time", 0) / all_rounds,
			"entry_opening_rate": float(roles.get("entry", {}).get("opening", 0.0)),
			"support_utility_damage": float(roles.get("support", {}).get("utility_damage", 0.0)),
			"sniper_kpr_vs_mean": float(roles.get("sniper", {}).get("kpr", 0.0)) / maxf(kpr, 0.001),
			"per_map": sides,
			"map_endings": map_endings,
			"by_role": roles,
		}
