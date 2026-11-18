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
	var counts: Dictionary = {}
	var round_kills: int = 0
	var alive: bool = true
	var contributed: bool = false
	var traded: bool = false

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

	func alive() -> Array[SimPlayer]:
		var list: Array[SimPlayer] = []
		for player: SimPlayer in players:
			if player.alive:
				list.append(player)
		return list


var rng: RandomNumberGenerator
var max_rounds: int = 8
## Compact log of the map: per round {winner: 0/1, how: String, attackers: 0/1}.
var rounds_log: Array[Dictionary] = []
## Short notable moments ("Vex wins a 1v3 clutch", "Rook aces the round").
var highlights: PackedStringArray = []
## +1 when the next fight is an attacker trading a teammate, −1 for a defender, 0 otherwise.
var _trading: int = 0


func _init(dice: RandomNumberGenerator, rounds_per_half: int = 8) -> void:
	rng = dice
	max_rounds = rounds_per_half


## Plays one map. Team 0 starts on attack. Returns {score: Vector2i, players: {id: counts with
## "rating"}, mvp: id, rounds: Array, highlights: PackedStringArray}.
func play_map(home: SimTeam, away: SimTeam) -> Dictionary:
	var teams: Array[SimTeam] = [home, away]
	rounds_log.clear()
	highlights.clear()
	for team: SimTeam in teams:
		_prepare(team)
	if home.players.is_empty() or away.players.is_empty():
		return _forfeit(home, away)
	var score: Array[int] = [0, 0]
	var round_number := 0
	var attackers := 0
	while not _decided(score):
		if _half_starts(round_number):
			for team: SimTeam in teams:
				team.money = START_MONEY if round_number < max_rounds * 2 else OVERTIME_MONEY
				team.loss_streak = 0
			if round_number > 0:
				attackers = 1 - attackers
		var winner := _play_round(teams, attackers, _decisive(score))
		score[winner] += 1
		round_number += 1
	var stats: Dictionary = {}
	var mvp := ""
	var best := -1.0
	for team: SimTeam in teams:
		for player: SimPlayer in team.players:
			player.counts["rounds"] = round_number
			var rating := MatchStatistics.rating(player.counts)
			var line: Dictionary = player.counts.duplicate()
			line["rating"] = rating
			stats[player.id] = line
			if rating > best:
				best = rating
				mvp = player.id
	return {"score": Vector2i(score[0], score[1]), "players": stats, "mvp": mvp, "rounds": rounds_log.duplicate(),
		"highlights": highlights.duplicate()}


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
	for team: SimTeam in teams:
		_buy(team, pistol)
		team.execution = rng.randfn(0.0, ROUND_EXECUTION)
		for player: SimPlayer in team.players:
			player.alive = true
			player.contributed = false
			player.traded = false
			player.round_kills = 0
	var defenders := 1 - attackers
	var planted := false
	var how := ""
	var last_death: SimPlayer = null
	var last_killer: SimPlayer = null
	var opening := true
	var saved: Array[SimPlayer] = []
	var clutch: Dictionary = {}
	while true:
		var attack_alive := teams[attackers].alive().filter(func(p: SimPlayer) -> bool: return not saved.has(p))
		var defence_alive := teams[defenders].alive()
		if attack_alive.is_empty():
			how = "defused" if planted else "eliminated"
			if planted and rng.randf() > DEFUSE_CHANCE:
				how = "detonated"
			break
		if defence_alive.is_empty():
			how = "eliminated" if not planted else "detonated"
			break
		_note_clutch(attack_alive, defence_alive, attackers, clutch)
		if not planted and rng.randf() < clampf(PLANT_BASE + PLANT_PER_EDGE * (attack_alive.size() - defence_alive.size()), 0.04, 0.6):
			planted = true
			var planter: SimPlayer = attack_alive[rng.randi() % attack_alive.size()]
			planter.counts["plants"] += 1
			planter.contributed = true
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
		var trade := last_killer == victim and last_death != null
		_kill(killer, victim, teams[attackers if attacker_wins else defenders], opening, trade, last_death)
		opening = false
		last_death = victim
		last_killer = killer
	var winner := attackers if how == "detonated" or (how == "eliminated" and teams[defenders].alive().is_empty()) else defenders
	if how == "defused":
		var defuser: Array[SimPlayer] = teams[defenders].alive()
		if not defuser.is_empty():
			defuser[rng.randi() % defuser.size()].counts["defuses"] += 1
	_finish_round(teams, winner, attackers, planted, how, clutch)
	for player: SimPlayer in saved:
		player.contributed = true
	for team: SimTeam in teams:
		for player: SimPlayer in team.players:
			if player.alive or player.contributed or player.traded:
				player.counts["kast_rounds"] += 1
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
	return value


func _kill(killer: SimPlayer, victim: SimPlayer, killer_team: SimTeam, opening: bool, trade: bool, last_death: SimPlayer) -> void:
	victim.alive = false
	victim.counts["deaths"] += 1
	killer.counts["kills"] += 1
	killer.round_kills += 1
	killer.contributed = true
	victim.counts["damage"] += rng.randi_range(0, 45)
	killer.counts["damage"] += rng.randi_range(65, 95)
	if opening:
		killer.counts["opening_kills"] += 1
		victim.counts["opening_deaths"] += 1
	if trade and last_death != null:
		killer.counts["trade_kills"] += 1
		last_death.traded = true
		last_death.counts["traded_deaths"] += 1
	if rng.randf() < ASSIST_CHANCE + killer_team.utility / 400.0:
		var helpers: Array[SimPlayer] = []
		for player: SimPlayer in killer_team.players:
			if player != killer and (player.alive or player.round_kills > 0):
				helpers.append(player)
		if not helpers.is_empty():
			var helper: SimPlayer = helpers[rng.randi() % helpers.size()]
			helper.counts["assists"] += 1
			helper.counts["damage"] += rng.randi_range(40, 80)
			helper.contributed = true
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
			player.counts["clutch_attempts"] += 1
			clutch["player"] = player
			clutch["team"] = int(side[2])
			clutch["against"] = other.size()
			return


func _finish_round(teams: Array[SimTeam], winner: int, attackers: int, planted: bool, how: String, clutch: Dictionary) -> void:
	# A clutch is won only by a player still standing (not by a bomb after they died).
	if not clutch.is_empty() and int(clutch["team"]) == winner and (clutch["player"] as SimPlayer).alive:
		var hero: SimPlayer = clutch["player"]
		hero.counts["clutch_wins"] += 1
		if int(clutch["against"]) >= 3:
			highlights.append("%s wins a 1v%d clutch in round %d" % [hero.name, int(clutch["against"]), rounds_log.size() + 1])
	for index: int in 2:
		var team := teams[index]
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
	rounds_log.append({"winner": winner, "how": how, "attackers": attackers})


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
