class_name BotSquad
extends Node
## Spawns and drives the AI players of a match on top of [BotController]'s individual combat:
## buying, per-round placement, and simple objective play — attackers take one site and the
## carrier plants, defenders split between sites, everyone converges on a planted bomb and
## defenders defuse. Team tactics and the IGL replace this simple layer in Milestone 7.
##
## Utility (Milestone 7 B): bots buy grenades on rifle rounds. Attackers gather before the
## entrance of their site ([SiteExecute]), smoke the hold nearest it and the defenders' rotation,
## burn the next hold, flash in over the entrance and go in together; defenders throw delay
## utility at attackers seen pushing near them. Every throw is solved against the map
## ([UtilityLineup]) and thrown by the bot as a player would.

const CALLSIGNS: Array[String] = ["Ardent", "Basalt", "Cipher", "Drift", "Ember", "Flint", "Grit",
	"Halcyon", "Ion", "Jolt"]
const TEAM_KEYS: Array[StringName] = [&"home", &"away"]
const TEAM_COLORS: Array[Color] = [Color("b8542a"), Color("2e7d8c")]
const DECIDE_INTERVAL: float = 0.25
## Execute timing (seconds): give up gathering, give up on utility, go after the flash.
const GATHER_LIMIT: float = 14.0
const UTILITY_LIMIT: float = 12.0
const GO_AFTER_FLASH: float = 0.45
## Bots within this distance of the staging place count as gathered; utility is thrown from there.
const GATHERED_RADIUS: float = 6.0
## Line-ups must go off this close to their target (metres).
const LINEUP_TOLERANCE: float = 2.5
## Utility each side wants on a rifle round, in buying order.
const ATTACK_UTILITY: Array[StringName] = [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE,
	EquipmentCatalog.FLASH]
const DEFENCE_UTILITY: Array[StringName] = [EquipmentCatalog.FIRE, EquipmentCatalog.SMOKE, EquipmentCatalog.FRAG]

enum Execute { NONE, GATHER, UTILITY, GO }

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
## This round's take of the attack site (null on maps without a simulation graph: walk straight
## in) and where it stands.
var execute: SiteExecute = null
var execute_phase: Execute = Execute.NONE
var _sim_map: SimMap = null
var _phase_time: float = 0.0
## Throws still to make this execute: {utility: StringName, target: Vector3}.
var _pending_throws: Array[Dictionary] = []
var _smoked_at: float = -1.0
var _flashed_at: float = -1.0
## Defenders who already used their delay utility this round.
var _delayed: Dictionary[String, bool] = {}
## A throw that had no line-up from the staging place: its thrower walks to the entrance's throw
## spot to try from there ("" when none).
var _walker_id: String = ""
var _walk_throw: Dictionary = {}
var _site_positions: Dictionary[String, Vector3] = {}
## Optional "ai_hold" hint pieces per bombsite letter (authored in the map editor).
var _hold_points: Dictionary[String, Array] = {}


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
		bot.utility_finished.connect(_on_utility_finished)
		bot.knowledge = knowledge[player_state.team] if not knowledge[player_state.team].places.is_empty() else null
		bots[id] = bot
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
	_plan_execute()
	_decide_timer = 0.0


func on_round_ended() -> void:
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
	_phase_time += delta
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = DECIDE_INTERVAL
		_decide()
	_update_bomb_actions(delta)


# --- Decisions -------------------------------------------------------------------------------

func _decide() -> void:
	_advance_execute()
	_defender_delay()
	var state := director.state
	var attack_spawn := director.level.spawn_point("attack")[0] as Vector3
	var defence_spawn := director.level.spawn_point("defence")[0] as Vector3
	var dropped_runner := _closest_attacker_to(state.bomb_position) if state.is_bomb_dropped else ""
	var defence_index := 0
	for id: String in bots:
		var bot := bots[id]
		if not bot.is_alive():
			continue
		var side := state.side_of(id)
		var spread := _spread_offset(id)
		if side == MatchRules.SIDE_ATTACK:
			if state.is_bomb_planted:
				bot.set_goal(_on_navmesh(state.bomb_position + spread * 2.0))
				bot.set_watch_point(defence_spawn + Vector3(0, 1.5, 0))
			elif id == dropped_runner:
				bot.set_goal(_on_navmesh(state.bomb_position))
			elif execute_phase == Execute.GATHER or execute_phase == Execute.UTILITY:
				if id == _walker_id:
					bot.set_goal(_on_navmesh(execute.throw_spot))
					bot.set_watch_point(execute.entrance + Vector3(0, 1.5, 0))
				elif not bot.is_throwing():
					bot.set_goal(_on_navmesh(execute.staging + spread))
					bot.set_watch_point(execute.entrance + Vector3(0, 1.5, 0))
			elif _site_positions.has(attack_site):
				bot.set_goal(_on_navmesh(_site_positions[attack_site] + (Vector3.ZERO if id == state.bomb_carrier_id else spread)))
				bot.set_watch_point(defence_spawn + Vector3(0, 1.5, 0))
			bot.interact_held = id == state.bomb_carrier_id and state.phase == MatchState.Phase.LIVE \
				and not MapZones.bombsite_at(director.document, bot.global_position).is_empty() \
				and bot.is_on_floor() and not bot.sees_enemy()
		else:
			if state.is_bomb_planted:
				bot.set_goal(_on_navmesh(state.bomb_position))
				bot.interact_held = _flat_distance(bot.global_position, state.bomb_position) <= MatchDirector.DEFUSE_RADIUS - 0.2 \
					and not bot.sees_enemy()
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

## A new round: plan the take of this round's attack site (only when bots attack).
func _plan_execute() -> void:
	execute = null
	execute_phase = Execute.NONE
	_phase_time = 0.0
	_pending_throws.clear()
	_smoked_at = -1.0
	_flashed_at = -1.0
	_delayed.clear()
	_walker_id = ""
	_walk_throw = {}
	if attack_site.is_empty() or _living_attackers().is_empty():
		return
	execute = SiteExecute.plan(_sim_map, attack_site, _hold_points.get(attack_site, []))
	if execute == null:
		return
	execute_phase = Execute.GATHER
	for point: Vector3 in execute.smokes:
		_pending_throws.append({"utility": EquipmentCatalog.SMOKE, "target": point})
	if execute.fire != Vector3.INF:
		_pending_throws.append({"utility": EquipmentCatalog.FIRE, "target": execute.fire})
	if execute.flash != Vector3.INF:
		_pending_throws.append({"utility": EquipmentCatalog.FLASH, "target": execute.flash})


## Gather, then utility, then go. Contact with the enemy, a dropped bomb or the clock cuts it short.
func _advance_execute() -> void:
	if execute_phase == Execute.NONE or execute_phase == Execute.GO:
		return
	var state := director.state
	if state.phase == MatchState.Phase.FREEZE:
		_phase_time = 0.0
		return
	var attackers := _living_attackers()
	if attackers.is_empty() or state.is_bomb_planted or state.is_bomb_dropped or state.phase != MatchState.Phase.LIVE \
			or state.phase_time_left < 30.0 or attackers.any(func(bot: BotController) -> bool: return bot.target != null):
		execute_phase = Execute.GO
		return
	match execute_phase:
		Execute.GATHER:
			var gathered := attackers.all(func(bot: BotController) -> bool:
				return _flat_distance(bot.global_position, execute.staging) <= GATHERED_RADIUS)
			if gathered or _phase_time > GATHER_LIMIT:
				execute_phase = Execute.UTILITY
				_phase_time = 0.0
		Execute.UTILITY:
			if _phase_time > UTILITY_LIMIT or (_flashed_at >= 0.0 and _phase_time - _flashed_at >= GO_AFTER_FLASH):
				execute_phase = Execute.GO
				return
			if attackers.any(func(bot: BotController) -> bool: return bot.is_throwing()):
				return
			if not _walker_id.is_empty():
				_walk_and_throw()
				return
			if _pending_throws.is_empty():
				if _flashed_at < 0.0:
					execute_phase = Execute.GO
				return
			# The flash waits for the smokes to bloom.
			var next: Dictionary = _pending_throws[0]
			if next["utility"] == EquipmentCatalog.FLASH and _smoked_at >= 0.0 and _phase_time - _smoked_at < 1.2:
				return
			_pending_throws.pop_front()
			var utility := next["utility"] as StringName
			var carrier := _carrier(attackers, utility)
			if carrier != null and not _throw_now(carrier, utility, next["target"] as Vector3):
				# No line-up from here: walk up to the entrance and try from there.
				_walker_id = carrier.bot_id
				_walk_throw = next
				_walk_throw["since"] = _phase_time


func _living_attackers() -> Array[BotController]:
	var list: Array[BotController] = []
	for id: String in bots:
		if bots[id].is_alive() and director.state.side_of(id) == MatchRules.SIDE_ATTACK:
			list.append(bots[id])
	return list


## The thrower walking to the entrance: throws once there (or gives up after a few seconds),
## then rejoins the others.
func _walk_and_throw() -> void:
	var bot: BotController = bots.get(_walker_id)
	var alive := bot != null and bot.is_alive()
	var arrived := alive and _flat_distance(bot.global_position, execute.throw_spot) <= 1.0
	if alive and not arrived and _phase_time - float(_walk_throw["since"]) < 6.0:
		return
	if arrived:
		_throw_now(bot, _walk_throw["utility"] as StringName, _walk_throw["target"] as Vector3)
	_walker_id = ""
	_walk_throw = {}


## The first of [param candidates] carrying [param utility] and free to throw (null when none).
func _carrier(candidates: Array[BotController], utility: StringName) -> BotController:
	for bot: BotController in candidates:
		if bot.weapons.utility_count(utility) > 0 and not bot.is_throwing() and bot.target == null:
			return bot
	return null


## [param bot] throws [param utility] at [param target] if the map allows a line-up from where it
## stands. Returns true when the throw started.
func _throw_now(bot: BotController, utility: StringName, target: Vector3) -> bool:
	var space := director.level.get_world_3d().direct_space_state
	var lineup := UtilityLineup.solve(space, utility, bot.head.global_position, target, LINEUP_TOLERANCE,
		bot.weapons.exclude)
	return lineup != null and bot.throw_utility(lineup)


## Times the execute from when a grenade actually leaves a hand.
func _on_utility_finished(utility: StringName, thrown: bool) -> void:
	if not thrown:
		return
	var kind := EquipmentCatalog.utility_kind(utility)
	if kind == EquipmentCatalog.KIND_FLASH:
		_flashed_at = _phase_time
	elif kind == EquipmentCatalog.KIND_SMOKE:
		_smoked_at = _phase_time


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
