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
var _starting_side: StringName = MatchRules.SIDE_ATTACK
var _starting_spawn: int = 0


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
	if bool(options.get("editor_playtest", false)):
		if options.get("playtest_team") == "defence":
			_starting_side = MatchRules.SIDE_DEFENCE
		_starting_spawn = int(options.get("playtest_spawn", 0))
	state = MatchState.new(setup, rules, _starting_side)
	for member: Dictionary in setup.home_lineup:
		if bool(member.get("is_human", false)):
			local_player_id = str(member["player_id"])
			break
	player.weapons.shooter_id = local_player_id
	player.health.owner_id = local_player_id
	state.add_player(local_player_id, "You", MatchState.HOME, true)
	player.weapons.shot_attempted.connect(state.record_shot.bind(local_player_id))
	player.weapons.utility_thrown.connect(func(id: StringName) -> void: state.record_throw(local_player_id, id))
	player.health.damaged.connect(state.record_damage.bind(local_player_id))
	level.utility.combatant_flashed.connect(state.record_flash)
	if opponents == OPPONENTS_BOTS:
		var skill := StringName(str(options.get("skill", "normal")))
		squad = BotSquad.new(self, skill)
		add_child(squad)
		squad.add_players(MatchState.HOME, rules.team_size - 1)
		squad.add_players(MatchState.AWAY, rules.team_size)
		player.set_team(BotSquad.TEAM_KEYS[MatchState.HOME])
		level.build_navigation()
		squad.spawn_bots()
		squad.call_made.connect(_on_call_made)
		for bot: BotController in squad.bots.values():
			bot.weapons.shot_attempted.connect(state.record_shot.bind(bot.bot_id))
			var thrower := bot.bot_id
			bot.weapons.utility_thrown.connect(func(id: StringName) -> void: state.record_throw(thrower, id))
			bot.health.damaged.connect(state.record_damage.bind(bot.bot_id))
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


## The chosen editor spawn applies to the starting side. Its bot teammates use the other spawns.
func human_spawn_index(spawn_count: int) -> int:
	return clampi(_starting_spawn, 0, spawn_count - 1) if human_side() == _starting_side else 0


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


## The team-call menu takes the number keys before anything else sees them (they also pick
## weapons).
func _input(event: InputEvent) -> void:
	if state == null or paused or not hud.is_call_menu_open():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code >= KEY_1 and code <= KEY_9:
		make_call(int(code - KEY_1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.TEAM_CALL):
		hud.hide_call_menu()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if state == null or paused or state.phase == MatchState.Phase.MATCH_END:
		return
	if event.is_action_pressed(InputActions.TEAM_CALL) and can_call():
		var lines: Array[String] = []
		for call: TeamCall in call_options():
			lines.append(call.label())
		hud.show_call_menu(lines)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.BUY_MENU):
		if is_buy_menu_open():
			close_buy_menu()
		elif can_open_buy_menu():
			open_buy_menu()
		get_viewport().set_input_as_handled()


# --- Team calls (IGL) -------------------------------------------------------------------------

## Whether the player can make team calls now: bots on their team and a round being played.
func can_call() -> bool:
	if squad == null or state == null:
		return false
	if state.phase != MatchState.Phase.LIVE and state.phase != MatchState.Phase.FREEZE:
		return false
	return state.teams[MatchState.HOME].player_ids.any(func(id: String) -> bool: return squad.bots.has(id))


## The calls the player can make on their current side, in menu order.
func call_options() -> Array[TeamCall]:
	var options: Array[TeamCall] = []
	if squad != null:
		options = TeamCall.menu(human_side(), squad.site_letters())
	return options


## Makes the call at [param index] of [method call_options] for the player's team; the menu closes.
func make_call(index: int) -> bool:
	hud.hide_call_menu()
	var options := call_options()
	if index < 0 or index >= options.size() or not can_call():
		return false
	var call := options[index]
	call.caller = local_player_id
	return squad.issue_call(MatchState.HOME, call)


func _on_call_made(team_index: int, call: TeamCall) -> void:
	if team_index != MatchState.HOME:
		return
	var who := "IGL"
	if call.caller == local_player_id:
		who = "You"
	elif squad.tactics[team_index] != null:
		who = "%s (IGL)" % _feed_name(squad.tactics[team_index].leader_id())
	hud.show_call("%s: %s%s" % [who, call.label(), "  ·  " + call.reason if not call.reason.is_empty() else ""])


## Called by the runtime on Esc. Returns true if the director consumed it (closing the buy menu).
func handle_escape() -> bool:
	if hud.is_call_menu_open():
		hud.hide_call_menu()
		return true
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
		SoundPlayer.play_ui(&"ui_buy")
	else:
		last_buy_message = "Cannot buy %s: %s" % [ShopCatalog.display_name(item_id), error]
		SoundPlayer.play_ui(&"ui_denied")
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
		ShopCatalog.KIND_UTILITY:
			player.weapons.give_utility(item_id)


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
		if ShopCatalog.kind(id) == ShopCatalog.KIND_UTILITY:
			var have := me.utility_count(id)
			var limit := EquipmentCatalog.carry_limit(id)
			owned = have >= limit or me.utility.size() >= EquipmentCatalog.UTILITY_CARRY_LIMIT
			note = "%d/%d" % [have, limit] if have > 0 else ""
			if me.utility.size() >= EquipmentCatalog.UTILITY_CARRY_LIMIT and have < limit:
				note = "utility full"
		elif owned:
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
	SoundPlayer.play_at(level, &"bomb_planted", state.bomb_position + Vector3(0, 0.3, 0), &"bomb")
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
	SoundPlayer.play_flat(self, &"round_start", &"UI")
	_clear_bomb()
	level.utility.clear()
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
	var spawns := level.spawn_points(String(human_side()))
	var spawn := spawns[human_spawn_index(spawns.size())]
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
		dummy.health.damaged.connect(state.record_damage.bind(id))
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
	if reason == MatchRules.REASON_DETONATED:
		SoundPlayer.play_at(level, &"bomb_explode", state.bomb_position + Vector3(0, 0.5, 0), &"explosion", 4.0)
	elif reason == MatchRules.REASON_DEFUSED:
		SoundPlayer.play_at(level, &"bomb_defused", state.bomb_position + Vector3(0, 0.3, 0), &"bomb")
	SoundPlayer.play_flat(self, &"round_end", &"UI")
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
