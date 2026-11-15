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
