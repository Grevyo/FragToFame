class_name MatchDirector
extends Node3D
## Runs a competitive match inside the FPS runtime.
##
## Input: a [MatchSetup] + [MatchRules] (from orchestration) and the loaded map. Output:
## [signal match_finished] with a [MatchResult]. Owns the [MatchState] and translates between it
## and the 3D world: places players every round, handles buying, the bomb (carry, drop, pick up,
## plant, defuse) and drives the [MatchHud]. Opponents are either AI bots ([BotSquad], the default
## for practice) or passive target dummies (option "opponents": "passive", used by rules tests).
## Never touches career data.

signal match_finished(result: MatchResult)

const HUMAN_ID: String = "player_local"
const BOMB_PICKUP_RADIUS: float = 1.2
const DEFUSE_RADIUS: float = 1.6
const OPPONENTS_BOTS: StringName = &"bots"
const OPPONENTS_PASSIVE: StringName = &"passive"

var state: MatchState
var document: MapDocument
var player: FirstPersonController
var level: SandboxLevel
var sandbox_hud: SandboxHud
var hud: MatchHud
## The dropped or planted bomb in the world (null while someone carries it).
var bomb: BombDevice
## Passive-mode target dummies by player ID (empty in bots mode).
var combatants: Dictionary[String, TargetDummy] = {}
## Bots mode: the AI players (null in passive mode).
var squad: BotSquad = null
var opponents: StringName = OPPONENTS_PASSIVE
var local_player_id: String = HUMAN_ID
## True while plant/defuse is requested. Read from the interact key while player input is
## enabled; scripts and tests may set it directly while input is disabled.
var interact_held: bool = false
var plant_progress: float = 0.0
var defuse_progress: float = 0.0
## When true (local pause) the match clock stops.
var paused: bool = false
var last_buy_message: String = ""

var _last_safe_position: Vector3 = Vector3.ZERO


func begin(setup: MatchSetup, rules: MatchRules, doc: MapDocument, player_node: FirstPersonController,
		level_node: SandboxLevel, hud_node: SandboxHud, options: Dictionary = {}) -> void:
	opponents = StringName(str(options.get("opponents", OPPONENTS_PASSIVE)))
	document = doc
	player = player_node
	level = level_node
	sandbox_hud = hud_node
	hud = MatchHud.new()
	hud.name = "MatchHud"
	add_child(hud)
	hud.item_chosen.connect(func(id: StringName) -> void: try_buy(id))
	hud.buy_menu_closed.connect(close_buy_menu)
	state = MatchState.new(setup, rules)
	for member: Dictionary in setup.home_lineup:
		if bool(member.get("is_human", false)):
			local_player_id = str(member["player_id"])
			break
	player.weapons.shooter_id = local_player_id
	player.health.owner_id = local_player_id
	state.add_player(local_player_id, "You", MatchState.HOME, true)
	if opponents == OPPONENTS_BOTS:
		var skill := StringName(str(options.get("skill", "normal")))
		squad = BotSquad.new(self, skill)
		add_child(squad)
		squad.add_players(MatchState.HOME, rules.team_size - 1)
		squad.add_players(MatchState.AWAY, rules.team_size)
		player.set_team(BotSquad.TEAM_KEYS[MatchState.HOME])
		level.build_navigation()
		squad.spawn_bots()
		if bool(options.get("career_fixture", false)):
			hud.set_notice("%s · MR%d · vs %s" % [setup.competition, setup.max_rounds, setup.away_team_name])
		elif not setup.away_lineup.is_empty():
			hud.set_notice("PRACTICE · vs %s · bots play from their career abilities" % setup.away_team_name)
		else:
			hud.set_notice("PRACTICE · %dv%d with bots (%s)" % [
				rules.team_size, rules.team_size, skill])
	else:
		for i: int in rules.team_size:
			state.add_player("target_%d" % (i + 1), "Target %d" % (i + 1), MatchState.AWAY)
		hud.set_notice("PRACTICE · opponents are passive targets")
	state.round_started.connect(_on_round_started)
	state.round_ended.connect(_on_round_ended)
	state.sides_switched.connect(func() -> void: hud.show_banner("SIDES SWITCHED", 3.0))
	state.bomb_planted.connect(_on_bomb_planted)
	state.bomb_dropped.connect(_on_bomb_dropped)
	state.bomb_picked_up.connect(_on_bomb_picked_up)
	state.match_ended.connect(_on_match_ended)
	state.player_killed.connect(_on_player_killed)
	player.health.died.connect(_on_player_died)
	state.start()


func human() -> MatchState.PlayerState:
	return state.get_player(local_player_id)


func human_side() -> StringName:
	return state.side_of(local_player_id)


func feet_position() -> Vector3:
	return player.global_position


func _physics_process(delta: float) -> void:
	if state == null or paused:
		return
	if player.input_enabled:
		interact_held = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed(InputActions.INTERACT)
	state.tick(delta)
	if squad != null:
		squad.physics_update(delta)
	if player.is_on_floor():
		_last_safe_position = player.global_position
	_update_plant(delta)
	_update_defuse(delta)
	_update_bomb_pickup()
	if bomb != null and state.is_bomb_planted:
		bomb.time_left = state.bomb_time_left
	player.frozen = state.phase == MatchState.Phase.FREEZE or plant_progress > 0.0 or defuse_progress > 0.0
	if is_buy_menu_open() and not can_open_buy_menu():
		close_buy_menu()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state == null or paused or state.phase == MatchState.Phase.MATCH_END:
		return
	if event.is_action_pressed(InputActions.BUY_MENU):
		if is_buy_menu_open():
			close_buy_menu()
		elif can_open_buy_menu():
			open_buy_menu()
		get_viewport().set_input_as_handled()


## Called by the runtime on Esc. Returns true if the director consumed it (closing the buy menu).
func handle_escape() -> bool:
	if is_buy_menu_open():
		close_buy_menu()
		return true
	return false


# --- Buying ----------------------------------------------------------------------------------

func can_open_buy_menu() -> bool:
	return state.can_buy(local_player_id) and MapZones.is_in_buy_zone(document, String(human_side()), feet_position())


func is_buy_menu_open() -> bool:
	return hud != null and hud.is_buy_menu_open()


func open_buy_menu() -> void:
	_refresh_buy_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false


func close_buy_menu() -> void:
	if not is_buy_menu_open():
		return
	hud.hide_buy_menu()
	if not paused and state.phase != MatchState.Phase.MATCH_END:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.input_enabled = true


## Buys an item for the human player (must be in their buy zone during the buy window).
## Returns "" on success or the reason it failed.
func try_buy(item_id: StringName) -> String:
	var error := ""
	if not MapZones.is_in_buy_zone(document, String(human_side()), feet_position()):
		error = "you are not in your buy zone"
	else:
		error = state.buy(local_player_id, item_id)
	if error.is_empty():
		_apply_purchase(item_id)
		last_buy_message = "Bought %s" % ShopCatalog.display_name(item_id)
	else:
		last_buy_message = "Cannot buy %s: %s" % [ShopCatalog.display_name(item_id), error]
	if is_buy_menu_open():
		_refresh_buy_menu()
	return error


func _apply_purchase(item_id: StringName) -> void:
	var me := human()
	match ShopCatalog.kind(item_id):
		ShopCatalog.KIND_WEAPON:
			player.weapons.give_weapon(item_id)
		ShopCatalog.KIND_ARMOUR:
			player.health.armour = me.armour
			player.health.has_helmet = me.helmet


func _refresh_buy_menu() -> void:
	var me := human()
	var entries: Array[Dictionary] = []
	for id: StringName in ShopCatalog.item_ids():
		var price := ShopCatalog.price(id)
		var note := ""
		var restriction := ShopCatalog.side_restriction(id)
		var owned := me.primary == id or me.secondary == id \
			or (id == ShopCatalog.ARMOUR_VEST and me.armour >= ShopCatalog.FULL_ARMOUR) \
			or (id == ShopCatalog.ARMOUR_VEST_HELMET and me.armour >= ShopCatalog.FULL_ARMOUR and me.helmet) \
			or (id == ShopCatalog.DEFUSE_KIT and me.has_kit)
		if id == ShopCatalog.ARMOUR_VEST_HELMET and me.armour >= ShopCatalog.FULL_ARMOUR and not me.helmet:
			price = ShopCatalog.HELMET_UPGRADE_PRICE
			note = "helmet only"
		if owned:
			note = "owned"
		elif restriction != &"" and restriction != human_side():
			note = "%s only" % restriction
		var enabled := not owned and (restriction == &"" or restriction == human_side()) and me.money >= price
		entries.append({"id": id, "name": ShopCatalog.display_name(id), "price": price, "enabled": enabled, "note": note})
	hud.show_buy_menu(entries, me.money, last_buy_message)


# --- Bomb ------------------------------------------------------------------------------------

func _update_plant(delta: float) -> void:
	var site := MapZones.bombsite_at(document, feet_position())
	var can_plant := state.phase == MatchState.Phase.LIVE and not state.is_bomb_planted \
		and state.bomb_carrier_id == local_player_id and not player.health.is_dead \
		and not site.is_empty() and player.is_on_floor()
	if not (can_plant and interact_held):
		plant_progress = 0.0
		return
	plant_progress += delta
	if plant_progress >= state.rules.plant_time:
		plant_progress = 0.0
		state.plant_bomb(local_player_id, feet_position())


func _update_defuse(delta: float) -> void:
	var can_defuse := state.phase == MatchState.Phase.LIVE and state.is_bomb_planted \
		and human_side() == MatchRules.SIDE_DEFENCE and not player.health.is_dead \
		and feet_position().distance_to(state.bomb_position) <= DEFUSE_RADIUS
	if not (can_defuse and interact_held):
		defuse_progress = 0.0
		return
	defuse_progress += delta
	if defuse_progress >= state.defuse_duration(local_player_id):
		defuse_progress = 0.0
		state.defuse_bomb(local_player_id)


func _update_bomb_pickup() -> void:
	if not state.is_bomb_dropped or player.health.is_dead or human_side() != MatchRules.SIDE_ATTACK:
		return
	if feet_position().distance_to(state.bomb_position) <= BOMB_PICKUP_RADIUS:
		state.pick_up_bomb(local_player_id)


func _spawn_bomb(at: Vector3) -> void:
	_clear_bomb()
	bomb = BombDevice.new()
	bomb.name = "Bomb"
	add_child(bomb)
	bomb.global_position = at


func _clear_bomb() -> void:
	if bomb != null:
		bomb.queue_free()
		bomb = null


func _on_bomb_planted(player_id: String) -> void:
	_spawn_bomb(state.bomb_position)
	bomb.set_planted(state.bomb_time_left, state.rules.bomb_timer)
	var who := "You" if player_id == local_player_id else state.get_player(player_id).display_name
	hud.show_banner("BOMB PLANTED · %s" % who, 3.0)


func _on_bomb_dropped(at: Vector3) -> void:
	_spawn_bomb(at)


func _on_bomb_picked_up(player_id: String) -> void:
	_clear_bomb()
	if player_id == local_player_id:
		hud.show_banner("You picked up the bomb", 2.0)


# --- Rounds ----------------------------------------------------------------------------------

func _on_round_started(round_number: int) -> void:
	_clear_bomb()
	plant_progress = 0.0
	defuse_progress = 0.0
	last_buy_message = ""
	if squad != null:
		squad.on_round_started()
	else:
		_place_combatants()
	_place_human()
	sandbox_hud.set_death_state(-1.0)
	var side_text := "ATTACK" if human_side() == MatchRules.SIDE_ATTACK else "DEFEND"
	var extra := " · you carry the bomb" if state.bomb_carrier_id == local_player_id else ""
	hud.show_banner("ROUND %d · %s%s" % [round_number, side_text, extra], 3.0)


func _place_human() -> void:
	var me := human()
	var spawn := level.spawn_points(String(human_side()))[0]
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	player.respawn()
	player.weapons.set_loadout(me.loadout())
	player.health.armour = me.armour
	player.health.has_helmet = me.helmet
	player.frozen = true
	_last_safe_position = player.global_position


func _place_combatants() -> void:
	for dummy: TargetDummy in combatants.values():
		dummy.queue_free()
	combatants.clear()
	var away := state.teams[MatchState.AWAY]
	var spawns := level.spawn_points(String(away.side))
	for i: int in away.player_ids.size():
		var id := away.player_ids[i]
		var spawn := spawns[i % spawns.size()]
		var dummy := TargetDummy.new()
		dummy.name = "Combatant_%s" % id
		dummy.combatant_id = id
		dummy.respawn_delay = -1.0
		dummy.position = (spawn[0] as Vector3) + Vector3(0.8 * floorf(float(i) / spawns.size()), 0, 0)
		dummy.rotation.y = float(spawn[1])
		level.add_child(dummy)
		dummy.health.armour = state.get_player(id).armour
		dummy.health.has_helmet = state.get_player(id).helmet
		dummy.health.died.connect(_on_combatant_died.bind(dummy))
		combatants[id] = dummy


func _on_combatant_died(info: DamageInfo, dummy: TargetDummy) -> void:
	state.record_kill(dummy.combatant_id, info.source_id, info.weapon_id, info.is_headshot(), dummy.global_position)


## Kill feed for every elimination in the match (the human's, bots', and passive targets').
func _on_player_killed(victim_id: String, killer_id: String) -> void:
	var event: Dictionary = {}
	for i: int in range(state.events.size() - 1, -1, -1):
		if state.events[i].get("type") == "kill" and state.events[i].get("victim") == victim_id:
			event = state.events[i]
			break
	var weapon := WeaponCatalog.get_definition(StringName(str(event.get("weapon", ""))))
	var killer := _feed_name(killer_id) if not killer_id.is_empty() else "World"
	sandbox_hud.push_feed("%s  [%s%s]  %s" % [killer, weapon.display_name if weapon != null else "—",
		" · HEADSHOT" if bool(event.get("headshot", false)) else "", _feed_name(victim_id)])


func _feed_name(player_id: String) -> String:
	if player_id == local_player_id:
		return "You"
	var player_state := state.get_player(player_id)
	return player_state.display_name if player_state != null else player_id


func _on_player_died(info: DamageInfo) -> void:
	if state.phase == MatchState.Phase.MATCH_END:
		return
	state.record_kill(local_player_id, info.source_id, info.weapon_id, info.is_headshot(), _last_safe_position)
	plant_progress = 0.0
	defuse_progress = 0.0
	sandbox_hud.show_death_message("You will respawn next round")


func _on_round_ended(winner: int, reason: StringName) -> void:
	if not player.health.is_dead:
		state.set_player_armour(local_player_id, player.health.armour, player.health.has_helmet)
	for id: String in combatants:
		var dummy := combatants[id]
		if is_instance_valid(dummy) and not dummy.health.is_dead:
			state.set_player_armour(id, dummy.health.armour, dummy.health.has_helmet)
	if squad != null:
		squad.on_round_ended()
	var side := state.teams[winner].side
	var reason_text: String = {
		MatchRules.REASON_ELIMINATION: "Enemy team eliminated",
		MatchRules.REASON_TIME: "Time ran out",
		MatchRules.REASON_DETONATED: "Bomb detonated",
		MatchRules.REASON_DEFUSED: "Bomb defused",
	}.get(reason, "")
	var side_name := "ATTACKERS" if side == MatchRules.SIDE_ATTACK else "DEFENDERS"
	hud.show_banner("%s WIN · %s" % [side_name, reason_text], state.rules.round_end_delay)


func _on_match_ended(result: MatchResult) -> void:
	close_buy_menu()
	if squad != null:
		squad.freeze_all()
	player.input_enabled = false
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var won := result.winner_side() == "home"
	hud.show_match_end("VICTORY" if won else "DEFEAT",
		"Final score %d – %d (%d rounds)\n%s vs %s" % [
			result.home_score, result.away_score, result.rounds_played,
			state.teams[MatchState.HOME].display_name, state.teams[MatchState.AWAY].display_name])
	match_finished.emit(result)


# --- HUD -------------------------------------------------------------------------------------

func _update_hud() -> void:
	var home := state.teams[MatchState.HOME]
	var away := state.teams[MatchState.AWAY]
	hud.set_scoreboard(home.display_name, home.score, home.side, away.display_name, away.score, away.side,
		state.round_label())
	var phase_text := ""
	var clock := state.phase_time_left
	match state.phase:
		MatchState.Phase.FREEZE:
			phase_text = "BUY"
		MatchState.Phase.LIVE:
			phase_text = "BOMB" if state.is_bomb_planted else "LIVE"
			if state.is_bomb_planted:
				clock = state.bomb_time_left
		MatchState.Phase.ROUND_END:
			phase_text = "NEXT"
		MatchState.Phase.MATCH_END:
			phase_text = "FINAL"
	hud.set_clock(clock, state.is_bomb_planted and state.phase == MatchState.Phase.LIVE, phase_text)
	hud.set_money(human().money)
	if plant_progress > 0.0:
		hud.set_progress("Planting…", plant_progress / state.rules.plant_time)
	elif defuse_progress > 0.0:
		hud.set_progress("Defusing…", defuse_progress / state.defuse_duration(local_player_id))
	else:
		hud.set_progress("", -1.0)
	hud.set_hint(_context_hint())


func _context_hint() -> String:
	if state.phase == MatchState.Phase.MATCH_END or player.health.is_dead:
		return ""
	if plant_progress > 0.0 or defuse_progress > 0.0:
		return ""
	var site := MapZones.bombsite_at(document, feet_position())
	if state.phase == MatchState.Phase.LIVE and state.bomb_carrier_id == local_player_id and not site.is_empty():
		return "Hold E to plant the bomb (site %s)" % site
	if state.phase == MatchState.Phase.LIVE and state.is_bomb_planted and human_side() == MatchRules.SIDE_DEFENCE \
			and feet_position().distance_to(state.bomb_position) <= DEFUSE_RADIUS:
		return "Hold E to defuse"
	if can_open_buy_menu() and not is_buy_menu_open():
		return "Press B to buy"
	return ""
