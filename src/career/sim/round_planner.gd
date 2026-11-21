class_name RoundPlanner
extends RefCounted
## A team's in-game leader in a simulated match: picks each round's plan ([RoundPlan]) on the
## map's [SimMap] and makes the calls during the round (where to hit, rotate, retake or save).
## Pure career-layer logic, one planner per team per map.
##
## Nothing here is a fixed rate. Each choice is weighed from who is playing (the leader's
## tactics, the team's utility, coordination and aggression, who has which role and traits),
## the economy, the score, and what has happened earlier in the match: which plans won, where the
## opponents attacked, how many defenders were found on each site, whether they rotated fast.
## A sharper leader picks the best-weighed option more consistently; a weaker one wanders.

## Metres per second players cover between places (about a rifle's running pace with stops).
const RUN_SPEED: float = 5.0
const ATTACK_KINDS: Array[StringName] = [RoundPlan.DEFAULT, RoundPlan.EXECUTE, RoundPlan.SPLIT, RoundPlan.RUSH, RoundPlan.FAKE]
const DEFENCE_KINDS: Array[StringName] = [RoundPlan.STANDARD, RoundPlan.STACK, RoundPlan.AGGRESSIVE]


## What the leader knows when calling a round.
class Situation extends RefCounted:
	var round_index: int = 0
	var own_score: int = 0
	var their_score: int = 0
	## Rounds needed to win the map.
	var to_win: int = 9
	var buy: StringName = &"full"
	## What the leader expects the opponents to have ("eco" after they lost with little money).
	var their_buy: StringName = &"full"
	var round_time: float = 105.0


var map: SimMap
var team: MatchEngine.SimTeam
var rng: RandomNumberGenerator
## "kind|site" -> [rounds tried, rounds won] for our attacks.
var _attack_record: Dictionary[String, Array] = {}
## Last attack plans we ran ("kind|site"), newest last.
var _recent_attacks: Array[String] = []
## Site -> times the opponents attacked it while we defended.
var _attacked_at: Dictionary[String, int] = {}
## Site -> [defenders found there in total, rounds looked] while we attacked.
var _defenders_at: Dictionary[String, Array] = {}
## Rounds we attacked and how often the opponents rotated before our hit landed.
var _rotations_seen: Array[int] = [0, 0]
# Map answers worked out once per map.
var _approaches: Dictionary[String, Array] = {}
var _holds: Dictionary[String, Array] = {}
var _site_of_place: Dictionary[String, String] = {}


func _init(sim_map: SimMap, own: MatchEngine.SimTeam, dice: RandomNumberGenerator) -> void:
	map = sim_map
	team = own
	rng = dice


# --- Attack ------------------------------------------------------------------------------------

## The attack plan for this round.
func plan_attack(situation: Situation, players: Array[MatchEngine.SimPlayer]) -> RoundPlan:
	var plan := RoundPlan.new()
	plan.side = &"attack"
	var kinds := attack_weights(situation, players.size())
	plan.kind = _pick(kinds)
	plan.site = _pick(site_weights(plan.kind))
	if plan.kind == RoundPlan.FAKE:
		plan.fake_site = _other_site(plan.site)
	plan.reasons = _attack_reasons(plan, situation)
	_assign_attack(plan, players)
	plan.hit_at = _hit_time(plan, situation)
	return plan


## Weight of each attack kind this round (exposed for tests and the match view).
func attack_weights(situation: Situation, player_count: int) -> Dictionary[StringName, float]:
	var tactics := team.tactics / 55.0
	var utility := team.utility / 55.0
	var coordination := team.coordination / 55.0
	var aggression := _average_aggression()
	var buy := situation.buy
	var full := buy == &"full" or buy == &"pistol"
	# Rounds left to lose before the map is gone, against our lead or deficit.
	var deficit := situation.their_score - situation.own_score
	var pressure := float(deficit) / maxf(situation.to_win - situation.their_score, 1.0)
	var weights: Dictionary[StringName, float] = {
		RoundPlan.DEFAULT: pow(tactics, 2.0) * (1.0 if full else 0.4),
		RoundPlan.EXECUTE: pow((utility + coordination) / 2.0, 2.0) * (1.0 if buy == &"full" else 0.5 if buy != &"eco" else 0.15),
		RoundPlan.SPLIT: pow(coordination, 3.0) * (1.0 if full else 0.3) * (1.0 if player_count >= 4 else 0.1),
		RoundPlan.RUSH: pow(aggression, 2.0) * (2.2 if buy == &"eco" else 1.3 if buy == &"force" else 0.7 if buy == &"pistol" else 0.35),
		RoundPlan.FAKE: pow(tactics, 3.0) * (0.4 + _rotation_rate()) * (0.9 if full else 0.25) * (1.0 if player_count >= 4 else 0.2),
	}
	# Behind with few rounds to spare, leaders gamble; ahead, they play the slow default.
	if pressure > 0.0:
		weights[RoundPlan.RUSH] *= 1.0 + pressure
		weights[RoundPlan.FAKE] *= 1.0 + pressure
	elif pressure < 0.0:
		weights[RoundPlan.DEFAULT] *= 1.0 - pressure
	# The opponents expected to be on an eco: take the map slowly rather than run into them.
	if situation.their_buy == &"eco":
		weights[RoundPlan.DEFAULT] *= 1.5
		weights[RoundPlan.RUSH] *= 0.6
	for kind: StringName in weights:
		weights[kind] *= _record_factor(kind, "")
		# Running the same plan again lets the opponents read it.
		var repeats := 0
		for recent: String in _recent_attacks:
			if recent.begins_with(str(kind) + "|"):
				repeats += 1
		weights[kind] /= 1.0 + 0.5 * repeats
	return weights


## Weight of each site for an attack of [param kind].
func site_weights(kind: StringName) -> Dictionary[String, float]:
	var weights: Dictionary[String, float] = {}
	var attack := map.spawn("attack")
	var nearest := INF
	for site: String in map.sites():
		nearest = minf(nearest, map.distance(attack, site))
	for site: String in map.sites():
		var closeness := nearest / maxf(map.distance(attack, site), 1.0)
		var weight := closeness if kind != RoundPlan.RUSH else pow(closeness, 3.0)
		weight /= 1.0 + _defenders_seen(site)
		weight *= _record_factor(kind, site)
		weights[site] = weight
	return weights


## Default rounds: once the team has information, the site to hit. [param spotted] is site ->
## defenders seen on or around it; the leader goes where fewest were seen for the distance.
func call_hit(plan: RoundPlan, spotted: Dictionary[String, int]) -> String:
	var best := plan.site
	var best_score := -INF
	for site: String in map.sites():
		var score := -float(spotted.get(site, 0)) - map.distance(map.spawn("attack"), site) / 100.0
		if score > best_score:
			best_score = score
			best = site
	return best


## Whether attackers without a plant give up the round and keep their weapons.
func attack_should_save(alive: int, defenders_alive: int, seconds_left: float, metres_to_site: float) -> bool:
	if alive <= 0:
		return true
	var arrival := metres_to_site / RUN_SPEED
	var odds := float(alive) / maxf(defenders_alive, 1.0) + (team.coordination - 50.0) / 100.0
	var no_time := arrival + 5.0 > seconds_left
	return no_time or odds < 0.4 + _caution() * 0.15


## What the leader learns from a round they attacked: where defenders were found and whether
## the opponents rotated before the hit landed.
func learn_attack(plan: RoundPlan, won: bool, defenders_found: Dictionary[String, int], rotated: bool) -> void:
	var key := "%s|%s" % [plan.kind, plan.site]
	var record: Array = _attack_record.get(key, [0, 0])
	_attack_record[key] = [int(record[0]) + 1, int(record[1]) + (1 if won else 0)]
	_recent_attacks.append(key)
	if _recent_attacks.size() > 2:
		_recent_attacks.pop_front()
	for site: String in defenders_found:
		var seen: Array = _defenders_at.get(site, [0, 0])
		_defenders_at[site] = [int(seen[0]) + defenders_found[site], int(seen[1]) + 1]
	_rotations_seen = [_rotations_seen[0] + 1, _rotations_seen[1] + (1 if rotated else 0)]


# --- Defence -----------------------------------------------------------------------------------

## The defence setup for this round.
func plan_defence(situation: Situation, players: Array[MatchEngine.SimPlayer]) -> RoundPlan:
	var plan := RoundPlan.new()
	plan.side = &"defence"
	plan.kind = _pick(defence_weights(situation))
	if plan.kind == RoundPlan.STACK:
		plan.site = _most_attacked_site()
	_assign_defence(plan, players)
	plan.reasons = _defence_reasons(plan, situation)
	return plan


func defence_weights(situation: Situation) -> Dictionary[StringName, float]:
	var sense := team.tactics / 55.0
	var aggression := _average_aggression()
	var read := _attack_concentration()
	var eco := situation.buy == &"eco"
	var weights: Dictionary[StringName, float] = {
		RoundPlan.STANDARD: pow(sense, 2.0) * (0.7 if eco else 1.0),
		# A stack is a read: it grows with how one-sided the opponents' attacks have been and with
		# how many attacks it rests on.
		RoundPlan.STACK: pow(2.0 * read, 2.0) * sense * _attacks_seen() / (_attacks_seen() + 4.0) * (1.6 if eco else 1.0),
		RoundPlan.AGGRESSIVE: pow(aggression, 2.0) * 0.6 * (1.5 if eco else 1.0) * (0.5 if situation.their_buy == &"eco" else 1.0),
	}
	if _attacked_at.is_empty():
		weights[RoundPlan.STACK] = 0.0
	return weights


## Where a defender goes once the attack shows itself ("" to stay). [param seen] is site ->
## attackers seen or heard there; [param planted_at] is the bomb's site ("" before a plant).
## Rotators move on the first real contact; anchors hold unless the attack is clearly elsewhere,
## and players with better game sense read it sooner.
func rotation_for(plan: RoundPlan, player: MatchEngine.SimPlayer, seen: Dictionary[String, int], planted_at: String) -> String:
	var own_site := _site_of(plan.spots.get(player.id, ""))
	if not planted_at.is_empty():
		return planted_at if planted_at != own_site else ""
	var hot := ""
	var most := 0
	for site: String in seen:
		if seen[site] > most:
			most = seen[site]
			hot = site
	if hot.is_empty() or hot == own_site:
		return ""
	var job: StringName = plan.jobs.get(player.id, RoundPlan.ANCHOR)
	var needed := clampf(3.5 - (player.skill(&"game_sense") - 50.0) / 25.0, 2.0, 4.0)
	if job == RoundPlan.ROTATOR:
		needed -= 1.5
	elif job == RoundPlan.ANCHOR and int(seen.get(own_site, 0)) > 0:
		return ""
	return hot if most >= needed else ""


## After a plant: "retake" when the defenders have the numbers and the time, otherwise "save".
## [param metres_away] is the walk of the furthest defender who must join the retake.
func retake_or_save(alive: int, attackers_alive: int, seconds_left: float, metres_away: float, has_kit: bool,
		next_round_money: int) -> StringName:
	if alive <= 0:
		return &"save"
	var defuse := 5.0 if has_kit else 10.0
	if metres_away / RUN_SPEED + defuse > seconds_left:
		return &"save"
	var odds := float(alive - attackers_alive) + (team.coordination - 50.0) / 25.0 + (team.tactics - 50.0) / 50.0
	# A team that cannot afford a gun next round plays for this one.
	if next_round_money < MatchEngine.FORCE_MONEY:
		odds += 1.0
	return &"retake" if odds >= -1.0 + _caution() else &"save"


## What the leader learns from a round they defended: where the attack went.
func learn_defence(attacked_site: String) -> void:
	if not attacked_site.is_empty():
		_attacked_at[attacked_site] = int(_attacked_at.get(attacked_site, 0)) + 1


# --- Positions ---------------------------------------------------------------------------------

## The places a site is approached from by the attackers: entrances the map marks as this site's
## (callout role "entrance_<letter>") plus the last place before the site on the attackers' walk.
func approaches(site: String) -> Array[String]:
	var cached: Array[String] = []
	if _approaches.has(site):
		cached.assign(_approaches[site])
		return cached
	var letter := str(map.nodes.get(site, {}).get("site", ""))
	var list: Array[String] = []
	for place: String in map.entrances(site):
		if str(map.nodes[place].get("role", "")) == "entrance_" + letter.to_lower():
			list.append(place)
	var cluster := map.site_cluster(site)
	var walk := map.route(map.spawn("attack"), site)
	for i: int in range(walk.size() - 1, 0, -1):
		if cluster.has(walk[i]) and not cluster.has(walk[i - 1]):
			if not list.has(walk[i - 1]):
				list.append(walk[i - 1])
			break
	list.sort_custom(func(a: String, b: String) -> bool:
		return map.distance(map.spawn("attack"), a) < map.distance(map.spawn("attack"), b))
	_approaches[site] = list.duplicate()
	return list


## Where defenders hold a site: the site and the areas on it, biggest floor first.
func holds(site: String) -> Array[String]:
	var list: Array[String] = []
	if _holds.has(site):
		list.assign(_holds[site])
		return list
	list = map.site_cluster(site)
	list.sort_custom(func(a: String, b: String) -> bool:
		return float(map.nodes[a].get("floor", 0.0)) > float(map.nodes[b].get("floor", 0.0)))
	_holds[site] = list.duplicate()
	return list


## The place between the sites a rotator waits at: off both sites, the shortest worst-case walk
## to either.
func rotator_spot() -> String:
	var best := ""
	var best_walk := INF
	var on_site: Array[String] = []
	for site: String in map.sites():
		on_site.append_array(map.site_cluster(site))
	for place: String in map.ids_of_kind(SimMap.KIND_AREA):
		if on_site.has(place):
			continue
		# Rotators stay on the defenders' half: closer to their spawn than the attackers are.
		if map.distance(map.spawn("defence"), place) >= map.distance(map.spawn("attack"), place):
			continue
		var worst := 0.0
		for site: String in map.sites():
			worst = maxf(worst, map.distance(place, site))
		if worst < best_walk:
			best_walk = worst
			best = place
	return best


func _assign_attack(plan: RoundPlan, players: Array[MatchEngine.SimPlayer]) -> void:
	var order := players.duplicate()
	order.sort_custom(func(a: MatchEngine.SimPlayer, b: MatchEngine.SimPlayer) -> bool: return _entry_drive(a) > _entry_drive(b))
	var lurker: MatchEngine.SimPlayer = null
	if plan.kind != RoundPlan.RUSH and players.size() >= 4:
		for player: MatchEngine.SimPlayer in players:
			if player.role == &"lurker" or player.trait_strength(&"tr_lone_wolf") > 0:
				lurker = player
				break
	var target := approaches(plan.site)
	var other_site := plan.fake_site if not plan.fake_site.is_empty() else _other_site(plan.site)
	var elsewhere := approaches(other_site) if not other_site.is_empty() else target
	var count := 0
	for player: MatchEngine.SimPlayer in order:
		var job: StringName
		var spot: String
		if player == lurker:
			job = RoundPlan.LURK
			spot = elsewhere[0] if not elsewhere.is_empty() else target[0] if not target.is_empty() else plan.site
		elif plan.kind == RoundPlan.FAKE and count >= players.size() - 2:
			job = RoundPlan.FAKER
			spot = elsewhere[count % elsewhere.size()] if not elsewhere.is_empty() else plan.site
		elif plan.kind == RoundPlan.DEFAULT and count >= 2:
			# Map control: the rest spread over every way in, both sites.
			job = RoundPlan.SUPPORT
			var spread: Array[String] = target + elsewhere
			spot = spread[count % spread.size()] if not spread.is_empty() else plan.site
		else:
			job = RoundPlan.ENTRY if count == 0 else RoundPlan.TRADE if count == 1 else RoundPlan.SUPPORT
			# Splits send the entry pair through the first way in and the rest through another.
			var lane := 0 if plan.kind != RoundPlan.SPLIT or count < 2 else mini(1, target.size() - 1)
			spot = target[lane] if not target.is_empty() else plan.site
		if player != lurker:
			count += 1
		plan.jobs[player.id] = job
		plan.spots[player.id] = spot
		plan.routes[player.id] = map.route(map.spawn("attack"), spot)


func _assign_defence(plan: RoundPlan, players: Array[MatchEngine.SimPlayer]) -> void:
	var sites := map.sites()
	if sites.is_empty():
		return
	# How many hold each site.
	var share: Dictionary[String, int] = {}
	for site: String in sites:
		share[site] = 0
	var free := players.size()
	var rotators := 0
	if plan.kind == RoundPlan.STACK and share.has(plan.site):
		for site: String in sites:
			share[site] = 1 if site != plan.site else 0
		free -= sites.size() - 1
		share[plan.site] = free
		free = 0
	else:
		for site: String in sites:
			if free > 0:
				share[site] = 1
				free -= 1
		# The site attacked most gets the next player; a fifth player rotates.
		var order := sites.duplicate()
		order.sort_custom(func(a: String, b: String) -> bool: return int(_attacked_at.get(a, 0)) > int(_attacked_at.get(b, 0)))
		var index := 0
		while free > 1 or (free == 1 and players.size() < 5):
			share[order[index % order.size()]] += 1
			free -= 1
			index += 1
		rotators = free
	# Who goes where: aggressors forward, the most patient anchor, the best reader rotates.
	var pool := players.duplicate()
	var rotator_place := rotator_spot()
	if rotators > 0 and not rotator_place.is_empty():
		pool.sort_custom(func(a: MatchEngine.SimPlayer, b: MatchEngine.SimPlayer) -> bool:
			return a.skill(&"game_sense") > b.skill(&"game_sense"))
		var reader: MatchEngine.SimPlayer = pool.pop_front()
		plan.jobs[reader.id] = RoundPlan.ROTATOR
		plan.spots[reader.id] = rotator_place
		plan.routes[reader.id] = map.route(map.spawn("defence"), rotator_place)
	pool.sort_custom(func(a: MatchEngine.SimPlayer, b: MatchEngine.SimPlayer) -> bool: return _anchor_drive(a) > _anchor_drive(b))
	var aggressors := 0
	if plan.kind == RoundPlan.AGGRESSIVE:
		aggressors = 2 if pool.size() >= 4 else 1
	for site: String in sites:
		var places := holds(site)
		var forward := approaches(site)
		for n: int in share[site]:
			if pool.is_empty():
				break
			var player: MatchEngine.SimPlayer
			var job := RoundPlan.ANCHOR
			var spot := places[n % places.size()]
			if aggressors > 0 and not forward.is_empty() and n > 0:
				player = pool.pop_back()  # least patient
				job = RoundPlan.AGGRESSOR
				spot = forward[0]
				aggressors -= 1
			else:
				player = pool.pop_front()
				if n > 0:
					job = RoundPlan.SUPPORT
			plan.jobs[player.id] = job
			plan.spots[player.id] = spot
			plan.routes[player.id] = map.route(map.spawn("defence"), spot)


## When the attack goes onto the site (seconds into the round).
func _hit_time(plan: RoundPlan, situation: Situation) -> float:
	var travel := 0.0
	for id: String in plan.spots:
		travel = maxf(travel, map.distance(map.spawn("attack"), plan.spots[id]) / RUN_SPEED)
	var patience := clampf(team.tactics / 60.0, 0.6, 1.4)
	var latest := situation.round_time - 25.0
	match plan.kind:
		RoundPlan.RUSH:
			return minf(travel, latest)
		RoundPlan.EXECUTE, RoundPlan.SPLIT:
			return minf(travel + 12.0 * patience, latest)
		RoundPlan.FAKE:
			return minf(travel + 25.0 * patience, latest)
	# Default: map control first, the call comes late.
	return minf(maxf(travel + 30.0 * patience, situation.round_time * 0.5), latest)


# --- Reading the opponents ----------------------------------------------------------------------

func _record_factor(kind: StringName, site: String) -> float:
	var tries := 0
	var wins := 0
	for key: String in _attack_record:
		var parts := key.split("|")
		if parts[0] == str(kind) and (site.is_empty() or parts[1] == site):
			tries += int(_attack_record[key][0])
			wins += int(_attack_record[key][1])
	return 2.0 * (wins + 1.0) / (tries + 2.0)


func _defenders_seen(site: String) -> float:
	var seen: Array = _defenders_at.get(site, [0, 0])
	return float(seen[0]) / maxf(float(seen[1]), 1.0)


func _rotation_rate() -> float:
	return float(_rotations_seen[1]) / maxf(float(_rotations_seen[0]), 1.0)


## How one-sided the opponents' attacks have been (0.5 even split between two sites .. 1).
func _attack_concentration() -> float:
	var total := 0
	var most := 0
	for site: String in _attacked_at:
		total += _attacked_at[site]
		most = maxi(most, _attacked_at[site])
	return float(most) / float(total) if total > 0 else 1.0 / maxf(map.sites().size(), 1.0)


func _most_attacked_site() -> String:
	var best := ""
	var most := -1
	for site: String in map.sites():
		if int(_attacked_at.get(site, 0)) > most:
			most = int(_attacked_at.get(site, 0))
			best = site
	return best


func _other_site(site: String) -> String:
	var best := ""
	for other: String in map.sites():
		if other != site and (best.is_empty() or _defenders_seen(other) < _defenders_seen(best)):
			best = other
	return best


## The site a place belongs to ("" when it is between sites).
func _site_of(place: String) -> String:
	if _site_of_place.has(place):
		return _site_of_place[place]
	var found := ""
	for site: String in map.sites():
		if map.site_cluster(site).has(place) or (approaches(site).has(place) and RoundPlan._belongs_to(map, place, site)):
			found = site
			break
	_site_of_place[place] = found
	return found


# --- People ------------------------------------------------------------------------------------

func _average_aggression() -> float:
	var total := 0.0
	for player: MatchEngine.SimPlayer in team.players:
		total += player.aggression
	return total / maxf(team.players.size(), 1.0)


## How careful the leader is (−1 .. 1): cautious leaders save sooner, risk-takers play on.
func _caution() -> float:
	var leader := _leader()
	if leader == null:
		return 0.0
	return clampf(0.5 * (leader.trait_strength(&"tr_cautious") - leader.trait_strength(&"tr_risk_taker")), -1.0, 1.0)


func _leader() -> MatchEngine.SimPlayer:
	var best: MatchEngine.SimPlayer = null
	for player: MatchEngine.SimPlayer in team.players:
		if player.role == &"igl":
			return player
		if best == null or player.skill(&"leadership") > best.skill(&"leadership"):
			best = player
	return best


static func _entry_drive(player: MatchEngine.SimPlayer) -> float:
	return player.aggression + (1.0 if player.role == &"entry" else 0.0) - (0.5 if player.role == &"sniper" else 0.0)


static func _anchor_drive(player: MatchEngine.SimPlayer) -> float:
	return player.skill(&"positioning") / 50.0 - player.aggression + (0.5 if player.role == &"sniper" else 0.0)


# --- Choosing -----------------------------------------------------------------------------------

## Picks a key by weight. A sharper leader (tactics) leans harder towards the heaviest option.
func _pick(weights: Dictionary) -> Variant:
	var sharpness := clampf(0.6 + (team.tactics - 40.0) / 30.0, 0.6, 2.5)
	var keys: Array = weights.keys()
	keys.sort()
	var total := 0.0
	var scaled: Array[float] = []
	for key: Variant in keys:
		var weight := pow(maxf(float(weights[key]), 0.0), sharpness)
		scaled.append(weight)
		total += weight
	if total <= 0.0:
		return keys[0] if not keys.is_empty() else null
	var roll := rng.randf() * total
	for i: int in keys.size():
		roll -= scaled[i]
		if roll <= 0.0:
			return keys[i]
	return keys.back()


func _attack_reasons(plan: RoundPlan, situation: Situation) -> PackedStringArray:
	var reasons: PackedStringArray = []
	if situation.buy == &"eco" or situation.buy == &"force":
		reasons.append("%s round" % situation.buy)
	if situation.their_score - situation.own_score >= 3:
		reasons.append("behind %d–%d" % [situation.own_score, situation.their_score])
	var record: Array = _attack_record.get("%s|%s" % [plan.kind, plan.site], [0, 0])
	if int(record[1]) > 0:
		reasons.append("won %d of %d like this" % [int(record[1]), int(record[0])])
	if _defenders_seen(plan.site) < _defenders_seen(_other_site(plan.site)):
		reasons.append("fewer defenders seen on %s" % map.name_of(plan.site))
	if plan.kind == RoundPlan.FAKE and _rotation_rate() > 0.4:
		reasons.append("they rotate early")
	return reasons


func _defence_reasons(plan: RoundPlan, situation: Situation) -> PackedStringArray:
	var reasons: PackedStringArray = []
	if situation.buy == &"eco":
		reasons.append("eco round")
	if plan.kind == RoundPlan.STACK:
		reasons.append("%d of their %d attacks went to %s" % [int(_attacked_at.get(plan.site, 0)), _attacks_seen(), map.name_of(plan.site)])
	return reasons


func _attacks_seen() -> int:
	var total := 0
	for site: String in _attacked_at:
		total += _attacked_at[site]
	return total
