extends SceneTree
## Developer aid (needs a window, not headless): opens a map in the Creation Studio and saves an
## overhead screenshot plus any perspective shots to user://screens/.
##
## Run:  <godot> --path <project> --script res://tools/capture_map.gd -- <map file or official id>
##       [x,y,z,yaw_degrees ...]   (each extra argument is one perspective shot from that point)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass a map file path or an official map ID.")
		quit(1)
		return
	var studio: Node = (load("res://scenes/creation_studio/creation_studio.tscn") as PackedScene).instantiate()
	root.add_child(studio)
	await process_frame
	(studio.get("ui") as StudioUI).confirm_dialog.hide()
	var source := args[0]
	var loaded := bool(studio.call("load_official", source)) if OfficialMaps.is_official(source) \
		else bool(studio.call("load_map", source))
	if not loaded:
		printerr("Could not open ", source)
		quit(1)
		return
	var doc := (studio.get("controller") as MapEditController).document
	var box := AABB()
	for piece: Dictionary in doc.pieces:
		box = box.merge(AABB(piece["position"] as Vector3, Vector3.ONE))
	# Hide tactics, gameplay and roof layers so the shots show the playable space.
	var controller := studio.get("controller") as MapEditController
	for entry: Dictionary in doc.layers.duplicate():
		var layer_name := str(entry["name"])
		if layer_name.contains("Tactics") or layer_name.contains("Gameplay") or layer_name.contains("hide"):
			controller.set_layer_field(str(entry["id"]), "visible", false)
	(studio.get("ui") as StudioUI).hide()
	var camera := studio.get("camera") as EditorFlyCamera
	DirAccess.make_dir_recursive_absolute("user://screens")
	studio.call("set_overhead", true)
	camera.size = maxf(box.size.x, box.size.z) * 1.05
	camera.position = Vector3(box.get_center().x, 150, box.get_center().z)
	await _shot("user://screens/%s_top.png" % doc.map_id)
	studio.call("set_overhead", false)
	for index: int in range(1, args.size()):
		var parts := args[index].split(",")
		if parts.size() < 4:
			continue
		var at := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		camera.set_view(Transform3D(Basis(Vector3.UP, deg_to_rad(float(parts[3]))), at))
		await _shot("user://screens/%s_%d.png" % [doc.map_id, index])
	quit(0)


func _shot(path: String) -> void:
	for i: int in 8:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
