class_name BotTactics
extends RefCounted
## The in-game leader of one team of match bots. It is the career simulation's own
## [RoundPlanner] (pure career-sim logic, no database) fed with the bots' players, so a bot team
## in a match calls rounds the way the same team would in a simulated match: what kind of round
## (default, execute, split, rush, fake; standard, stack, aggressive), which site, who does which
## job (entry, trade, support, lurk, faker; anchor, rotator, aggressor), when a default round hits
## and where (on what the team has seen), when defenders rotate, and whether to retake or save.
## It learns from each round as in the simulation. The squad turns the calls into bot orders.
##
## Mid-round (Milestone 7 D) it reads how the round is going and makes [TeamCall]s, at most one
## of each kind a round: attackers save when the numbers or the clock are against them (the
## simulation's own [method RoundPlanner.attack_should_save]), take the other site when they find
## a stack before committing, and regroup when the entry pair falls at the door; defenders
## regroup outside a site that has fallen, to retake it together instead of one by one.
##
## Buying (Milestone 7 E) is the team's call too, as in the simulation ([SimEconomy]): from the
## money the bots hold between them the leader calls pistol, eco, force or full; each bot buys
## for its role (entries' flashes, supports' smokes and fire, a sniper's rifle), players with
## money to spare drop a rifle for a teammate who cannot afford one, and some defenders buy kits.

## Attackers who lose this many as their push starts, still outside the site, regroup.
const REGROUP_LOSSES: int = 2
## The push's first seconds, where losses count towards a regroup.
const PUSH_WINDOW: float = 10.0
## Sightings within this distance of a site's places count as players seen at that site.
const SEEN_RADIUS: float = 14.0
const SEEN_WITHIN: float = 4.0

var map: SimMap
var planner: RoundPlanner
var team: MatchEngine.SimTeam
var players: Dictionary[String, MatchEngine.SimPlayer] = {}
## This round's plan (null before the first round).
var plan: RoundPlan = null
## Attack: the most opponents seen at once around each site this round (what the leader learns).
var found: Dictionary[String, int] = {}
var rng: RandomNumberGenerator
## This round's buy call: "pistol", "eco", "force" or "full" ("" before the first buy).
var buy_call: StringName = &""
## Roles for bots with no lineup entry (the sandbox's), in order, so a team has a leader,
## entries and support.
const FALLBACK_ROLES: Array[StringName] = [&"igl", &"entry", &"support", &"rifler", &"lurker"]
## Kinds of [TeamCall] already made this round.
var called: Dictionary[TeamCall.Kind, bool] = {}


## A leader for the bots [param ids] from their [param lineup] entries ({player_id, role,
## abilities}); players without one play at [param fallback_ability] in every ability (the
## sandbox's skill presets).
static func create(sim_map: SimMap, ids: Array[String], lineup: Array[Dictionary], fallback_ability: float,
		dice: RandomNumberGenerator) -> BotTactics:
	if sim_map == null or ids.is_empty():
		return null
	var tactics := BotTactics.new()
	tactics.map = sim_map
	tactics.rng = dice
	tactics.team = MatchEngine.SimTeam.new()
	var by_id: Dictionary[String, Dictionary] = {}
	for entry: Dictionary in lineup:
		by_id[str(entry.get("player_id", ""))] = entry
	for id: String in ids:
		var player := MatchEngine.SimPlayer.new()
		player.id = id
		var entry: Dictionary = by_id.get(id, {})
		player.role = StringName(str(entry.get("role", FALLBACK_ROLES[tactics.team.players.size() % FALLBACK_ROLES.size()])))
		var abilities: Dictionary = entry.get("abilities", {})
		if abilities.is_empty():
			for key: StringName in CareerCatalog.ABILITIES:
				abilities[String(key)] = fallback_ability
		player.skills = abilities
		tactics.team.players.append(player)
		tactics.players[id] = player
	MatchEngine.new(dice).prepare_team(tactics.team)
	tactics.planner = RoundPlanner.new(sim_map, tactics.team, dice)
	return tactics


## Calls this round for the living bots [param ids] on [param side].
func plan_round(side: StringName, situation: RoundPlanner.Situation, ids: Array[String]) -> RoundPlan:
	var living: Array[MatchEngine.SimPlayer] = []
	for id: String in ids:
		if players.has(id):
			living.append(players[id])
	found.clear()
	called.clear()
	plan = planner.plan_attack(situation, living) if side == MatchRules.SIDE_ATTACK else planner.plan_defence(situation, living)
	return plan


## The bots' attack style for an attack plan: the plan's kind, and for an execute the way this
## team executes (well-drilled teams wait for the full set, aggressive ones throw and go,
## utility-heavy ones send a pair in behind their supports).
func style_for(attack: RoundPlan) -> AttackPlay.Style:
	match attack.kind:
		RoundPlan.DEFAULT:
			return AttackPlay.Style.DEFAULT
		RoundPlan.RUSH:
			return AttackPlay.Style.RUSH
		RoundPlan.SPLIT:
			return AttackPlay.Style.SPLIT
		RoundPlan.FAKE:
			return AttackPlay.Style.FAKE
	var aggression := 0.0
	for player: MatchEngine.SimPlayer in team.players:
		aggression += player.aggression / maxf(team.players.size(), 1.0)
	var weights: Dictionary[AttackPlay.Style, float] = {
		AttackPlay.Style.EXECUTE: pow(team.coordination / 55.0, 2.0) * 1.4,
		AttackPlay.Style.EXECUTE_TOGETHER: pow(aggression, 2.0),
		AttackPlay.Style.SUPPORTED_ENTRY: pow(team.utility / 55.0, 2.0) if team.players.size() >= 3 else 0.0,
	}
	var total := 0.0
	for weight: float in weights.values():
		total += weight
	var roll := rng.randf() * total
	for key: AttackPlay.Style in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return AttackPlay.Style.EXECUTE


## The team's buy for the round. [param carried] is bot ID → what it holds now ({"money",
## "primary", "secondary", "armour", "helmet", "kit", "utility": Array[StringName]});
## [param their_money] the opponents' average. Returns the purchases to make, in order, each
## {"buyer", "for", "item"} ("for" another bot is a drop); [member buy_call] holds the call.
func team_buy(carried: Dictionary[String, Dictionary], side: StringName, pistol: bool, their_money: float,
		loss_streak: int) -> Array[Dictionary]:
	var buyers: Array[MatchEngine.SimPlayer] = []
	for id: String in carried:
		if not players.has(id):
			continue
		var player := players[id]
		var held: Dictionary = carried[id]
		player.money = int(held.get("money", 0))
		player.primary = StringName(str(held.get("primary", "")))
		player.secondary = StringName(str(held.get("secondary", WeaponCatalog.DEFAULT_SECONDARY)))
		player.armour = int(held.get("armour", 0))
		player.helmet = bool(held.get("helmet", false))
		player.kit = bool(held.get("kit", false))
		player.grenades.assign(held.get("utility", []))
		buyers.append(player)
	var buying := MatchEngine.SimTeam.new()
	buying.players = buyers
	buying.loss_streak = loss_streak
	var economy_side := "attack" if side == MatchRules.SIDE_ATTACK else "defence"
	buy_call = SimEconomy.call_buy(buying, economy_side, pistol, their_money)
	SimEconomy.buy(buying, economy_side, buy_call)
	var orders: Array[Dictionary] = []
	orders.assign(SimEconomy.receipts.duplicate(true))
	return orders


## The ID of the player who leads the team's calls.
func leader_id() -> String:
	var leader := planner.in_game_leader()
	return leader.id if leader != null else ""


## Attack, mid-round: the leader's read of the round (null: carry on).
## [param site_letter] is the site the play goes for, [param committed] whether the hit is on
## (not still taking map control early), [param going] whether the push has started.
## [param seen] is site ID → defenders seen there; [param metres] site ID → how far the team is.
## [param lost_in_push] counts attackers lost in the push's first seconds while
## [param outside_site] says nobody has got onto the site yet.
func adapt_attack(site_letter: String, committed: bool, going: bool, seen: Dictionary[String, int], alive: int,
		defenders_alive: int, seconds_left: float, metres: Dictionary[String, float], lost_in_push: int,
		outside_site: bool) -> TeamCall:
	var site_id := "site_" + site_letter
	var to_site := float(metres.get(site_id, 0.0))
	if committed and not called.has(TeamCall.Kind.SAVE) \
			and planner.attack_should_save(alive, defenders_alive, seconds_left, to_site):
		return _made(TeamCall.make(TeamCall.Kind.SAVE, "", "",
			"%d against %d with %d s left" % [alive, defenders_alive, roundi(seconds_left)]))
	if not going and not called.has(TeamCall.Kind.EXECUTE) and plan != null \
			and plan.kind != RoundPlan.RUSH and plan.kind != RoundPlan.FAKE:
		var other := planner.call_hit(plan, seen)
		# A careful leader turns away from two defenders, a bold one from three.
		var stack := 2 if planner.caution() >= 0.0 else 3
		var here := int(seen.get(site_id, 0))
		if other != site_id and here >= stack and here - int(seen.get(other, 0)) >= 2 \
				and seconds_left > float(metres.get(other, 0.0)) / RoundPlanner.RUN_SPEED + 30.0:
			return _made(TeamCall.make(TeamCall.Kind.EXECUTE, letter_of(other), "", "%d on %s" % [here, site_letter]))
	if going and outside_site and lost_in_push >= REGROUP_LOSSES and alive >= 3 \
			and not called.has(TeamCall.Kind.REGROUP) and seconds_left > to_site / RoundPlanner.RUN_SPEED + 35.0:
		return _made(TeamCall.make(TeamCall.Kind.REGROUP, site_letter, "", "lost %d at the door" % lost_in_push))
	return null


## Defence, mid-round: [param fallen] is a site ID the attackers hold with none of the team left
## on it ("" when none), before any plant. With two or more alive the leader gathers them
## outside it to retake together (null: carry on).
func adapt_defence(fallen: String, alive: int) -> TeamCall:
	if fallen.is_empty() or alive < 2 or called.has(TeamCall.Kind.REGROUP):
		return null
	return _made(TeamCall.make(TeamCall.Kind.REGROUP, letter_of(fallen), "", "%s has fallen" % letter_of(fallen)))


func _made(call: TeamCall) -> TeamCall:
	called[call.kind] = true
	return call


## The place nearest [param position] (for a play that starts from where the team is).
func place_near(position: Vector3) -> String:
	var best := ""
	var best_distance := INF
	for id: String in map.nodes:
		var distance := centre(id).distance_to(position)
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


## The bombsite letter of a site place ID ("site_A" → "A").
func letter_of(site_id: String) -> String:
	return str(map.nodes.get(site_id, {}).get("site", site_id.trim_prefix("site_")))


## The position of a place.
func centre(place_id: String) -> Vector3:
	return map.nodes.get(place_id, {}).get("centre", Vector3.ZERO) as Vector3


## Site ID → opponents a teammate saw around it in the last few seconds.
func seen_at(knowledge: TeamKnowledge) -> Dictionary[String, int]:
	var seen: Dictionary[String, int] = {}
	if knowledge == null:
		return seen
	for site: String in map.sites():
		var places := map.site_cluster(site) + map.entrances(site)
		var count := 0
		for sighting: Dictionary in knowledge.sightings:
			if knowledge.now - float(sighting["time"]) > SEEN_WITHIN:
				continue
			var at := sighting["position"] as Vector3
			if places.any(func(id: String) -> bool: return centre(id).distance_to(at) <= SEEN_RADIUS):
				count += 1
		if count > 0:
			seen[site] = count
	return seen


## Attack: remembers the most defenders seen at once around each site (for [method learn]).
func note_seen(knowledge: TeamKnowledge) -> void:
	var seen := seen_at(knowledge)
	for site: String in seen:
		found[site] = maxi(int(found.get(site, 0)), seen[site])


## The round is over: the leader learns what happened, as in the simulation.
func learn(won: bool, attacked_site: String) -> void:
	if plan == null:
		return
	if plan.side == MatchRules.SIDE_ATTACK:
		planner.learn_attack(plan, won, found, false)
	else:
		planner.learn_defence(attacked_site)
