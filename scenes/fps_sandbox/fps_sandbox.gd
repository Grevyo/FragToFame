extends Node3D
## FPS runtime root (FPS Sandbox / map playtest): loads a map, owns mouse capture, pause and
## respawn state, records training stats, and wires the HUD to the player, the weapons and the
## local match network session.

const SandboxBots := preload("res://scenes/fps_sandbox/sandbox_bots.gd")

@onready var player: FirstPersonController = $Player
@onready var hud: SandboxHud = $Hud
@onready var match_session: MatchSession = $MatchSession
@onready var level: SandboxLevel = $Level
@onready var effects: WeaponEffects = $Effects
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var is_paused: bool = false
## Present only while a competitive match is running in this runtime.
var match_director: MatchDirector = null
## Present only while a training drill is running in this runtime.
var training_director: TrainingDirector = null
## Seconds between the player's death and respawn.
var respawn_delay: float = 3.0
## Recorded shooting numbers for this session (shown in the HUD; not persisted yet).
var tally := CombatTally.new()
var _respawn_left: float = -1.0
var _death_cause: String = ""
var _last_network_message: String = ""
var _match_options: Dictionary = {}
var _sandbox_shop: MatchHud
var _sandbox_bots: SandboxBots


func _ready() -> void:
	hud.resume_requested.connect(resume)
	hud.main_menu_requested.connect(_on_main_menu_requested)
	hud.return_to_editor_requested.connect(_on_return_to_editor)
	hud.host_match_requested.connect(_on_host_match_requested)
	hud.join_match_requested.connect(_on_join_match_requested)
	hud.leave_match_requested.connect(func() -> void: match_session.leave("left"))
	hud.practice_match_requested.connect(_on_practice_match_requested)
	hud.sandbox_weapons_chosen.connect(set_sandbox_weapons)
	match_session.local_body = player
	match_session.local_appearance = CosmeticProfile.current().appearance.to_dict() \
		if not CosmeticProfile.current().appearance.body.is_empty() else {}
	match_session.session_ended.connect(_on_session_ended)
	effects.bind(player.weapons, player.camera)
	player.weapons.shot_fired.connect(_on_shot_fired)
	player.weapons.target_hit.connect(_on_target_hit)
	player.died.connect(_on_player_died)
	# The environment is a shared scene resource; map lighting must not leak into the next map.
	world_environment.environment = world_environment.environment.duplicate() as Environment
	_load_level()
	resume()


func _load_level() -> void:
	if App.has_pending_match():
		_start_match()
		return
	if App.has_pending_training():
		_start_training()
		return
	var playtest := App.is_playtesting()
	var chosen := App.sandbox_map
	App.sandbox_map = null
	var doc := App.playtest_map if playtest else (chosen if chosen != null else MapTemplates.sandbox_arena())
	level.load_map(doc)
	MapLighting.apply_atmosphere(doc.lighting, sun, world_environment.environment)
	MapLighting.apply(doc.lighting, sun, world_environment.environment)
	# The editor can playtest as either team from any spawn.
	var options := App.playtest_options if playtest else {}
	var team := str(options.get("team", "attack"))
	var spawns := level.spawn_points(team)
	var spawn := spawns[clampi(int(options.get("spawn", 0)), 0, spawns.size() - 1)]
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	player.noclip_allowed = true  # Free roam only; a match never allows it.
	hud.set_mode("PLAYTEST · %s · %s spawn %d" % [doc.name, team, spawns.find(spawn) + 1] if playtest
		else "FPS SANDBOX · %s" % doc.name, playtest)
	_sandbox_bots = SandboxBots.new(level, player, team)
	_sandbox_bots.roster_changed.connect(hud.set_sandbox_bot_count)
	_sandbox_bots.kill_reported.connect(hud.push_feed)
	_sandbox_bots.spawn_failed.connect(func() -> void: hud.set_pause_message("No clear bot spawn on this map."))
	add_child(_sandbox_bots)
	hud.add_bot_requested.connect(func() -> void:
		if not match_session.is_active():
			hud.set_pause_message("")
			_sandbox_bots.request_add())
	hud.remove_bots_requested.connect(_sandbox_bots.clear)


func _start_match() -> void:
	var match_data := App.consume_pending_match()
	var setup := match_data[0] as MatchSetup
	var rules := match_data[1] as MatchRules
	var doc := match_data[2] as MapDocument
	_match_options = (match_data[3] as Dictionary).duplicate(true)
	level.load_map(doc, false)
	MapLighting.apply_atmosphere(doc.lighting, sun, world_environment.environment)
	MapLighting.apply(doc.lighting, sun, world_environment.environment)
	var spawn := level.spawn_point("attack")
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	player.weapons.set_loadout([WeaponCatalog.DEFAULT_SECONDARY])
	var career_fixture := _is_career_fixture()
	var editor_playtest := App.is_playtesting()
	var heading := "CAREER FIXTURE" if career_fixture else ("BOT PLAYTEST" if editor_playtest else "PRACTICE MATCH")
	hud.set_mode("%s · %s" % [heading, doc.name], editor_playtest, true, career_fixture)
	match_director = MatchDirector.new()
	match_director.name = "MatchDirector"
	add_child(match_director)
	match_director.begin(setup, rules, doc, player, level, hud, _match_options)
	match_director.hud.main_menu_requested.connect(_on_main_menu_requested)
	match_director.hud.play_again_requested.connect(_on_practice_match_requested)
	match_director.hud.set_career_fixture(career_fixture)
	if editor_playtest:
		match_director.hud.main_menu_button.text = "Return to Creation Studio"
	match_director.match_finished.connect(_on_match_finished)


func _start_training() -> void:
	var drill := App.consume_pending_training()
	var doc := drill["map"] as MapDocument
	level.load_map(doc, false)
	MapLighting.apply_atmosphere(doc.lighting, sun, world_environment.environment)
	MapLighting.apply(doc.lighting, sun, world_environment.environment)
	var spawn := level.spawn_point("attack")
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	var drill_id := drill["drill"] as StringName
	hud.set_mode("TRAINING · %s" % TrainingDrills.drill_name(drill_id), false)
	training_director = TrainingDirector.new()
	training_director.name = "TrainingDirector"
	add_child(training_director)
	training_director.begin(drill_id, level, player)
	training_director.training_finished.connect(func(result: TrainingResult) -> void:
		training_director.set_result_message(App.report_training_finished(result)))
	training_director.again_requested.connect(func() -> void: App.start_training(drill_id, App.is_career_training()))
	training_director.leave_requested.connect(_on_main_menu_requested)


func _is_career_fixture() -> bool:
	return bool(_match_options.get("career_fixture", false))


func _on_match_finished(result: MatchResult) -> void:
	var message := App.report_match_finished(result)
	if _is_career_fixture():
		hud.practice_button.disabled = true
		match_director.hud.set_result_message(message)


## True while a shop or the match-end screen needs a free mouse cursor.
func _overlay_owns_mouse() -> bool:
	return (_sandbox_shop != null and _sandbox_shop.is_buy_menu_open()) or (training_director != null
		and training_director.is_finished()) or (match_director != null
		and (match_director.is_buy_menu_open() or match_director.state.phase == MatchState.Phase.MATCH_END))


func _on_practice_match_requested() -> void:
	match_session.leave("starting practice match")
	if App.is_playtesting():
		App.start_playtest_with_bots()
		return
	if match_director == null:
		var map_id := hud.selected_practice_map_id()
		var chosen := level.document if map_id.is_empty() else App.map_by_id(map_id)
		App.start_practice_match(chosen if chosen != null else level.document)
		return
	var prior := match_director.state
	if _is_career_fixture():
		var problem := App.start_career_fixture(prior.setup.fixture_id)
		if not problem.is_empty():
			hud.set_pause_message(problem)
		return
	var setup := MatchSetup.from_fixture(prior.setup.to_dict())
	setup.fixture_id = Ids.generate("practice")
	App.start_match(setup, prior.rules, level.document, _match_options.duplicate(true))


func _unhandled_input(event: InputEvent) -> void:
	if match_director == null and training_director == null and not is_paused:
		var shop_open := _sandbox_shop != null and _sandbox_shop.is_buy_menu_open()
		if shop_open and (event.is_action_pressed(InputActions.PAUSE_MENU) or event.is_action_pressed(InputActions.BUY_MENU)):
			_close_sandbox_shop()
			get_viewport().set_input_as_handled()
			return
		if not shop_open and not player.health.is_dead and event.is_action_pressed(InputActions.BUY_MENU):
			_show_sandbox_shop()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(InputActions.PAUSE_MENU) and match_director != null and match_director.handle_escape():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.INSPECT) and not is_paused and not _overlay_owns_mouse():
		effects.inspect()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		if is_paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
		return
	# Recapture after the mouse was freed without pausing (e.g. window focus loss).
	var click := event as InputEventMouseButton
	if click != null and click.pressed and not is_paused and not _overlay_owns_mouse() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var p := player.global_position
	var speed := player.horizontal_speed()
	hud.set_debug_text("pos %.1f, %.2f, %.1f   speed %.2f m/s (%.0f u/s)   %s%s   %d fps" % [
		p.x, p.y, p.z, speed, PlayerMovement.to_units(speed),
		"NOCLIP" if player.noclip else ("grounded" if player.is_on_floor() else "airborne"),
		" · crouched" if player.is_crouched() else "",
		Engine.get_frames_per_second(),
	])
	hud.set_location_text(MapTactical.area_name_at(level.document, p))
	hud.set_vision(player.blind_amount(), level.utility.smoke_cover(player.camera.global_position) if level.utility != null else 0.0)
	_update_combat_hud()
	_update_network_hud()
	if _respawn_left >= 0.0 and not is_paused:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			respawn_player()
		else:
			hud.set_death_state(_respawn_left, _death_cause)


## Free roam only: carry the chosen primary and secondary.
func set_sandbox_weapons(primary: StringName, secondary: StringName) -> bool:
	if match_director != null:
		return false
	var primary_definition := WeaponCatalog.get_definition(primary)
	var secondary_definition := WeaponCatalog.get_definition(secondary)
	if primary_definition == null or primary_definition.category != WeaponDefinition.CATEGORY_PRIMARY:
		return false
	if secondary_definition == null or secondary_definition.category != WeaponDefinition.CATEGORY_SECONDARY:
		return false
	var utility: Array[StringName] = []
	for id: StringName in EquipmentCatalog.UTILITY:
		for i: int in player.weapons.utility_count(id):
			utility.append(id)
	var loadout: Array[StringName] = [primary, secondary, EquipmentCatalog.KNIFE]
	loadout.append_array(utility)
	player.weapons.set_loadout(loadout)
	return true


func _show_sandbox_shop(message: String = "") -> void:
	if _sandbox_shop == null:
		_sandbox_shop = MatchHud.new()
		_sandbox_shop.practice_shop_only = true
		_sandbox_shop.buy_menu_closed.connect(_close_sandbox_shop)
		_sandbox_shop.item_chosen.connect(_take_sandbox_item)
		_sandbox_shop.knife_chosen.connect(take_sandbox_knife)
		add_child(_sandbox_shop)
	var entries: Array[Dictionary] = []
	for id: StringName in ShopCatalog.item_ids():
		if ShopCatalog.kind(id) == ShopCatalog.KIND_KIT:
			continue
		var full := ShopCatalog.kind(id) == ShopCatalog.KIND_UTILITY \
			and player.weapons.utility_count(id) >= EquipmentCatalog.carry_limit(id)
		entries.append({"id": id, "name": ShopCatalog.display_name(id), "enabled": not full,
			"note": "full" if full else ""})
	player.input_enabled = false
	player.weapons.trigger = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sandbox_shop.show_buy_menu(entries, 0, message)
	_sandbox_shop.show_knives(WeaponModels.KNIVES, CosmeticProfile.current().equipped_knife())


## Sandbox shop knife column: carries another knife look (saved, as in the Armoury) and puts it
## in hand so it can be tried straight away.
func take_sandbox_knife(model_id: StringName) -> void:
	var profile := CosmeticProfile.current()
	if not profile.set_knife(model_id).is_empty():
		return
	var saved := profile.save()
	player.weapons.select_slot(WeaponCatalog.get_definition(EquipmentCatalog.KNIFE).slot)
	effects.refresh_cosmetics()
	_show_sandbox_shop("Carrying the %s" % WeaponModels.display_name(model_id)
		+ ("" if saved == OK else " (could not save: %s)" % error_string(saved)))


func _take_sandbox_item(id: StringName) -> void:
	match ShopCatalog.kind(id):
		ShopCatalog.KIND_WEAPON:
			player.weapons.give_weapon(id)
		ShopCatalog.KIND_ARMOUR:
			player.health.armour = ShopCatalog.FULL_ARMOUR
			player.health.has_helmet = player.health.has_helmet or id == ShopCatalog.ARMOUR_VEST_HELMET
		ShopCatalog.KIND_UTILITY:
			player.weapons.give_utility(id)
		_:
			return
	_show_sandbox_shop("Equipped %s" % ShopCatalog.display_name(id))


func _close_sandbox_shop() -> void:
	if _sandbox_shop == null or not _sandbox_shop.is_buy_menu_open():
		return
	_sandbox_shop.hide_buy_menu()
	if not is_paused:
		player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn_player() -> void:
	_respawn_left = -1.0
	hud.set_death_state(-1.0)
	player.respawn()


func is_awaiting_respawn() -> bool:
	return _respawn_left >= 0.0


func _update_combat_hud() -> void:
	var weapon := player.weapons.current()
	if weapon != null and weapon.definition.is_firearm():
		hud.set_weapon(weapon.definition.display_name, weapon.ammo, weapon.reserve,
			weapon.reload_progress() if weapon.is_reloading() else -1.0)
	elif weapon != null:
		hud.set_equipment(weapon.definition.display_name, weapon.ammo if weapon.definition.is_utility() else -1)
	hud.set_utility(player.weapons.utility_counts(), weapon.definition.id if weapon != null else &"")
	hud.set_health(player.health.current, player.health.max_health)
	hud.set_crosshair_gap(_spread_to_pixels(player.weapons.current_spread()))
	if training_director != null:
		hud.set_training_stats(training_director.status_text())
		return
	hud.set_training_stats("Shots %d · Hits %d · Accuracy %d%% · Headshots %d%% · Kills %d · Damage %d" % [
		tally.shots, tally.hits, roundi(tally.accuracy() * 100.0), roundi(tally.headshot_rate() * 100.0),
		tally.kills, tally.damage,
	])


## Converts a spread half-angle (degrees) into a crosshair gap in screen pixels.
func _spread_to_pixels(spread_degrees: float) -> float:
	var half_height := get_viewport().get_visible_rect().size.y / 2.0
	var half_fov := deg_to_rad(player.camera.fov / 2.0)
	return tan(deg_to_rad(spread_degrees)) / tan(half_fov) * half_height + 3.0


func _on_shot_fired(_origin: Vector3, _end: Vector3, _result: Hitscan.Result) -> void:
	tally.record_shot()


func _on_target_hit(info: DamageInfo, target: Health, killed: bool) -> void:
	tally.record_hit(info, killed)
	hud.show_hit_marker(info.is_headshot(), killed)
	if killed and match_director == null:
		var weapon := WeaponCatalog.get_definition(info.weapon_id)
		var bot_name := _sandbox_bots.display_name_for(target.owner_id)
		hud.push_feed("You  [%s%s]  %s  · %.0f m" % [
			weapon.display_name if weapon != null else "?", " · HEADSHOT" if info.is_headshot() else "",
			bot_name if not bot_name.is_empty() else "Target dummy", info.distance])


func _on_player_died(info: DamageInfo) -> void:
	if match_director != null:
		return
	if training_director != null:
		respawn_player()
		return
	_close_sandbox_shop()
	_death_cause = "Fell out of the world" if info.cause == DamageInfo.CAUSE_WORLD else "Killed"
	var bot_name := _sandbox_bots.display_name_for(info.source_id)
	if not bot_name.is_empty():
		_death_cause = "Killed by %s" % bot_name
	_respawn_left = respawn_delay
	hud.set_death_state(_respawn_left, _death_cause)


func pause() -> void:
	_close_sandbox_shop()
	if _sandbox_bots != null:
		_sandbox_bots.set_paused(true)
	if match_director != null:
		match_director.close_buy_menu()
		match_director.paused = true
		# Pause only the local practice simulation. The menu and career networking stay active.
		level.process_mode = Node.PROCESS_MODE_DISABLED
		player.process_mode = Node.PROCESS_MODE_DISABLED
	is_paused = true
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_paused(true)


func resume() -> void:
	if _sandbox_bots != null:
		_sandbox_bots.set_paused(false)
	if match_director != null:
		match_director.paused = false
		level.process_mode = Node.PROCESS_MODE_INHERIT
		player.process_mode = Node.PROCESS_MODE_INHERIT
		if match_director.state.phase == MatchState.Phase.MATCH_END:
			is_paused = false
			hud.set_paused(false)
			return
	is_paused = false
	if training_director != null and training_director.is_finished():
		hud.set_paused(false)
		return
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_paused(false)


func _on_main_menu_requested() -> void:
	match_session.leave("left the FPS runtime")
	if match_director != null and App.is_playtesting():
		App.end_playtest()
		return
	App.playtest_map = null
	if training_director != null and training_director.session != null and not training_director.is_finished():
		App.report_training_finished(training_director.session.abandon())
	if _is_career_fixture() or App.is_career_training():
		App.open_career_hub()
	else:
		App.go_to(App.SCENE_MAIN_MENU)


func _on_return_to_editor() -> void:
	match_session.leave("returned to editor")
	App.end_playtest()


func _on_host_match_requested(port: int) -> void:
	var err := match_session.host(port)
	if err == OK:
		if _sandbox_bots != null:
			_sandbox_bots.clear()
		_last_network_message = "Hosting on port %d" % port
	else:
		_last_network_message = "Could not host on port %d (error %d)" % [port, err]


func _on_join_match_requested(address: String, port: int) -> void:
	var err := match_session.join(address, port)
	if err == OK:
		if _sandbox_bots != null:
			_sandbox_bots.clear()
		_last_network_message = "Connecting to %s:%d..." % [address, port]
	else:
		_last_network_message = "Could not start connection (error %d)" % err


func _on_session_ended(reason: String) -> void:
	_last_network_message = "Session ended: %s" % reason


func _update_network_hud() -> void:
	var role := match_session.role
	var badge := ""
	var status := _last_network_message if not _last_network_message.is_empty() else "Offline"
	if match_session.is_connected_to_match():
		var role_text := "HOST" if role == MatchSession.Role.HOST else "CLIENT"
		badge = "NET %s · peer %d · %d player(s)" % [role_text, match_session.local_peer_id(), match_session.player_count()]
		status = "%s · match %s" % [badge, match_session.match_id]
	elif role == MatchSession.Role.CLIENT:
		badge = "NET connecting..."
	hud.set_network_state(match_session.is_active(), status, badge)
