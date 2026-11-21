extends TestSuite
## Knife looks: the seven knife models made from the knife pack, their Coat zone masks and kits,
## the butterfly knife's moving handles, each knife's own inspection, the knife the player carries
## (CosmeticProfile) and how it shows in first person and in the Armoury.
##
## The only Coat images used here are flat diagnostic colours made in memory (test assets).

const TEST_DIR: String = "user://tests/knives"
const ARMOURY_SCENE: String = "res://scenes/armoury/armoury.tscn"
const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const KIT_FILES: Array[String] = ["Coat_BaseColor.png", "Coat_Template.png", "Start_Here.png", "Parts.txt", "README.txt",
	"Which_Model.txt"]


func suite_name() -> String:
	return "Knives"


func run() -> void:
	_wipe(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var real_profile := CosmeticProfile.current()
	var profile := CosmeticProfile.new()
	profile.path = TEST_DIR.path_join("cosmetics.json")
	CosmeticProfile.use(profile)
	CoatLibrary.set_custom_dir(TEST_DIR.path_join("coats"))
	_test_data()
	_test_masks()
	_test_models()
	_test_butterfly()
	_test_coats()
	_test_profile()
	_test_inspects()
	_test_grips()
	await _test_first_person()
	await _test_armoury()
	CosmeticProfile.use(real_profile)
	CoatLibrary.set_custom_dir(CoatLibrary.CUSTOM_DIR)
	_wipe(TEST_DIR)


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe(path.path_join(sub))
		dir.remove(sub)
	for file_name: String in dir.get_files():
		dir.remove(file_name)


func _test_data() -> void:
	section("Knife looks")
	var names: Dictionary[String, bool] = {}
	var all_ok := true
	for knife: StringName in WeaponModels.KNIVES:
		names[WeaponModels.display_name(knife)] = true
		all_ok = all_ok and WeaponModels.has_model(knife) and WeaponModels.is_knife(knife) and not WeaponModels.has_slots(knife) \
			and WeaponModels.coat_size(knife) == Vector2i(2048, 2048) and str(WeaponModels.info(knife)["credit"]["author"]).contains("BUttERflY_Bee") \
			and str(WeaponModels.info(knife)["credit"]["license"]) == "CC-BY-4.0" and not WeaponCatalog.has(knife)
	check(WeaponModels.KNIVES.size() == 7 and names.size() == 7 and all_ok,
		"seven knife looks, each named, credited (CC BY), Coat-ready, without Magnet slots and with no gameplay of its own")
	check(WeaponModels.KNIVES.has(WeaponModels.DEFAULT_KNIFE) and WeaponModels.display_name(&"knf_karambit") == "Karambit",
		"a default knife exists and names read well")
	check(WeaponModels.ids().size() == 10 and not WeaponModels.ids().has(&"knf_combat")
		and WeaponModels.all_ids().size() == 10 + WeaponModels.KNIVES.size(), "the gun list is unchanged; all_ids adds the knives")
	check(not WeaponModels.is_knife(WeaponCatalog.AK47) and WeaponModels.has_slots(WeaponCatalog.AK47), "guns still take Magnets")
	var kits_ok := true
	for knife: StringName in WeaponModels.KNIVES:
		var kit := ProjectSettings.globalize_path("res://authoring/coat_kits").path_join(str(WeaponModels.info(knife)["kit"]))
		for file_name: String in KIT_FILES:
			kits_ok = kits_ok and FileAccess.file_exists(kit.path_join(file_name))
		for zone: String in WeaponModels.info(knife)["zones"]:
			kits_ok = kits_ok and FileAccess.file_exists(kit.path_join("Masks").path_join(zone + ".png"))
	check(kits_ok, "every knife has a Coat kit for artists: factory finish, guide, legend, masks and notes")


func _test_masks() -> void:
	section("Coat zone masks")
	var ok := true
	var notes: Array[String] = []
	for knife: StringName in WeaponModels.KNIVES:
		var zones := WeaponModels.zone_paths(knife)
		var masks: Array[Image] = []
		for index: int in zones.size():
			var mask := CoatLibrary.zone_mask(knife, index)
			if mask == null:
				ok = false
				notes.append("%s zone %d missing" % [knife, index + 1])
				continue
			masks.append(mask)
		if masks.size() != zones.size():
			continue
		# Sample on a coarse grid: each zone covers something, and zones never share a pixel.
		var covered: Array[int] = []
		covered.resize(masks.size())
		var shared := 0
		for y: int in range(0, 2048, 8):
			for x: int in range(0, 2048, 8):
				var hits := 0
				for index: int in masks.size():
					if masks[index].get_pixel(x, y).r > 0.5:
						covered[index] += 1
						hits += 1
				if hits > 1:
					shared += 1
		if covered.has(0) or shared > 0:
			ok = false
			notes.append("%s covered %s shared %d" % [knife, covered, shared])
	check(ok, "every knife zone mask exists, covers part of the knife and never overlaps another zone %s" % [notes])


func _test_models() -> void:
	section("Knife models")
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var sizes_ok := true
	var blades_ok := true
	var notes: Array[String] = []
	for knife: StringName in WeaponModels.KNIVES:
		var visual := WeaponVisual.new()
		holder.add_child(visual)
		var built := visual.setup(knife)
		var factory := visual.factory_texture()
		sizes_ok = sizes_ok and built and is_equal_approx(visual.size.z, float(WeaponModels.info(knife)["length"])) \
			and visual.accepts_coats() and factory != null and Vector2i(factory.get_size()) == Vector2i(2048, 2048)
		# The blade zone lies toward the tip (-Z) and the grip toward the butt.
		var shape := visual.geometry()
		var points: PackedVector3Array = shape[0]
		var uvs: PackedVector2Array = shape[1]
		var blade := CoatLibrary.zone_mask(knife, 0)
		var grip := CoatLibrary.zone_mask(knife, 1)
		var blade_z := [0.0, 0]
		var grip_z := [0.0, 0]
		for i: int in range(0, points.size(), 3):
			var uv := (uvs[i] + uvs[i + 1] + uvs[i + 2]) / 3.0
			var pixel := Vector2i(clampi(int(uv.x * 2048), 0, 2047), clampi(int(uv.y * 2048), 0, 2047))
			var z := (points[i].z + points[i + 1].z + points[i + 2].z) / 3.0
			if blade.get_pixelv(pixel).r > 0.5:
				blade_z[0] += z
				blade_z[1] += 1
			elif grip.get_pixelv(pixel).r > 0.5:
				grip_z[0] += z
				grip_z[1] += 1
		var blade_mean := float(blade_z[0]) / maxi(1, int(blade_z[1]))
		var grip_mean := float(grip_z[0]) / maxi(1, int(grip_z[1]))
		if int(blade_z[1]) == 0 or int(grip_z[1]) == 0 or blade_mean >= grip_mean:
			blades_ok = false
			notes.append("%s blade %.3f grip %.3f" % [knife, blade_mean, grip_mean])
		visual.free()
	holder.free()
	check(sizes_ok, "every knife builds at its length with its 2048 x 2048 factory finish")
	check(blades_ok, "every knife points its blade forward (-Z) and its blade and grip zones match the model %s" % [notes])


func _test_butterfly() -> void:
	section("Butterfly knife handles")
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var visual := WeaponVisual.new()
	holder.add_child(visual)
	visual.setup(&"knf_butterfly")
	check(visual.part_names().size() == 2 and visual.part_names().has(&"handle_a") and visual.part_names().has(&"handle_b"),
		"the butterfly knife has two moving handles")
	var handle := holder.find_child("handle_a", true, false) as MeshInstance3D
	var rest_z := _centre_z(handle, visual)
	var turned := visual.set_part_angle(&"handle_a", 180.0)
	var closed_z := _centre_z(handle, visual)
	check(turned and rest_z > 0.0 and closed_z < 0.0 and is_equal_approx(visual.size.z, 0.23),
		"swinging a handle half a turn about its pin folds it over the blade (centre z %.3f -> %.3f)" % [rest_z, closed_z])
	check(absf(visual.part_angle(&"handle_a") - 180.0) < 0.5 or absf(visual.part_angle(&"handle_a") + 180.0) < 0.5,
		"the handle reports its angle")
	visual.set_part_angle(&"handle_a", 0.0)
	check(is_equal_approx(_centre_z(handle, visual), rest_z) and not visual.set_part_angle(&"blade", 10.0),
		"back at zero it rests where it started; the blade is not a moving part")
	visual.setup(&"knf_karambit")
	check(visual.part_names().is_empty() and not visual.set_part_angle(&"handle_a", 90.0), "other knives are one piece")
	holder.free()


## Mean z of a mesh's vertices in [param visual]'s space (0 when there is no mesh).
func _centre_z(mesh: MeshInstance3D, visual: WeaponVisual) -> float:
	if mesh == null:
		return 0.0
	var points := WeaponVisual.mesh_points(mesh, visual)
	var total := 0.0
	for point: Vector3 in points:
		total += point.z
	return total / maxi(1, points.size())


func _test_coats() -> void:
	section("Knife Coats")
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var visual := WeaponVisual.new()
	holder.add_child(visual)
	visual.setup(&"knf_karambit")
	var base := visual.factory_texture().get_image()
	holder.free()
	var red := Color(1, 0, 0)
	var painted := CoatLibrary.compose(&"knf_karambit", base, {0: red})
	var blade := CoatLibrary.zone_mask(&"knf_karambit", 0)
	var inside := Vector2i(-1, -1)
	var outside := Vector2i(-1, -1)
	for y: int in range(0, 2048, 16):
		for x: int in range(0, 2048, 16):
			var any := false
			for index: int in WeaponModels.zone_paths(&"knf_karambit").size():
				any = any or CoatLibrary.zone_mask(&"knf_karambit", index).get_pixel(x, y).r > 0.01
			if inside.x < 0 and blade.get_pixel(x, y).r > 0.99:
				inside = Vector2i(x, y)
			if outside.x < 0 and not any:
				outside = Vector2i(x, y)
	if base.is_compressed():
		base.decompress()
	check(inside.x >= 0 and painted.get_pixelv(inside).is_equal_approx(red), "painting the blade zone paints the blade")
	check(outside.x >= 0 and painted.get_pixelv(outside).is_equal_approx(base.get_pixelv(outside)), "outside every zone stays factory")
	var image := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.9))
	var result := CoatLibrary.register_image(&"knf_karambit", image, "Test blue")
	var profile := CosmeticProfile.current()
	check(str(result["error"]).is_empty() and CoatLibrary.fits(&"knf_karambit", str(result["id"]))
		and profile.set_coat(&"knf_karambit", str(result["id"])).is_empty() and not CoatLibrary.fits(&"knf_bayonet", str(result["id"])),
		"a Coat made with a knife's kit is stored for that knife only and can be equipped")
	check(not profile.set_magnet(&"knf_karambit", 0, MagnetCatalog.ids()[0]).is_empty(), "knives refuse Magnets")
	profile.set_coat(&"knf_karambit", "")
	CoatLibrary.remove_custom(str(result["id"]))


func _test_profile() -> void:
	section("The knife the player carries")
	var profile := CosmeticProfile.new()
	profile.path = TEST_DIR.path_join("knife_profile.json")
	check(profile.equipped_knife() == WeaponModels.DEFAULT_KNIFE and profile.model_for(EquipmentCatalog.KNIFE) == WeaponModels.DEFAULT_KNIFE,
		"a new player carries the default knife")
	check(profile.set_knife(&"knf_butterfly").is_empty() and profile.model_for(EquipmentCatalog.KNIFE) == &"knf_butterfly"
		and profile.model_for(WeaponCatalog.AK47) == WeaponCatalog.AK47, "choosing a knife changes only the knife's model")
	check(not profile.set_knife(WeaponCatalog.AK47).is_empty() and profile.equipped_knife() == &"knf_butterfly", "a gun is not a knife")
	check(profile.save() == OK, "the choice saves")
	var loaded := CosmeticProfile.new()
	loaded.path = profile.path
	check(loaded.load_file() and loaded.equipped_knife() == &"knf_butterfly", "and loads back")
	var file := FileAccess.open(profile.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": CosmeticProfile.FORMAT, "format_version": CosmeticProfile.FORMAT_VERSION,
		"weapons": {}, "knife": "knf_made_up"}))
	file.close()
	check(loaded.load_file() and loaded.equipped_knife() == WeaponModels.DEFAULT_KNIFE, "an unknown knife falls back to the default")
	file = FileAccess.open(profile.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": CosmeticProfile.FORMAT, "format_version": CosmeticProfile.FORMAT_VERSION, "weapons": {}}))
	file.close()
	check(loaded.load_file() and loaded.equipped_knife() == WeaponModels.DEFAULT_KNIFE, "profiles saved before knife looks still load")


func _test_inspects() -> void:
	section("Knife inspections")
	var unique: Dictionary[String, bool] = {}
	var all_ok := true
	for knife: StringName in WeaponModels.KNIVES:
		all_ok = all_ok and InspectLibrary.has_inspect(knife)
		unique[JSON.stringify(InspectLibrary.for_item(knife))] = true
		var finish := InspectLibrary.sample(knife, 1.0)
		var parts: Dictionary = finish["parts"]
		for part: Variant in parts:
			all_ok = all_ok and is_zero_approx(fposmod(float(parts[part]), 360.0))
	check(all_ok and unique.size() == WeaponModels.KNIVES.size(), "every knife has its own inspection, ending with its parts at rest")
	var closed := InspectLibrary.sample(&"knf_butterfly", 0.44)["parts"] as Dictionary
	check(is_equal_approx(float(closed.get(&"handle_a", 0.0)), 180.0) and is_equal_approx(float(closed.get(&"handle_b", 0.0)), -180.0),
		"halfway through, the butterfly knife is closed")
	var spin := InspectLibrary.sample(&"knf_karambit", 0.55)
	check(absf((spin["rot"] as Vector3).y) >= 700.0 and (spin["pivot"] as Vector3).is_equal_approx(Vector3(0, 0.152, 0.385)),
		"the karambit spins twice about the middle of its ring")
	check((InspectLibrary.sample(&"knf_combat", 0.5)["parts"] as Dictionary).is_empty(), "one-piece knives move no parts")
	var fingers := InspectLibrary.sample(&"knf_karambit", 0.325)["fingers"] as Dictionary
	check(float(fingers.get(&"Index", 0.0)) >= 1.0 and float(fingers.get(&"Little", 1.0)) < 0.2 and float(fingers.get(&"Middle", 1.0)) < 0.2
		and float(fingers.get(&"Thumb", 1.0)) < 0.5,
		"mid-spin the karambit's index finger stays hooked in the ring while the other fingers and the thumb open out of its way")
	var caught := InspectLibrary.sample(&"knf_nomad", 0.35)["fingers"] as Dictionary
	var at_rest := true
	for value: Variant in (InspectLibrary.sample(&"knf_nomad", 0.0)["fingers"] as Dictionary).values():
		at_rest = at_rest and is_equal_approx(float(value), 1.0)
	check(float(caught.get(&"Index", 1.0)) < 0.2 and at_rest,
		"the hand opens to catch the tossed nomad, and holds as usual at rest")
	var left_side := InspectLibrary.sample(&"wpn_ak47", 0.35)["rot"] as Vector3
	var pistol_side := InspectLibrary.sample(&"wpn_g17", 0.35)["rot"] as Vector3
	check(left_side.y >= 50.0 and pistol_side.y >= 60.0 and absf((InspectLibrary.sample(&"wpn_g17", 0.7)["rot"] as Vector3).z) >= 90.0,
		"gun inspections turn the barrel across the view to show the side, then turn the gun over to show the other")
	check(InspectLibrary.for_item(&"wpn_g17") == InspectLibrary.PISTOL and not bool(InspectLibrary.PISTOL.get("support", true))
		and InspectLibrary.for_item(&"wpn_ak47") == InspectLibrary.DEFAULT and bool(InspectLibrary.DEFAULT.get("grip_pivot", false)),
		"pistols let the support hand go for their inspection; rifles turn about the firing hand with both hands on")
	check(is_equal_approx(WeaponEffects._hand_angle(-80.0, 90.0), -80.0) and is_zero_approx(WeaponEffects._hand_angle(720.0, 50.0))
		and absf(WeaponEffects._hand_angle(170.0, 50.0)) < 10.0,
		"the hand turns with a held pose but not through a spin (the item turns on in the fingers)")


func _test_grips() -> void:
	section("How each knife sits in the fist")
	var visual := WeaponVisual.new()
	var inside := true
	var placed := true
	var fist := Transform3D(WeaponModels.hand_basis(Vector3(-0.5, -0.2, -1), Vector3(-1, -0.4, 0.3)), Vector3(0.1, -0.2, -0.3))
	for knife: StringName in WeaponModels.KNIVES:
		visual.setup(knife)
		var grip := WeaponModels.hand_points(knife, visual.size)[&"Right"]
		inside = inside and WeaponModels.KNIFE_GRIPS.has(knife) and grip.z > 0.0 and grip.z < visual.size.z * 0.5 \
			and absf(grip.y) < visual.size.y * 0.5 and WeaponModels.hand_frames(knife)[&"Right"].is_equal_approx(WeaponModels.knife_hold(knife).basis)
		placed = placed and (WeaponModels.knife_in_fist(knife, fist) * WeaponModels.knife_hold(knife)).is_equal_approx(fist)
	visual.free()
	check(inside, "every knife is held at its own handle (behind the blade, within the model), the hand turned to match")
	check(placed, "a knife placed in a fist puts its handle in the middle of that fist, turned with it")
	var hammer := true
	for knife: StringName in [&"knf_combat", &"knf_bayonet", &"knf_butterfly", &"knf_nomad", &"knf_skeleton"]:
		var frame := WeaponModels.knife_hold(knife).basis
		# z is the thumb's side of the fist: toward the blade; the knuckles across the handle, slanted.
		hammer = hammer and frame.z.dot(Vector3.FORWARD) > 0.5 and absf(frame.x.dot(Vector3.FORWARD)) < 0.7
	check(hammer, "straight knives sit in a hammer grip: the handle across the palm, the blade out by the thumb")
	var karambit := WeaponModels.knife_hold(&"knf_karambit").basis
	check(karambit.z.dot(Vector3.BACK) > 0.5, "the karambit's ring is at the index finger, its blade out below the little finger")
	var dagger := WeaponModels.knife_hold(&"knf_t_dagger").basis
	check(dagger.x.dot(Vector3.FORWARD) > 0.9 and absf(dagger.z.dot(Vector3.UP)) > 0.9,
		"the T-handle dagger is a push dagger: crossbar across the palm, blade out from the knuckles")


func _test_first_person() -> void:
	section("Knives in first person")
	var profile := CosmeticProfile.current()
	profile.set_knife(&"knf_karambit")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var player := sandbox.get_node("Player") as FirstPersonController
	var effects := sandbox.get_node("Effects") as WeaponEffects
	player.input_enabled = false
	player.weapons.select_slot(WeaponCatalog.get_definition(EquipmentCatalog.KNIFE).slot)
	await wait_frames(2)
	var view := effects.weapon_visual
	check(player.weapons.current().definition.id == EquipmentCatalog.KNIFE and view != null and view.weapon_id == &"knf_karambit"
		and effects.viewmodel.is_ancestor_of(view), "holding the knife shows the chosen knife look")
	profile.set_knife(&"knf_butterfly")
	effects.refresh_cosmetics()
	await wait_frames(1)
	view = effects.weapon_visual
	check(view != null and view.weapon_id == &"knf_butterfly", "choosing another knife swaps the model in hand")
	player.weapons.draw_remaining = 0.0
	check(effects.inspect() and effects.get("_inspect_id") == &"knf_butterfly", "inspecting plays the butterfly knife's own inspection")
	var seconds := InspectLibrary.seconds(&"knf_butterfly")
	effects.set("_inspect_left", seconds * (1.0 - 0.44))
	await wait_frames(1)
	check(absf(view.part_angle(&"handle_a")) > 150.0 and absf(view.part_angle(&"handle_b")) > 150.0,
		"mid-inspection the handles fold round the blade")
	effects.set("_inspect_left", 0.0001)
	await wait_frames(2)
	check(not effects.is_inspecting() and absf(view.part_angle(&"handle_a")) < 0.5 and absf(view.part_angle(&"handle_b")) < 0.5,
		"after the inspection the knife is open in the hand again")
	profile.set_knife(&"knf_karambit")
	effects.refresh_cosmetics()
	await wait_frames(1)
	view = effects.weapon_visual
	var hand := effects.get("_hand_item") as Node3D
	var ring := Vector3(0, 0.152, 0.385) * view.size
	effects.inspect()
	effects.set("_inspect_left", InspectLibrary.seconds(&"knf_karambit") * (1.0 - 0.4))
	await wait_frames(1)
	var turned := rad_to_deg(hand.global_basis.get_rotation_quaternion().angle_to(view.global_basis.get_rotation_quaternion()))
	var open_fingers := effects.arms.finger_grip.duplicate()
	check((hand.global_transform * ring).distance_to(view.global_transform * ring) < 0.005 and turned > 60.0,
		"mid-spin the karambit turns on round the finger in its ring (%.0f degrees from the hand)" % turned)
	effects.set("_inspect_left", 0.0001)
	await wait_frames(2)
	check(float(open_fingers.get(&"Little", 1.0)) < 0.5 and effects.arms.finger_grip.is_empty()
		and effects.arms.rig.retargeter.finger_curls.get(&"Right", {}).is_empty(),
		"the inspection moves the hand's fingers, and they hold as usual again after")
	effects.inspect()
	effects.set("_inspect_left", InspectLibrary.seconds(&"knf_karambit") * (1.0 - 0.4))
	await wait_frames(1)
	var mid_spin := not effects.arms.finger_grip.is_empty()
	profile.set_knife(&"knf_nomad")
	effects.refresh_cosmetics()
	await wait_frames(1)
	check(mid_spin and effects.arms.finger_grip.is_empty() and not effects.is_inspecting(),
		"changing what is in hand mid-inspection lets the fingers hold as usual again")
	profile.set_knife(&"knf_combat")
	effects.refresh_cosmetics()
	await wait_frames(1)
	view = effects.weapon_visual
	hand = effects.get("_hand_item") as Node3D
	var grip := WeaponModels.hand_points(view.weapon_id, view.size)[&"Right"]
	var axes := view.transform.basis * WeaponModels.knife_hold(view.weapon_id).basis
	var wrist := view.transform * grip + axes * WeaponEffects.WRIST_FROM_FIST
	effects.inspect()
	var twist_at := 0.2
	effects.set("_inspect_left", InspectLibrary.seconds(&"knf_combat") * (1.0 - twist_at))
	await wait_frames(1)
	var pose := InspectLibrary.sample(&"knf_combat", twist_at)
	var hand_root := effects.get("_hand_root") as Node3D
	var apart := rad_to_deg(hand.global_basis.get_rotation_quaternion().angle_to(view.global_basis.get_rotation_quaternion()))
	var wrist_moved := (hand_root.transform * wrist).distance_to(wrist + (pose["pos"] as Vector3))
	check(absf((pose["rot"] as Vector3).x) > 80.0 and apart < 1.0
		and (hand.global_transform * grip).distance_to(view.global_transform * grip) < 0.001 and wrist_moved < 0.001,
		"a knife inspection twists the forearm: the knife turns with the fist, the wrist stays where it is")
	effects.set("_inspect_left", 0.0001)
	await wait_frames(2)
	profile.set_knife(&"knf_nomad")
	effects.refresh_cosmetics()
	await wait_frames(1)
	view = effects.weapon_visual
	hand = effects.get("_hand_item") as Node3D
	grip = WeaponModels.hand_points(view.weapon_id, view.size)[&"Right"]
	var rest_grip := effects.viewmodel.global_transform * (view.transform * grip)
	effects.inspect()
	effects.set("_inspect_left", InspectLibrary.seconds(&"knf_nomad") * (1.0 - 0.35))
	await wait_frames(1)
	check((view.global_transform * grip).distance_to(rest_grip) > 0.15
		and (hand.global_transform * grip).distance_to(effects.viewmodel.global_transform * (view.transform * grip)) < WeaponEffects.HAND_FOLLOW + 0.01,
		"a tossed knife flies up out of the hand; the hand only flicks after it")
	effects.set("_inspect_left", 0.0001)
	await wait_frames(2)
	profile.set_knife(&"knf_butterfly")
	effects.refresh_cosmetics()
	await wait_frames(1)
	player.weapons.select_slot(2)
	await wait_frames(1)
	player.weapons.draw_remaining = 0.0
	effects.inspect()
	effects.set("_inspect_left", 1.0)
	await wait_frames(1)
	var released := effects.arms.support_released
	effects.set("_inspect_left", 0.0001)
	await wait_frames(2)
	check(WeaponModels.GRIPS.has(player.weapons.current().definition.id) and released and not effects.arms.support_released,
		"a pistol inspection lets the support hand go, and it takes hold again after")
	player.weapons.select_slot(1)
	await wait_frames(1)
	check(effects.weapon_visual != null and effects.weapon_visual.weapon_id == player.weapons.current().definition.id,
		"guns are unaffected by the knife choice")
	var buy := InputEventAction.new()
	buy.action = InputActions.BUY_MENU
	buy.pressed = true
	sandbox.call("_unhandled_input", buy)
	var shop := sandbox.get("_sandbox_shop") as MatchHud
	var buttons := shop.knife_buttons() if shop != null else []
	check(shop != null and shop.is_buy_menu_open() and buttons.size() == WeaponModels.KNIVES.size()
		and buttons[WeaponModels.KNIVES.find(&"knf_butterfly")].disabled, "the sandbox shop has a knife column, the carried knife marked")
	if buttons.size() == WeaponModels.KNIVES.size():
		buttons[WeaponModels.KNIVES.find(&"knf_nomad")].pressed.emit()
		await wait_frames(2)
		var saved := CosmeticProfile.new()
		saved.path = profile.path
		check(profile.equipped_knife() == &"knf_nomad" and saved.load_file() and saved.equipped_knife() == &"knf_nomad"
			and player.weapons.current().definition.id == EquipmentCatalog.KNIFE and effects.weapon_visual.weapon_id == &"knf_nomad"
			and shop.is_buy_menu_open() and shop.knife_buttons()[WeaponModels.KNIVES.find(&"knf_nomad")].disabled,
			"picking a knife there saves it and puts it in hand, with the shop still open")
	profile.set_knife(WeaponModels.DEFAULT_KNIFE)
	sandbox.queue_free()
	await wait_frames(2)


func _test_armoury() -> void:
	section("Knives in the Armoury")
	var armoury := spawn_scene(ARMOURY_SCENE) as Armoury
	if armoury == null:
		return
	await wait_frames(2)
	var first_knife := WeaponModels.ids().size()
	check(armoury.weapon_list.get_item_text(first_knife).begins_with("Knife · Combat Knife")
		and armoury.weapon_list.get_item_text(first_knife).ends_with("✓"), "knives follow the guns, the carried one marked")
	check(armoury.select_weapon(&"knf_skeleton") and armoury.visual.weapon_id == &"knf_skeleton" and not armoury.magnet_section.visible
		and armoury.knife_button.visible and not armoury.knife_button.disabled, "a knife shows without Magnet slots, with a carry button")
	check(armoury.coat_list.get_item_text(0) == "Factory finish", "it takes Coats like a gun")
	armoury.knife_button.pressed.emit()
	check(armoury.draft.equipped_knife() == &"knf_skeleton" and armoury.is_dirty() and armoury.knife_button.disabled
		and CosmeticProfile.current().equipped_knife() != &"knf_skeleton", "carrying it changes the draft only")
	check(armoury.save() == OK and CosmeticProfile.current().equipped_knife() == &"knf_skeleton" and not armoury.is_dirty(),
		"saving makes it the knife carried")
	armoury.select_weapon(WeaponCatalog.AK47)
	check(armoury.magnet_section.visible and not armoury.knife_button.visible, "guns show their Magnet slots again")
	CosmeticProfile.current().set_knife(WeaponModels.DEFAULT_KNIFE)
	armoury.queue_free()
	await wait_frames(2)
