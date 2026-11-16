extends SceneTree
## Developer aid: prints each weapon model's bounds and, when run with a window, saves a
## picture of it with coloured axes (X red, Y green, Z blue) to user://screens/weapons/.
## Used to work out each model's orientation and scale for WeaponModels.
##
## Run:  <godot> --path <project> --script res://tools/inspect_weapon_models.gd [-- --oriented]
## With --oriented the models are shown as the game shows them (WeaponVisual), with Magnet
## slot markers, from the left and the right.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var oriented := OS.get_cmdline_user_args().has("--oriented")
	var headless := DisplayServer.get_name() == "headless"
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.35, 0.37, 0.4)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.9
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute("user://screens/weapons")
	for weapon_id: StringName in WeaponModels.ids():
		var holder := Node3D.new()
		world.add_child(holder)
		var model: Node3D
		if oriented:
			var visual := WeaponVisual.new()
			holder.add_child(visual)
			visual.setup(weapon_id)
			visual.show_slot_markers(true)
			for slot: int in WeaponModels.SLOT_COUNT:
				visual.set_magnet(slot, MagnetCatalog.ids()[slot * 5])
			model = visual
		else:
			model = (load(WeaponModels.model_path(weapon_id)) as PackedScene).instantiate() as Node3D
			holder.add_child(model)
		await process_frame
		var bounds := WeaponVisual.merged_bounds(model, holder)
		print("%s  size %s  centre %s  meshes %d" % [weapon_id, bounds.size, bounds.get_center(),
			model.find_children("*", "MeshInstance3D", true, false).size()])
		if not headless:
			var reach := bounds.size.length()
			var centre := bounds.get_center()
			var views: Array[Vector3] = [Vector3(1, 0.7, 1), Vector3(-1, 0.7, -1)]
			if oriented:
				views = [Vector3(-1, 0.15, 0), Vector3(1, 0.15, 0)]
			_axes(holder, centre, reach * 0.5)
			for i: int in views.size():
				camera.size = reach * 1.05
				camera.position = centre + views[i].normalized() * reach * 2.0
				camera.look_at(centre)
				for frame: int in 6:
					await process_frame
				root.get_texture().get_image().save_png("user://screens/weapons/%s_%s%d.png" % [weapon_id, "game" if oriented else "raw", i])
		holder.queue_free()
		await process_frame
	print("pictures: ", ProjectSettings.globalize_path("user://screens/weapons"))
	quit(0)


func _axes(parent: Node3D, origin: Vector3, length: float) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for axis: Array in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
		mesh.surface_set_color(axis[1] as Color)
		mesh.surface_add_vertex(origin)
		mesh.surface_set_color(axis[1] as Color)
		mesh.surface_add_vertex(origin + (axis[0] as Vector3) * length)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
