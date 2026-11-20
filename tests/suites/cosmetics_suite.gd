extends TestSuite
## Weapon models, Coats (weapon finishes) and Magnets (weapon stickers): the ten modelled
## weapons, their factory finish, the Coat infrastructure and kit conversion, the 26 imported
## Magnets, five slots per weapon, the saved customisation profile, the Armoury screen and the
## first-person viewmodel with inspection.
##
## The only Coat textures used here are diagnostic images made in memory or in the test folder
## (LEFT/RIGHT colours). They are test assets, never game content.

const TEST_DIR: String = "user://tests/cosmetics"
const ARMOURY_SCENE: String = "res://scenes/armoury/armoury.tscn"
const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const EXPECTED_WEAPONS: Array[String] = ["wpn_ak47", "wpn_m4a1", "wpn_desert_eagle", "wpn_g17", "wpn_m1911", "wpn_mk23",
	"wpn_l118a1", "wpn_m24", "wpn_sks", "wpn_m14_ebr"]


func suite_name() -> String:
	return "Weapons, Coats and Magnets"


func run() -> void:
	_wipe(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var real_profile := CosmeticProfile.current()
	var profile := CosmeticProfile.new()
	profile.path = TEST_DIR.path_join("cosmetics.json")
	CosmeticProfile.use(profile)
	CoatLibrary.set_custom_dir(TEST_DIR.path_join("coats"))
	check(CoatLibrary.custom_dir == TEST_DIR.path_join("coats"), "tests write Coats to a scratch folder, never the player's")
	_test_catalogues()
	await _test_weapon_visuals()
	_test_coats()
	_test_profile()
	await _test_armoury()
	await _test_first_person()
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


## A diagnostic Coat image for a weapon: left half blue, right half orange. Test asset only.
func _diagnostic(weapon_id: StringName) -> Image:
	var size := WeaponModels.coat_size(weapon_id)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, size.x / 2, size.y), Color(0.41, 0.79, 0.98))
	image.fill_rect(Rect2i(size.x / 2, 0, size.x - size.x / 2, size.y), Color(1.0, 0.61, 0.43))
	return image


## Colours equal to within one 8-bit step.
func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _test_catalogues() -> void:
	section("Weapon and Magnet catalogues")
	var ids: Array[String] = []
	for id: StringName in WeaponModels.ids():
		ids.append(String(id))
	check(ids == EXPECTED_WEAPONS, "all ten weapons are registered for models (%d)" % ids.size())
	var gameplay_ok := true
	var shop_ok := true
	for id: StringName in WeaponModels.ids():
		var definition := WeaponCatalog.get_definition(id)
		gameplay_ok = gameplay_ok and definition != null and definition.damage > 0.0 and definition.magazine_size > 0 \
			and (definition.slot == 1 or definition.category == WeaponDefinition.CATEGORY_SECONDARY)
		shop_ok = shop_ok and ShopCatalog.has_item(id) and ShopCatalog.price(id) > 0 and ShopCatalog.kind(id) == ShopCatalog.KIND_WEAPON
	check(gameplay_ok, "each has a gameplay definition in the existing WeaponCatalog")
	check(shop_ok, "each can be bought through the existing shop")
	var shop_weapon_count := 0
	for id: StringName in ShopCatalog.item_ids():
		if ShopCatalog.kind(id) == ShopCatalog.KIND_WEAPON:
			shop_weapon_count += 1
	check(shop_weapon_count == EXPECTED_WEAPONS.size() and WeaponCatalog.ids().size() == EXPECTED_WEAPONS.size(),
		"the match shop and weapon catalogue contain only the ten modelled weapons")
	var retired_ok := true
	for id: StringName in WeaponCatalog.RETIRED_NAMES:
		retired_ok = retired_ok and not ShopCatalog.has_item(id) and WeaponCatalog.get_definition(id) == null \
			and WeaponCatalog.recorded_name(id) == WeaponCatalog.RETIRED_NAMES[id]
	check(retired_ok, "retired weapon IDs resolve to old names in career history only")
	check(WeaponCatalog.get_definition(&"wpn_ak47").display_name == "AK-47" and WeaponCatalog.get_definition(&"wpn_g17").slot == 2
		and not WeaponCatalog.get_definition(&"wpn_l118a1").is_automatic(), "names, slots and fire modes are set")
	var data_ok := true
	var zones := 0
	for id: StringName in WeaponModels.ids():
		var info := WeaponModels.info(id)
		data_ok = data_ok and ResourceLoader.exists(WeaponModels.model_path(id)) and WeaponModels.coat_size(id).x > 0 \
			and WeaponModels.slot_specs(id).size() == 5 and not str(info["kit"]).is_empty() and (info["credit"] as Dictionary).has("license")
		for path: String in WeaponModels.zone_paths(id):
			data_ok = data_ok and ResourceLoader.exists(path)
			zones += 1
		data_ok = data_ok and WeaponModels.zone_names(id).size() == WeaponModels.zone_paths(id).size()
	check(data_ok and zones == 47, "every weapon has a model, a Coat layout, its kit's paint-zone masks and a credit (%d zones)" % zones)

	check(MagnetCatalog.ids().size() == 26, "all 26 existing Magnets are registered")
	var unique: Dictionary[String, bool] = {}
	var art_ok := true
	for magnet_id: String in MagnetCatalog.ids():
		unique[magnet_id] = true
		var texture := MagnetCatalog.texture(magnet_id)
		art_ok = art_ok and texture != null and texture.get_size() == Vector2(512, 512) and not MagnetCatalog.display_name(magnet_id).is_empty() \
			and magnet_id.begins_with("mag_") and MagnetCatalog.is_unlocked(magnet_id)
	check(unique.size() == 26 and art_ok, "each Magnet has a unique ID, a name and its 512 x 512 artwork")
	var sample := MagnetCatalog.texture("mag_ghost").get_image()
	if sample.is_compressed():
		sample.decompress()
	check(sample.detect_alpha() != Image.ALPHA_NONE and sample.get_pixel(2, 2).a < 0.05, "Magnet artwork keeps its transparency")
	check(MagnetCatalog.texture("mag_missing") == null and not MagnetCatalog.has("mag_missing") and MagnetCatalog.display_name("mag_mvp") == "MVP",
		"unknown Magnets are rejected")

	section("No Coats or test art are shipped")
	check(CoatLibrary.all().is_empty(), "the game ships no Coats: every weapon keeps its factory finish")
	var stray: Array[String] = []
	_find_files("res://assets", ["sample_coat", "diagnostic", "coat_template", "start_here", ".ora"], stray)
	_find_files("res://data", ["sample_coat", "diagnostic"], stray)
	check(stray.is_empty(), "no kit samples, templates or diagnostic textures are in runtime content (%s)" % ", ".join(stray))
	check(FileAccess.file_exists("res://authoring/.gdignore"), "authoring kits are kept out of the game's imported content")


func _find_files(path: String, needles: Array[String], found: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_find_files(path.path_join(sub), needles, found)
	for file_name: String in dir.get_files():
		for needle: String in needles:
			if file_name.to_lower().contains(needle):
				found.append(path.path_join(file_name))


func _test_weapon_visuals() -> void:
	section("Every weapon: model, factory finish, Coat support, five Magnet slots")
	var world := Node3D.new()
	tree.root.add_child(world)
	var magnet_ids := MagnetCatalog.ids()
	for id: StringName in WeaponModels.ids():
		var visual := WeaponVisual.new()
		world.add_child(visual)
		var built := visual.setup(id)
		var length := float(WeaponModels.info(id)["length"])
		var meshes := visual.find_children("*", "MeshInstance3D", true, false).size()
		check(built and meshes > 0 and is_equal_approx(visual.size.z, length) and visual.size.x < visual.size.y and visual.size.y < visual.size.z,
			"%s: model loads upright along the barrel at %.2f m (%d meshes)" % [id, length, meshes])
		var factory := visual.factory_texture()
		check(visual.accepts_coats() and factory != null and Vector2i(factory.get_size()) == WeaponModels.coat_size(id),
			"%s: factory texture is in place and matches its Coat layout %s" % [id, WeaponModels.coat_size(id)])
		var uv_ok := true
		var geometry := visual.geometry()
		var uvs: PackedVector2Array = geometry[1]
		var spread := Rect2(uvs[0], Vector2.ZERO)
		for uv: Vector2 in uvs:
			spread = spread.expand(uv)
		uv_ok = (geometry[0] as PackedVector3Array).size() == uvs.size() and spread.size.x > 0.3 and spread.size.y > 0.3
		var slots := WeaponModels.slots(id)
		var sides_differ := slots.size() == 5 and (slots[0]["uv"] as Vector2).distance_to(slots[3]["uv"] as Vector2) > 0.01
		check(uv_ok and sides_differ, "%s: UVs cover the texture and the two sides use different texture areas" % id)

		var slots_ok := slots.size() == 5
		var half := visual.size / 2.0 + Vector3.ONE * 0.002
		for i: int in slots.size():
			var position: Vector3 = slots[i]["position"]
			var normal: Vector3 = slots[i]["normal"]
			slots_ok = slots_ok and absf(position.x) <= half.x and absf(position.y) <= half.y and absf(position.z) <= half.z \
				and is_equal_approx(normal.length(), 1.0) and signf(position.x) == signf(normal.x) and visual.decal(i) != null
		check(slots_ok, "%s: exactly five Magnet slots sit on the weapon's surface" % id)
		var applied := true
		for i: int in 5:
			applied = applied and visual.set_magnet(i, magnet_ids[i + 3])
		var shown := true
		for i: int in 5:
			var item := visual.decal(i)
			shown = shown and item.visible and item.texture_albedo == MagnetCatalog.texture(magnet_ids[i + 3]) \
				and item.cull_mask == WeaponVisual.WEAPON_LAYER and is_equal_approx(item.size.x, float(slots[i]["size"]))
		check(applied and shown and visual.magnets[4] == magnet_ids[7], "%s: a different Magnet shows in each of the five slots" % id)
		check(not visual.set_magnet(5, magnet_ids[0]) and not visual.set_magnet(0, "mag_missing") and visual.decal(0).visible,
			"%s: a sixth slot and unknown Magnets are refused" % id)

		var coat := ImageTexture.create_from_image(_diagnostic(id))
		visual.apply_coat(coat, "test")
		var painted := true
		for entry: Array in visual.paint_surfaces():
			var material := (entry[0] as MeshInstance3D).get_surface_override_material(int(entry[1])) as BaseMaterial3D
			painted = painted and material.albedo_texture == coat and material != entry[2]
		check(painted and visual.coat_id == "test" and visual.decal(2).visible and visual.decal(2).texture_albedo != coat,
			"%s: a Coat texture replaces the finish while Magnets stay separate on top" % id)
		visual.apply_coat(null)
		var restored := true
		for entry: Array in visual.paint_surfaces():
			restored = restored and (entry[0] as MeshInstance3D).get_surface_override_material(int(entry[1])) == entry[2]
		check(restored and visual.coat_id.is_empty() and visual.factory_texture() == factory, "%s: removing the Coat restores the factory finish" % id)
		check(visual.set_magnet(1, "") and not visual.decal(1).visible and visual.decal(0).visible, "%s: a Magnet can be removed from one slot" % id)
		visual.queue_free()
		await wait_frames(1)
	world.queue_free()
	await wait_frames(1)


func _test_coats() -> void:
	section("Coat library and kit conversion")
	var weapon := &"wpn_g17"
	var size := WeaponModels.coat_size(weapon)
	var base := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	base.fill(Color(0.2, 0.2, 0.2))
	var mask := CoatLibrary.zone_mask(weapon, 0)
	check(mask != null and mask.get_size() == size, "a kit's zone mask loads at the weapon's Coat size")
	mask.convert(Image.FORMAT_L8)
	var inside := Vector2i(-1, -1)
	var outside := Vector2i(-1, -1)
	for y: int in range(0, size.y, 16):
		for x: int in range(0, size.x, 16):
			var value := mask.get_pixel(x, y).r
			if value > 0.98 and inside.x < 0:
				inside = Vector2i(x, y)
			elif value < 0.02 and outside.x < 0:
				outside = Vector2i(x, y)
	var composed := CoatLibrary.compose(weapon, base, {0: Color(0.9, 0.1, 0.1)})
	check(inside.x >= 0 and outside.x >= 0 and composed.get_size() == size
		and _close(composed.get_pixelv(inside), Color(0.9, 0.1, 0.1)) and _close(composed.get_pixelv(outside), Color(0.2, 0.2, 0.2)),
		"painting a zone colours only that zone; everything else keeps the base")
	var art := _diagnostic(weapon)
	var with_art := CoatLibrary.compose(weapon, base, {0: art, 99: Color.GREEN})
	check(_close(with_art.get_pixelv(inside), art.get_pixelv(inside)) and _close(with_art.get_pixelv(outside), Color(0.2, 0.2, 0.2)),
		"a zone can take artwork, and unknown zones are ignored")
	check(_close(base.get_pixelv(inside), Color(0.2, 0.2, 0.2)), "composition never changes the base image")

	var result := CoatLibrary.register_image(weapon, composed, "Diagnostic test finish", "elite")
	var coat_id := str(result["id"])
	check(str(result["error"]).is_empty() and CoatLibrary.coats_for(weapon).size() == 1 and CoatLibrary.fits(weapon, coat_id)
		and CoatLibrary.coat(coat_id)["rarity"] == "elite" and CoatLibrary.coat(coat_id)["source"] == CoatLibrary.SOURCE_CUSTOM,
		"a kit export becomes a Coat by adding a PNG and a record (no code change)")
	var texture := CoatLibrary.texture(weapon, coat_id)
	check(texture != null and Vector2i(texture.get_size()) == size, "the Coat's texture loads at runtime")
	check(not CoatLibrary.fits(&"wpn_ak47", coat_id) and CoatLibrary.texture(&"wpn_ak47", coat_id) == null and CoatLibrary.coats_for(&"wpn_ak47").is_empty(),
		"a Coat only fits the weapon it was made for")
	check(CoatLibrary.texture(weapon, "") == null and CoatLibrary.texture(weapon, "coat_missing") == null, "an empty or unknown Coat means the factory finish")
	var half := composed.duplicate() as Image
	half.resize(size.x / 2, size.y / 2)
	check(str(CoatLibrary.register_image(weapon, half, "Half size")["error"]).is_empty(), "a same-shape image is resized to the layout")
	var wrong := Image.create(300, 700, false, Image.FORMAT_RGBA8)
	check(str(CoatLibrary.register_image(weapon, wrong, "Wrong shape")["error"]).contains("2048"), "a wrong-shaped image is refused with the expected size")
	check(not str(CoatLibrary.register_image(&"wpn_wasp_smg", composed, "No model")["error"]).is_empty()
		and not str(CoatLibrary.register_image(weapon, composed, "Bad rarity", "mythic")["error"]).is_empty(), "weapons without a model and unknown rarities are refused")
	var png := TEST_DIR.path_join("export_from_kit.png")
	composed.save_png(png)
	var imported := CoatLibrary.import_png(weapon, png, "Imported")
	check(str(imported["error"]).is_empty() and CoatLibrary.coats_for(weapon).size() == 3, "a PNG file exported from a kit is imported")
	check(not str(CoatLibrary.import_png(weapon, TEST_DIR.path_join("missing.png"), "Nope")["error"]).is_empty(), "an unreadable file is refused")
	CoatLibrary.refresh()
	check(CoatLibrary.coats_for(weapon).size() == 3 and CoatLibrary.fits(weapon, coat_id), "Coats are found again after a reload")
	check(CoatLibrary.remove_custom(str(imported["id"])) and CoatLibrary.coats_for(weapon).size() == 2 and not CoatLibrary.remove_custom("coat_missing"),
		"a custom Coat can be removed")
	check(CoatLibrary.RARITIES.size() >= 4 and CoatLibrary.validate({"id": "coat_x", "name": "X", "weapon_id": "wpn_g17", "texture": "res://x.png"}).is_empty()
		and not CoatLibrary.validate({"id": "../x", "name": "X", "weapon_id": "wpn_g17", "texture": "a"}).is_empty(), "records are validated and rarity tiers exist")


func _test_profile() -> void:
	section("Saved customisation")
	var profile := CosmeticProfile.current()
	var weapon := &"wpn_ak47"
	check(profile.loadout(weapon) == {"coat": "", "magnets": ["", "", "", "", ""]}, "a weapon starts with the factory finish and five empty slots")
	check(profile.set_magnet(weapon, 0, "mag_ace").is_empty() and profile.set_magnet(weapon, 4, "mag_ghost").is_empty()
		and profile.loadout(weapon)["magnets"] == ["mag_ace", "", "", "", "mag_ghost"], "Magnets are stored per slot")
	check(not profile.set_magnet(weapon, 5, "mag_ace").is_empty() and not profile.set_magnet(weapon, 0, "mag_missing").is_empty()
		and not profile.set_magnet(&"wpn_wasp_smg", 0, "mag_ace").is_empty(), "bad slots, unknown Magnets and weapons without models are refused")
	var g17_coat := str(CoatLibrary.coats_for(&"wpn_g17")[0]["id"])
	check(profile.set_coat(&"wpn_g17", g17_coat).is_empty() and not profile.set_coat(weapon, g17_coat).is_empty()
		and not profile.set_coat(weapon, "coat_missing").is_empty() and profile.loadout(weapon)["coat"] == "", "a Coat can only be equipped on its own weapon")
	check(profile.save() == OK and FileAccess.file_exists(profile.path), "the profile is saved")
	var saved := JSON.parse_string(FileAccess.get_file_as_string(profile.path)) as Dictionary
	check(saved["format"] == CosmeticProfile.FORMAT and int(saved["format_version"]) == 1, "the file has a format and version")
	var reloaded := CosmeticProfile.new()
	reloaded.path = profile.path
	check(reloaded.load_file() and reloaded.loadout(weapon)["magnets"] == ["mag_ace", "", "", "", "mag_ghost"]
		and reloaded.loadout(&"wpn_g17")["coat"] == g17_coat, "loading restores Coats and Magnets")
	profile.set_magnet(weapon, 0, "")
	check(profile.save() == OK and FileAccess.file_exists(profile.path + ".bak"), "saving again keeps the previous file as a backup")
	var stale := FileAccess.open(profile.path, FileAccess.WRITE)
	stale.store_string(JSON.stringify({"format": CosmeticProfile.FORMAT, "format_version": 1, "weapons": {
		"wpn_ak47": {"coat": g17_coat, "magnets": ["mag_gone", "mag_mvp", 7]}, "wpn_removed": {"coat": "", "magnets": []}}}))
	stale.close()
	check(reloaded.load_file() and reloaded.loadout(weapon) == {"coat": "", "magnets": ["", "mag_mvp", "", "", ""]}
		and not reloaded.weapons.has("wpn_removed"), "stale entries fall back to factory finish and empty slots")
	stale = FileAccess.open(profile.path, FileAccess.WRITE)
	stale.store_string("{\"format\": \"f2f.cosmetics\", \"format_version\": 9}")
	stale.close()
	check(not reloaded.load_file() and reloaded.weapons.is_empty(), "an unsupported file is ignored")
	profile.weapons.clear()
	profile.save()


func _test_armoury() -> void:
	section("Armoury")
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)
	var entry := tree.current_scene.get("armoury_button") as Button
	check(entry != null and entry.text == "Armoury", "the main menu has an Armoury entry")
	entry.pressed.emit()
	await wait_frames(3)
	var armoury := tree.current_scene as Armoury
	check(armoury != null and App.current_scene_id == App.SCENE_ARMOURY, "it opens the Armoury")
	if armoury == null:
		return
	check(armoury.weapon_list.item_count == 10 and armoury.weapon_id == &"wpn_ak47" and armoury.visual.weapon_id == &"wpn_ak47",
		"all ten weapons are listed and the first is shown for inspection")
	check(armoury.slot_buttons.size() == 5 and armoury.magnet_buttons.size() == 26, "it offers five Magnet slots and all 26 Magnets")
	check(armoury.coat_list.item_count == 1 and armoury.coat_list.get_item_text(0) == "Factory finish",
		"the Coat list shows only the factory finish: no fabricated Coats")
	_test_armoury_magnet_switch(armoury)
	check(armoury.select_weapon(&"wpn_m4a1") and armoury.visual.weapon_id == &"wpn_m4a1" and not armoury.select_weapon(&"wpn_wasp_smg"),
		"selecting a weapon shows it")
	armoury.select_slot(3)
	check(armoury.selected_slot == 3 and armoury.slot_buttons[3].button_pressed, "a slot can be selected")
	(armoury.magnet_buttons["mag_red_fox"] as Button).pressed.emit()
	check(armoury.visual.decal(3).visible and armoury.visual.decal(3).texture_albedo == MagnetCatalog.texture("mag_red_fox")
		and armoury.slot_buttons[3].text.contains("Red Fox") and armoury.is_dirty() and not armoury.save_button.disabled,
		"clicking a Magnet applies it to the selected slot in the preview")
	armoury.select_slot(0)
	armoury.set_magnet("mag_gg")
	check(armoury.visual.magnets[0] == "mag_gg" and armoury.visual.magnets[3] == "mag_red_fox", "slots hold different Magnets")
	armoury.select_slot(3)
	armoury.remove_magnet_button.pressed.emit()
	check(not armoury.visual.decal(3).visible and armoury.remove_magnet_button.disabled, "a Magnet can be removed")
	check(CosmeticProfile.current().loadout(&"wpn_m4a1")["magnets"] == ["", "", "", "", ""], "nothing reaches the profile before saving")
	armoury.revert()
	check(not armoury.is_dirty() and armoury.visual.magnets[0].is_empty(), "Revert discards the draft")
	armoury.select_slot(1)
	armoury.set_magnet("mag_mvp")
	armoury.select_weapon(&"wpn_g17")
	check(armoury.coat_list.item_count == 3, "Coats the player imported for this weapon are listed")
	var coat_id := str(CoatLibrary.coats_for(&"wpn_g17")[0]["id"])
	armoury.coat_list.item_selected.emit(1)
	check(armoury.draft.loadout(&"wpn_g17")["coat"] == coat_id and armoury.visual.coat_id == coat_id, "choosing a Coat previews it on the weapon")
	armoury.save_button.pressed.emit()
	check(not armoury.is_dirty() and armoury.save_button.disabled and CosmeticProfile.current().loadout(&"wpn_m4a1")["magnets"][1] == "mag_mvp"
		and CosmeticProfile.current().loadout(&"wpn_g17")["coat"] == coat_id, "Save writes the customisation to the profile")
	armoury.back_button.pressed.emit()
	await wait_frames(3)
	check(App.current_scene_id == App.SCENE_MAIN_MENU, "Back returns to the main menu")

	var fresh := CosmeticProfile.new()
	fresh.path = CosmeticProfile.current().path
	fresh.load_file()
	CosmeticProfile.use(fresh)
	App.go_to(App.SCENE_ARMOURY)
	await wait_frames(3)
	armoury = tree.current_scene as Armoury
	armoury.select_weapon(&"wpn_m4a1")
	check(armoury.visual.magnets[1] == "mag_mvp" and armoury.visual.decal(1).visible, "after a reload the saved Magnets are back on the weapon")
	armoury.select_weapon(&"wpn_g17")
	check(armoury.visual.coat_id == coat_id, "and the saved Coat is equipped")
	armoury.set_coat("")
	armoury.set_magnet("mag_ace")
	armoury.back_button.pressed.emit()
	check(armoury.confirm_dialog.visible and App.current_scene_id == App.SCENE_ARMOURY, "leaving with unsaved changes asks first")
	armoury.confirm_dialog.hide()
	armoury.save()
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)


func _test_armoury_magnet_switch(armoury: Armoury) -> void:
	armoury.select_slot(0)
	armoury.set_magnet("mag_ace")
	var ak_decal := armoury.visual.decal(0)
	armoury.select_weapon(WeaponCatalog.M4A1)
	var m4_decals := armoury.visual.find_children("*", "Decal", true, false)
	check(not ak_decal.is_inside_tree() and m4_decals.size() == WeaponModels.SLOT_COUNT
		and m4_decals.all(func(node: Node) -> bool: return not (node as Decal).visible),
		"switching from a decorated AK-47 to an empty M4A1 immediately removes all old decals")
	armoury.set_magnet("mag_red_fox")
	armoury.select_weapon(WeaponCatalog.AK47)
	check(armoury.visual.decal(0).visible and armoury.visual.magnets[0] == "mag_ace",
		"the AK-47 retains its own draft Magnet after switching back")
	armoury.select_weapon(WeaponCatalog.M4A1)
	var m4_returned := armoury.visual.find_children("*", "Decal", true, false)
	check(armoury.visual.magnets[0] == "mag_red_fox" and m4_returned.size() == WeaponModels.SLOT_COUNT,
		"the M4A1 retains its own draft Magnet and repeated switches keep exactly five decals")
	armoury.revert()


func _test_first_person() -> void:
	section("First person and inspection")
	var profile := CosmeticProfile.current()
	profile.set_magnet(&"wpn_ak47", 2, "mag_flame")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var player := sandbox.get_node("Player") as FirstPersonController
	var effects := sandbox.get_node("Effects") as WeaponEffects
	var hud := sandbox.get_node("Hud") as SandboxHud
	player.input_enabled = false
	check(effects.weapon_visual != null and effects.weapon_visual.weapon_id == WeaponCatalog.AK47
		and player.weapons.loadout_ids() == [WeaponCatalog.AK47, WeaponCatalog.G17, EquipmentCatalog.KNIFE],
		"the sandbox starts with a modelled AK-47, the G17 and the knife")
	check(hud.choose_sandbox_weapons(&"wpn_m4a1", &"wpn_m1911")
		and player.weapons.loadout_ids() == [&"wpn_m4a1", &"wpn_m1911", EquipmentCatalog.KNIFE],
		"the sandbox pause menu equips only the selected primary and secondary (plus the knife)")
	check(not bool(sandbox.call("set_sandbox_weapons", WeaponCatalog.G17, WeaponCatalog.AK47))
		and player.weapons.loadout_ids() == [WeaponCatalog.M4A1, WeaponCatalog.M1911, EquipmentCatalog.KNIFE],
		"the sandbox refuses swapped categories and retains the loadout")
	hud.choose_sandbox_weapons(WeaponCatalog.AK47, WeaponCatalog.G17)
	await wait_frames(2)
	var view := effects.weapon_visual
	check(view != null and view.weapon_id == &"wpn_ak47" and view.is_inside_tree() and effects.viewmodel.is_ancestor_of(view),
		"the AK-47 model is the first-person viewmodel")
	check(view != null and view.magnets[2] == "mag_flame" and view.decal(2).visible, "the saved Magnets show in first person")
	var held_ok := true
	for id: StringName in WeaponModels.ids():
		var definition := WeaponCatalog.get_definition(id)
		var secondary := definition.category == WeaponDefinition.CATEGORY_SECONDARY
		sandbox.call("set_sandbox_weapons", &"wpn_ak47" if secondary else id, id if secondary else &"wpn_g17")
		player.weapons.select_slot(definition.slot)
		await wait_frames(1)
		held_ok = held_ok and effects.weapon_visual != null and effects.weapon_visual.weapon_id == id and player.weapons.current().definition.id == id
	check(held_ok, "all ten weapons can be held and show their model in first person")
	player.weapons.draw_remaining = 0.0
	check(effects.inspect() and effects.is_inspecting(), "the weapon can be inspected")
	effects.set("_inspect_left", InspectLibrary.DEFAULT_SECONDS * 0.3)
	await wait_frames(2)
	var item_root := effects.get("_gun_root") as Node3D
	check(absf(item_root.rotation_degrees.y) > 20.0, "inspection turns the weapon to show its side")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	check(press.is_action_pressed(InputActions.INSPECT) and not InputActions.is_locked(InputActions.INSPECT), "F is the (rebindable) inspect key")
	var ammo := player.weapons.current().ammo
	player.weapons.trigger = true
	await wait_physics_frames(6)
	player.weapons.trigger = false
	check(player.weapons.current().ammo < ammo and not effects.is_inspecting(), "the modelled weapon fires through the existing weapon code, which ends the inspection")
	profile.set_magnet(&"wpn_ak47", 0, "mag_gg")
	sandbox.call("set_sandbox_weapons", &"wpn_ak47", &"wpn_g17")
	await wait_frames(1)
	effects.refresh_cosmetics()
	check(effects.weapon_visual.magnets[0] == "mag_gg", "the viewmodel picks up a changed customisation")
	await despawn(sandbox)
	await wait_frames(2)
