extends SceneTree
## Developer aid (needs a window): photographs every base character in its default look from the
## front and side, a contact sheet of every installed item on its body, and the animation set on
## every body. Saves to user://screens/characters/.
##
## Run:  <godot> --path <project> --resolution 1280x720 --script res://tools/capture_characters.gd

const OUT: String = "user://screens/characters"
const POSES: Array[StringName] = [&"Idle_Gun", &"Run", &"Walk", &"Gun_Shoot", &"Death"]

var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var stage := _stage()
	var catalog := CharacterCatalog.shared()
	var bodies: Array[String] = []
	for body_id: String in catalog.body_ids():
		if catalog.is_available(body_id):
			bodies.append(body_id)
	var rigs: Array[CharacterRig] = []
	for index: int in bodies.size():
		var rig := CharacterRig.new()
		rig.position.x = (index - (bodies.size() - 1) / 2.0) * 1.3
		stage.add_child(rig)
		rig.apply(CharacterWardrobe.default_appearance(catalog, bodies[index]))
		rigs.append(rig)
	_camera.position = Vector3(0, 1.0, 4.6)
	for clip: StringName in POSES:
		for rig: CharacterRig in rigs:
			rig.play(clip, 0.0)
			rig.animation_player.seek(1.2 if clip == &"Death" else 0.35, true)
		await _save("bodies_%s" % clip)
	for rig: CharacterRig in rigs:
		rig.play(&"Idle_Neutral", 0.0)
		rig.rotation.y = PI / 2.0
	await _save("bodies_side")
	for rig: CharacterRig in rigs:
		rig.queue_free()
	await process_frame
	await _item_sheets(stage, catalog, bodies)
	print("pictures: ", ProjectSettings.globalize_path(OUT))
	quit(0)


## Each item worn on the default look of the first body it fits, eight to a picture.
func _item_sheets(stage: Node3D, catalog: CharacterCatalog, bodies: Array[String]) -> void:
	var ids: Array[String] = []
	for item_id: String in catalog.items:
		if catalog.is_available(item_id):
			ids.append(item_id)
	var sheet := 0
	var labels: Array[Label3D] = []
	var rigs: Array[CharacterRig] = []
	for start: int in range(0, ids.size(), 8):
		for offset: int in mini(8, ids.size() - start):
			var item_id := ids[start + offset]
			var body_id := ""
			for fit: Variant in catalog.item(item_id)["fits"]:
				if bodies.has(str(fit)):
					body_id = str(fit)
					break
			var appearance := CharacterWardrobe.default_appearance(catalog, body_id)
			CharacterWardrobe.equip(catalog, appearance, item_id)
			var rig := CharacterRig.new()
			rig.position.x = (offset - 3.5) * 1.15
			stage.add_child(rig)
			rig.apply(appearance)
			rig.play(&"Idle_Neutral", 0.0)
			rigs.append(rig)
			var label := Label3D.new()
			label.text = catalog.display_name(item_id)
			label.pixel_size = 0.0035
			label.position = Vector3(rig.position.x, -0.15, 0.3)
			stage.add_child(label)
			labels.append(label)
		_camera.position = Vector3(0, 0.95, 6.2)
		await _save("items_%02d" % sheet)
		sheet += 1
		for rig: CharacterRig in rigs:
			rig.queue_free()
		for label: Label3D in labels:
			label.queue_free()
		rigs.clear()
		labels.clear()
		await process_frame


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.35, 0.37, 0.4)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.65, 0.65)
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 25, 0)
	stage.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	stage.add_child(_camera)
	_camera.make_current()
	return stage


func _save(file_name: String) -> void:
	for frame: int in 4:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, file_name])
