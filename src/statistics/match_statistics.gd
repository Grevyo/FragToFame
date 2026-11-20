class_name MatchStatistics
extends RefCounted
## Reduces recorded round events into counters. The reducer has no scene or database dependencies.

const EVENT_VERSION: int = 1
const RATING_VERSION: int = 1
const ASSIST_DAMAGE: int = 40
const TRADE_SECONDS: float = 5.0
const COUNTERS: Array[String] = [
	"rounds", "kills", "deaths", "assists", "kast_rounds", "damage", "shots", "hits",
	"headshot_kills", "first_shots", "first_hits", "opening_kills", "opening_deaths",
	"trade_kills", "traded_deaths", "clutch_attempts", "clutch_wins", "plants", "defuses",
	"utility_thrown", "utility_damage", "enemies_flashed", "flash_assists",
]

var _totals: Dictionary[String, Dictionary] = {}
var _teams: Dictionary[String, int] = {}
var _alive: Dictionary[String, bool] = {}
var _contributed: Dictionary[String, bool] = {}
var _damage_to: Dictionary[String, Dictionary] = {}
var _round_shots: Dictionary[String, int] = {}
var _kills: Array[Dictionary] = []
## Victim -> {"by": thrower, "until": match time the blindness ends} for this round's flashes.
var _flashed: Dictionary[String, Dictionary] = {}
var _clutch_players: Dictionary[int, String] = {}
var _clutch_sizes: Dictionary[int, int] = {}
var _round: int
var _live: bool
var _opening_recorded: bool
var _score: Array[int] = [0, 0]


static func calculate(result: MatchResult) -> Dictionary[String, Dictionary]:
	var reducer := MatchStatistics.new()
	return reducer._reduce(result)


static func empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for key: String in COUNTERS:
		counts[key] = 0
	return counts


static func ratio(numerator: float, denominator: float) -> float:
	return numerator / denominator if denominator > 0.0 else 0.0


## F2F rating v1. Weights use rates per round so short and long matches are comparable.
static func rating(counts: Dictionary) -> float:
	var rounds := int(counts["rounds"])
	if rounds <= 0:
		return 0.0
	var kills := ratio(int(counts["kills"]), rounds)
	var damage := ratio(int(counts["damage"]), rounds)
	var kast := ratio(int(counts["kast_rounds"]), rounds)
	var survival := 1.0 - ratio(int(counts["deaths"]), rounds)
	return snappedf(clampf(0.44 * kills / 0.70 + 0.27 * damage / 75.0
		+ 0.19 * kast / 0.70 + 0.10 * survival / 0.35, 0.0, 3.0), 0.001)


func _reduce(result: MatchResult) -> Dictionary[String, Dictionary]:
	if result == null or result.events.size() < 2:
		return {}
	var start := result.events.front() as Dictionary
	var finish := result.events.back() as Dictionary
	if start.get("type") != "match_started" or start.get("fixture_id") != result.fixture_id \
			or finish.get("type") != "match_ended" or not start.get("lineup") is Dictionary:
		return {}
	for player: Variant in start["lineup"]:
		var team := int(start["lineup"][player])
		if team not in [0, 1] or str(player).is_empty():
			return {}
		_teams[str(player)] = team
		var counts := empty_counts()
		counts["weapons"] = {}
		counts["clutches"] = {}
		_totals[str(player)] = counts
	if _teams.is_empty():
		return {}

	for event: Dictionary in result.events:
		var type := str(event.get("type", ""))
		var round_number := int(event.get("round", -1))
		match type:
			"round_started":
				if _live or round_number != _round + 1:
					return {}
				_start_round(round_number)
			"round_ended":
				var winner := int(event.get("winner_team", -1))
				if not _live or round_number != _round or winner not in [0, 1]:
					return {}
				_end_round(winner)
			_:
				if _live and round_number == _round:
					_apply_event(type, event)

	if _live or _round != result.rounds_played or _score != [result.home_score, result.away_score]:
		return {}
	return _totals


func _start_round(number: int) -> void:
	_round = number
	_live = true
	_opening_recorded = false
	_contributed.clear()
	_damage_to.clear()
	_round_shots.clear()
	_kills.clear()
	_flashed.clear()
	_clutch_players.clear()
	_clutch_sizes.clear()
	for player: String in _teams:
		_alive[player] = true


func _end_round(winner: int) -> void:
	_live = false
	_score[winner] += 1
	for player: String in _teams:
		_add(player, "rounds")
		if _alive[player] or _contributed.has(player):
			_add(player, "kast_rounds")
	var clutch: String = _clutch_players.get(winner, "")
	if not clutch.is_empty() and _alive[clutch]:
		_add(clutch, "clutch_wins")
		_clutch(_counts(clutch), _clutch_sizes[winner])["wins"] += 1


func _apply_event(type: String, event: Dictionary) -> void:
	var actor := str(event.get("player", ""))
	match type:
		"shot":
			if _alive.get(actor, false):
				_add(actor, "shots")
				_weapon(actor, str(event.get("weapon", "")))["shots"] += 1
				_round_shots[actor] = _round_shots.get(actor, 0) + 1
				if _round_shots[actor] == 1:
					_add(actor, "first_shots")
		"damage":
			_record_damage(actor, event)
		"utility_thrown":
			if _alive.get(actor, false):
				_add(actor, "utility_thrown")
		"flashed":
			_record_flash(actor, event)
		"kill":
			_record_kill(event)
		"bomb_planted", "bomb_defused":
			if _teams.has(actor):
				_add(actor, "plants" if type == "bomb_planted" else "defuses")


func _record_damage(actor: String, event: Dictionary) -> void:
	var victim := str(event.get("victim", ""))
	var hp := int(event.get("hp", 0))
	if not _alive.get(victim, false) or not _alive.get(actor, false) \
			or _teams[actor] == _teams[victim] or hp <= 0:
		return
	_add(actor, "damage", hp)
	if bool(event.get("utility", false)):
		_add(actor, "utility_damage", hp)
	elif _round_shots.get(actor, 0) > 0:
		_add(actor, "hits")
		_weapon(actor, str(event.get("weapon", "")))["hits"] += 1
		if _round_shots[actor] == 1:
			_add(actor, "first_hits")
	if not _damage_to.has(victim):
		_damage_to[victim] = {}
	var contributors := _damage_to[victim]
	contributors[actor] = int(contributors.get(actor, 0)) + hp


func _record_kill(event: Dictionary) -> void:
	var victim := str(event.get("victim", ""))
	var killer := str(event.get("killer", ""))
	if not _alive.get(victim, false):
		return
	_alive[victim] = false
	_add(victim, "deaths")
	if _teams.has(killer) and _teams[killer] != _teams[victim]:
		_add(killer, "kills")
		_contributed[killer] = true
		_weapon(killer, str(event.get("weapon", "")))["kills"] += 1
		if bool(event.get("headshot", false)):
			_add(killer, "headshot_kills")
		if not _opening_recorded:
			_opening_recorded = true
			_add(killer, "opening_kills")
			_add(victim, "opening_deaths")
		_credit_assist(killer, victim)
		_credit_flash_assist(killer, victim, float(event.get("t", 0.0)))
		_credit_trade(killer, victim, float(event.get("t", 0.0)))
		_kills.append({"killer": killer, "victim": victim, "t": event.get("t", 0.0), "traded": false})
	_track_clutches()


func _credit_assist(killer: String, victim: String) -> void:
	var contributors: Dictionary = _damage_to.get(victim, {})
	var best := ASSIST_DAMAGE - 1
	var assister := ""
	for player: String in contributors:
		var amount := int(contributors[player])
		if player != killer and (amount > best or (amount == best and not assister.is_empty() and player < assister)):
			best = amount
			assister = player
	if not assister.is_empty():
		_add(assister, "assists")
		_contributed[assister] = true


## Blinding an enemy counts when the flash came from an enemy of the victim and they were alive.
func _record_flash(actor: String, event: Dictionary) -> void:
	var victim := str(event.get("victim", ""))
	if not _teams.has(actor) or not _alive.get(victim, false) or _teams[actor] == _teams.get(victim, -1):
		return
	_add(actor, "enemies_flashed")
	var until := float(event.get("t", 0.0)) + float(event.get("seconds", 0.0))
	var prior: Dictionary = _flashed.get(victim, {})
	if prior.is_empty() or float(prior["until"]) < until:
		_flashed[victim] = {"by": actor, "until": until}


## A teammate of the killer who blinded the victim, still blind at the kill, gets a flash
## assist (and KAST credit for the round).
func _credit_flash_assist(killer: String, victim: String, time: float) -> void:
	var flash: Dictionary = _flashed.get(victim, {})
	if flash.is_empty() or time > float(flash["until"]):
		return
	var by := str(flash["by"])
	if by != killer and _teams.get(by, -1) == _teams[killer]:
		_add(by, "flash_assists")
		_contributed[by] = true


func _credit_trade(killer: String, victim: String, time: float) -> void:
	var trade := false
	for prior: Dictionary in _kills:
		var teammate := str(prior["victim"])
		if not bool(prior["traded"]) and prior["killer"] == victim and _teams[teammate] == _teams[killer] \
				and time - float(prior["t"]) <= TRADE_SECONDS:
			prior["traded"] = true
			_add(teammate, "traded_deaths")
			_contributed[teammate] = true
			trade = true
	if trade:
		_add(killer, "trade_kills")


func _track_clutches() -> void:
	var survivors := [[], []]
	for player: String in _teams:
		if _alive[player]:
			survivors[_teams[player]].append(player)
	for team: int in 2:
		var opponents: int = survivors[1 - team].size()
		if not _clutch_players.has(team) and survivors[team].size() == 1 and opponents > 0:
			var player: String = survivors[team][0]
			_clutch_players[team] = player
			_clutch_sizes[team] = opponents
			_add(player, "clutch_attempts")
			_clutch(_counts(player), opponents)["attempts"] += 1


func _add(player: String, counter: String, amount: int = 1) -> void:
	var counts := _counts(player)
	counts[counter] = int(counts[counter]) + amount


func _counts(player: String) -> Dictionary:
	return _totals[player]


func _weapon(player: String, id: String) -> Dictionary:
	var weapons: Dictionary = _counts(player)["weapons"]
	if not weapons.has(id):
		weapons[id] = {"shots": 0, "hits": 0, "kills": 0}
	return weapons[id]


static func _clutch(counts: Dictionary, opponent_count: int) -> Dictionary:
	var sizes: Dictionary = counts["clutches"]
	var key := str(opponent_count)
	if not sizes.has(key):
		sizes[key] = {"attempts": 0, "wins": 0}
	return sizes[key]
