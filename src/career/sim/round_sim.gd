class_name RoundSim
extends RefCounted
## One simulated round on a map's [SimMap]: ten players moving through its places second by
## second, following their leaders' [RoundPlan]s, and fighting where they meet. Pure career-layer
## logic used by [MatchEngine]; career attributes never reach the FPS runtime.
##
## - Movement: attackers walk their routes to their places, wait for the hit and then go onto the
##   target site (a default calls the site on what map control found; fakers make noise first).
##   Defenders walk to their holds; rotators and readers move when the attack shows itself
##   ([method RoundPlanner.rotation_for]); after a plant the leader calls a retake or a save.
## - Contact: opponents in the same place meet; a player walking into a place someone is holding
##   peeks them. Who sees whom first comes from reaction, crosshair placement, positioning and game
##   sense against the peeker's movement and the peeker's advantage.
## - Fights: bursts are exchanged with each player's weapon (from the team's buy and the player's
##   role); every bullet hits on aim, spray control, distance and movement, and a hit is a headshot
##   on aim and crosshair placement. Damage and armour carry over between fights. Teammates in the
##   same place join in: crossfires, and kills on a player who just got a kill are trades.
## - The bomb: the carrier plants on the site when no defender is there; if they die, the nearest
##   attacker picks it up. A defender on the site alone defuses (faster with a kit).

const STEP: float = 1.0
const ROUND_TIME: float = 105.0
const BOMB_TIMER: float = 40.0
const PLANT_TIME: float = 3.0
const DEFUSE_TIME: float = 10.0
const DEFUSE_KIT_TIME: float = 5.0
## Bursts each side fires in one exchange before somebody backs off.
const MAX_BURSTS: int = 3
## Ability points turn into seconds of reaction (higher is faster).
const REACTION_PER_POINT: float = 0.002
## A peeker moving into an angle sees a holder a little before the holder can react.
const PEEKER_ADVANTAGE: float = 0.04
## Weapons as the simulation sees them: damage per hit (against armour / without), bullets per
## burst and the distance (m) up to which the weapon is accurate.
const WEAPONS: Dictionary[StringName, Dictionary] = {
	&"pistol": {"body": [18, 25], "head": [55, 95], "burst": 2, "range": 12.0},
	&"heavy_pistol": {"body": [35, 45], "head": [105, 170], "burst": 1, "range": 20.0},
	&"smg": {"body": [22, 29], "head": [70, 90], "burst": 4, "range": 14.0},
	&"rifle": {"body": [27, 36], "head": [108, 143], "burst": 3, "range": 30.0},
	&"sniper": {"body": [100, 115], "head": [300, 400], "burst": 1, "range": 60.0},
}


## A player during the round.
class Body extends RefCounted:
	var player: MatchEngine.SimPlayer
	var team: int = 0
	var job: StringName = &""
	var place: String = ""
	## Places still to walk through, next first.
	var path: Array[String] = []
	## Metres walked from [member place] towards the first place of [member path].
	var progress: float = 0.0
	var hp: int = 100
	var armour: bool = false
	var weapon: StringName = &"rifle"
	var has_bomb: bool = false
	## Left the fight (saving their weapon).
	var hidden: bool = false
	## Stays put this step (fighting, planting, defusing).
	var busy: bool = false
	var rotated: bool = false
	var last_kill_time: float = -INF
	var damage_from: Dictionary[String, int] = {}

	func alive() -> bool:
		return hp > 0

	func moving() -> bool:
		return not path.is_empty()


var engine: MatchEngine
var map: SimMap
var rng: RandomNumberGenerator
var teams: Array[MatchEngine.SimTeam]
var attackers: int = 0
var plans: Array[RoundPlan]
var planners: Array[RoundPlanner]
var decisive: bool = false

var time: float = 0.0
var bodies: Array[Body] = []
var site: String = ""
var planted: bool = false
var planted_at: float = 0.0
var bomb_place: String = ""
var plant_progress: float = 0.0
var defuse_progress: float = 0.0
var retake_called: StringName = &""
var retake_pushed: bool = false
## Players alive on each side (attackers, defenders) when the bomb went down.
var alive_at_plant: Vector2i = Vector2i(-1, -1)
var hit_called: bool = false
## Site -> defenders the attackers have seen there (what map control found).
var spotted: Dictionary[String, int] = {}
var clutch: Dictionary = {}
var _opening: bool = true
var _by_id: Dictionary[String, Body] = {}
## Victim id -> killer id this round.
var _killed_by: Dictionary[String, String] = {}
var _form_cache: Dictionary[String, float] = {}
## Per-map answers (kept on the map: they do not change between rounds).
var _near_cache: Dictionary
var _open_cache: Dictionary


func _init(owner: MatchEngine, round_teams: Array[MatchEngine.SimTeam], attacking: int, round_plans: Array[RoundPlan],
		leaders: Array[RoundPlanner], is_decisive: bool) -> void:
	engine = owner
	map = owner.sim_map
	rng = owner.rng
	teams = round_teams
	attackers = attacking
	plans = round_plans
	planners = leaders
	decisive = is_decisive
	site = plans[attackers].site
	if not map.memo.has("round_sim_near"):
		map.memo["round_sim_near"] = {}
		map.memo["round_sim_open"] = {}
	_near_cache = map.memo["round_sim_near"]
	_open_cache = map.memo["round_sim_open"]


## Plays the round. Returns {"winner": team index, "how": "eliminated"|"defused"|"detonated"|
## "time", "planted": bool, "site": String, "clutch": Dictionary, "spotted": Dictionary,
## "rotated": bool}.
func play() -> Dictionary:
	_place_players()
	var how := ""
	while how.is_empty():
		time += STEP
		for body: Body in bodies:
			body.busy = false
		_think()
		_fight()
		_bomb()
		_move()
		how = _ended()
	var winner := attackers if how == "detonated" or (how == "eliminated" and _alive(1 - attackers).is_empty()) else 1 - attackers
	var rotated := false
	for body: Body in bodies:
		rotated = rotated or (body.team != attackers and body.rotated)
	return {"winner": winner, "how": how, "planted": planted, "site": site, "clutch": clutch, "spotted": spotted.duplicate(),
		"rotated": rotated, "retake": str(retake_called), "alive_at_plant": alive_at_plant, "seconds": time}


# --- Setup -------------------------------------------------------------------------------------

func _place_players() -> void:
	for index: int in 2:
		var plan := plans[index]
		var team := teams[index]
		var spawn := map.spawn("attack" if index == attackers else "defence")
		for player: MatchEngine.SimPlayer in team.players:
			var body := Body.new()
			body.player = player
			body.team = index
			body.place = spawn
			body.job = plan.jobs.get(player.id, &"")
			var walk: Array = plan.routes.get(player.id, [])
			body.path.assign(walk.slice(1))
			body.weapon = _weapon(player, team.buy)
			body.armour = team.buy == &"full" or team.buy == &"force"
			bodies.append(body)
			_by_id[player.id] = body
	# The bomb goes to a support or trade player, never the lurker or the entry.
	var carrier: Body = null
	for body: Body in _alive(attackers):
		if carrier == null or _carry_preference(body) > _carry_preference(carrier):
			carrier = body
	if carrier != null:
		carrier.has_bomb = true


func _carry_preference(body: Body) -> int:
	return {RoundPlan.SUPPORT: 3, RoundPlan.TRADE: 2, RoundPlan.FAKER: 1}.get(body.job, 0)


## A player's weapon this round: snipers take the rifle they paid for on a full buy.
static func _weapon(player: MatchEngine.SimPlayer, buy: StringName) -> StringName:
	match buy:
		&"full":
			return &"sniper" if player.role == &"sniper" else &"rifle"
		&"force":
			return &"smg" if player.role != &"entry" else &"rifle"
		&"eco":
			return &"heavy_pistol" if player.skill(&"aim") >= 65 else &"pistol"
	return &"pistol"


# --- Decisions ---------------------------------------------------------------------------------

func _think() -> void:
	var attack_plan := plans[attackers]
	# The hit: a default is called on what map control found.
	if not hit_called and time >= attack_plan.hit_at:
		hit_called = true
		if attack_plan.kind == RoundPlan.DEFAULT:
			site = planners[attackers].call_hit(attack_plan, spotted)
		for body: Body in _alive(attackers):
			if body.job != RoundPlan.LURK and not body.hidden:
				_send(body, site)
	# The lurker comes in behind once the bomb is down or the hit is late.
	if hit_called:
		for body: Body in _alive(attackers):
			if body.job == RoundPlan.LURK and not body.moving() and not map.site_cluster(site).has(body.place) \
					and (planted or time >= attack_plan.hit_at + 12.0):
				_send(body, site)
	# The bomb carrier died: the nearest attacker fetches it.
	if not planted and not bomb_place.is_empty() and not _anyone_has_bomb():
		var nearest: Body = null
		for body: Body in _alive(attackers):
			if not body.hidden and (nearest == null or map.distance(body.place, bomb_place) < map.distance(nearest.place, bomb_place)):
				nearest = body
		if nearest != null and (nearest.path.is_empty() or nearest.path.back() != bomb_place):
			nearest.path = _walk(nearest.place, bomb_place)
			nearest.progress = 0.0
	_think_attack_save()
	_think_defence()


func _think_attack_save() -> void:
	if planted or not hit_called:
		return
	var alive := _alive(attackers).filter(func(b: Body) -> bool: return not b.hidden)
	if alive.is_empty():
		return
	var closest := INF
	for body: Body in alive:
		closest = minf(closest, map.distance(body.place, site))
	if planners[attackers].attack_should_save(alive.size(), _alive(1 - attackers).size(), ROUND_TIME - time, closest):
		for body: Body in alive:
			body.hidden = true
			body.path.clear()


func _think_defence() -> void:
	var defence := 1 - attackers
	var plan := plans[defence]
	if planted:
		if retake_called.is_empty():
			var alive := _alive(defence)
			var furthest := 0.0
			for body: Body in alive:
				furthest = maxf(furthest, map.distance(body.place, site))
			retake_called = planners[defence].retake_or_save(alive.size(), _alive(attackers).size(),
				BOMB_TIMER - (time - planted_at), furthest, teams[defence].buy == &"full", teams[defence].money)
			for body: Body in alive:
				if retake_called == &"retake":
					# Retakers gather just outside the site before going in together.
					body.path = _walk(body.place, _staging(body.place))
					body.progress = 0.0
				else:
					body.hidden = true
					body.path.clear()
		elif retake_called == &"retake" and not retake_pushed:
			var alive := _alive(defence)
			var gathered := alive.all(func(b: Body) -> bool: return not b.moving())
			var furthest := 0.0
			for body: Body in alive:
				furthest = maxf(furthest, map.distance(body.place, bomb_place))
			var left := BOMB_TIMER - (time - planted_at)
			if gathered or left <= furthest / RoundPlanner.RUN_SPEED + DEFUSE_TIME + 3.0:
				retake_pushed = true
				for body: Body in alive:
					_send(body, site)
		return
	var seen := _attack_seen()
	for body: Body in _alive(defence):
		if body.rotated or body.moving():
			continue
		var destination := planners[defence].rotation_for(plan, body.player, seen, "")
		if not destination.is_empty():
			body.rotated = true
			_send(body, destination)


## Site -> attackers the defenders have seen or heard around it (fakers make extra noise once
## they start their fake).
func _attack_seen() -> Dictionary[String, int]:
	var seen: Dictionary[String, int] = {}
	var attack_plan := plans[attackers]
	for body: Body in _alive(attackers):
		if body.hidden:
			continue
		var near := _site_near(body.place)
		if near.is_empty():
			continue
		var watched := _alive(1 - attackers).any(func(d: Body) -> bool:
			return d.place == body.place or map.neighbours(d.place).has(body.place))
		if not watched:
			continue
		var noise := 1
		if body.job == RoundPlan.FAKER and time >= attack_plan.hit_at - 15.0 and not hit_called:
			noise = 2 + roundi(teams[attackers].utility / 40.0)
		seen[near] = int(seen.get(near, 0)) + noise
	return seen


## The site a place is on or leads straight into ("" between sites).
func _site_near(place: String) -> String:
	if _near_cache.has(place):
		return str(_near_cache[place])
	var found := ""
	for candidate: String in map.sites():
		if map.site_cluster(candidate).has(place):
			found = candidate
	if found.is_empty():
		for candidate: String in map.sites():
			if map.entrances(candidate).has(place) and RoundPlan._belongs_to(map, place, candidate):
				found = candidate
	_near_cache[place] = found
	return found


## The last place before the site on the way from [param from] to the bomb (where a retake gathers).
func _staging(from: String) -> String:
	var cluster := map.site_cluster(site)
	var walk := map.route(from, bomb_place)
	var last := from
	for place: String in walk:
		if cluster.has(place):
			break
		last = place
	return last


func _send(body: Body, target_site: String) -> void:
	var goal := target_site
	if body.team != attackers:
		# Retakes go to the bomb; rotations to the site's main hold.
		goal = bomb_place if planted and not bomb_place.is_empty() else planners[body.team].holds(target_site)[0]
	body.path = _walk(body.place, goal)
	body.progress = 0.0


func _walk(from: String, to: String) -> Array[String]:
	var walk := map.route(from, to)
	if walk.is_empty():
		return []
	return walk.slice(1)


# --- Fights ------------------------------------------------------------------------------------

## Every place where opponents meet this step becomes a fight.
func _fight() -> void:
	var places: Dictionary[String, bool] = {}
	for body: Body in bodies:
		if body.alive() and not body.hidden:
			places[body.place] = true
	for place: String in places:
		var duels := 0
		while duels < 3:
			var pair := _contact(place)
			if pair.is_empty():
				break
			_duel(pair[0], pair[1], place)
			duels += 1


## The next two opponents in contact at [param place]: both standing there, one holding it and
## the other walking into it from a neighbouring place, or standing in two places of the same site
## (a site is open ground: its areas see each other).
func _contact(place: String) -> Array[Body]:
	var here: Array[Body] = []
	var peekers: Array[Body] = []
	var open := _open_ground(place)
	for body: Body in bodies:
		if not body.alive() or body.hidden:
			continue
		if body.place == place:
			here.append(body)
		elif not body.path.is_empty() and body.path[0] == place and body.progress > 0.0 \
				and map.distance(body.place, place) - body.progress <= 10.0:
			peekers.append(body)
		elif open.has(body.place) and body.team == attackers:
			peekers.append(body)
	var everyone := here + peekers
	var best: Array[Body] = []
	var best_score := -INF
	for a: Body in everyone:
		for b: Body in everyone:
			if a.team != attackers or b.team == attackers:
				continue
			# Two players each only walking into the place have not met yet.
			if not here.has(a) and not here.has(b):
				continue
			var score := a.player.aggression + (2.0 if a.job == RoundPlan.ENTRY else 0.0) + b.player.skill(&"positioning") / 100.0 \
				- 0.4 * (a.player.round_kills + b.player.round_kills) + rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = [a, b]
	if not best.is_empty():
		_note_spotted(best[1])
	return best


## The other places of the site [param place] is on that border it ([] off the sites).
func _open_ground(place: String) -> Array[String]:
	var list: Array[String] = []
	if _open_cache.has(place):
		list.assign(_open_cache[place] as Array)
		return list
	var near := _site_near(place)
	if not near.is_empty() and map.site_cluster(near).has(place):
		var cluster := map.site_cluster(near)
		for other: String in map.neighbours(place):
			if cluster.has(other):
				list.append(other)
	_open_cache[place] = list.duplicate()
	return list


## Opponents [param body] can see from where they stand (their place and, on a site, its areas).
func _enemies_seen(body: Body) -> Array[Body]:
	var open := _open_ground(body.place)
	var list: Array[Body] = []
	for other: Body in bodies:
		if other.team != body.team and other.alive() and not other.hidden and (other.place == body.place or open.has(other.place)):
			list.append(other)
	return list


func _note_spotted(defender: Body) -> void:
	var near := _site_near(defender.place)
	if not near.is_empty():
		spotted[near] = maxi(int(spotted.get(near, 0)), _alive(1 - attackers).filter(func(d: Body) -> bool:
			return _site_near(d.place) == near).size())


## One exchange between an attacker and a defender at [param place]; teammates there help.
func _duel(attacker: Body, defender: Body, place: String) -> void:
	attacker.busy = true
	defender.busy = true
	var distance := _distance(place, attacker, defender)
	var a_ready := _ready_time(attacker, defender, place)
	var d_ready := _ready_time(defender, attacker, place)
	var order: Array[Body] = [attacker, defender]
	if d_ready < a_ready:
		order.reverse()
	var first := order[0]
	first.player.counts["first_shots"] += 1
	for burst: int in MAX_BURSTS * 2:
		var shooter := order[burst % 2]
		var target := order[(burst + 1) % 2]
		if not shooter.alive() or not target.alive():
			break
		var killer: Body = shooter if _shoot(shooter, target, distance, burst == 0) else null
		# A teammate holding the same place gets a shot in too (crossfire).
		if killer == null:
			for helper: Body in _helpers(shooter, place):
				if rng.randf() < 0.35 + (teams[helper.team].coordination - 50.0) / 200.0 and _shoot(helper, target, distance, false):
					killer = helper
					break
		if killer != null:
			_kill(killer, target)
			break


func _helpers(shooter: Body, place: String) -> Array[Body]:
	var list: Array[Body] = []
	for body: Body in bodies:
		if body != shooter and body.team == shooter.team and body.alive() and not body.hidden and body.place == place \
				and not body.moving():
			list.append(body)
	return list


## Seconds until [param body] fires at [param other]: reaction, plus crosshair placement and
## positioning for a holder, movement and the peeker's advantage for a peeker, and the day.
func _ready_time(body: Body, other: Body, place: String) -> float:
	var p := body.player
	var form := _form(body)
	var value := 0.32 - (p.skill(&"reaction") + form - 50.0) * REACTION_PER_POINT
	var holding := not body.moving()
	if holding:
		value -= (p.skill(&"crosshair_placement") + form - 50.0) * REACTION_PER_POINT
		value -= (p.skill(&"positioning") - 50.0) * REACTION_PER_POINT * 0.5
		# A holder who knows the attack is coming (game sense) is already looking at it.
		value -= (p.skill(&"game_sense") - 50.0) * REACTION_PER_POINT * 0.5
	else:
		value -= PEEKER_ADVANTAGE + (p.skill(&"movement") - 50.0) * REACTION_PER_POINT * 0.75
	# A coordinated execute's utility (flashes, smokes) slows the defenders on the site.
	if body.team != attackers and hit_called and plans[attackers].kind in [RoundPlan.EXECUTE, RoundPlan.SPLIT] \
			and map.site_cluster(site).has(place):
		value += maxf(0.0, teams[attackers].utility - teams[body.team].utility * 0.5) * 0.002
	# Someone who just saw a teammate die knows exactly where the killer is.
	if other.last_kill_time >= time - MatchStatistics.TRADE_SECONDS:
		value -= 0.05 + (teams[body.team].coordination - 50.0) * 0.001
	return value + rng.randfn(0.0, 0.07)


## One burst from [param shooter] at [param target]; true when it kills.
func _shoot(shooter: Body, target: Body, distance: float, opening_burst: bool) -> bool:
	var gun: Dictionary = WEAPONS[shooter.weapon]
	var p := shooter.player
	var form := _form(shooter)
	var skill := (0.5 * p.skill(&"aim") + 0.3 * p.skill(&"spray_control") + 0.2 * p.skill(&"crosshair_placement") + form) / 100.0
	var hit_chance := 0.22 + 0.5 * skill
	var reach := float(gun["range"])
	if distance > reach:
		hit_chance *= reach / distance
	if shooter.moving():
		hit_chance *= 0.55 + p.skill(&"movement") / 250.0
	if target.moving():
		hit_chance *= 0.88
	var head_chance := 0.06 + 0.2 * (0.5 * p.skill(&"aim") + 0.5 * p.skill(&"crosshair_placement") + form) / 100.0
	var armoured := 0 if target.armour else 1
	for bullet: int in int(gun["burst"]):
		p.counts["shots"] += 1
		if rng.randf() >= clampf(hit_chance, 0.03, 0.92):
			continue
		p.counts["hits"] += 1
		if opening_burst and bullet == 0:
			p.counts["first_hits"] += 1
		var head := rng.randf() < head_chance
		var damage := int((gun["head"] if head else gun["body"])[armoured])
		var dealt := mini(damage, target.hp)
		target.hp -= dealt
		p.counts["damage"] += dealt
		target.damage_from[p.id] = int(target.damage_from.get(p.id, 0)) + dealt
		if not target.alive():
			if head:
				p.counts["headshot_kills"] += 1
			return true
	return false


## How far apart the two are: across the place for those standing in it, or from the doorway.
func _distance(place: String, a: Body, b: Body) -> float:
	var room := clampf(sqrt(maxf(float(map.nodes.get(place, {}).get("floor", 40.0)), 1.0)) * 0.8, 6.0, 40.0)
	if a.place == b.place:
		return room * rng.randf_range(0.5, 1.0)
	return room * rng.randf_range(0.7, 1.2)


## Ability points from the day (form, the team's map and round, momentum, tilt, big rounds).
func _form(body: Body) -> float:
	var key := "%s|%d|%d" % [body.player.id, _alive_count(body.team), _alive_count(1 - body.team)]
	if not _form_cache.has(key):
		_form_cache[key] = engine.form_points(body.player, teams[body.team], _alive_count(body.team), _alive_count(1 - body.team), decisive)
	return _form_cache[key]


func _kill(killer: Body, victim: Body) -> void:
	var k := killer.player
	var v := victim.player
	v.alive = false
	v.counts["deaths"] += 1
	k.counts["kills"] += 1
	k.round_kills += 1
	k.contributed = true
	if _opening:
		_opening = false
		k.counts["opening_kills"] += 1
		v.counts["opening_deaths"] += 1
	# A trade: the victim had just killed one of the killer's teammates.
	if victim.last_kill_time >= time - MatchStatistics.TRADE_SECONDS:
		k.counts["trade_kills"] += 1
		for body: Body in bodies:
			if body.team == killer.team and not body.alive() and not body.player.traded and _killed_by.get(body.player.id, "") == v.id:
				body.player.traded = true
				body.player.counts["traded_deaths"] += 1
	_killed_by[v.id] = k.id
	killer.last_kill_time = time
	for id: String in victim.damage_from:
		if id != k.id and victim.damage_from[id] >= MatchStatistics.ASSIST_DAMAGE and _by_id.has(id):
			_by_id[id].player.counts["assists"] += 1
			_by_id[id].player.contributed = true
	if victim.has_bomb:
		victim.has_bomb = false
		bomb_place = victim.place
	victim.path.clear()
	_note_clutch()


func _note_clutch() -> void:
	if not clutch.is_empty():
		return
	for index: int in 2:
		var own := _alive(index)
		var other := _alive(1 - index)
		if own.size() == 1 and other.size() >= 2:
			var player := (own[0] as Body).player
			player.counts["clutch_attempts"] += 1
			clutch = {"player": player, "team": index, "against": other.size()}
			return


# --- Bomb and movement --------------------------------------------------------------------------

func _bomb() -> void:
	var cluster := map.site_cluster(site)
	if not planted:
		for body: Body in _alive(attackers):
			# Picking up a dropped bomb.
			if not bomb_place.is_empty() and body.place == bomb_place and not body.hidden and not _anyone_has_bomb():
				body.has_bomb = true
				bomb_place = ""
				if hit_called:
					_send(body, site)
			if body.has_bomb and cluster.has(body.place) and not body.busy and _enemies_seen(body).is_empty():
				body.busy = true
				body.path.clear()
				plant_progress += STEP
				if plant_progress >= PLANT_TIME:
					planted = true
					planted_at = time
					alive_at_plant = Vector2i(_alive(attackers).size(), _alive(1 - attackers).size())
					bomb_place = body.place
					body.has_bomb = false
					body.player.counts["plants"] += 1
					body.player.contributed = true
					# Post-plant: the others spread over the site's places to hold the bomb.
					var holds := planners[attackers].holds(site)
					var spot := 0
					for other: Body in _alive(attackers):
						if other != body and not other.hidden:
							spot += 1
							other.path = _walk(other.place, holds[spot % holds.size()])
							other.progress = 0.0
				return
		plant_progress = 0.0 if not _anyone_planting() else plant_progress
		return
	for body: Body in _alive(1 - attackers):
		if cluster.has(body.place) and not body.busy and _alive(attackers).filter(func(a: Body) -> bool:
				return cluster.has(a.place) and not a.hidden).is_empty():
			body.busy = true
			body.path.clear()
			defuse_progress += STEP
			if defuse_progress >= (DEFUSE_KIT_TIME if teams[body.team].buy == &"full" else DEFUSE_TIME):
				body.player.counts["defuses"] += 1
				body.player.contributed = true
			return
	defuse_progress = 0.0


func _move() -> void:
	for body: Body in bodies:
		if not body.alive() or body.busy or body.hidden or body.path.is_empty():
			continue
		var speed := RoundPlanner.RUN_SPEED * (0.8 if plans[body.team].kind == RoundPlan.DEFAULT and not hit_called else 1.0)
		var left := speed * STEP
		while left > 0.0 and not body.path.is_empty():
			var leg := maxf(map.distance(body.place, body.path[0]), 0.5)
			if body.progress + left < leg:
				body.progress += left
				left = 0.0
			else:
				left -= leg - body.progress
				body.place = body.path.pop_front()
				body.progress = 0.0
				# Stop on arrival where someone is waiting: the fight happens next step.
				if not _enemies_at(body).is_empty():
					break


func _ended() -> String:
	var defence_left := _alive(1 - attackers)
	if planted:
		if defuse_progress >= (DEFUSE_KIT_TIME if teams[1 - attackers].buy == &"full" else DEFUSE_TIME):
			return "defused"
		if time - planted_at >= BOMB_TIMER:
			return "detonated"
		if defence_left.is_empty():
			return "detonated"
		return ""
	if defence_left.is_empty():
		return "eliminated"
	if _alive(attackers).is_empty():
		return "eliminated"
	if time >= ROUND_TIME:
		return "time"
	return ""


# --- Helpers ------------------------------------------------------------------------------------

func _alive_count(team: int) -> int:
	var count := 0
	for body: Body in bodies:
		if body.team == team and body.hp > 0:
			count += 1
	return count


func _alive(team: int) -> Array[Body]:
	var list: Array[Body] = []
	for body: Body in bodies:
		if body.team == team and body.alive():
			list.append(body)
	return list


func _enemies_at(body: Body) -> Array[Body]:
	var list: Array[Body] = []
	for other: Body in bodies:
		if other.team != body.team and other.alive() and not other.hidden and other.place == body.place:
			list.append(other)
	return list


func _anyone_has_bomb() -> bool:
	return bodies.any(func(b: Body) -> bool: return b.alive() and b.has_bomb)


func _anyone_planting() -> bool:
	return bodies.any(func(b: Body) -> bool: return b.alive() and b.has_bomb and b.busy)
