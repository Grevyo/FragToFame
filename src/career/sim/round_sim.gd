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
## - Fights: bursts are exchanged with each player's own weapon ([SimEconomy]; damage, fire rate,
##   armour penetration, falloff and spread from [WeaponCatalog]); every bullet hits on aim, spray
##   control, distance and movement, lands on a body zone (a headshot on aim and crosshair
##   placement) and goes through [DamageModel]'s armour rules. Damage and armour carry over between
##   fights. Teammates in the same place join in: crossfires, and kills on a fresh killer are trades.
## - Utility: each player throws the grenades they bought, as well as their utility skill lets them.
##   Attackers smoke off the defenders' way in and the site's other holds when they hit, and burn
##   out a hold; whoever walks into a place with enemies in it flashes or frags it first; defenders
##   burn and smoke the way in the attack is coming through. Flashes blind the named players they
##   catch (turning away from it is game sense), smokes block sight between places and slow fights
##   in them, fire burns whoever stands in it and holds up a push, frags damage everyone in reach.
## - The bomb: the carrier plants on the site when no defender is there; if they die, the nearest
##   attacker picks it up. A defender on the site alone defuses (faster with a kit).
## - Events: everything that happens is logged through [method MatchEngine.record] in the FPS
##   runtime's event format (shot, damage, utility_thrown, flashed, kill, bomb_planted,
##   bomb_defused), and [MatchStatistics] builds every statistic from that stream, as it does for a
##   played match. The round keeps no counters of its own.

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
## Where a hit lands when it is not the head (the rest of the body, by how much of it shows).
const BODY_ZONES: Array[Array] = [[DamageModel.ZONE_CHEST, 0.45], [DamageModel.ZONE_STOMACH, 0.25],
	[DamageModel.ZONE_ARMS, 0.15], [DamageModel.ZONE_LEGS, 0.15]]
## Seconds a smoke stays thick enough to block sight.
const SMOKE_SECONDS: float = 17.5
## A throw worse than this misses its spot (a smoke that blocks nothing, a flash that hits no one).
const POOR_THROW: float = 0.25

static var _guns: Dictionary[StringName, Dictionary] = {}


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
	var armour: int = 0
	var helmet: bool = false
	var kit: bool = false
	var weapon: StringName = WeaponCatalog.DEFAULT_SECONDARY
	var grenades: Array[StringName] = []
	## Blind until this time into the round.
	var blind_until: float = -INF
	## Reasons this player has already thrown for this round ("hit", "delay").
	var threw: Dictionary[String, bool] = {}
	var has_bomb: bool = false
	## Left the fight (saving their weapon).
	var hidden: bool = false
	## Stays put this step (fighting, planting, defusing).
	var busy: bool = false
	var rotated: bool = false
	var last_kill_time: float = -INF

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
## Place -> time its smoke clears.
var smokes: Dictionary[String, float] = {}
## Place -> {"until": time the fire burns out, "by": Body who threw it}.
var fires: Dictionary[String, Dictionary] = {}
## Place -> last time a flash or frag went into it.
var _cleared: Dictionary[String, float] = {}
var _defuser_kit: bool = false
var _form_cache: Dictionary[String, float] = {}
## Whether the last killing bullet [method _shoot] fired was a headshot.
var _headshot_kill: bool = false
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
		_utility()
		_burn()
		_fight()
		_bomb()
		_move()
		how = _ended()
	var winner := attackers if how == "detonated" or (how == "eliminated" and _alive(1 - attackers).is_empty()) else 1 - attackers
	var rotated := false
	var dropped: Array[StringName] = []
	for body: Body in bodies:
		rotated = rotated or (body.team != attackers and body.rotated)
		# Survivors keep what they carry; the dead leave their rifle on the floor.
		if body.alive():
			body.player.armour = body.armour
			body.player.grenades = body.grenades.duplicate()
		elif not body.player.primary.is_empty():
			dropped.append(body.player.primary)
	return {"winner": winner, "how": how, "planted": planted, "site": site, "clutch": clutch, "spotted": spotted.duplicate(),
		"rotated": rotated, "retake": str(retake_called), "alive_at_plant": alive_at_plant, "seconds": time, "dropped": dropped}


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
			body.weapon = player.primary if not player.primary.is_empty() else player.secondary
			body.armour = player.armour
			body.helmet = player.helmet
			body.kit = player.kit
			body.grenades = player.grenades.duplicate()
			bodies.append(body)
	# The bomb goes to a support or trade player, never the lurker or the entry.
	var carrier: Body = null
	for body: Body in _alive(attackers):
		if carrier == null or _carry_preference(body) > _carry_preference(carrier):
			carrier = body
	if carrier != null:
		carrier.has_bomb = true


func _carry_preference(body: Body) -> int:
	return {RoundPlan.SUPPORT: 3, RoundPlan.TRADE: 2, RoundPlan.FAKER: 1}.get(body.job, 0)


## A weapon as the simulation shoots it, from [WeaponCatalog]: damage, armour penetration,
## falloff, standing and running spread, and the bullets one burst (about a third of a second) fires.
static func gun(id: StringName) -> Dictionary:
	if _guns.has(id):
		return _guns[id]
	var data: Dictionary = WeaponCatalog.DATA.get(id, WeaponCatalog.DATA[WeaponCatalog.DEFAULT_SECONDARY])
	var made := {"damage": float(data["damage"]), "penetration": float(data["armour_penetration"]),
		"falloff": float(data["falloff_per_10m"]), "spread": float(data["base_spread"]), "run_spread": float(data["run_spread"]),
		"burst": clampi(roundi(float(data["rpm"]) / 220.0), 1, 3)}
	_guns[id] = made
	return made


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
				BOMB_TIMER - (time - planted_at), furthest, alive.any(func(b: Body) -> bool: return b.kit), teams[defence].money)
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
	_think_personal_save()
	var seen := _attack_seen()
	for body: Body in _alive(defence):
		if body.rotated or body.moving():
			continue
		var destination := planners[defence].rotation_for(plan, body.player, seen, "")
		if not destination.is_empty():
			body.rotated = true
			_send(body, destination)


## A last defender facing three or more with a rifle worth keeping may hide and keep it: the
## careful and less confident do; clutch players and the composed play it out.
func _think_personal_save() -> void:
	var defenders := _alive(1 - attackers)
	if defenders.size() != 1 or defenders[0].hidden or defenders[0].player.primary.is_empty():
		return
	var last := defenders[0]
	var against := _alive(attackers).filter(func(b: Body) -> bool: return not b.hidden).size()
	var nerve := 1.5 + last.player.skill(&"composure") / 50.0 + last.player.trait_strength(&"tr_clutch_player") \
		+ 0.5 * last.player.trait_strength(&"tr_risk_taker") - 0.5 * last.player.trait_strength(&"tr_cautious")
	if against >= 3 and float(against) > nerve:
		last.hidden = true
		last.path.clear()


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
		elif open.has(body.place) and body.team == attackers and not _smoked(body.place) and not _smoked(place):
			# Across a site, unless a smoke stands between.
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
	for burst: int in MAX_BURSTS * 2:
		var shooter := order[burst % 2]
		var target := order[(burst + 1) % 2]
		if not shooter.alive() or not target.alive():
			break
		var killer: Body = shooter if _shoot(shooter, target, distance) else null
		# A teammate holding the same place gets a shot in too (crossfire).
		if killer == null:
			for helper: Body in _helpers(shooter, place):
				if rng.randf() < 0.35 + (teams[helper.team].coordination - 50.0) / 200.0 and _shoot(helper, target, distance):
					killer = helper
					break
		if killer != null:
			_kill(killer, target, killer.weapon, _headshot_kill)
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
	# Blind players wait for their eyes; smoke hides the first sight of each other.
	if body.blind_until > time:
		value += minf(body.blind_until - time, 1.5)
	if _smoked(place):
		value += 0.25
	# Someone who just saw a teammate die knows exactly where the killer is.
	if other.last_kill_time >= time - MatchStatistics.TRADE_SECONDS:
		value -= 0.05 + (teams[body.team].coordination - 50.0) * 0.001
	return value + rng.randfn(0.0, 0.07)


## One burst from [param shooter] at [param target], every bullet logged; true when it kills
## ([member _headshot_kill] then says whether the last bullet was a headshot).
func _shoot(shooter: Body, target: Body, distance: float) -> bool:
	var weapon := gun(shooter.weapon)
	var p := shooter.player
	var form := _form(shooter)
	var skill := (0.5 * p.skill(&"aim") + 0.3 * p.skill(&"spray_control") + 0.2 * p.skill(&"crosshair_placement") + form) / 100.0
	var hit_chance := 0.22 + 0.5 * skill
	# The weapon's own spread grows the miss with distance.
	hit_chance *= clampf(1.0 - float(weapon["spread"]) * distance / 10.0, 0.25, 1.0)
	if shooter.moving():
		hit_chance *= (0.8 + p.skill(&"movement") / 250.0) / (1.0 + float(weapon["run_spread"]) * 0.12)
	if target.moving():
		hit_chance *= 0.88
	if shooter.blind_until > time:
		hit_chance *= 0.15
	if _smoked(shooter.place) or _smoked(target.place):
		hit_chance *= 0.5
	var head_chance := 0.06 + 0.2 * (0.5 * p.skill(&"aim") + 0.5 * p.skill(&"crosshair_placement") + form) / 100.0
	for bullet: int in int(weapon["burst"]):
		_log("shot", {"player": p.id, "weapon": String(shooter.weapon)})
		if rng.randf() >= clampf(hit_chance, 0.03, 0.92):
			continue
		var zone := DamageModel.ZONE_HEAD if rng.randf() < head_chance else _body_zone()
		var amount := roundi(float(weapon["damage"]) * DamageModel.zone_multiplier(zone) * pow(float(weapon["falloff"]), distance / 10.0))
		if _hurt(shooter, target, amount, float(weapon["penetration"]), zone, shooter.weapon):
			_headshot_kill = zone == DamageModel.ZONE_HEAD
			return true
	return false


func _body_zone() -> StringName:
	var roll := rng.randf()
	for zone: Array in BODY_ZONES:
		roll -= float(zone[1])
		if roll <= 0.0:
			return zone[0]
	return DamageModel.ZONE_CHEST


## Deals [param amount] to [param target] through their armour; true when it kills (the kill is
## recorded with [param weapon] only for grenades: gunfire kills are recorded by the duel).
func _hurt(attacker: Body, target: Body, amount: int, penetration: float, zone: StringName, weapon: StringName) -> bool:
	if not target.alive():
		return false
	var split := DamageModel.armour_split(amount, penetration, zone, target.armour, target.helmet)
	target.armour = maxi(target.armour - split[1], 0)
	var dealt := mini(split[0], target.hp)
	target.hp -= dealt
	if attacker.team != target.team and dealt > 0:
		var data := {"player": attacker.player.id, "victim": target.player.id, "hp": dealt, "weapon": String(weapon),
			"headshot": zone == DamageModel.ZONE_HEAD}
		if EquipmentCatalog.is_utility(weapon):
			data["utility"] = true
		_log("damage", data)
	if target.alive():
		return false
	if EquipmentCatalog.is_utility(weapon):
		_kill(attacker, target, weapon)
	return true


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


## A kill, logged as the runtime logs one; [MatchStatistics] works out openings, trades, assists
## and flash assists from the stream.
func _kill(killer: Body, victim: Body, weapon: StringName, headshot: bool = false) -> void:
	var k := killer.player
	var v := victim.player
	v.alive = false
	k.round_kill_weapons.append(weapon)
	k.round_kills += 1
	_log("kill", {"victim": v.id, "killer": k.id, "weapon": String(weapon), "headshot": headshot})
	killer.last_kill_time = time
	if victim.has_bomb:
		victim.has_bomb = false
		bomb_place = victim.place
	victim.path.clear()
	_note_clutch()


## Logs [param type] at this moment of the round.
func _log(type: String, data: Dictionary) -> void:
	engine.record(type, time, data)


func _note_clutch() -> void:
	if not clutch.is_empty():
		return
	for index: int in 2:
		var own := _alive(index)
		var other := _alive(1 - index)
		if own.size() == 1 and other.size() >= 2:
			var player := (own[0] as Body).player
			clutch = {"player": player, "team": index, "against": other.size()}
			return


# --- Utility -----------------------------------------------------------------------------------

## Grenades this step: the attack's smokes and fire as it hits, flashes and frags before walking
## into enemies, the defence's fire and smoke on the way in the attack is using.
func _utility() -> void:
	if hit_called and not planted:
		_hit_utility()
	for body: Body in bodies:
		if body.alive() and not body.hidden and body.moving() and body.blind_until <= time:
			_clear_ahead(body)
	if not planted:
		_delay_utility()


## As the attack goes in: smoke off the defenders' way in and the site's other holds, burn a hold.
func _hit_utility() -> void:
	var targets := _smoke_targets()
	var smoke_index := 0
	for body: Body in _alive(attackers):
		if body.hidden or body.threw.has("hit") or body.job == RoundPlan.LURK:
			continue
		body.threw["hit"] = true
		if body.grenades.has(EquipmentCatalog.SMOKE) and smoke_index < targets.size():
			var quality := _throw(body, EquipmentCatalog.SMOKE)
			if quality >= POOR_THROW:
				smokes[targets[smoke_index]] = time + SMOKE_SECONDS
			smoke_index += 1
		if body.grenades.has(EquipmentCatalog.FIRE):
			var hold := _held_place(site)
			if not hold.is_empty():
				var quality := _throw(body, EquipmentCatalog.FIRE)
				if quality >= POOR_THROW:
					fires[hold] = {"until": time + _fire_seconds(), "by": body}


## Places a hit smokes, most useful first: the way defenders come from their spawn, then the
## site's holds other than the main one.
func _smoke_targets() -> Array[String]:
	var list: Array[String] = []
	var cluster := map.site_cluster(site)
	var from_spawn := map.route(map.spawn("defence"), site)
	for i: int in range(from_spawn.size() - 1, 0, -1):
		if cluster.has(from_spawn[i]) and not cluster.has(from_spawn[i - 1]):
			list.append(from_spawn[i - 1])
			break
	var holds := planners[attackers].holds(site)
	for place: String in holds.slice(1):
		list.append(place)
	return list


## A site place a defender is standing in ("" when none is seen).
func _held_place(site_id: String) -> String:
	var cluster := map.site_cluster(site_id)
	for body: Body in _alive(1 - attackers):
		if cluster.has(body.place) and not body.moving():
			return body.place
	return ""


## Before walking into a place with enemies in sight, a flash (or a frag) goes in first, thrown by
## the walker or a teammate beside them.
func _clear_ahead(body: Body) -> void:
	var ahead: String = body.path[0]
	if time - float(_cleared.get(ahead, -INF)) < 4.0:
		return
	var enemies := _enemies_in(ahead, body.team)
	if enemies.is_empty():
		return
	var thrower := _teammate_with(body, EquipmentCatalog.FLASH)
	if thrower != null:
		_cleared[ahead] = time
		_flash(thrower, enemies)
		return
	thrower = _teammate_with(body, EquipmentCatalog.FRAG)
	if thrower != null:
		_cleared[ahead] = time
		_frag(thrower, enemies)


## Defenders on a site burn or smoke the way in attackers are gathering at, to hold the push up.
func _delay_utility() -> void:
	for body: Body in _alive(1 - attackers):
		if body.hidden or body.moving() or body.threw.has("delay"):
			continue
		var near := _site_near(body.place)
		if near.is_empty() or not map.site_cluster(near).has(body.place):
			continue
		for way: String in map.neighbours(body.place):
			if map.site_cluster(near).has(way) or _enemies_in(way, body.team).size() < 2:
				continue
			for id: StringName in [EquipmentCatalog.FIRE, EquipmentCatalog.SMOKE]:
				if not body.grenades.has(id):
					continue
				body.threw["delay"] = true
				var quality := _throw(body, id)
				if quality >= POOR_THROW:
					if id == EquipmentCatalog.FIRE:
						fires[way] = {"until": time + _fire_seconds(), "by": body}
					else:
						smokes[way] = time + SMOKE_SECONDS
				return


## Takes a grenade from [param body]'s pockets and returns how well it was thrown (0..1): their
## utility skill (and being a utility expert), with the usual spread of a throw under pressure.
func _throw(body: Body, id: StringName) -> float:
	body.grenades.erase(id)
	_log("utility_thrown", {"player": body.player.id, "item": String(id)})
	var skill := body.player.skill(&"utility") / 100.0 + 0.08 * body.player.trait_strength(&"tr_utility_expert")
	return clampf(rng.randfn(skill, 0.18), 0.0, 1.0)


## A flash blinds each enemy caught by it for up to the flashbang's full blindness: less for a poor
## throw, and less for those who turn away in time (game sense).
func _flash(thrower: Body, enemies: Array[Body]) -> void:
	var quality := _throw(thrower, EquipmentCatalog.FLASH)
	if quality < POOR_THROW:
		return
	var flash := EquipmentCatalog.params(EquipmentCatalog.FLASH)
	var full := float(flash.get("max_blind", 4.8))
	for enemy: Body in enemies:
		var turned := clampf(enemy.player.skill(&"game_sense") / 200.0 + rng.randf() * 0.4, 0.0, 1.0 - float(flash.get("behind_share", 0.22)))
		var seconds := full * quality * (1.0 - turned)
		if seconds >= 0.8:
			enemy.blind_until = maxf(enemy.blind_until, time + seconds)
			_log("flashed", {"player": thrower.player.id, "victim": enemy.player.id, "seconds": snappedf(seconds, 0.01), "enemy": true})


func _frag(thrower: Body, enemies: Array[Body]) -> void:
	var quality := _throw(thrower, EquipmentCatalog.FRAG)
	var frag := EquipmentCatalog.params(EquipmentCatalog.FRAG)
	var reach := float(frag.get("radius", 7.5))
	var penetration := float(EquipmentCatalog.DATA[EquipmentCatalog.FRAG].get("armour_penetration", 0.55))
	for enemy: Body in enemies:
		var distance := rng.randf_range(1.0, reach) * (1.0 - 0.6 * quality)
		var amount := roundi(float(frag.get("damage", 98)) * maxf(0.0, 1.0 - distance / reach))
		if amount > 0:
			_hurt(thrower, enemy, amount, penetration, DamageModel.ZONE_CHEST, EquipmentCatalog.FRAG)


## Fire burns whoever stands in it (they get out as fast as they can: about half a step in it).
func _burn() -> void:
	var fire := EquipmentCatalog.params(EquipmentCatalog.FIRE)
	var dps := float(fire.get("dps", 38.0))
	for place: String in fires.keys():
		var burning: Dictionary = fires[place]
		if float(burning["until"]) <= time:
			fires.erase(place)
			continue
		var thrower: Body = burning["by"]
		for body: Body in bodies:
			if body.alive() and not body.hidden and body.place == place and body.team != thrower.team:
				_hurt(thrower, body, roundi(dps * STEP * 0.5), 1.0, DamageModel.ZONE_LEGS, EquipmentCatalog.FIRE)
				# A holder steps off the fire to another spot on the site.
				if body.alive() and not body.moving() and body.team != attackers:
					var near := _site_near(place)
					if not near.is_empty():
						for spot: String in planners[body.team].holds(near):
							if spot != place:
								body.path = _walk(place, spot)
								body.progress = 0.0
								break


func _fire_seconds() -> float:
	return float(EquipmentCatalog.params(EquipmentCatalog.FIRE).get("duration", 7.0))


func _burning(place: String) -> bool:
	return fires.has(place) and float(fires[place]["until"]) > time


func _smoked(place: String) -> bool:
	return float(smokes.get(place, -INF)) > time


## Enemies of [param team] standing in [param place] or seen from it across a site.
func _enemies_in(place: String, team: int) -> Array[Body]:
	var open := _open_ground(place)
	var list: Array[Body] = []
	for other: Body in bodies:
		if other.team != team and other.alive() and not other.hidden and (other.place == place or (open.has(other.place)
				and not _smoked(other.place))):
			list.append(other)
	return list


## [param body] or a teammate in the same place who still has [param id] (body first).
func _teammate_with(body: Body, id: StringName) -> Body:
	if body.grenades.has(id):
		return body
	for other: Body in bodies:
		if other != body and other.team == body.team and other.alive() and not other.hidden and other.place == body.place \
				and other.grenades.has(id) and other.blind_until <= time:
			return other
	return null


func _defuse_needed() -> float:
	return DEFUSE_KIT_TIME if _defuser_kit else DEFUSE_TIME


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
					_log("bomb_planted", {"player": body.player.id})
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
			_defuser_kit = body.kit
			if defuse_progress >= _defuse_needed():
				_log("bomb_defused", {"player": body.player.id})
			return
	defuse_progress = 0.0


func _move() -> void:
	for body: Body in bodies:
		if not body.alive() or body.busy or body.hidden or body.path.is_empty():
			continue
		# Nobody walks into fire unless the round will not wait: a rush, or a retake on the clock.
		if _burning(body.path[0]) and not (body.team == attackers and plans[attackers].kind == RoundPlan.RUSH) \
				and not (planted and body.team != attackers and retake_pushed):
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
		if defuse_progress >= _defuse_needed() and defuse_progress > 0.0:
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
