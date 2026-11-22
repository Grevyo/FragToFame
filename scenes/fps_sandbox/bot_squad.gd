class_name BotSquad
extends Node
## Spawns and drives the AI players of a match on top of [BotController]'s individual combat:
## buying, per-round placement, and simple objective play — attackers take one site and the
## carrier plants, defenders split between sites, everyone converges on a planted bomb and
## defenders defuse. Team tactics and the IGL replace this simple layer in Milestone 7.
##
## Utility and attack styles (Milestone 7 B, C): bots buy grenades on rifle rounds, and each
## round the attackers take their site in one of several styles ([AttackPlay]: rush, default
## with an off-the-cuff flash, execute, throw-and-go, supported entry, split from two lanes) with
## an entry pair double-peeking the entrance; defenders throw delay utility at attackers seen
## pushing near them. Every throw is solved against the map ([UtilityLineup]) and thrown by the
## bot as a player would, at its own pace.
##
## Calls (Milestone 7 C): each bot team has a leader ([BotTactics], the career simulation's own
## round planner) that calls every round: the attack's kind, site, jobs, lurker and map-control
## spots (a default round hits where the team has seen the fewest defenders), the defence's
## spots, rotations on what the team has seen, and retake or save after a plant. Attackers
## cover the planter and hold the site's entrances after a plant. The leaders learn round to
## round. A sandbox map without a simulation graph keeps the simple placement.

const CALLSIGNS: Array[String] = ["Ardent", "Basalt", "Cipher", "Drift", "Ember", "Flint", "Grit",
	"Halcyon", "Ion", "Jolt"]
const TEAM_KEYS: Array[StringName] = [&"home", &"away"]
const TEAM_COLORS: Array[Color] = [Color("b8542a"), Color("2e7d8c")]
const DECIDE_INTERVAL: float = 0.25
## Utility each side wants on a rifle round, in buying order.
const ATTACK_UTILITY: Array[StringName] = [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE,
	EquipmentCatalog.FLASH]
const DEFENCE_UTILITY: Array[StringName] = [EquipmentCatalog.FIRE, EquipmentCatalog.SMOKE, EquipmentCatalog.FRAG]


var director: MatchDirector
var bots: Dictionary[String, BotController] = {}
var skill_name: StringName = &"normal"
## Plant/defuse hold progress per bot ID (seconds).
var plant_progress: Dictionary[String, float] = {}
var defuse_progress: Dictionary[String, float] = {}
## Site the attackers go for this round.
var attack_site: String = ""
var rng := RandomNumberGenerator.new()
## Per-bot mechanics: from the lineup's abilities when the MatchSetup has a lineup, otherwise the
## squad's preset.
var skills: Dictionary[String, BotSkill] = {}

var _decide_timer: float = 0.0
## One shared picture per team (index): places cleared and enemies seen ([TeamKnowledge]).
var knowledge: Array[TeamKnowledge] = []
## This round's attack (null on maps without a simulation graph, or when no bot attacks: they
## walk straight in) and, for tests and tools, a style to force instead of choosing one.
var attack: AttackPlay = null
var forced_style: int = -1
## Each team's leader (by team index; null without a simulation graph or bots on that team).
var tactics: Array[BotTactics] = [null, null]
## Defence: bot ID -> site ID a rotation call sent it to.
var rotations: Dictionary[String, String] = {}
## After a plant: the defenders' retake (an attack from their spawn onto the bomb's site), or a save.
var retake: AttackPlay = null
var saving: bool = false
var _retake_called: bool = false
## The site the defence saw the attack go for (what its leader learns).
var _attacked_site: String = ""
var _sim_map: SimMap = null
## Defenders who already used their delay utility this round.
var _delayed: Dictionary[String, bool] = {}
## Line-ups must go off this close to their target (metres).
const LINEUP_TOLERANCE: float = 2.5
var _site_positions: Dictionary[String, Vector3] = {}
## Optional "ai_hold" hint pieces per bombsite letter (authored in the map editor).
var _hold_points: Dictionary[String, Array] = {}
## A defender takes a site's hold hint within this flat distance of its planned place.
const HOLD_REACH: float = 14.0


func _init(owner_director: MatchDirector, skill: StringName) -> void:
	director = owner_director
	skill_name = skill
	name = "BotSquad"
	rng.seed = hash(owner_director.state.setup.fixture_id)


## Registers bot players with the match state (call before the match starts). AI entries of the
## MatchSetup lineup come first (their player IDs, nicknames and abilities); any remaining slots
## are filled with generic callsign bots at the squad's skill preset.
func add_players(team_index: int, count: int) -> void:
	var added := 0
	for entry: Dictionary in director.state.setup.lineup(team_index):
		if added >= count:
			break
		if bool(entry.get("is_human", false)):
			continue
		var id := str(entry.get("player_id", ""))
		if id.is_empty() or director.state.players.has(id):
			continue
		director.state.add_player(id, str(entry.get("name", id)), team_index)
		skills[id] = BotSkill.from_abilities(entry.get("abilities", {}) as Dictionary)
		added += 1
	for i: int in range(added, count):
		var id := "bot_%s_%d" % [TEAM_KEYS[team_index], i + 1]
		var callsign := CALLSIGNS[(i + team_index * 5) % CALLSIGNS.size()]
		director.state.add_player(id, callsign, team_index)
		skills[id] = BotSkill.preset(skill_name)


## Creates a BotController for every bot player and reads the bombsites from the map.
func spawn_bots() -> void:
	for site: Dictionary in director.document.pieces_of_type("bombsite"):
		var letter := str(site.get("props", {}).get("site", "A"))
		# Raw centre: the navmesh may not be synced yet, goals are snapped when they are set.
		_site_positions[letter] = site["position"] as Vector3
		_hold_points[letter] = MapTactical.hints(director.document, "ai_hold", letter)
	# The map's places come from its simulation graph (map data, not the career database); a map
	# without one gives empty knowledge and the bots look along their paths.
	var sim_map := SimMap.for_map(director.document.map_id)
	_sim_map = sim_map
	knowledge = [TeamKnowledge.from_sim_map(sim_map), TeamKnowledge.from_sim_map(sim_map)]
	for id: String in director.state.players:
		var player_state := director.state.get_player(id)
		if player_state.is_human:
			continue
		var bot := BotController.new()
		bot.setup(id, player_state.display_name, TEAM_KEYS[player_state.team], skills[id] if skills.has(id) else BotSkill.preset(skill_name),
			director.state.setup.team_colour(player_state.team, TEAM_COLORS[player_state.team]))
		director.level.add_child(bot)
		bot.health.died.connect(_on_bot_died.bind(bot))
		bot.utility_finished.connect(_on_utility_finished.bind(bot))
		bot.knowledge = knowledge[player_state.team] if not knowledge[player_state.team].places.is_empty() else null
		bots[id] = bot
	var level: float = {&"easy": 35.0, &"normal": 55.0, &"hard": 80.0}.get(skill_name, 55.0)
	for team_index: int in 2:
		var ids: Array[String] = []
		for id: String in bots:
			if director.state.get_player(id).team == team_index:
				ids.append(id)
		tactics[team_index] = BotTactics.create(sim_map, ids, director.state.setup.lineup(team_index), level, rng)
	var everyone := healths()
	everyone.append(director.player.health)
	for bot: BotController in bots.values():
		bot.enemies = everyone


func healths() -> Array[Health]:
	var list: Array[Health] = []
	for bot: BotController in bots.values():
		list.append(bot.health)
	return list


func on_round_started() -> void:
	var state := director.state
	attack_site = _site_positions.keys()[rng.randi() % _site_positions.size()] if not _site_positions.is_empty() else ""
	plant_progress.clear()
	defuse_progress.clear()
	for team_knowledge: TeamKnowledge in knowledge:
		team_knowledge.reset()
	for team_index: int in 2:
		var side := state.teams[team_index].side
		var spawns := director.level.spawn_points(String(side))
		var is_home := team_index == MatchState.HOME
		var first_spawn := director.human_spawn_index(spawns.size()) if is_home else 0
		var slot := 1 if is_home else 0
		for id: String in state.teams[team_index].player_ids:
			if not bots.has(id):
				continue
			_buy(id)
			var spawn := spawns[(first_spawn + slot) % spawns.size()]
			var offset := Vector3(0.9 * floorf(float(slot) / spawns.size()), 0, 0)
			slot += 1
			var bot := bots[id]
			bot.respawn_at((spawn[0] as Vector3) + offset, float(spawn[1]))
			var player_state := state.get_player(id)
			bot.weapons.set_loadout(player_state.loadout())
			bot.health.armour = player_state.armour
			bot.health.has_helmet = player_state.helmet
			bot.frozen = true
	_call_round()
	plan_attack()
	_decide_timer = 0.0


func on_round_ended() -> void:
	var winner := director.state.last_round_winner
	for team_index: int in 2:
		if tactics[team_index] != null:
			tactics[team_index].learn(winner == team_index, _attacked_site)
	for id: String in bots:
		var bot := bots[id]
		if bot.is_alive():
			director.state.set_player_armour(id, bot.health.armour, bot.health.has_helmet)


func freeze_all() -> void:
	for bot: BotController in bots.values():
		bot.frozen = true
		bot.interact_held = false


func physics_update(delta: float) -> void:
	var state := director.state
	var frozen := state.phase == MatchState.Phase.FREEZE or state.phase == MatchState.Phase.MATCH_END
	for bot: BotController in bots.values():
		bot.frozen = frozen
	if frozen:
		return
	for team_knowledge: TeamKnowledge in knowledge:
		team_knowledge.advance(delta)
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = DECIDE_INTERVAL
		_decide()
	_update_bomb_actions(delta)


# --- Decisions -------------------------------------------------------------------------------

func _decide() -> void:
	_advance_attack()
	_advance_defence()
	_defender_delay()
	var state := director.state
	var attack_spawn := director.level.spawn_point("attack")[0] as Vector3
	var defence_spawn := director.level.spawn_point("defence")[0] as Vector3
	var dropped_runner := _closest_attacker_to(state.bomb_position) if state.is_bomb_dropped else ""
	var defence_index := 0
	var attack_index := 0
	var carrier: BotController = bots.get(state.bomb_carrier_id)
	var planting := carrier != null and carrier.is_alive() and carrier.interact_held
	for id: String in bots:
		var bot := bots[id]
		if not bot.is_alive():
			continue
		var side := state.side_of(id)
		var spread := _spread_offset(id)
		if side == MatchRules.SIDE_ATTACK:
			attack_index += 1
			if state.is_bomb_planted:
				_cover_order(bot, attack_index, state.bomb_position)
			elif planting and id != state.bomb_carrier_id and bot.global_position.distance_to(carrier.global_position) < 20.0:
				# The planter is covered: hold the ways in while the bomb goes down.
				_cover_order(bot, attack_index, carrier.global_position)
			elif id == dropped_runner:
				bot.set_goal(_on_navmesh(state.bomb_position))
			elif not _follow_order(bot, spread) and _site_positions.has(attack_site):
				bot.set_goal(_on_navmesh(_site_positions[attack_site] + (Vector3.ZERO if id == state.bomb_carrier_id else spread)))
				bot.set_watch_point(defence_spawn + Vector3(0, 1.5, 0))
			bot.interact_held = id == state.bomb_carrier_id and state.phase == MatchState.Phase.LIVE \
				and not MapZones.bombsite_at(director.document, bot.global_position).is_empty() \
				and bot.is_on_floor() and not bot.sees_enemy()
		else:
			if state.is_bomb_planted and saving:
				# A save: keep the gun for the next round, away from the bomb.
				bot.set_goal(_on_navmesh(defence_spawn + spread))
				bot.set_watch_point(state.bomb_position + Vector3(0, 1.5, 0))
				bot.interact_held = false
			elif state.is_bomb_planted and retake != null and not retake.is_going() and _follow_play(retake, bot, spread):
				bot.interact_held = false
			elif state.is_bomb_planted:
				bot.set_goal(_on_navmesh(state.bomb_position))
				bot.interact_held = _flat_distance(bot.global_position, state.bomb_position) <= MatchDirector.DEFUSE_RADIUS - 0.2 \
					and not bot.sees_enemy()
			elif _defence_order(bot, spread):
				bot.interact_held = false
			else:
				var letters := _site_positions.keys()
				var watch := attack_spawn + Vector3(0, 1.5, 0)
				if not letters.is_empty():
					var letter: String = letters[defence_index % letters.size()]
					var holds: Array = _hold_points.get(letter, [])
					if holds.is_empty():
						bot.set_goal(_on_navmesh(_site_positions[letter] + spread))
					else:
						# Authored hold point: stand on it and watch along its facing.
						var hold: Dictionary = holds[floori(float(defence_index) / letters.size()) % holds.size()]
						bot.set_goal(_on_navmesh(hold["position"] as Vector3))
						watch = MapTactical.hint_watch_point(hold)
				defence_index += 1
				bot.set_watch_point(watch)
				bot.interact_held = false


func _update_bomb_actions(delta: float) -> void:
	var state := director.state
	for id: String in bots:
		var bot := bots[id]
		if not bot.is_alive() or state.phase != MatchState.Phase.LIVE:
			plant_progress[id] = 0.0
			defuse_progress[id] = 0.0
			continue
		var side := state.side_of(id)
		if state.is_bomb_dropped and side == MatchRules.SIDE_ATTACK \
				and _flat_distance(bot.global_position, state.bomb_position) <= MatchDirector.BOMB_PICKUP_RADIUS:
			state.pick_up_bomb(id)
		var planting := bot.interact_held and side == MatchRules.SIDE_ATTACK and id == state.bomb_carrier_id \
			and not state.is_bomb_planted
		var defusing := bot.interact_held and side == MatchRules.SIDE_DEFENCE and state.is_bomb_planted \
			and _flat_distance(bot.global_position, state.bomb_position) <= MatchDirector.DEFUSE_RADIUS
		plant_progress[id] = plant_progress.get(id, 0.0) + delta if planting else 0.0
		defuse_progress[id] = defuse_progress.get(id, 0.0) + delta if defusing else 0.0
		if planting and plant_progress[id] >= state.rules.plant_time:
			plant_progress[id] = 0.0
			bot.interact_held = false
			state.plant_bomb(id, bot.global_position)
		elif defusing and defuse_progress[id] >= state.defuse_duration(id):
			defuse_progress[id] = 0.0
			bot.interact_held = false
			state.defuse_bomb(id)


## Simple economy: AK-47 when affordable with armour, SKS as a cheaper option, then armour,
## then a kit for defenders with money to spare.
func _buy(id: String) -> void:
	var state := director.state
	var me := state.get_player(id)
	if me.primary == &"":
		if me.money >= ShopCatalog.price(WeaponCatalog.AK47) + ShopCatalog.price(ShopCatalog.ARMOUR_VEST):
			state.buy(id, WeaponCatalog.AK47)
		elif me.money >= ShopCatalog.price(WeaponCatalog.SKS) + ShopCatalog.price(ShopCatalog.ARMOUR_VEST):
			state.buy(id, WeaponCatalog.SKS)
	if me.armour < ShopCatalog.FULL_ARMOUR or not me.helmet:
		if me.money >= ShopCatalog.price(ShopCatalog.ARMOUR_VEST_HELMET):
			state.buy(id, ShopCatalog.ARMOUR_VEST_HELMET)
		elif me.armour < ShopCatalog.FULL_ARMOUR and me.money >= ShopCatalog.price(ShopCatalog.ARMOUR_VEST):
			state.buy(id, ShopCatalog.ARMOUR_VEST)
	if state.side_of(id) == MatchRules.SIDE_DEFENCE and me.money >= ShopCatalog.price(ShopCatalog.DEFUSE_KIT) + 1000:
		state.buy(id, ShopCatalog.DEFUSE_KIT)
	# Utility on rifle rounds only (a pistol round's money goes on armour).
	if me.primary == &"":
		return
	for item: StringName in ATTACK_UTILITY if state.side_of(id) == MatchRules.SIDE_ATTACK else DEFENCE_UTILITY:
		if me.money >= ShopCatalog.price(item):
			state.buy(id, item)


# --- Utility -----------------------------------------------------------------------------------

## A new round: the attackers' play for it (only when bots attack).
func plan_attack() -> void:
	attack = null
	_delayed.clear()
	var attackers := _living_attackers()
	if attack_site.is_empty() or attackers.is_empty() or _sim_map == null:
		return
	var utility := 0
	var flashes := 0
	for bot: BotController in attackers:
		for item: StringName in EquipmentCatalog.UTILITY:
			utility += bot.weapons.utility_count(item)
		flashes += bot.weapons.utility_count(EquipmentCatalog.FLASH)
	var entrances := _sim_map.entrances("site_" + attack_site).size()
	var leader := leader_of(MatchRules.SIDE_ATTACK)
	var details: Dictionary = {}
	var style: AttackPlay.Style
	if leader != null:
		style = leader.style_for(leader.plan)
		details = _attack_details(leader, forced_style < 0)
	else:
		style = AttackPlay.choose_style(rng, attackers.size(), utility, flashes, entrances)
	if forced_style >= 0:
		style = forced_style as AttackPlay.Style
	attack = AttackPlay.create(style, _sim_map, attack_site, _hold_points.get(attack_site, []), attackers,
		director.level.get_world_3d().direct_space_state, rng, director.state.bomb_carrier_id, details)


## Moves the play on. Contact with the enemy, a dropped or planted bomb or the clock running
## down sends everyone in at once. A default round's leader calls the hit when it is time (or on
## contact), on the site where the team has seen the fewest defenders.
func _advance_attack() -> void:
	var state := director.state
	if attack == null or state.phase != MatchState.Phase.LIVE:
		return
	var attackers := _living_attackers()
	var contact := attackers.any(func(bot: BotController) -> bool: return bot.target != null)
	var cut_short := attackers.is_empty() or state.is_bomb_planted or state.is_bomb_dropped or state.phase_time_left < 30.0 or contact
	var leader := leader_of(MatchRules.SIDE_ATTACK)
	if leader != null:
		var team_knowledge := knowledge[state.team_on_side(MatchRules.SIDE_ATTACK)]
		leader.note_seen(team_knowledge)
		if attack.in_map_control() and (state.live_elapsed >= leader.plan.hit_at or cut_short):
			_call_hit(leader, team_knowledge)
	attack.carrier_id = state.bomb_carrier_id
	attack.update(DECIDE_INTERVAL, cut_short)


## The leader's call on a default round: hit the site with the fewest defenders seen.
func _call_hit(leader: BotTactics, team_knowledge: TeamKnowledge) -> void:
	var letter := leader.letter_of(leader.planner.call_hit(leader.plan, leader.seen_at(team_knowledge)))
	if letter != attack_site and _site_positions.has(letter):
		attack_site = letter
		var details := _attack_details(leader, false)
		var moved := AttackPlay.create(AttackPlay.Style.DEFAULT, _sim_map, attack_site, _hold_points.get(attack_site, []),
			_living_attackers(), director.level.get_world_3d().direct_space_state, rng, director.state.bomb_carrier_id, details)
		if moved != null:
			attack = moved
	attack.start_approach()


# --- Calls ---------------------------------------------------------------------------------------

## Each bot team's leader calls the round: the attack's site and kind, the defence's setup.
func _call_round() -> void:
	rotations.clear()
	retake = null
	saving = false
	_retake_called = false
	_attacked_site = ""
	var state := director.state
	for team_index: int in 2:
		var leader := tactics[team_index]
		if leader == null:
			continue
		var side := state.teams[team_index].side
		var ids: Array[String] = []
		for id: String in bots:
			if state.get_player(id).team == team_index and bots[id].is_alive():
				ids.append(id)
		var call := leader.plan_round(side, _situation(team_index), ids)
		if side == MatchRules.SIDE_ATTACK and _site_positions.has(leader.letter_of(call.site)):
			attack_site = leader.letter_of(call.site)


## The leader of the team on [param side] once it has called this round on that side (else null).
func leader_of(side: StringName) -> BotTactics:
	var leader := tactics[director.state.team_on_side(side)]
	return leader if leader != null and leader.plan != null and leader.plan.side == side else null


## What the leader knows when calling: the round, the score, both teams' money.
func _situation(team_index: int) -> RoundPlanner.Situation:
	var state := director.state
	var situation := RoundPlanner.Situation.new()
	situation.round_index = state.rounds_played()
	situation.own_score = state.teams[team_index].score
	situation.their_score = state.teams[1 - team_index].score
	situation.to_win = state.setup.rounds_to_win()
	situation.buy = _buy_kind(team_index)
	# A team that lost the last two rounds is expected to be saving.
	situation.their_buy = &"eco" if state.teams[1 - team_index].loss_streak >= 2 and state.rounds_played() > 0 else &"full"
	situation.round_time = state.rules.round_time
	return situation


## "pistol", "eco", "force" or "full" from what the team's bots carry.
func _buy_kind(team_index: int) -> StringName:
	var state := director.state
	var count := 0
	var rifles := 0
	for id: String in state.teams[team_index].player_ids:
		count += 1
		if state.get_player(id).primary != &"":
			rifles += 1
	if state.rounds_played() == 0:
		return &"pistol"
	if rifles == 0:
		return &"eco"
	return &"full" if rifles >= ceili(count * 0.6) else &"force"


## The leader's plan as [AttackPlay] details: jobs, the lurker's spot, a default round's
## map-control spots (when [param with_spots]) and a fake's other site.
func _attack_details(leader: BotTactics, with_spots: bool) -> Dictionary:
	var call := leader.plan
	var jobs: Dictionary[String, StringName] = {}
	var lurkers: Dictionary[String, Array] = {}
	var spots: Dictionary[String, Vector3] = {}
	for id: String in call.jobs:
		if not bots.has(id):
			continue
		jobs[id] = call.jobs[id]
		var spot := leader.centre(str(call.spots.get(id, "")))
		if call.jobs[id] == RoundPlan.LURK and with_spots:
			lurkers[id] = [spot, _nearest_site_centre(spot) + Vector3(0, 1.5, 0)]
		elif call.kind == RoundPlan.DEFAULT and with_spots:
			spots[id] = spot
	var fake_letter := leader.letter_of(call.fake_site) if not call.fake_site.is_empty() else ""
	return {"jobs": jobs, "lurkers": lurkers, "spots": spots, "fake_site": fake_letter,
		"fake_holds": _hold_points.get(fake_letter, [])}


func _nearest_site_centre(point: Vector3) -> Vector3:
	var best := point
	for letter: String in _site_positions:
		if best == point or _site_positions[letter].distance_to(point) < best.distance_to(point):
			best = _site_positions[letter]
	return best


## The letter of the site nearest [param point] ("" when the map has none).
func _site_letter_at(point: Vector3) -> String:
	var best := ""
	for letter: String in _site_positions:
		if best.is_empty() or _site_positions[letter].distance_to(point) < _site_positions[best].distance_to(point):
			best = letter
	return best


## Defence: rotations on what the team has seen, and after a plant the retake-or-save call.
func _advance_defence() -> void:
	var state := director.state
	var leader := leader_of(MatchRules.SIDE_DEFENCE)
	if leader == null or state.phase != MatchState.Phase.LIVE:
		return
	var team_index := state.team_on_side(MatchRules.SIDE_DEFENCE)
	var seen := leader.seen_at(knowledge[team_index])
	var most := 0
	for site: String in seen:
		if seen[site] > most:
			most = seen[site]
			_attacked_site = site
	var planted_at := ""
	if state.is_bomb_planted:
		planted_at = "site_" + _site_letter_at(state.bomb_position)
		_attacked_site = planted_at
	for id: String in bots:
		if not bots[id].is_alive() or state.side_of(id) != MatchRules.SIDE_DEFENCE or not leader.players.has(id):
			continue
		var called := leader.planner.rotation_for(leader.plan, leader.players[id], seen, planted_at)
		if not called.is_empty():
			rotations[id] = called
	if state.is_bomb_planted and not _retake_called:
		_retake_called = true
		_call_retake(leader, team_index)
	if retake != null:
		var defenders := _living_defenders()
		var contact := defenders.any(func(bot: BotController) -> bool: return bot.target != null)
		retake.update(DECIDE_INTERVAL, contact or state.bomb_time_left < 16.0)


## Retake together, or save the guns, as the leader judges the numbers, time and money.
func _call_retake(leader: BotTactics, team_index: int) -> void:
	var state := director.state
	var defenders := _living_defenders()
	if defenders.is_empty():
		return
	var furthest := 0.0
	var kit := false
	var money := 1 << 30
	for bot: BotController in defenders:
		furthest = maxf(furthest, bot.global_position.distance_to(state.bomb_position))
		kit = kit or state.get_player(bot.bot_id).has_kit
		money = mini(money, state.get_player(bot.bot_id).money)
	var call := leader.planner.retake_or_save(defenders.size(), state.alive_count(1 - team_index), state.bomb_time_left,
		furthest, kit, money)
	if call != &"retake":
		saving = true
		return
	var letter := _site_letter_at(state.bomb_position)
	var style := AttackPlay.Style.EXECUTE_TOGETHER if leader.team.coordination < 55.0 else AttackPlay.Style.EXECUTE
	retake = AttackPlay.create(style, _sim_map, letter, _hold_points.get(letter, []), defenders,
		director.level.get_world_3d().direct_space_state, rng, "", {"from": _sim_map.spawn("defence")})


func _living_defenders() -> Array[BotController]:
	var list: Array[BotController] = []
	for id: String in bots:
		if bots[id].is_alive() and director.state.side_of(id) == MatchRules.SIDE_DEFENCE:
			list.append(bots[id])
	return list


## A defender's spot from the leader's call: a rotation, else the planned place (an authored
## hold hint there when the map has one, facing along it).
func _defence_order(bot: BotController, spread: Vector3) -> bool:
	var leader := leader_of(MatchRules.SIDE_DEFENCE)
	if leader == null:
		return false
	var place := str(leader.plan.spots.get(bot.bot_id, ""))
	if rotations.has(bot.bot_id):
		place = rotations[bot.bot_id]
	if place.is_empty():
		return false
	var spot := leader.centre(place)
	var letter := str(_sim_map.nodes.get(place, {}).get("site", ""))
	var watch := director.level.spawn_point("attack")[0] as Vector3 + Vector3(0, 1.5, 0)
	var best_hold: Dictionary = {}
	var best_distance := HOLD_REACH
	for hold: Dictionary in _hold_points.get(letter, []):
		var at := hold["position"] as Vector3
		var distance := Vector2(at.x - spot.x, at.z - spot.z).length()
		if distance <= best_distance and not _hold_taken(bot, at):
			best_hold = hold
			best_distance = distance
	if not best_hold.is_empty():
		bot.set_goal(_on_navmesh(best_hold["position"] as Vector3))
		bot.set_watch_point(MapTactical.hint_watch_point(best_hold))
	else:
		bot.set_goal(_on_navmesh(spot + spread * 0.5))
		var site_id := "site_" + letter if not letter.is_empty() else ""
		var doors: Array[String] = []
		if _sim_map.nodes.has(site_id):
			doors = _sim_map.entrances(site_id)
		if not doors.is_empty():
			watch = leader.centre(doors[0]) + Vector3(0, 1.5, 0)
		bot.set_watch_point(watch)
	return true


## Whether another living defender is already heading for the hold at [param at].
func _hold_taken(bot: BotController, at: Vector3) -> bool:
	for other: BotController in bots.values():
		if other != bot and not other.health.is_dead and other.has_goal \
				and director.state.side_of(other.bot_id) == MatchRules.SIDE_DEFENCE \
				and Vector2(other.goal_position.x - at.x, other.goal_position.z - at.z).length() < 1.0:
			return true
	return false


## Where an attacker covers from once the bomb is going down or down: around the bomb, facing
## one of the site's entrances (spread over them by bot).
func _cover_order(bot: BotController, index: int, around: Vector3) -> void:
	var letter := _site_letter_at(around)
	var doors: Array[String] = []
	if _sim_map != null and _sim_map.nodes.has("site_" + letter):
		doors = _sim_map.entrances("site_" + letter)
	if doors.is_empty():
		bot.set_goal(_on_navmesh(around + _spread_offset(bot.bot_id) * 2.0))
		return
	var door := _sim_map.nodes[doors[index % doors.size()]]["centre"] as Vector3
	var out := door - around
	var reach := minf(7.0, out.length() * 0.6)
	bot.set_goal(_on_navmesh(around + Vector3(out.x, 0.0, out.z).normalized() * reach))
	bot.set_watch_point(door + Vector3(0, 1.5, 0))





## Sets [param bot]'s goal from its part in the attack. False when it has none (push the site).
func _follow_order(bot: BotController, spread: Vector3) -> bool:
	return attack != null and _follow_play(attack, bot, spread)


func _follow_play(play: AttackPlay, bot: BotController, spread: Vector3) -> bool:
	var order := play.order_for(bot)
	if order.is_empty():
		return false
	if order.get("hold", false):
		bot.set_goal(bot.global_position)
	else:
		var goal := order["goal"] as Vector3
		bot.set_goal(_on_navmesh(goal + (spread if order.get("spread", false) else Vector3.ZERO)))
	if order.has("watch"):
		bot.set_watch_point(order["watch"] as Vector3)
	return true


func _living_attackers() -> Array[BotController]:
	var list: Array[BotController] = []
	for id: String in bots:
		if bots[id].is_alive() and director.state.side_of(id) == MatchRules.SIDE_ATTACK:
			list.append(bots[id])
	return list


## [param bot] throws [param utility] at [param target] if the map allows a line-up from where it
## stands. Returns true when the throw started.
func _throw_now(bot: BotController, utility: StringName, target: Vector3) -> bool:
	var space := director.level.get_world_3d().direct_space_state
	var lineup := UtilityLineup.solve(space, utility, bot.head.global_position, target, LINEUP_TOLERANCE,
		bot.weapons.exclude)
	return lineup != null and bot.throw_utility(lineup)


## A grenade left a bot's hand (or a throw was given up): the attack's timing hangs on it.
func _on_utility_finished(utility: StringName, thrown: bool, bot: BotController) -> void:
	if attack != null:
		attack.on_utility_finished(bot, utility, thrown)
	if retake != null:
		retake.on_utility_finished(bot, utility, thrown)


## Defenders throw delay utility (fire, then frag, then smoke) at attackers a teammate has just
## seen pushing near them, once a round each (one solve per decision at most).
func _defender_delay() -> void:
	var state := director.state
	if state.phase != MatchState.Phase.LIVE or state.is_bomb_planted:
		return
	for id: String in bots:
		var bot := bots[id]
		if not bot.is_alive() or _delayed.has(id) or state.side_of(id) != MatchRules.SIDE_DEFENCE \
				or bot.target != null or bot.is_throwing() or bot.knowledge == null:
			continue
		var push := Vector3.INF
		for sighting: Dictionary in bot.knowledge.sightings:
			var at := sighting["position"] as Vector3
			if bot.knowledge.now - float(sighting["time"]) <= 1.5 and at.distance_to(bot.global_position) <= 28.0:
				push = at
				break
		if push == Vector3.INF:
			continue
		_delayed[id] = true
		for utility: StringName in [EquipmentCatalog.FIRE, EquipmentCatalog.FRAG, EquipmentCatalog.SMOKE]:
			if bot.weapons.utility_count(utility) > 0:
				_throw_now(bot, utility, push)
				break
		return


func _closest_attacker_to(point: Vector3) -> String:
	var best := ""
	var best_distance := INF
	for id: String in bots:
		var bot := bots[id]
		if bot.is_alive() and director.state.side_of(id) == MatchRules.SIDE_ATTACK:
			var distance := bot.global_position.distance_to(point)
			if distance < best_distance:
				best = id
				best_distance = distance
	return best


## Horizontal distance with a vertical tolerance (bots stop at goals by flat distance, and the
## bomb may sit at a player's origin rather than on the navmesh).
static func _flat_distance(a: Vector3, b: Vector3) -> float:
	if absf(a.y - b.y) > 1.2:
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


func _spread_offset(id: String) -> Vector3:
	var angle := float(hash(id) % 628) / 100.0
	return Vector3(cos(angle), 0, sin(angle)) * 1.8


func _on_navmesh(point: Vector3) -> Vector3:
	var map := director.level.get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, point)


func _on_bot_died(info: DamageInfo, bot: BotController) -> void:
	director.state.record_kill(bot.bot_id, info.source_id, info.weapon_id, info.is_headshot(), bot.global_position)
