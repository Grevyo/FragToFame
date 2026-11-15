extends SceneTree
## Headless smoke tests for Milestone 1.
##
## Run:  <godot> --headless --path <project> --script res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = failures.

const MAIN_MENU_SCENE: String = "res://scenes/main_menu/main_menu.tscn"
const CAREER_HUB_SCENE: String = "res://scenes/career_hub/career_hub.tscn"
const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const CREATION_STUDIO_SCENE: String = "res://scenes/creation_studio/creation_studio.tscn"

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Frag to Fame headless tests ==")
	await process_frame

	_test_app_autoload()
	_test_input_actions()
	_test_theme()
	_test_sample_data()
	await _test_main_menu()
	await _test_career_hub()
	await _test_fps_sandbox()
	await _test_creation_studio()
	await _test_scene_routing()

	print("== %d passed, %d failed ==" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- helpers ------------------------------------------------------------------------------------

func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  ", description)
	else:
		_failed += 1
		printerr("  FAIL  ", description)


func _spawn(path: String) -> Node:
	var packed := load(path) as PackedScene
	check(packed != null, "scene loads: %s" % path)
	if packed == null:
		return null
	var instance := packed.instantiate()
	check(instance != null, "scene instantiates: %s" % path)
	root.add_child(instance)
	return instance


func _wait_frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _wait_physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _despawn(node: Node) -> void:
	if node != null:
		node.queue_free()
	await process_frame


# --- tests --------------------------------------------------------------------------------------

func _test_app_autoload() -> void:
	print("[App autoload]")
	var app := root.get_node_or_null("App")
	check(app != null, "App autoload is present")
	if app == null:
		return
	var paths: Dictionary = app.get("SCENE_PATHS")
	check(paths.size() == 4, "App registers 4 top-level scenes")
	for scene_id: StringName in paths:
		check(ResourceLoader.exists(paths[scene_id] as String), "scene path exists for '%s'" % scene_id)
	check(root.theme != null, "root window theme is assigned")


func _test_input_actions() -> void:
	print("[Input actions]")
	InputActions.register_defaults()
	for action: StringName in InputActions.all_actions():
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
			"action '%s' registered with a binding" % action)


func _test_theme() -> void:
	print("[Theme]")
	var theme := F2FTheme.build()
	for variation: StringName in [&"TitleLabel", &"MenuButtonLarge", &"SidebarButton", &"CardPanel", &"DevBadgePanel"]:
		check(theme.get_type_variation_base(variation) != &"", "theme defines variation '%s'" % variation)


func _test_sample_data() -> void:
	print("[Dev sample data]")
	check(DevSampleData.IS_SAMPLE, "sample data is flagged as sample")
	check(not DevSampleData.teams().is_empty(), "sample teams present")
	var ids: Dictionary = {}
	for team: Dictionary in DevSampleData.teams():
		ids[team["id"]] = true
	check(ids.size() == DevSampleData.teams().size(), "sample team IDs are unique")
	check(DevSampleData.player_profile().has("id"), "sample player has a stable id field")


func _test_main_menu() -> void:
	print("[Main menu]")
	var menu := _spawn(MAIN_MENU_SCENE)
	if menu == null:
		return
	await _wait_frames(2)
	for button_name: String in ["career_button", "sandbox_button", "studio_button", "quit_button"]:
		var b := menu.get(button_name) as Button
		check(b != null and b.is_visible_in_tree(), "menu has visible %s" % button_name)
		if b != null:
			check(b.pressed.get_connections().size() > 0, "%s is connected" % button_name)
	var texts: Array[String] = []
	for b: Node in menu.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	for expected: String in ["Career Hub", "FPS Sandbox", "Creation Studio", "Quit"]:
		check(texts.has(expected), "menu button labelled '%s'" % expected)
	var labels: Array[String] = []
	for l: Node in menu.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	check(labels.has("FRAG TO FAME"), "title text shown")
	check(labels.has("FPS Career Simulator"), "subtitle text shown")
	await _despawn(menu)


func _test_career_hub() -> void:
	print("[Career Hub]")
	var hub := _spawn(CAREER_HUB_SCENE)
	if hub == null:
		return
	await _wait_frames(2)
	check(hub.get("current_page_id") == &"home", "hub opens on Home")
	var expected_titles: Dictionary[StringName, String] = {
		&"home": "Home", &"profile": "Player Profile", &"teams": "Teams",
		&"competitions": "Competitions", &"calendar": "Calendar", &"statistics": "Statistics",
	}
	for page_id: StringName in expected_titles:
		var ok: bool = hub.call("show_page", page_id)
		await _wait_frames(1)
		var page := hub.get("current_page") as CareerPage
		check(ok and page != null and page.get_page_title() == expected_titles[page_id],
			"page '%s' shows '%s'" % [page_id, expected_titles[page_id]])
		check(page != null and page.get_child_count() > 0, "page '%s' has content" % page_id)
	# Pages must be replaced, not stacked.
	var holder := (hub.get("current_page") as Node).get_parent()
	check(holder.get_child_count() == 1, "only one page is mounted at a time")
	var bad: bool = hub.call("show_page", &"does_not_exist")
	check(not bad, "unknown page id is rejected")
	var menu_button := hub.get("main_menu_button") as Button
	check(menu_button != null and menu_button.pressed.get_connections().size() > 0, "main menu button connected")
	await _despawn(hub)


func _test_fps_sandbox() -> void:
	print("[FPS Sandbox]")
	var sandbox := _spawn(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await _wait_frames(1)
	var player := sandbox.get_node_or_null("Player") as FirstPersonController
	check(player != null, "player controller present")
	check(sandbox.get_node_or_null("Player/Head/Camera") is Camera3D, "first-person camera present")
	var level := sandbox.get_node_or_null("Level")
	check(level != null and level.get_child_count() > 10, "level geometry built")
	if player == null:
		await _despawn(sandbox)
		return
	await _wait_physics_frames(45)
	check(player.is_on_floor(), "player lands on the floor (collision works)")
	check(player.global_position.y > -0.2 and player.global_position.y < 0.3, "player rests near ground height")
	var yaw_before := player.rotation.y
	player.look(Vector2(100, 50))
	check(not is_equal_approx(player.rotation.y, yaw_before), "mouse look rotates yaw")
	player.look(Vector2(0, 100000))
	check(player.head.rotation.x >= deg_to_rad(-89.01), "pitch is clamped")
	sandbox.call("pause")
	check(sandbox.get("is_paused") == true and not player.input_enabled, "pause disables player input")
	var hud := sandbox.get_node("Hud") as SandboxHud
	check(hud.pause_overlay.visible, "pause overlay visible when paused")
	check(hud.main_menu_button.pressed.get_connections().size() > 0, "return-to-menu button connected")
	sandbox.call("resume")
	check(sandbox.get("is_paused") == false and player.input_enabled, "resume re-enables player input")
	player.global_position = Vector3(0, -40, 0)
	await _wait_physics_frames(2)
	check(player.global_position.y > -1.0, "falling out of the world respawns the player")
	await _despawn(sandbox)


func _test_creation_studio() -> void:
	print("[Creation Studio]")
	var studio := _spawn(CREATION_STUDIO_SCENE)
	if studio == null:
		return
	await _wait_frames(2)
	var camera := studio.get_node_or_null("EditorCamera") as EditorFlyCamera
	check(camera != null and camera.current, "editor fly camera is current")
	var grid := studio.get_node_or_null("Grid") as EditorGrid
	check(grid != null and grid.line_count() > 0, "grid mesh generated")
	if grid != null:
		var lines_at_1m := grid.line_count()
		studio.call("set_snap_size", 0.5)
		check(grid.line_count() > lines_at_1m, "finer snap produces more grid lines")
		studio.call("set_snap_size", 1.0)
	# Use the stretched visible rect (same space as get_mouse_position), not the raw window size.
	var screen_centre := root.get_visible_rect().size / 2.0
	var cell: Variant = studio.call("ground_cell_at", screen_centre)
	check(cell is Vector3, "screen centre ray hits the ground plane")
	if cell is Vector3:
		var v := cell as Vector3
		check(is_equal_approx(fposmod(v.x, 1.0), 0.5) and is_equal_approx(fposmod(v.z, 1.0), 0.5),
			"cursor snaps to 1 m cell centres")
	if camera != null:
		camera.position = Vector3(100, 100, 100)
		camera.reset_view()
		check(camera.position.is_equal_approx(EditorFlyCamera.DEFAULT_POSITION), "reset view restores camera")
	var menu_button := studio.get("main_menu_button") as Button
	check(menu_button != null and menu_button.pressed.get_connections().size() > 0, "main menu button connected")
	await _despawn(studio)


func _test_scene_routing() -> void:
	print("[Scene routing via App.go_to]")
	var app := root.get_node_or_null("App")
	if app == null:
		check(false, "App autoload required for routing test")
		return
	var paths: Dictionary = app.get("SCENE_PATHS")
	for scene_id: StringName in [&"career_hub", &"fps_sandbox", &"creation_studio", &"main_menu"]:
		var err: Error = app.call("go_to", scene_id)
		await _wait_frames(3)
		check(err == OK and current_scene != null and current_scene.scene_file_path == paths[scene_id],
			"go_to('%s') switches the active scene" % scene_id)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or scene_id == &"fps_sandbox",
			"mouse released after entering '%s'" % scene_id)
	var bad: Error = app.call("go_to", &"nope")
	check(bad == ERR_DOES_NOT_EXIST, "go_to rejects unknown scene id")
