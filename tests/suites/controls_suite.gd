extends TestSuite
## Button remapping (up to four bindings per action, saved to disk) and sandbox noclip.

const CONTROLS_SCENE: String = "res://scenes/settings/controls_screen.tscn"
const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const TEST_PATH: String = "user://tests/input_bindings_test.json"


func suite_name() -> String:
	return "Controls: remapping and noclip"


func run() -> void:
	# Keep whatever bindings this machine's player has; the tests put them back at the end.
	var original := InputBindings.to_dict()["actions"] as Dictionary
	DirAccess.make_dir_recursive_absolute("user://tests")
	InputBindings.reset_all()
	_test_bindings()
	await _test_screen()
	await _test_noclip()
	InputBindings.reset_all()
	for action: String in original:
		var list: Array[String] = []
		list.assign(original[action] as Array)
		InputBindings.set_bindings(StringName(action), list)
	DirAccess.remove_absolute(TEST_PATH)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _test_bindings() -> void:
	section("Bindings: four slots, conflicts, save and load")
	var ids: Dictionary[StringName, bool] = {}
	var defaults_ok := true
	for definition: Dictionary in InputActions.DEFINITIONS:
		ids[definition["id"]] = true
		for binding: String in definition["defaults"]:
			defaults_ok = defaults_ok and InputActions.binding_to_event(binding) != null
		defaults_ok = defaults_ok and InputActions.GROUP_ORDER.has(str(definition["group"]))
	check(ids.size() == InputActions.DEFINITIONS.size() and defaults_ok, "every action has a unique ID, a group and valid defaults")
	check(InputBindings.bindings(InputActions.MOVE_FORWARD) == ["key:%d" % KEY_W] and InputBindings.bindings(InputActions.FIRE) == ["mouse:1"]
		and InputBindings.bindings(InputActions.CROUCH).size() == 2, "defaults are registered (W, left mouse, two crouch keys)")
	check(InputBindings.bindings(InputActions.NOCLIP) == ["key:%d" % KEY_V], "noclip defaults to V")
	check(InputActions.event_to_binding(_key(KEY_K)) == "key:%d" % KEY_K and InputActions.event_to_binding(_mouse(MOUSE_BUTTON_XBUTTON1)) == "mouse:8"
		and InputActions.event_to_binding(InputEventMouseMotion.new()).is_empty() and InputActions.binding_to_event("key:abc") == null
		and InputActions.binding_to_event("pad:3") == null, "events convert to binding strings and back; anything else is rejected")
	check(InputBindings.label("key:%d" % KEY_W) == "W" and InputBindings.label("mouse:1") == "Left mouse", "bindings have readable names")

	var jump := InputActions.JUMP
	for code: Key in [KEY_K, KEY_L, KEY_M]:
		InputBindings.assign(jump, InputBindings.MAX_BINDINGS - 1, "key:%d" % code)
	check(InputBindings.bindings(jump).size() == 4 and InputBindings.bindings(jump)[0] == "key:%d" % KEY_SPACE,
		"an action takes up to four bindings")
	var press := _key(KEY_L)
	check(press.is_action_pressed(jump) and _key(KEY_SPACE).is_action_pressed(jump) and _key(KEY_M).is_action_pressed(jump),
		"every bound key triggers the action")
	InputBindings.assign(jump, 3, "key:%d" % KEY_N)
	check(InputBindings.bindings(jump).size() == 4 and InputBindings.bindings(jump)[3] == "key:%d" % KEY_N
		and not _key(KEY_M).is_action_pressed(jump), "a fifth binding replaces the chosen slot, never a fifth slot")
	check(InputBindings.assign(jump, 4, "key:%d" % KEY_P) == null, "there is no fifth slot")
	InputBindings.assign(jump, 1, "key:%d" % KEY_N)
	check(InputBindings.bindings(jump).count("key:%d" % KEY_N) == 1 and InputBindings.bindings(jump).size() == 3,
		"the same key is never bound twice to one action")

	var taken: Array[StringName] = InputBindings.assign(jump, 3, "key:%d" % KEY_R)
	check(taken == [InputActions.RELOAD] and InputBindings.bindings(InputActions.RELOAD).is_empty() and _key(KEY_R).is_action_pressed(jump),
		"binding a key used by another game action moves it and reports which action lost it")
	var shared: Array[StringName] = InputBindings.assign(InputActions.EDITOR_DOWN, 1, "key:%d" % KEY_E)
	check(shared == [InputActions.EDITOR_UP] and InputBindings.bindings(InputActions.INTERACT) == ["key:%d" % KEY_E],
		"game and editor controls may share a key; conflicts only count within one mode")
	check(InputBindings.assign(jump, 0, "key:%d" % KEY_ESCAPE) == null and InputBindings.refusal(jump, "key:%d" % KEY_ESCAPE).contains("reserved")
		and InputBindings.assign(InputActions.PAUSE_MENU, 0, "key:%d" % KEY_P) == null
		and InputBindings.bindings(InputActions.PAUSE_MENU) == ["key:%d" % KEY_ESCAPE], "Esc stays on the pause menu and cannot be taken or changed")
	check(InputBindings.clear_slot(jump, 0) and not _key(KEY_SPACE).is_action_pressed(jump) and not InputBindings.clear_slot(jump, 9),
		"a slot can be cleared")

	check(InputBindings.save(TEST_PATH) == OK, "bindings are saved")
	var saved := JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH)) as Dictionary
	check(saved["format"] == InputBindings.FORMAT and int(saved["format_version"]) == 1
		and not (saved["actions"] as Dictionary).has("pause_menu"), "the file has a format and version")
	var custom := InputBindings.bindings(jump)
	InputBindings.reset_all()
	check(InputBindings.bindings(jump) == ["key:%d" % KEY_SPACE] and InputBindings.bindings(InputActions.RELOAD) == ["key:%d" % KEY_R],
		"reset restores every default")
	check(InputBindings.load_file(TEST_PATH) and InputBindings.bindings(jump) == custom and InputBindings.bindings(InputActions.RELOAD).is_empty(),
		"loading restores the saved bindings, including an action left with none")
	var odd := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	odd.store_string(JSON.stringify({"format": InputBindings.FORMAT, "format_version": 1, "actions": {
		"jump": ["key:%d" % KEY_J, "nonsense", 7, "key:%d" % KEY_ESCAPE], "made_up_action": ["key:65"], "pause_menu": ["key:80"]}}))
	odd.close()
	check(InputBindings.load_file(TEST_PATH) and InputBindings.bindings(jump) == ["key:%d" % KEY_J]
		and InputBindings.bindings(InputActions.PAUSE_MENU) == ["key:%d" % KEY_ESCAPE] and not InputMap.has_action(&"made_up_action"),
		"invalid entries, unknown actions and locked actions in a file are ignored")
	odd = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	odd.store_string("{\"format\": \"f2f.input_bindings\", \"format_version\": 2, \"actions\": {}}")
	odd.close()
	check(not InputBindings.load_file(TEST_PATH) and not InputBindings.load_file("user://tests/none.json")
		and InputBindings.bindings(jump) == ["key:%d" % KEY_J], "an unsupported or missing file changes nothing")
	InputBindings.reset_all()


func _test_screen() -> void:
	section("Controls screen")
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)
	var menu_button := tree.current_scene.get("controls_button") as Button
	check(menu_button != null and menu_button.text == "Controls", "the main menu has a Controls entry")
	menu_button.pressed.emit()
	await wait_frames(3)
	var screen := tree.current_scene as ControlsScreen
	check(screen != null and App.current_scene_id == App.SCENE_CONTROLS, "it opens the Controls screen")
	if screen == null:
		return
	screen.bindings_path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	var rows_ok := true
	for action: StringName in InputActions.all_actions():
		rows_ok = rows_ok and screen.slot_buttons.has(action) and screen.slot_buttons[action].size() == 4
	check(rows_ok, "every action has a row of four slots")
	var forward := screen.slot_buttons[InputActions.MOVE_FORWARD] as Array
	check((forward[0] as Button).text == "W" and (forward[1] as Button).text == "—" and not (forward[1] as Button).disabled
		and (forward[2] as Button).disabled, "slots show the bound key; only the next empty slot can be filled")
	check((screen.slot_buttons[InputActions.PAUSE_MENU][0] as Button).disabled, "the pause key is shown but locked")

	(forward[1] as Button).pressed.emit()
	check(screen.is_listening() and (forward[1] as Button).text == "press…", "clicking a slot waits for an input")
	check(screen.apply_event(_key(KEY_UP)) and not screen.is_listening() and (forward[1] as Button).text == "Up"
		and _key(KEY_UP).is_action_pressed(InputActions.MOVE_FORWARD) and _key(KEY_W).is_action_pressed(InputActions.MOVE_FORWARD),
		"the pressed key becomes a second binding")
	check(FileAccess.file_exists(TEST_PATH), "the change is saved at once")
	screen.begin_listen(InputActions.MOVE_FORWARD, 2)
	check(screen.apply_event(_mouse(MOUSE_BUTTON_XBUTTON1)) and (forward[2] as Button).text == "Mouse 4", "mouse buttons can be bound")
	screen.begin_listen(InputActions.MOVE_FORWARD, 3)
	check(screen.apply_event(_key(KEY_ESCAPE)) and not screen.is_listening() and (forward[3] as Button).text == "—", "Esc cancels without binding")
	screen.begin_listen(InputActions.MOVE_FORWARD, 3)
	check(screen.apply_event(_key(KEY_S)) and (screen.slot_buttons[InputActions.MOVE_BACK][0] as Button).text == "—"
		and (forward[3] as Button).text == "S", "taking another action's key updates both rows")
	screen.begin_listen(InputActions.MOVE_FORWARD, 0)
	check(screen.apply_event(_key(KEY_BACKSPACE)) and (forward[0] as Button).text == "Up" and (forward[3] as Button).text == "—",
		"Backspace clears the slot and the rest move up")
	check(not screen.begin_listen(InputActions.PAUSE_MENU, 0) and not screen.apply_event(_key(KEY_Q)), "nothing is captured when not listening")
	screen.reset_action(InputActions.MOVE_FORWARD)
	check(InputBindings.bindings(InputActions.MOVE_FORWARD) == ["key:%d" % KEY_W], "Default resets one action")
	screen.reset_button.pressed.emit()
	check(InputBindings.bindings(InputActions.MOVE_BACK) == ["key:%d" % KEY_S], "Reset all restores the defaults")
	screen.back_button.pressed.emit()
	await wait_frames(3)
	check(App.current_scene_id == App.SCENE_MAIN_MENU, "Back returns to the main menu")


func _test_noclip() -> void:
	section("Sandbox noclip")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var player := sandbox.get_node("Player") as FirstPersonController
	var hud := sandbox.get_node("Hud") as SandboxHud
	player.input_enabled = false
	check(player.noclip_allowed and not player.noclip, "the sandbox allows noclip; it starts off")
	check(player.set_noclip(true) and player.noclip and player.collision.disabled, "noclip switches collision off")
	var start := player.global_position
	player.scripted_climb = 1.0
	await wait_physics_frames(30)
	check(player.global_position.y > start.y + 3.0, "the player flies up with no gravity (%.1f m)" % (player.global_position.y - start.y))
	player.scripted_climb = 0.0
	var hover := player.global_position.y
	await wait_physics_frames(20)
	check(is_equal_approx(player.global_position.y, hover) and not player.health.is_dead, "it hovers when no key is held")
	# Fly straight down through the floor.
	player.scripted_climb = -1.0
	await wait_physics_frames(80)
	check(player.global_position.y < -2.0, "it passes through the floor (y %.1f)" % player.global_position.y)
	player.scripted_climb = 0.0
	player.global_position = Vector3(0, -80, 0)
	await wait_physics_frames(5)
	check(not player.health.is_dead, "falling out of the world does not kill while noclipping")
	player.global_position = start + Vector3(0, 4, 0)
	check(player.set_noclip(false) and not player.collision.disabled, "noclip switches off")
	var landed := await wait_until(func() -> bool: return player.is_on_floor(), 3.0)
	check(landed and absf(player.global_position.y - start.y) < 0.3, "gravity and collision return")
	var toggle := _key(KEY_V)
	check(toggle.is_action_pressed(InputActions.NOCLIP), "V is the noclip key")

	hud.open_controls()
	await wait_frames(2)
	check(hud.controls_screen != null and hud.controls_screen.embedded, "the pause menu opens Controls as an overlay")
	hud.controls_screen.back_button.pressed.emit()
	await wait_frames(2)
	check(hud.controls_screen == null and tree.root.is_ancestor_of(sandbox), "closing it returns to the game without leaving the map")
	await despawn(sandbox)

	var setup := MatchSetup.new()
	setup.fixture_id = "noclip_test"
	setup.home_team_id = "team_a"
	setup.away_team_id = "team_b"
	setup.max_rounds = 2
	var map := MapTemplates.sandbox_arena()
	setup.map_id = map.map_id
	App.pending_match_setup = setup
	App.pending_match_rules = MatchRules.practice(2)
	App.pending_match_map = map
	App.pending_match_options = {"opponents": "passive"}
	sandbox = spawn_scene(FPS_SANDBOX_SCENE)
	await wait_physics_frames(3)
	player = sandbox.get_node("Player") as FirstPersonController
	check(sandbox.get("match_director") != null and not player.noclip_allowed and not player.set_noclip(true) and not player.noclip,
		"noclip is refused during a match")
	App.last_match_result = null
	await despawn(sandbox)
	await wait_frames(2)
