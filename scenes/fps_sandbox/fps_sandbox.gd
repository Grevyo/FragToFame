extends Node3D
## FPS runtime root (FPS Sandbox / map playtest): loads a map, owns mouse capture, pause and
## respawn state, records training stats, and wires the HUD to the player, the weapons and the
## local match network session.

@onready var player: FirstPersonController = $Player
@onready var hud: SandboxHud = $Hud
@onready var match_session: MatchSession = $MatchSession
@onready var level: SandboxLevel = $Level
@onready var effects: WeaponEffects = $Effects

var is_paused: bool = false
## Present only while a competitive match is running in this runtime.
var match_director: MatchDirector = null
## Seconds between the player's death and respawn.
var respawn_delay: float = 3.0
## Recorded shooting numbers for this session (shown in the HUD; not persisted yet).
var tally := CombatTally.new()
var _respawn_left: float = -1.0
var _death_cause: String = ""
var _last_network_message: String = ""
var _match_options: Dictionary = {}


func _ready() -> void:
	hud.resume_requested.connect(resume)
	hud.main_menu_requested.connect(_on_main_menu_requested)
	hud.return_to_editor_requested.connect(_on_return_to_editor)
	hud.host_match_requested.connect(_on_host_match_requested)
	hud.join_match_requested.connect(_on_join_match_requested)
	hud.leave_match_requested.connect(func() -> void: match_session.leave("left"))
	hud.practice_match_requested.connect(_on_practice_match_requested)
	match_session.local_body = player
	match_session.session_ended.connect(_on_session_ended)
	effects.bind(player.weapons, player.camera)
	player.weapons.shot_fired.connect(_on_shot_fired)
	player.weapons.target_hit.connect(_on_target_hit)
	player.died.connect(_on_player_died)
	_load_level()
	resume()


func _load_level() -> void:
	if App.has_pending_match():
		_start_match()
		return
	var playtest := App.is_playtesting()
	var doc := App.playtest_map if playtest else MapTemplates.sandbox_arena()
	level.load_map(doc)
	var spawn := level.spawn_point("attack")
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	hud.set_mode("PLAYTEST · %s" % doc.name if playtest else "FPS SANDBOX · %s" % doc.name, playtest)


func _start_match() -> void:
	var match_data := App.consume_pending_match()
	var setup := match_data[0] as MatchSetup
	var rules := match_data[1] as MatchRules
	var doc := match_data[2] as MapDocument
	_match_options = (match_data[3] as Dictionary).duplicate(true)
	level.load_map(doc, false)
	var spawn := level.spawn_point("attack")
	player.set_spawn(spawn[0] as Vector3, float(spawn[1]))
	player.weapons.set_loadout([WeaponCatalog.DEFAULT_SECONDARY])
	hud.set_mode("PRACTICE MATCH · %s" % doc.name, false, true)
	match_director = MatchDirector.new()
	match_director.name = "MatchDirector"
	add_child(match_director)
	match_director.begin(setup, rules, doc, player, level, hud, _match_options)
	match_director.hud.main_menu_requested.connect(_on_main_menu_requested)
	match_director.hud.play_again_requested.connect(_on_practice_match_requested)


## True while the match UI (buy menu, final screen) needs a free mouse cursor.
func _match_owns_mouse() -> bool:
	return match_director != null and (match_director.is_buy_menu_open()
		or match_director.state.phase == MatchState.Phase.MATCH_END)


func _on_practice_match_requested() -> void:
	match_session.leave("starting practice match")
	if match_director == null:
		App.start_practice_match(level.document)
		return
	var prior := match_director.state
	var setup := MatchSetup.from_fixture(prior.setup.to_dict())
	setup.fixture_id = Ids.generate("practice")
	App.start_match(setup, prior.rules, level.document, _match_options.duplicate(true))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU) and match_director != null and match_director.handle_escape():
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
	if click != null and click.pressed and not is_paused and not _match_owns_mouse() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var p := player.global_position
	hud.set_debug_text("pos %.1f, %.1f, %.1f   speed %.2f m/s   %s%s   %d fps" % [
		p.x, p.y, p.z, player.horizontal_speed(),
		"grounded" if player.is_on_floor() else "airborne",
		" · crouched" if player.is_crouched() else "",
		Engine.get_frames_per_second(),
	])
	_update_combat_hud()
	_update_network_hud()
	if _respawn_left >= 0.0 and not is_paused:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			respawn_player()
		else:
			hud.set_death_state(_respawn_left, _death_cause)


func respawn_player() -> void:
	_respawn_left = -1.0
	hud.set_death_state(-1.0)
	player.respawn()


func is_awaiting_respawn() -> bool:
	return _respawn_left >= 0.0


func _update_combat_hud() -> void:
	var weapon := player.weapons.current()
	if weapon != null:
		hud.set_weapon(weapon.definition.display_name, weapon.ammo, weapon.reserve,
			weapon.reload_progress() if weapon.is_reloading() else -1.0)
	hud.set_health(player.health.current, player.health.max_health)
	hud.set_crosshair_gap(_spread_to_pixels(player.weapons.current_spread()))
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


func _on_target_hit(info: DamageInfo, _target: Health, killed: bool) -> void:
	tally.record_hit(info, killed)
	hud.show_hit_marker(info.is_headshot(), killed)
	if killed and match_director == null:
		var weapon := WeaponCatalog.get_definition(info.weapon_id)
		hud.push_feed("You  [%s%s]  Target dummy  · %.0f m" % [
			weapon.display_name if weapon != null else "?", " · HEADSHOT" if info.is_headshot() else "", info.distance])


func _on_player_died(info: DamageInfo) -> void:
	if match_director != null:
		return
	_death_cause = "Fell out of the world" if info.cause == DamageInfo.CAUSE_WORLD else "Killed"
	_respawn_left = respawn_delay
	hud.set_death_state(_respawn_left, _death_cause)


func pause() -> void:
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
	if match_director != null:
		match_director.paused = false
		level.process_mode = Node.PROCESS_MODE_INHERIT
		player.process_mode = Node.PROCESS_MODE_INHERIT
		if match_director.state.phase == MatchState.Phase.MATCH_END:
			is_paused = false
			hud.set_paused(false)
			return
	is_paused = false
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_paused(false)


func _on_main_menu_requested() -> void:
	match_session.leave("returned to main menu")
	App.playtest_map = null
	App.go_to(App.SCENE_MAIN_MENU)


func _on_return_to_editor() -> void:
	match_session.leave("returned to editor")
	App.end_playtest()


func _on_host_match_requested(port: int) -> void:
	var err := match_session.host(port)
	if err == OK:
		_last_network_message = "Hosting on port %d" % port
	else:
		_last_network_message = "Could not host on port %d (error %d)" % [port, err]


func _on_join_match_requested(address: String, port: int) -> void:
	var err := match_session.join(address, port)
	if err == OK:
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
