class_name MatchEngine
extends RefCounted
## Round-by-round simulation of one map between two career lineups. Pure: no database, nodes or
## FPS runtime. Used for every series nobody plays (and the development "simulate match").
##
## A map is played round by round under the competitive format (halves of [member max_rounds]
## rounds, sides swap, overtime in blocks of [constant OVERTIME_ROUNDS] per half). Each round:
## - both teams buy from their bank (pistol, eco, force or full buy) and get an equipment edge;
## - the attackers try to win fights and plant; the defenders hold, retake and defuse;
## - the round is a chain of duels between living players. Who takes the next fight depends on
##   role and personality (entries and aggressive players go first; patient players hold), and
##   who wins it depends on the two players' duel skill on the day, side, numbers, equipment,
##   post-plant position, the teams' tactics, utility and coordination, and momentum;
## - deaths can be traded, kills earn assists, a last player alive plays a clutch (some save
##   their weapon instead), and winning or losing moves the bank and the team's momentum.
##
## Every player has a form on the day: a random swing around their morale whose size comes from
## consistency and personality (streaky players swing more, steady ones less). Traits nudge the
## numbers (flick and spray specialists duel better, clutch players rise in 1vX, players who feel
## the pressure fade in decisive rounds, hot heads tilt during losing streaks, calm players don't).
##
## On a map with a baked [SimMap] ([member sim_map]), each team's leader ([RoundPlanner]) calls
## every round's plan: the attack's strategy and target site, the defence's setup, each player's
## job and place. Plans are logged with the round and the leaders learn from what worked.
##
## People over a match (all in [method form_points], so both the planned rounds and the duel chain
## feel them; each comes from what happened and who the player is, never a flat bonus):
## - tilt: rounds in a row dying without a kill wear on a player, more for a hot head and for low
##   composure, hardly at all for a calm one; a kill clears it (the team's losing streak tilts hot
##   heads on top);
## - nerves: big rounds (match point, overtime, a map that decides the series) cost players with
##   low composure, less the more maps they have played ([member SimPlayer.experience]);
## - fatigue: rounds played across a series wear players down, less for consistent ones;
## - map familiarity: a team that has played the map a lot lately knows its positions and timings
##   ([member SimTeam.familiarity]); a player who has played well (or badly) on it before carries
##   that in ([member SimPlayer.map_comfort]). [CareerSeriesEngine] reads both from the history.
## Confidence comes from play time, training and the manager's tactics (Milestone 20).
##
## Every map logs the FPS runtime's event stream ([member events]: match_started, round_started,
## shot, damage, utility_thrown, flashed, kill, bomb_planted, bomb_defused, round_ended,
## match_ended) and every player's statistics are built from it by [MatchStatistics], the same
## reducer a played match goes through, so simulated and played statistics agree by construction.
##
## Career attributes are used here only, on the career layer; they never reach the FPS runtime.

const OVERTIME_ROUNDS: int = 3
## Ability points that turn into a 73% duel-win chance (logistic scale).
const DUEL_SCALE: float = 40.0
## Duel bonuses, in ability points.
const DEFENDER_EDGE: float = 1.5
const POST_PLANT_EDGE: float = 2.5
const MAN_ADVANTAGE: float = 12.0
const TRADE_EDGE: float = 4.0
## How well a team executes one round (a read, a mistake, a timing): spread in ability points.
const ROUND_EXECUTION: float = 6.0
## How the whole team plays on the day (one map), in ability points.
const MAP_FORM: float = 3.0
const MOMENTUM_STEP: float = 0.5
const MOMENTUM_CAP: float = 1.5
const TILT_PENALTY: float = 5.0
## Clutch players (or those who feel the pressure) per trait point when last alive.
const CLUTCH_TRAIT: float = 6.0
## Day form leans this many points per point of morale (−20..20).
const MORALE_FORM: float = 0.5
const TILT_STREAK: int = 3
## Equipment edge by buy (ability points), and what each buy costs per player.
const BUY_EDGE: Dictionary[StringName, float] = {&"pistol": 0.0, &"eco": -5.0, &"force": -2.0, &"full": 0.0}
const BUY_COST: Dictionary[StringName, int] = {&"pistol": 0, &"eco": 300, &"force": 2400, &"full": 4400}
const FULL_BUY_MONEY: int = 4000
const FORCE_MONEY: int = 2300
## Economy (per player).
const START_MONEY: int = 800
const OVERTIME_MONEY: int = 10000
const MAX_MONEY: int = 16000
const WIN_REWARD: int = 3250
const LOSS_BONUS: Array[int] = [1400, 1900, 2400, 2900, 3400]
const KILL_REWARD: int = 300
const PLANT_REWARD: int = 300
## Rounds: chance per fight step that the attackers plant, base and per extra attacker alive.
const PLANT_BASE: float = 0.16
const PLANT_PER_EDGE: float = 0.12
## A planted bomb is defused this often when the defenders win the fights.
const DEFUSE_CHANCE: float = 0.9
const ASSIST_CHANCE: float = 0.3
const TRADE_CHANCE: float = 0.35
## Tilt: ability points per round in a row dying without a kill (after the first), at composure 50,
## and the most it can cost.
const TILT_PER_ROUND: float = 1.2
const TILT_CAP: float = 6.0
## Nerves: ability points per point of composure below [constant NERVE_COMPOSURE], per unit of
## pressure; experience takes off up to [constant EXPERIENCE_CALM] of it.
const NERVE_COMPOSURE: float = 65.0
const NERVE_PER_POINT: float = 0.12
const EXPERIENCE_CALM: float = 0.7
## Fatigue: ability points per [constant FATIGUE_ROUNDS] rounds played in a series, for a player of
## no consistency (a consistent one tires less).
const FATIGUE_ROUNDS: float = 24.0
const FATIGUE_POINTS: float = 1.6
## Map familiarity: ability points between a team that has never played the map lately and one
## that plays it all the time.
const FAMILIARITY_POINTS: float = 3.0
## The fixture ID simulated maps log under (the career stores results by its own fixture IDs).
const SIM_FIXTURE: String = "simulated"
## Seconds between one round's end and the next one's start (end of round and freeze time).
const ROUND_GAP: float = 20.0
## Seconds into a round of the duel chain (maps without a [SimMap]): the first fight, the gap to
## the next one and to a trade.
const FIRST_FIGHT: float = 25.0
const FIGHT_GAP: float = 8.0
const TRADE_GAP: float = 3.0


## A player as the engine sees them. [member skills] holds the 13 career attributes (true values
## for AI players, perceived values for humans: the world only knows what it has seen).
class SimPlayer extends RefCounted:
	var id: String = ""
	var name: String = ""
	var role: StringName = &"rifler"
	var is_human: bool = false
	var skills: Dictionary = {}
	var traits: Dictionary = {}
	var morale: float = 0.0
	# Derived for one map.
	var duel: float = 50.0
	var day_form: float = 0.0
	var aggression: float = 1.0
	## The player's statistics for the map, built from [member MatchEngine.events].
	var counts: Dictionary = {}
	var round_kills: int = 0
	var alive: bool = true
	# Own money and equipment ([SimEconomy]; maps played on a [SimMap] only).
	var money: int = 0
	var primary: StringName = &""
	var secondary: StringName = WeaponCatalog.DEFAULT_SECONDARY
	var armour: int = 0
	var helmet: bool = false
	var kit: bool = false
	var grenades: Array[StringName] = []
	## The weapon of each kill this round (for kill rewards).
	var round_kill_weapons: Array[StringName] = []
	## Big-match experience, 0..1 (from the maps they have played; set by the career).
	var experience: float = 0.0
	## Ability points this player brings to this map from their history on it (set by the career).
	var map_comfort: float = 0.0
	## Rounds played so far in the series (fatigue); carried from map to map.
	var series_rounds: int = 0
	## Rounds in a row this player has died without a kill (tilt).
	var bad_rounds: int = 0

	func skill(key: StringName) -> float:
		return float(skills.get(key, 50))

	func trait_strength(key: StringName) -> int:
		return int(traits.get(key, 0))


class SimTeam extends RefCounted:
	var id: String = ""
	var name: String = ""
	var players: Array[SimPlayer] = []
	var form: int = 0
	## How well the players get on (-6..+6, from [CareerPeople] relationships); adds to coordination.
	var chemistry: float = 0.0
	# Team-wide values for one map.
	var tactics: float = 50.0
	var utility: float = 50.0
	var coordination: float = 50.0
	var money: int = START_MONEY
	var loss_streak: int = 0
	var win_streak: int = 0
	var buy: StringName = &"pistol"
	var execution: float = 0.0
	var map_form: float = 0.0
	## How much the team has played this map lately, 0..1 (set by the career; 0.5 when unknown).
	var familiarity: float = 0.5

	func alive() -> Array[SimPlayer]:
		var list: Array[SimPlayer] = []
		for player: SimPlayer in players:
			if player.alive:
				list.append(player)
		return list


var rng: RandomNumberGenerator
var max_rounds: int = 8
## The map's simulation graph (null: rounds are played without plans).
var sim_map: SimMap = null
## Compact log of the map: per round {winner: 0/1, how: String, attackers: 0/1}, plus
## {site, plans: [team 0 plan, team 1 plan]} (see [method RoundPlan.to_dict]) on a [member sim_map].
var rounds_log: Array[Dictionary] = []
## Short notable moments ("Vex wins a 1v3 clutch", "Rook aces the round").
var highlights: PackedStringArray = []
## The map's event stream in the FPS runtime's format (see [MatchState]); a new array per map.
var events: Array[Dictionary] = []
## True when this map decides the series (set by the caller): every round of it weighs more.
var series_decider: bool = false
## True while the map is in overtime.
var _overtime: bool = false
## Match time when the current round started, and its number (from 1).
var _clock: float = 0.0
var _round_number: int = 0
## Seconds into the current round of the duel chain.
var _fight_time: float = 0.0
## +1 when the next fight is an attacker trading a teammate, −1 for a defender, 0 otherwise.
var _trading: int = 0
var _planners: Array[RoundPlanner] = []
var _plans: Array[RoundPlan] = []
var _score: Array[int] = [0, 0]
## What the last planned round's [RoundSim] reported.
var _outcome: Dictionary = {}
## This round's buy calls and (planned maps) each player's kit after buying, for the round log.
var _buys: Array[String] = []
var _eco: Array[Array] = []


func _init(dice: RandomNumberGenerator, rounds_per_half: int = 8) -> void:
	rng = dice
	max_rounds = rounds_per_half


## Plays one map. Team 0 starts on attack. Returns {score: Vector2i, players: {id: counts with
## "rating"}, mvp: id, rounds: Array, highlights: PackedStringArray, events: Array, timeline:
## [MatchTimeline] data}.
func play_map(home: SimTeam, away: SimTeam) -> Dictionary:
	var teams: Array[SimTeam] = [home, away]
	rounds_log.clear()
	highlights.clear()
	events = []
	_clock = 0.0
	_round_number = 0
	_overtime = false
	for team: SimTeam in teams:
		_prepare(team)
	if home.players.is_empty() or away.players.is_empty():
		return _forfeit(home, away)
	_planners.clear()
	if sim_map != null:
		# The leaders get their own dice (from the match's, without drawing from it), so calling
		# plans does not change how the fights fall.
		for index: int in 2:
			var dice := RandomNumberGenerator.new()
			dice.seed = hash([rng.seed, rng.state, index])
			_planners.append(RoundPlanner.new(sim_map, teams[index], dice))
	var score: Array[int] = [0, 0]
	_score = score
	var lineup: Dictionary = {}
	for index: int in 2:
		for player: SimPlayer in teams[index].players:
			lineup[player.id] = index
	record("match_started", 0.0, {"fixture_id": SIM_FIXTURE, "lineup": lineup})
	var round_number := 0
	var attackers := 0
	while not _decided(score):
		if _half_starts(round_number):
			var rules := SimEconomy.rules()
			for team: SimTeam in teams:
				team.money = START_MONEY if round_number < max_rounds * 2 else OVERTIME_MONEY
				team.loss_streak = 0
				if not _planners.is_empty():
					team.money = rules.start_money if round_number < max_rounds * 2 else rules.overtime_start_money
					for player: SimPlayer in team.players:
						SimEconomy.start_half(player, team.money)
			if round_number > 0:
				attackers = 1 - attackers
		_round_number = round_number + 1
		_overtime = round_number >= max_rounds * 2
		record("round_started", 0.0, {"attack_team": attackers})
		var winner := _play_round(teams, attackers, _decisive(score))
		var seconds := float(_outcome["seconds"]) if not _plans.is_empty() else _fight_time
		record("round_ended", seconds, {"winner_team": winner, "reason": str(rounds_log.back()["how"])})
		_after_round(teams)
		_clock += snappedf(seconds, 0.01) + ROUND_GAP
		score[winner] += 1
		round_number += 1
	record("match_ended", 0.0, {"score": [score[0], score[1]]})
	var lines := _statistics(score)
	var stats: Dictionary = {}
	var mvp := ""
	var best := -1.0
	for team: SimTeam in teams:
		for player: SimPlayer in team.players:
			player.counts = lines.get(player.id, MatchStatistics.empty_counts())
			var rating := MatchStatistics.rating(player.counts)
			var line: Dictionary = player.counts.duplicate(true)
			line["rating"] = rating
			stats[player.id] = line
			if rating > best:
				best = rating
				mvp = player.id
	var map_id := sim_map.map_id if sim_map != null else ""
	return {"score": Vector2i(score[0], score[1]), "players": stats, "mvp": mvp, "rounds": rounds_log.duplicate(),
		"highlights": highlights.duplicate(), "events": events,
		"timeline": MatchTimeline.build(map_id, teams, events, rounds_log, stats)}


## What a round leaves on each player: a round more in their legs, and tilt for dying without a kill.
func _after_round(teams: Array[SimTeam]) -> void:
	for team: SimTeam in teams:
		for player: SimPlayer in team.players:
			player.series_rounds += 1
			if player.round_kills > 0:
				player.bad_rounds = 0
			elif not player.alive:
				player.bad_rounds += 1


## Logs an event [param round_time] seconds into the current round, in the FPS runtime's format.
func record(type: String, round_time: float, data: Dictionary) -> void:
	var entry := {"type": type, "t": snappedf(_clock + round_time, 0.01), "round": _round_number}
	entry.merge(data)
	events.append(entry)


## Every player's counters from the map's events, through the played-match reducer.
func _statistics(score: Array[int]) -> Dictionary[String, Dictionary]:
	var result := MatchResult.new()
	result.fixture_id = SIM_FIXTURE
	result.source = MatchResult.SOURCE_SIMULATION
	result.home_score = score[0]
	result.away_score = score[1]
	result.rounds_played = score[0] + score[1]
	result.events = events
	var lines := MatchStatistics.calculate(result)
	if lines.is_empty():
		push_error("MatchEngine: the simulated event stream did not reduce to statistics.")
	return lines


## Day form and team values (tactics, utility, coordination) for one map, for a planner outside
## a simulated match: the match bots' leader ([BotTactics]) plans with the same numbers.
func prepare_team(team: SimTeam) -> void:
	_prepare(team)


## Day form and derived skills for one map.
func _prepare(team: SimTeam) -> void:
	team.map_form = rng.randfn(0.0, MAP_FORM)
	team.money = START_MONEY
	team.loss_streak = 0
	team.win_streak = 0
	var leadership := 0.0
	var sense := 0.0
	var utility := 0.0
	var coordination := 0.0
	for player: SimPlayer in team.players:
		player.counts = MatchStatistics.empty_counts()
		player.bad_rounds = 0
		var swing := clampf(8.0 + (60.0 - player.skill(&"consistency")) / 5.0, 3.0, 16.0)
		swing *= maxf(0.3, 1.0 + 0.35 * player.trait_strength(&"tr_streaky") - 0.2 * player.trait_strength(&"tr_steady"))
		player.day_form = rng.randfn(player.morale * MORALE_FORM, swing)
		player.duel = (0.28 * player.skill(&"aim") + 0.18 * player.skill(&"reaction") + 0.18 * player.skill(&"crosshair_placement")
			+ 0.14 * player.skill(&"spray_control") + 0.1 * player.skill(&"movement") + 0.12 * player.skill(&"composure")
			+ 3.0 * (player.trait_strength(&"tr_flick_specialist") + player.trait_strength(&"tr_spray_master")))
		player.aggression = float({&"entry": 1.7, &"lurker": 0.9, &"sniper": 1.1, &"support": 0.7, &"igl": 0.8}.get(player.role, 1.0))
		player.aggression *= 1.0 + 0.25 * (player.trait_strength(&"tr_aggressive") + player.trait_strength(&"tr_risk_taker")) \
			- 0.15 * (player.trait_strength(&"tr_passive") + player.trait_strength(&"tr_cautious"))
		player.aggression = maxf(player.aggression, 0.2)
		var lead := player.skill(&"leadership") * (1.0 if player.role == &"igl" else 0.6)
		leadership = maxf(leadership, lead + 2.0 * player.trait_strength(&"tr_tactician"))
		sense += player.skill(&"game_sense") + player.skill(&"positioning") * 0.5
		utility += player.skill(&"utility") + 3.0 * player.trait_strength(&"tr_utility_expert")
		coordination += (player.skill(&"teamwork") + player.skill(&"communication")) / 2.0 \
			+ 2.0 * (player.trait_strength(&"tr_team_player") + player.trait_strength(&"tr_vocal")) \
			- 2.0 * (player.trait_strength(&"tr_lone_wolf") + player.trait_strength(&"tr_quiet"))
	var size := maxf(team.players.size(), 1.0)
	team.tactics = 0.6 * leadership + 0.4 * sense / size / 1.5
	team.utility = utility / size
	coordination /= size
	# Fewer than five players hurts coordination as well as numbers.
	team.coordination = coordination - 6.0 * (5 - mini(team.players.size(), 5)) + team.chemistry


func _play_round(teams: Array[SimTeam], attackers: int, decisive: bool) -> int:
	var pistol := _is_pistol(rounds_log.size())
	for index: int in 2:
		var team := teams[index]
		if _planners.is_empty():
			_buy(team, pistol)
		else:
			# Every player buys their own kit on their leader's call.
			var side := "attack" if index == attackers else "defence"
			SimEconomy.buy(team, side, SimEconomy.call_buy(team, side, pistol, _average_money(teams[1 - index])))
			team.money = roundi(_average_money(team))
		team.execution = rng.randfn(0.0, ROUND_EXECUTION)
		for player: SimPlayer in team.players:
			player.alive = true
			player.round_kills = 0
			player.round_kill_weapons.clear()
	_buys = [str(teams[0].buy), str(teams[1].buy)]
	_eco.clear()
	if not _planners.is_empty():
		for team: SimTeam in teams:
			for player: SimPlayer in team.players:
				_eco.append([player.money, str(player.primary if not player.primary.is_empty() else player.secondary),
					(2 if player.helmet else 1) if player.armour > 0 else 0, player.grenades.size()])
	_plan_round(teams, attackers)
	if not _plans.is_empty():
		return _play_planned(teams, attackers, decisive)
	var defenders := 1 - attackers
	var planted := false
	var how := ""
	var last_death: SimPlayer = null
	var last_killer: SimPlayer = null
	var saved: Array[SimPlayer] = []
	var clutch: Dictionary = {}
	_fight_time = FIRST_FIGHT
	while true:
		var attack_alive := teams[attackers].alive().filter(func(p: SimPlayer) -> bool: return not saved.has(p))
		var defence_alive := teams[defenders].alive()
		if attack_alive.is_empty():
			how = "defused" if planted else "eliminated"
			if planted and rng.randf() > DEFUSE_CHANCE:
				how = "detonated"
			break
		if defence_alive.is_empty():
			# Planted or not, the defenders are wiped out (as in a played match).
			how = "eliminated"
			break
		_note_clutch(attack_alive, defence_alive, attackers, clutch)
		if not planted and rng.randf() < clampf(PLANT_BASE + PLANT_PER_EDGE * (attack_alive.size() - defence_alive.size()), 0.04, 0.6):
			planted = true
			var planter: SimPlayer = attack_alive[rng.randi() % attack_alive.size()]
			record("bomb_planted", _fight_time, {"player": planter.id})
		# A lone attacker facing three or more without a plant may save their weapon.
		if not planted and attack_alive.size() == 1 and defence_alive.size() >= 3:
			var lone: SimPlayer = attack_alive[0]
			if rng.randf() < 0.25 + 0.2 * lone.trait_strength(&"tr_cautious") - 0.1 * lone.trait_strength(&"tr_risk_taker"):
				saved.append(lone)
				continue
		var fighters := _pick_fight(attack_alive, defence_alive, last_killer, last_death)
		var a: SimPlayer = fighters[0]
		var d: SimPlayer = fighters[1]
		var edge := _edge(teams, attackers, a, d, attack_alive.size(), defence_alive.size(), planted, decisive) \
			+ _trading * TRADE_EDGE
		var attacker_wins := rng.randf() < 1.0 / (1.0 + exp(-edge / DUEL_SCALE))
		var killer := a if attacker_wins else d
		var victim := d if attacker_wins else a
		_fight_time += TRADE_GAP if _trading != 0 else FIGHT_GAP + rng.randf() * 4.0
		_kill(killer, victim, teams[attackers if attacker_wins else defenders])
		last_death = victim
		last_killer = killer
	var winner := attackers if how == "detonated" or (how == "eliminated" and teams[defenders].alive().is_empty()) else defenders
	_fight_time += FIGHT_GAP
	if how == "defused":
		var defuser: Array[SimPlayer] = teams[defenders].alive()
		if not defuser.is_empty():
			record("bomb_defused", _fight_time, {"player": defuser[rng.randi() % defuser.size()].id})
	_finish_round(teams, winner, attackers, planted, how, clutch)
	return winner


## Who fights next: a trade on the last killer when possible, otherwise aggressive attackers
## and well-positioned defenders are more likely to be in the fight.
func _pick_fight(attack_alive: Array, defence_alive: Array, last_killer: SimPlayer, last_death: SimPlayer) -> Array[SimPlayer]:
	var a: SimPlayer = _weighted(attack_alive, true)
	var d: SimPlayer = _weighted(defence_alive, false)
	_trading = 0
	if last_killer != null and last_killer.alive and last_death != null and last_killer.round_kills <= 2 \
			and rng.randf() < TRADE_CHANCE:
		if attack_alive.has(last_killer):
			a = last_killer
			_trading = -1
		elif defence_alive.has(last_killer):
			d = last_killer
			_trading = 1
	var fight: Array[SimPlayer] = [a, d]
	return fight


func _weighted(list: Array, attacking: bool) -> SimPlayer:
	var total := 0.0
	var weights: Array[float] = []
	for player: SimPlayer in list:
		var weight := player.aggression if attacking else 1.0 + player.skill(&"positioning") / 100.0
		weight *= pow(0.3, player.round_kills)
		weights.append(weight)
		total += weight
	var roll := rng.randf() * total
	for index: int in list.size():
		roll -= weights[index]
		if roll <= 0.0:
			return list[index]
	return list.back()


## Attacker's edge in ability points for one duel.
func _edge(teams: Array[SimTeam], attackers: int, a: SimPlayer, d: SimPlayer, attack_count: int, defence_count: int,
		planted: bool, decisive: bool) -> float:
	var attack := teams[attackers]
	var defence := teams[1 - attackers]
	var edge := _duel_skill(a, attack, attack_count, defence_count, decisive) - _duel_skill(d, defence, defence_count, attack_count, decisive)
	edge -= DEFENDER_EDGE
	edge += (attack_count - defence_count) * MAN_ADVANTAGE
	edge += BUY_EDGE[attack.buy] - BUY_EDGE[defence.buy]
	edge += (attack.tactics - defence.tactics) * 0.04 + (attack.utility - defence.utility) * 0.03 \
		+ (attack.coordination - defence.coordination) * 0.02
	edge += (attack.form - defence.form) * 0.01 + attack.execution - defence.execution \
		+ attack.map_form - defence.map_form
	edge += clampf(attack.win_streak * MOMENTUM_STEP, 0.0, MOMENTUM_CAP) - clampf(defence.win_streak * MOMENTUM_STEP, 0.0, MOMENTUM_CAP)
	if planted:
		edge += POST_PLANT_EDGE
	# Snipers need the money for their rifle.
	if a.role == &"sniper" and attack.buy == &"full":
		edge += 1.5
	if d.role == &"sniper" and defence.buy == &"full":
		edge -= 1.5
	return edge


## Ability points a player gains or loses on top of their attributes right now: day form, the
## team's map and round, momentum, clutch and pressure, tilt ([RoundSim] adds these to skills).
func form_points(player: SimPlayer, team: SimTeam, own: int, other: int, decisive: bool) -> float:
	var momentum := clampf(team.win_streak * MOMENTUM_STEP, 0.0, MOMENTUM_CAP)
	return _duel_skill(player, team, own, other, decisive) - player.duel + team.map_form + team.execution + momentum \
		+ team.form * 0.01


func _duel_skill(player: SimPlayer, team: SimTeam, own: int, other: int, decisive: bool) -> float:
	var value := player.duel + player.day_form
	if own == 1 and other >= 1:
		value += CLUTCH_TRAIT * (player.trait_strength(&"tr_clutch_player") - player.trait_strength(&"tr_pressure_prone")) \
			+ (player.skill(&"composure") - 60.0) * 0.2
	if decisive:
		value += 2.5 * player.trait_strength(&"tr_clutch_player") - 3.5 * player.trait_strength(&"tr_pressure_prone")
	if team.loss_streak >= TILT_STREAK:
		value -= TILT_PENALTY * player.trait_strength(&"tr_hot_headed")
		value += 1.5 * player.trait_strength(&"tr_calm")
	value -= tilt(player) + nerves(player, decisive) + fatigue(player)
	value += player.map_comfort + (team.familiarity - 0.5) * FAMILIARITY_POINTS
	return value


## Ability points [param player] has lost to rounds in a row dying without a kill.
static func tilt(player: SimPlayer) -> float:
	if player.bad_rounds < 2:
		return 0.0
	var temper := maxf(0.0, 1.0 + 0.8 * player.trait_strength(&"tr_hot_headed") - 0.6 * player.trait_strength(&"tr_calm"))
	var steadiness := clampf((100.0 - player.skill(&"composure")) / 50.0, 0.2, 2.0)
	return minf(TILT_CAP, (player.bad_rounds - 1) * TILT_PER_ROUND * temper * steadiness)


## Ability points [param player] loses to nerves this round: how big it is (a decisive round,
## overtime, a deciding map) against their composure, softened by experience.
func nerves(player: SimPlayer, decisive: bool) -> float:
	var pressure := (1.0 if decisive else 0.0) + (0.5 if _overtime else 0.0) + (0.5 if series_decider else 0.0)
	var shaky := maxf(0.0, NERVE_COMPOSURE - player.skill(&"composure")) * NERVE_PER_POINT
	return pressure * shaky * (1.0 - EXPERIENCE_CALM * clampf(player.experience, 0.0, 1.0))


## Ability points [param player] has lost to the rounds played so far in the series.
static func fatigue(player: SimPlayer) -> float:
	return player.series_rounds / FATIGUE_ROUNDS * FATIGUE_POINTS * clampf(1.2 - player.skill(&"consistency") / 100.0, 0.2, 1.2)


## A duel-chain kill, logged with the damage behind it: now and then a teammate softened the
## victim up first (an assist), the victim hit back, and the killer finished them.
func _kill(killer: SimPlayer, victim: SimPlayer, killer_team: SimTeam) -> void:
	victim.alive = false
	killer.round_kills += 1
	var weapon := String(killer.primary if not killer.primary.is_empty() else killer.secondary)
	var left := 100
	if rng.randf() < ASSIST_CHANCE + killer_team.utility / 400.0:
		var helpers: Array[SimPlayer] = []
		for player: SimPlayer in killer_team.players:
			if player != killer and player.alive:
				helpers.append(player)
		if not helpers.is_empty():
			var helper: SimPlayer = helpers[rng.randi() % helpers.size()]
			var softened := rng.randi_range(40, 80)
			record("damage", _fight_time - 1.0, {"player": helper.id, "victim": victim.id, "hp": softened, "weapon": weapon})
			left -= softened
	var back := rng.randi_range(0, 45)
	if back > 0:
		record("damage", _fight_time - 0.5, {"player": victim.id, "victim": killer.id, "hp": back, "weapon": weapon})
	record("damage", _fight_time, {"player": killer.id, "victim": victim.id, "hp": left, "weapon": weapon})
	record("kill", _fight_time, {"victim": victim.id, "killer": killer.id, "weapon": weapon, "headshot": false})
	if killer.round_kills == 5:
		highlights.append("%s aces round %d" % [killer.name, rounds_log.size() + 1])


func _note_clutch(attack_alive: Array, defence_alive: Array, attackers: int, clutch: Dictionary) -> void:
	if not clutch.is_empty():
		return
	for side: Array in [[attack_alive, defence_alive, attackers], [defence_alive, attack_alive, 1 - attackers]]:
		var own: Array = side[0]
		var other: Array = side[1]
		if own.size() == 1 and other.size() >= 2:
			var player: SimPlayer = own[0]
			clutch["player"] = player
			clutch["team"] = int(side[2])
			clutch["against"] = other.size()
			return


func _finish_round(teams: Array[SimTeam], winner: int, attackers: int, planted: bool, how: String, clutch: Dictionary) -> void:
	# A clutch is won only by a player still standing (not by a bomb after they died).
	if not clutch.is_empty() and int(clutch["team"]) == winner and (clutch["player"] as SimPlayer).alive:
		var hero: SimPlayer = clutch["player"]
		if int(clutch["against"]) >= 3:
			highlights.append("%s wins a 1v%d clutch in round %d" % [hero.name, int(clutch["against"]), rounds_log.size() + 1])
	for index: int in 2:
		var team := teams[index]
		if not _plans.is_empty():
			_settle_players(team, index == winner, how, index == attackers, planted)
			continue
		var kills := 0
		for player: SimPlayer in team.players:
			kills += player.round_kills
		var spent := BUY_COST[team.buy]
		var income := roundi(float(kills * KILL_REWARD) / maxi(team.players.size(), 1))
		if index == winner:
			income += WIN_REWARD
			team.loss_streak = 0
			team.win_streak += 1
		else:
			income += LOSS_BONUS[mini(team.loss_streak, LOSS_BONUS.size() - 1)]
			team.loss_streak += 1
			team.win_streak = 0
			if index == attackers and planted:
				income += PLANT_REWARD
		# Survivors keep most of their equipment.
		var survivors := team.alive().size()
		var kept := roundi(spent * 0.7 * survivors / maxf(team.players.size(), 1.0))
		team.money = clampi(team.money - spent + kept + income, 0, MAX_MONEY)
	var entry := {"winner": winner, "how": how, "attackers": attackers, "buys": _buys.duplicate()}
	if not _eco.is_empty():
		entry["eco"] = _eco.duplicate(true)
	if not _outcome.is_empty() and not _plans.is_empty():
		entry["seconds"] = _outcome["seconds"]
		if bool(_outcome["planted"]):
			var at_plant: Vector2i = _outcome["alive_at_plant"]
			entry["at_plant"] = [at_plant.x, at_plant.y]
			entry["retake"] = _outcome["retake"]
	if not _plans.is_empty():
		_learn(winner, attackers, entry)
	rounds_log.append(entry)


## Each player's money after a planned round; the winners pick up rifles left on the floor.
func _settle_players(team: SimTeam, won: bool, how: String, attacking: bool, planted: bool) -> void:
	SimEconomy.settle(team, won, how, attacking, planted)
	if won:
		var dropped: Array[StringName] = []
		dropped.assign(_outcome.get("dropped", []))
		SimEconomy.pick_up(team, dropped)
		team.loss_streak = 0
		team.win_streak += 1
	else:
		team.loss_streak += 1
		team.win_streak = 0
	team.money = roundi(_average_money(team))


func _average_money(team: SimTeam) -> float:
	var total := 0.0
	for player: SimPlayer in team.players:
		total += player.money
	return total / maxf(team.players.size(), 1.0)


## Both leaders call the round: the attackers' strategy and site, the defenders' setup.
func _plan_round(teams: Array[SimTeam], attackers: int) -> void:
	_plans.clear()
	if _planners.is_empty():
		return
	var plans: Array[RoundPlan] = [null, null]
	for index: int in 2:
		var other := teams[1 - index]
		var situation := RoundPlanner.Situation.new()
		situation.round_index = rounds_log.size()
		situation.own_score = _score[index]
		situation.their_score = _score[1 - index]
		situation.to_win = winner_score(0, max_rounds)
		situation.buy = teams[index].buy
		# Leaders track the other team's money from the round results and kill feed.
		situation.their_buy = &"eco" if other.money < FORCE_MONEY and not _is_pistol(rounds_log.size()) else other.buy
		var players := teams[index].players
		plans[index] = _planners[index].plan_attack(situation, players) if index == attackers 			else _planners[index].plan_defence(situation, players)
	_plans = plans


## A round played out on the map ([RoundSim]): players move, meet and fight.
func _play_planned(teams: Array[SimTeam], attackers: int, decisive: bool) -> int:
	var sim := RoundSim.new(self, teams, attackers, _plans, _planners, decisive)
	_outcome = sim.play()
	var winner := int(_outcome["winner"])
	_finish_round(teams, winner, attackers, bool(_outcome["planted"]), str(_outcome["how"]), _outcome["clutch"] as Dictionary)
	for team: SimTeam in teams:
		for player: SimPlayer in team.players:
			if player.round_kills == 5:
				highlights.append("%s aces round %d" % [player.name, rounds_log.size()])
	return winner


## Each leader learns from the round: where the attack went, how many defended each site.
func _learn(winner: int, attackers: int, entry: Dictionary) -> void:
	var attack := _plans[attackers]
	attack.site = str(_outcome.get("site", attack.site))
	# The attackers learn what they saw: defenders found per site, and whether they rotated.
	var found: Dictionary[String, int] = {}
	for site: String in sim_map.sites():
		found[site] = int((_outcome.get("spotted", {}) as Dictionary).get(site, 0))
	_planners[attackers].learn_attack(attack, winner == attackers, found, bool(_outcome.get("rotated", false)))
	_planners[1 - attackers].learn_defence(attack.site)
	entry["site"] = attack.site
	entry["plans"] = [_plans[0].to_dict(), _plans[1].to_dict()]


func _buy(team: SimTeam, pistol: bool) -> void:
	if pistol:
		team.buy = &"pistol"
	elif team.money >= FULL_BUY_MONEY:
		team.buy = &"full"
	elif team.money >= FORCE_MONEY and (team.loss_streak >= 2 or rng.randf() < 0.35):
		team.buy = &"force"
	else:
		team.buy = &"eco"


func _is_pistol(round_index: int) -> bool:
	return round_index == 0 or round_index == max_rounds


func _half_starts(round_index: int) -> bool:
	if round_index == 0 or round_index == max_rounds:
		return true
	return round_index >= max_rounds * 2 and (round_index - max_rounds * 2) % OVERTIME_ROUNDS == 0


func _decided(score: Array[int]) -> bool:
	var high := maxi(score[0], score[1])
	var low := mini(score[0], score[1])
	return high >= MatchEngine.winner_score(low, max_rounds)


## Rounds the winner needs given the loser's score (same rule as the competitive rules).
static func winner_score(loser_score: int, rounds_per_half: int) -> int:
	if loser_score < rounds_per_half:
		return rounds_per_half + 1
	var block := floori(float(loser_score - rounds_per_half) / OVERTIME_ROUNDS)
	return rounds_per_half + (block + 1) * OVERTIME_ROUNDS + 1


func _decisive(score: Array[int]) -> bool:
	return maxi(score[0], score[1]) >= MatchEngine.winner_score(mini(score[0], score[1]), max_rounds) - 1


func _forfeit(home: SimTeam, away: SimTeam) -> Dictionary:
	var home_wins := not home.players.is_empty()
	var score := Vector2i(max_rounds + 1, 0) if home_wins else Vector2i(0, max_rounds + 1)
	return {"score": score, "players": {}, "mvp": "", "rounds": [], "highlights": PackedStringArray(["Forfeit"])}
