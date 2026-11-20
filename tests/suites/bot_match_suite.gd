class_name BotMatchSuite
extends TestSuite
## Milestone 6 (scene): a practice match played by bots — roster, buying, placement, combat
## kills recorded in the match state, bomb pick-up/plant by bots, rounds finishing.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Bot practice match (Milestone 6)"


func run() -> void:
	var app := tree.root.get_node("App")
	var setup := MatchSetup.new()
	setup.fixture_id = "bot_match_test"
	setup.home_team_id = "team_you"
	setup.home_team_name = "You"
	setup.away_team_id = "team_bots"
	setup.away_team_name = "Bots"
	setup.max_rounds = 4
	var rules := MatchRules.practice(4)
	rules.team_size = 3
	rules.freeze_time = 0.5
	rules.buy_time = 2.0
	rules.round_time = 45.0
	rules.round_end_delay = 0.5
	rules.bomb_timer = 20.0
	rules.plant_time = 1.0
	rules.defuse_time = 3.0
	rules.defuse_time_with_kit = 2.0
	var map := MapTemplates.sandbox_arena()
	setup.map_id = map.map_id
	app.set("pending_match_setup", setup)
	app.set("pending_match_rules", rules)
	app.set("pending_match_map", map)
	app.set("pending_match_options", {"opponents": "bots", "skill": "hard"})

	section("Bot match: setup")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var director := sandbox.get("match_director") as MatchDirector
	check(director != null and director.squad != null, "bots mode creates a BotSquad")
	if director == null or director.squad == null:
		await despawn(sandbox)
		return
	var state := director.state
	var squad := director.squad
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	check(state.players.size() == 6 and squad.bots.size() == 5, "3v3: the human, 2 bot teammates and 3 bot opponents")
	check(director.combatants.is_empty(), "no passive dummies in bots mode")
	check(director.hud.notice_text().contains("bots"), "HUD notice names the bot opponents")
	var home_bot := squad.bots["bot_home_1"]
	var away_bot := squad.bots["bot_away_1"]
	check(home_bot.team == player.health.team and away_bot.team != player.health.team, "bots are split into the two teams")
	check(home_bot.frozen and away_bot.frozen, "bots are frozen during freeze time")
	check(squad.bots.values().all(func(bot: BotController) -> bool:
		return bot.weapons.loadout_ids() == [WeaponCatalog.G17, EquipmentCatalog.KNIFE]),
		"all bots start with the modelled G17 and the knife")
	var defence_spawn := director.level.spawn_points("defence")[0][0] as Vector3
	check(away_bot.global_position.distance_to(defence_spawn) < 5.0, "opponent bots spawn at the defence spawns")
	var bought := 0
	for id: String in squad.bots:
		if state.get_player(id).armour > 0:
			bought += 1
	check(bought == 5, "every bot buys armour with its round-1 money (%d/5)" % bought)

	section("Bot match: objectives (combat disabled)")
	# Blind every bot for round 1 so the objective layer is tested on its own: the human dies,
	# a bot teammate must recover the bomb and plant it, and the defending bots must defuse.
	var all_enemies := squad.bots["bot_home_1"].enemies
	var blind: Array[Health] = []
	for bot: BotController in squad.bots.values():
		bot.enemies = blind
	var log: Array[String] = []
	var on_pickup := func(id: String) -> void: log.append("pickup:" + id)
	var on_plant := func(id: String) -> void: log.append("plant:" + id)
	var on_defuse := func(id: String) -> void: log.append("defuse:" + id)
	state.bomb_picked_up.connect(on_pickup)
	state.bomb_planted.connect(on_plant)
	state.bomb_defused.connect(on_defuse)
	Engine.time_scale = 4.0
	var live := await wait_until(func() -> bool: return state.phase == MatchState.Phase.LIVE, 3.0)
	check(live, "round goes live")
	await wait_physics_frames(2)
	check(not away_bot.frozen and away_bot.has_goal and home_bot.has_goal, "bots head for objectives once the round is live")
	var positions: Dictionary[String, Vector3] = {}
	var health_before: Dictionary[String, int] = {}
	var ammo_before: Dictionary[String, int] = {}
	for id: String in squad.bots:
		var bot := squad.bots[id]
		positions[id] = bot.global_position
		health_before[id] = bot.health.current
		ammo_before[id] = bot.weapons.current().ammo
		bot.weapons.trigger = true
	var time_before := state.phase_time_left
	var events_before := state.events.size()
	sandbox.call("pause")
	await wait_physics_frames(12)
	var bots_still := true
	for id: String in squad.bots:
		var bot := squad.bots[id]
		bots_still = bots_still and bot.global_position == positions[id] and bot.health.current == health_before[id] \
			and bot.weapons.current().ammo == ammo_before[id]
	check(bots_still and state.phase_time_left == time_before and state.events.size() == events_before,
		"offline pause stops bot movement, shooting, damage, objective events and the live clock")
	sandbox.call("resume")
	player.input_enabled = false
	await wait_physics_frames(2)
	check(state.phase_time_left < time_before and home_bot.can_process(), "resume restarts the clock and bot processing")
	player.health.kill()
	await wait_physics_frames(1)
	check(state.is_bomb_dropped, "the human's death drops the bomb")
	var round_over := func() -> bool: return state.round_number >= 2 or state.phase != MatchState.Phase.LIVE
	await wait_until(func() -> bool: return not log.is_empty() or round_over.call(), 10.0)
	check(not log.is_empty() and log[0].begins_with("pickup:bot_home"), "a bot teammate recovers the dropped bomb (%s)" % ", ".join(log))
	await wait_until(func() -> bool: return state.is_bomb_planted or round_over.call(), 20.0)
	check(log.any(func(entry: String) -> bool: return entry.begins_with("plant:bot_home")), "the carrier bot plants on a bombsite")
	await wait_until(round_over, 20.0)
	check(log.any(func(entry: String) -> bool: return entry.begins_with("defuse:bot_away"))
		and state.last_round_reason == MatchRules.REASON_DEFUSED,
		"defending bots retake and defuse (%s, %s)" % [", ".join(log), state.last_round_reason])
	state.bomb_picked_up.disconnect(on_pickup)
	state.bomb_planted.disconnect(on_plant)
	state.bomb_defused.disconnect(on_defuse)

	section("Bot match: combat round")
	for bot: BotController in squad.bots.values():
		bot.enemies = all_enemies
	var kills_before := state.events.filter(func(e: Dictionary) -> bool: return e.get("type") == "kill").size()
	var feed_before := director.sandbox_hud.feed_count()
	var ended := await wait_until(func() -> bool: return state.round_number >= 3 or state.phase == MatchState.Phase.MATCH_END, 40.0)
	check(ended, "round 2 is fought out by the bots (%s)" % state.last_round_reason)
	var bot_kills := 0
	for event: Dictionary in state.events:
		if event.get("type") == "kill" and event.get("round") == 2 and str(event.get("killer", "")).begins_with("bot_"):
			bot_kills += 1
	check(bot_kills >= 1, "bots score kills recorded in the match state (%d in round 2)" % bot_kills)
	check(state.events.filter(func(e: Dictionary) -> bool: return e.get("type") == "kill").size() > kills_before
		and director.sandbox_hud.feed_count() > feed_before, "kills appear in the kill feed")

	section("Bot match: next round")
	await wait_until(func() -> bool: return state.phase == MatchState.Phase.FREEZE or state.phase == MatchState.Phase.LIVE, 3.0)
	var alive := 0
	for bot: BotController in squad.bots.values():
		if bot.is_alive():
			alive += 1
	check(alive == 5, "every bot respawns for the next round")
	check(not player.health.is_dead, "the human respawns for the next round")
	Engine.time_scale = 1.0
	app.set("last_match_result", null)
	await despawn(sandbox)
	await wait_frames(2)
