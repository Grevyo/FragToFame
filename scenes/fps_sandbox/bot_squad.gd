class_name BotSquad
extends Node
## Spawns and drives the AI players of a match on top of [BotController]'s individual combat:
## buying, per-round placement, and simple objective play — attackers take one site and the
## carrier plants, defenders split between sites, everyone converges on a planted bomb and
## defenders defuse. Team tactics and the IGL replace this simple layer in Milestone 7.

const CALLSIGNS: Array[String] = ["Ardent", "Basalt", "Cipher", "Drift", "Ember", "Flint", "Grit",
	"Halcyon", "Ion", "Jolt"]
const TEAM_KEYS: Array[StringName] = [&"home", &"away"]
const TEAM_COLORS: Array[Color] = [Color("b8542a"), Color("2e7d8c")]
const DECIDE_INTERVAL: float = 0.25

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
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = DECIDE_INTERVAL
		_decide()
	_update_bomb_actions(delta)


# --- Decisions -------------------------------------------------------------------------------

func _decide() -> void:
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
