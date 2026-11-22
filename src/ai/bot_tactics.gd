class_name BotTactics
extends RefCounted
## The in-game leader of one team of match bots. It is the career simulation's own
## [RoundPlanner] (pure career-sim logic, no database) fed with the bots' players, so a bot team
## in a match calls rounds the way the same team would in a simulated match: what kind of round
## (default, execute, split, rush, fake; standard, stack, aggressive), which site, who does which
## job (entry, trade, support, lurk, faker; anchor, rotator, aggressor), when a default round hits
## and where (on what the team has seen), when defenders rotate, and whether to retake or save.
## It learns from each round as in the simulation. The squad turns the calls into bot orders.

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
		player.role = StringName(str(entry.get("role", "rifler")))
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
