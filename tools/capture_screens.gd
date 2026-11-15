extends SceneTree
## Developer tool: renders key screens and saves PNGs to user://screens (needs a real window,
## not --headless). Run:  <godot> --path . --script res://tools/capture_screens.gd
## Output folder: %APPDATA%/Godot/app_userdata/Frag to Fame/screens


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://screens")
	await _frames(5)
	var app := root.get_node("App")

	app.call("go_to", &"main_menu")
	await _shot("01_main_menu")

	app.call("go_to", &"career_hub")
	await _frames(3)
	current_scene.call("show_page", &"coop")
	await _shot("02_career_hub_coop")

	# Career screens use a throwaway save folder so real careers are untouched.
	app.set("career_saves", CareerSaves.new("user://screens/careers"))
	app.call("go_to", &"career_select")
	await _frames(3)
	var select := current_scene
	(select.get("first_name_edit") as LineEdit).text = "Rowan"
	(select.get("last_name_edit") as LineEdit).text = "Hartley"
	(select.get("nickname_edit") as LineEdit).text = "Sable"
	await _shot("11_career_select")
	(select.get("seed_edit") as LineEdit).text = "77"
	select.call("create_career")
	await _frames(4)
	await _shot("12_career_home")
	current_scene.call("show_page", &"teams")
	await _shot("13_career_teams")
	current_scene.call("show_page", &"players")
	await _frames(2)
	var players: Node = current_scene.get("current_page")
	var first_id := str((app.get("career") as CareerSession).repo.search_players({"limit": 1})[0]["id"])
	players.call("show_player", first_id)
	await _shot("14_career_players")
	current_scene.call("show_page", &"profile")
	await _shot("15_career_profile")
	app.call("close_career")

	app.call("go_to", &"creation_studio")
	await _frames(3)
	var studio := current_scene
	studio.call("load_template", "sandbox_arena")
	var ctl: RefCounted = studio.get("controller")
	ctl.call("select", "pc_13")
	await _shot("03_creation_studio")

	studio.call("_on_piece_type_selected", "crate")
	ctl.call("select", "")
	await _shot("04_creation_studio_place")

	app.call("go_to", &"fps_sandbox")
	await _frames(10)
	current_scene.call("pause")
	await _shot("05_fps_sandbox_paused")
	current_scene.call("resume")
	await _shot("06_fps_sandbox")
	var player := current_scene.get_node("Player") as FirstPersonController
	var level := current_scene.get_node("Level") as SandboxLevel
	player.input_enabled = false
	player.face_point(level.dummies[0].zone_position(DamageModel.ZONE_CHEST))
	player.weapons.trigger = true
	for i: int in 3:
		await physics_frame
	await _shot("07_fps_firing")
	player.weapons.trigger = false
	player.wants_crouch = true
	for i: int in 30:
		await physics_frame
	player.face_point(level.dummies[1].zone_position(DamageModel.ZONE_HEAD))
	await _shot("08_fps_crouched_far_target")

	app.call("start_practice_match")
	await _frames(10)
	# Untyped on purpose: MatchDirector depends on the App autoload, which this SceneTree
	# script cannot reference at compile time.
	var director: Node = current_scene.get("match_director")
	await _shot("09_practice_match_freeze")
	director.call("open_buy_menu")
	director.call("try_buy", &"armour_vest")
	await _shot("10_practice_match_buy")
	director.call("close_buy_menu")
	quit(0)


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _shot(file_name: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://screens/%s.png" % file_name
	image.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
