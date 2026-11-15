class_name FoundationSuite
extends TestSuite
## Milestone 1 foundation: autoloads, input, theme, sample data, all four scenes, routing.

const MAIN_MENU_SCENE: String = "res://scenes/main_menu/main_menu.tscn"
const CAREER_HUB_SCENE: String = "res://scenes/career_hub/career_hub.tscn"
const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const CREATION_STUDIO_SCENE: String = "res://scenes/creation_studio/creation_studio.tscn"


func suite_name() -> String:
	return "Foundation"


func run() -> void:
	_test_app_autoload()
	_test_input_actions()
	_test_theme()
	_test_sample_data()
	await _test_main_menu()
	await _test_career_hub()
	await _test_fps_sandbox()
	await _test_creation_studio()
	await _test_scene_routing()



func _test_app_autoload() -> void:
	section("App autoload")
	var app := tree.root.get_node_or_null("App")
	check(app != null, "App autoload is present")
	check(tree.root.get_node_or_null("CareerSync") != null, "CareerSync autoload is present")
	if app == null:
		return
	var paths: Dictionary = app.get("SCENE_PATHS")
	check(paths.size() == 4, "App registers 4 top-level scenes")
	for scene_id: StringName in paths:
		check(ResourceLoader.exists(paths[scene_id] as String), "scene path exists for '%s'" % scene_id)
	check(tree.root.theme != null, "root window theme is assigned")
	var layer := CanvasLayer.new()
	var probe := Label.new()
	probe.theme_type_variation = &"LogoLabel"
	layer.add_child(probe)
	tree.root.add_child(layer)
	check(probe.get_theme_color(&"font_color") == F2FTheme.ACCENT, "controls under a CanvasLayer get the F2F theme")
	layer.free()


func _test_input_actions() -> void:
	section("Input actions")
	InputActions.register_defaults()
	for action: StringName in InputActions.all_actions():
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
			"action '%s' registered with a binding" % action)


func _test_theme() -> void:
	section("Theme")
	var theme := F2FTheme.build()
	for variation: StringName in [&"TitleLabel", &"MenuButtonLarge", &"SidebarButton", &"CardPanel", &"DevBadgePanel"]:
		check(theme.get_type_variation_base(variation) != &"", "theme defines variation '%s'" % variation)


func _test_sample_data() -> void:
	section("Dev sample data")
	check(DevSampleData.IS_SAMPLE, "sample data is flagged as sample")
	check(not DevSampleData.teams().is_empty(), "sample teams present")
	var ids: Dictionary = {}
	for team: Dictionary in DevSampleData.teams():
		ids[team["id"]] = true
	check(ids.size() == DevSampleData.teams().size(), "sample team IDs are unique")
	check(DevSampleData.player_profile().has("id"), "sample player has a stable id field")


func _test_main_menu() -> void:
	section("Main menu")
	var menu := spawn_scene(MAIN_MENU_SCENE)
	if menu == null:
		return
	await wait_frames(2)
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
	await despawn(menu)


func _test_career_hub() -> void:
	section("Career Hub")
	var hub := spawn_scene(CAREER_HUB_SCENE)
	if hub == null:
		return
	await wait_frames(2)
	check(hub.get("current_page_id") == &"home", "hub opens on Home")
	var expected_titles: Dictionary[StringName, String] = {
		&"home": "Home", &"profile": "Player Profile", &"teams": "Teams",
		&"competitions": "Competitions", &"calendar": "Calendar", &"statistics": "Statistics",
		&"coop": "Co-op (Dev)",
	}
	for page_id: StringName in expected_titles:
		var ok: bool = hub.call("show_page", page_id)
		await wait_frames(1)
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
	await despawn(hub)


func _test_fps_sandbox() -> void:
	section("FPS Sandbox")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_frames(1)
	var player := sandbox.get_node_or_null("Player") as FirstPersonController
	check(player != null, "player controller present")
	check(sandbox.get_node_or_null("Player/Head/Camera") is Camera3D, "first-person camera present")
	var session := sandbox.get_node_or_null("MatchSession") as MatchSession
	check(session != null and not session.is_active(), "match session present and offline by default")
	var level := sandbox.get_node_or_null("Level") as SandboxLevel
	check(level != null and level.map_root != null and level.map_root.get_child_count() > 10,
		"default arena map built from map pieces")
	check(level != null and level.document.map_id == "map_dev_sandbox_arena", "sandbox uses the editable arena map")
	if player == null:
		await despawn(sandbox)
		return
	await wait_physics_frames(45)
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
	sandbox.set("respawn_delay", 0.2)
	player.global_position = Vector3(0, -40, 0)
	await wait_physics_frames(2)
	check(player.health.is_dead, "falling out of the world kills the player")
	var back := await wait_until(func() -> bool: return not player.health.is_dead, 2.0)
	check(back and player.global_position.y > -1.0, "player respawns at the spawn after the delay")
	await despawn(sandbox)


func _test_creation_studio() -> void:
	section("Creation Studio")
	var studio := spawn_scene(CREATION_STUDIO_SCENE)
	if studio == null:
		return
	await wait_frames(2)
	var camera := studio.get_node_or_null("EditorCamera") as EditorFlyCamera
	check(camera != null and camera.current, "editor fly camera is current")
	var grid := studio.get_node_or_null("Grid") as EditorGrid
	check(grid != null and grid.line_count() > 0, "grid mesh generated")
	if grid != null:
		var lines_at_1m := grid.line_count()
		studio.call("_set_snap", 0.5)
		check(grid.line_count() > lines_at_1m, "finer snap produces more grid lines")
		studio.call("_set_snap", 1.0)
	# Use the stretched visible rect (same space as get_mouse_position), not the raw window size.
	var screen_centre := tree.root.get_visible_rect().size / 2.0
	var point: Variant = studio.call("placement_point", screen_centre)
	check(point is Vector3, "screen centre ray finds a placement point")
	if point is Vector3:
		var v := point as Vector3
		check(is_equal_approx(fposmod(v.x, 1.0), 0.0) and is_equal_approx(fposmod(v.z, 1.0), 0.0),
			"placement snaps to the 1 m grid")
	if camera != null:
		camera.position = Vector3(100, 100, 100)
		camera.reset_view()
		check(camera.position.is_equal_approx(EditorFlyCamera.DEFAULT_POSITION), "reset view restores camera")
	var ui := studio.get_node_or_null("UI/StudioUI") as StudioUI
	check(ui != null and ui.main_menu_button.pressed.get_connections().size() > 0, "main menu button connected")
	await despawn(studio)


func _test_scene_routing() -> void:
	section("Scene routing via App.go_to")
	var app := tree.root.get_node_or_null("App")
	if app == null:
		check(false, "App autoload required for routing test")
		return
	var paths: Dictionary = app.get("SCENE_PATHS")
	for scene_id: StringName in [&"career_hub", &"fps_sandbox", &"creation_studio", &"main_menu"]:
		var err: Error = app.call("go_to", scene_id)
		await wait_frames(3)
		check(err == OK and tree.current_scene != null and tree.current_scene.scene_file_path == paths[scene_id],
			"go_to('%s') switches the active scene" % scene_id)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or scene_id == &"fps_sandbox",
			"mouse released after entering '%s'" % scene_id)
	var bad: Error = app.call("go_to", &"nope")
	check(bad == ERR_DOES_NOT_EXIST, "go_to rejects unknown scene id")
