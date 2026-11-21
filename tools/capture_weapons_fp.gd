extends SceneTree
## Developer aid (needs a window): holds each modelled gun in the FPS Sandbox with Magnets
## in all five slots and saves a first-person picture and a mid-inspection picture to
## user://screens/weapons/. Nothing is saved to the player's profile.
##
## Run:  <godot> --path <project> --script res://tools/capture_weapons_fp.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var profile := CosmeticProfile.new()
	profile.path = "user://screens/weapons/unused_profile.json"
	for weapon_id: StringName in WeaponModels.ids():
		for slot: int in WeaponModels.SLOT_COUNT:
			profile.set_magnet(weapon_id, slot, MagnetCatalog.ids()[(slot * 5 + 2) % MagnetCatalog.ids().size()])
	CosmeticProfile.use(profile)
	var sandbox: Node = (load("res://scenes/fps_sandbox/fps_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sandbox)
	for i: int in 10:
		await process_frame
	var player := sandbox.get_node("Player") as FirstPersonController
	var effects := sandbox.get_node("Effects") as WeaponEffects
	(sandbox.get_node("Hud") as CanvasLayer).visible = false
	player.input_enabled = false
	player.rotation.y = deg_to_rad(35.0)
	DirAccess.make_dir_recursive_absolute("user://screens/weapons")
	for weapon_id: StringName in WeaponModels.ids():
		var definition := WeaponCatalog.get_definition(weapon_id)
		var secondary := definition.category == WeaponDefinition.CATEGORY_SECONDARY
		sandbox.call("set_sandbox_weapons", WeaponCatalog.AK47 if secondary else weapon_id, weapon_id if secondary else WeaponCatalog.G17)
		player.weapons.select_slot(definition.slot)
		player.weapons.draw_remaining = 0.0
		for i: int in 8:
			await process_frame
		root.get_texture().get_image().save_png("user://screens/weapons/%s_fp.png" % weapon_id)
		effects.inspect()
		for part: Array in [[0.3, "a"], [0.7, "b"]]:
			effects.set("_inspect_left", InspectLibrary.seconds(weapon_id) * (1.0 - float(part[0])))
			for i: int in 4:
				await process_frame
			effects.set("_inspect_left", InspectLibrary.seconds(weapon_id) * (1.0 - float(part[0])))
			await process_frame
			root.get_texture().get_image().save_png("user://screens/weapons/%s_inspect_%s.png" % [weapon_id, part[1]])
		effects.set("_inspect_left", 0.0)
	print("pictures: ", ProjectSettings.globalize_path("user://screens/weapons"))
	quit(0)
