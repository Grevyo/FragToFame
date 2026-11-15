extends SceneTree
## Developer aid (needs a window, not headless): opens Kilnmarket in the Creation Studio and
## saves an overhead and a perspective screenshot to user://screens/.
##
## Run:  <godot> --path <project> --script res://tools/capture_kilnmarket.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var studio: Node = (load("res://scenes/creation_studio/creation_studio.tscn") as PackedScene).instantiate()
	root.add_child(studio)
	await process_frame
	(studio.get("ui") as StudioUI).confirm_dialog.hide()
	studio.call("load_official", OfficialMaps.DEFAULT_ID)
	(studio.get("ui") as StudioUI).hide()
	var camera := studio.get("camera") as EditorFlyCamera
	DirAccess.make_dir_recursive_absolute("user://screens")
	studio.call("set_overhead", true)
	camera.size = 125.0
	camera.position = Vector3(1, 150, 9)
	await _shot("user://screens/kilnmarket_top.png")
	studio.call("set_overhead", false)
	camera.set_view(Transform3D(Basis.IDENTITY, Vector3(-51, 1.62, 44)))
	await _shot("user://screens/kilnmarket_salt_road.png")
	camera.set_view(Transform3D(Basis(Vector3.UP, PI), Vector3(48, 4.1, -23)))
	await _shot("user://screens/kilnmarket_overlook.png")
	quit(0)


func _shot(path: String) -> void:
	for i: int in 8:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
