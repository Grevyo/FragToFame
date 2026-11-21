extends SceneTree
## Developer aid (needs a window): photographs every knife look from its left side and from above,
## the butterfly knife with its handles half and fully closed, and each knife held in the FPS
## Sandbox at rest and at three points of its inspection. Saves to user://screens/knives/.
##
## Run:  <godot> --path <project> --script res://tools/capture_knives.gd

const OUT: String = "user://screens/knives"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await _studio_shots()
	await _held_shots()
	print("pictures: ", ProjectSettings.globalize_path(OUT))
	quit(0)


func _studio_shots() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.35, 0.37, 0.4)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -60, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	var visual := WeaponVisual.new()
	stage.add_child(visual)
	for knife: StringName in WeaponModels.KNIVES:
		visual.setup(knife)
		camera.size = visual.size.z * 1.2
		# Left side: the camera on -X looking toward +X, blade tip (-Z) on the left of the picture.
		camera.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-2, 0, 0))
		await _save("%s_left" % knife)
		camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 2, 0))
		await _save("%s_top" % knife)
		if not visual.part_names().is_empty():
			camera.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-2, 0, 0))
			for angle: float in [90.0, 180.0]:
				visual.set_part_angle(&"handle_a", angle)
				visual.set_part_angle(&"handle_b", -angle)
				await _save("%s_handles_%d" % [knife, int(angle)])
	root.remove_child(stage)
	stage.queue_free()


func _held_shots() -> void:
	var sandbox: Node = (load("res://scenes/fps_sandbox/fps_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sandbox)
	for i: int in 10:
		await process_frame
	var player := sandbox.get_node("Player") as FirstPersonController
	var effects := sandbox.get_node("Effects") as WeaponEffects
	(sandbox.get_node("Hud") as CanvasLayer).visible = false
	player.input_enabled = false
	player.rotation.y = deg_to_rad(35.0)
	var profile := CosmeticProfile.new()
	profile.path = OUT.path_join("unused_profile.json")
	CosmeticProfile.use(profile)
	for knife: StringName in WeaponModels.KNIVES:
		profile.set_knife(knife)
		player.weapons.select_slot(WeaponCatalog.get_definition(EquipmentCatalog.KNIFE).slot)
		effects.refresh_cosmetics()
		player.weapons.draw_remaining = 0.0
		for i: int in 6:
			await process_frame
		await _save("%s_held" % knife)
		effects.inspect()
		var seconds := InspectLibrary.seconds(knife)
		for share: float in [0.3, 0.5, 0.7]:
			effects.set("_inspect_left", seconds * (1.0 - share))
			await process_frame
			effects.set("_inspect_left", seconds * (1.0 - share))
			await _save("%s_inspect_%d" % [knife, int(share * 100)])
		effects.set("_inspect_left", 0.0)
	root.remove_child(sandbox)
	sandbox.queue_free()


func _save(file_name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(OUT.path_join(file_name + ".png"))
