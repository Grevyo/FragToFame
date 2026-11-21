extends TestSuite
## Character models and the Developer Character Creator: the catalog of bodies and items from
## the downloaded packs, availability (the ithappy pack is local-only), what fits which body,
## dressing rules, appearances, unlocks, presets, the animated rig (every item on every body it
## fits), the player's stored look, the developer option, bots wearing models and the creator.
##
## Works with or without the ithappy pack installed: checks that need it say so and are skipped.

const TEST_DIR: String = "user://tests/characters"
const CREATOR_SCENE: String = "res://scenes/character_creator/character_creator.tscn"
const QM: String = "body_qm_modular_male"
const QU_MALE: String = "body_qu_male"
const QU_FEMALE: String = "body_qu_female"
const IH: String = "body_ih_creative"

var catalog: CharacterCatalog = CharacterCatalog.shared()


func suite_name() -> String:
	return "Character models and creator"


func run() -> void:
	_wipe(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var real_profile := CosmeticProfile.current()
	var profile := CosmeticProfile.new()
	profile.path = TEST_DIR.path_join("cosmetics.json")
	CosmeticProfile.use(profile)
	CharacterPresets.directory = TEST_DIR.path_join("presets")
	DevOptions.path = TEST_DIR.path_join("dev_options.json")
	DevOptions.reload()
	_test_catalog()
	_test_availability()
	_test_fit()
	_test_wardrobe()
	_test_appearance()
	_test_unlocks()
	_test_presets()
	await _test_rig()
	await _test_every_item()
	_test_profile()
	_test_dev_options()
	await _test_avatar_and_bots()
	await _test_creator()
	CosmeticProfile.use(real_profile)
	CharacterPresets.directory = CharacterPresets.DEFAULT_DIR
	DevOptions.path = DevOptions.DEFAULT_PATH
	DevOptions.reload()
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


func _ih_installed() -> bool:
	return catalog.is_available(IH)


# --- data ----------------------------------------------------------------------------------------

func _test_catalog() -> void:
	section("Character catalog")
	check(catalog.is_ok(), "the character catalog loads (%s)" % catalog.error)
	check(catalog.slot_ids().size() == 16, "16 slots, headwear to accessories")
	for slot_id: String in ["headwear", "facewear", "upper_body", "lower_body", "hands", "footwear", "accessory"]:
		check(catalog.has_slot(slot_id), "slot %s exists" % slot_id)
	check(catalog.body_ids().size() == 4, "4 base characters from 3 packs")
	check(catalog.items.size() == 82, "82 items: only what is in the downloaded files")
	var problems: Array[String] = []
	for item_id: String in catalog.items:
		var entry := catalog.item(item_id)
		if not item_id.begins_with(CharacterCatalog.ITEM_PREFIX):
			problems.append("%s: prefix" % item_id)
		if not catalog.has_slot(str(entry["slot"])):
			problems.append("%s: slot" % item_id)
		if not catalog.packs.has(str(entry["pack"])):
			problems.append("%s: pack" % item_id)
		if str((entry.get("unlock", {}) as Dictionary).get("kind", "")).is_empty():
			problems.append("%s: unlock" % item_id)
		for fit: Variant in entry.get("fits", []):
			if not catalog.has_body(str(fit)) or not (catalog.body(str(fit))["slots"] as Array).has(entry["slot"]):
				problems.append("%s: fits %s" % [item_id, fit])
		for channel: Dictionary in catalog.colour_channels(item_id):
			if str(channel.get("material", "")).is_empty():
				problems.append("%s: channel" % item_id)
		var pack := catalog.pack_of(item_id)
		if bool(pack.get("redistributable", false)) and not ResourceLoader.exists(str(entry["model"])):
			problems.append("%s: committed model missing" % item_id)
	check(problems.is_empty(), "every item has a known slot, pack, unlock, fitting bodies and colour channels %s" % [problems])
	check(ResourceLoader.exists(catalog.animation_library), "the shared animation library is imported")
	var bad := CharacterCatalog.from_dict({"format": "f2f.character_catalog", "format_version": 99})
	check(not bad.is_ok(), "a catalog of an unknown version is refused")


func _test_availability() -> void:
	section("Availability")
	for body_id: String in [QM, QU_MALE, QU_FEMALE]:
		check(catalog.is_available(body_id), "%s is installed (CC0, in the repository)" % catalog.display_name(body_id))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CharacterCatalog.PATH))
	var items: Array = data["items"]
	var ghost := (items[0] as Dictionary).duplicate(true)
	ghost["id"] = "chr_test_missing"
	ghost["model"] = "res://assets/characters/not_here.glb"
	items.append(ghost)
	var copy := CharacterCatalog.from_dict(data)
	check(not copy.is_available("chr_test_missing"), "an item whose model is missing is not available")
	check(copy.unavailable_reason("chr_test_missing").begins_with("Not installed"), "and says it is not installed")
	var problem := CharacterWardrobe.equip(copy, CharacterWardrobe.default_appearance(copy, str(ghost["fits"][0])), "chr_test_missing")
	check(problem.begins_with("Not installed"), "a missing item cannot be worn")
	if _ih_installed():
		check(catalog.unavailable_reason("chr_ih_hat_010").is_empty(), "ithappy pack installed locally: its items are available")
	else:
		check(catalog.unavailable_reason("chr_ih_hat_010").contains("not in this build"), "ithappy pack absent: its items say why")


func _test_fit() -> void:
	section("What fits which body")
	check(catalog.fit_mode("chr_qu_hair_long", QU_FEMALE) == CharacterCatalog.FIT_SKINNED, "Universal hair is skinned on Universal bodies")
	check(not catalog.fit_problem("chr_qu_hair_long", QM).is_empty(), "Universal hair does not go on the modular body (no hair slot)")
	check(catalog.fit_problem("chr_qm_swat_body", QU_MALE).contains("upper body"), "modular clothing does not go on a Universal body")
	check(catalog.fit_mode("chr_ih_hat_010", QU_MALE) == CharacterCatalog.FIT_HEAD, "an ithappy hat is adapted to the Universal head")
	check(catalog.fit_mode("chr_ih_hat_057", QU_MALE).is_empty(), "hat 057 is not adapted to Universal heads (the strap reads as a beard)")
	check(catalog.fit_problem("chr_ih_hat_057", QU_MALE).begins_with("Made for"), "and says what it was made for")
	check(catalog.items_for("hair", QU_MALE).has("chr_ih_hairstyle_male_010"), "adapted items are listed for the bodies they are adapted to")
	check(not catalog.items_for("hair", IH).has("chr_qu_hair_long"), "rejected adaptations are not listed (long hair on ithappy)")


func _test_wardrobe() -> void:
	section("Dressing rules")
	var look := CharacterWardrobe.default_appearance(catalog, QM)
	for slot_id: String in ["head", "upper_body", "lower_body", "footwear"]:
		check(not look.item_in(slot_id).is_empty(), "the modular default fills %s" % slot_id)
	check(not CharacterWardrobe.unequip(catalog, look, "head").is_empty(), "a required slot cannot be emptied")
	check(CharacterWardrobe.equip(catalog, look, "chr_qm_swat_head").is_empty(), "the swat head goes on")
	if _ih_installed():
		check(CharacterWardrobe.equip(catalog, look, "chr_ih_hat_010").is_empty(), "a hat over the swat helmet goes on")
		check(look.item_in("head").is_empty(), "and the swat head (which covers headwear) comes off")
		var notes := CharacterWardrobe.sanitize(catalog, look)
		check(look.item_in("head") == catalog.default_item(QM, "head") and notes.size() == 1, "sanitising puts the default head back")
		check(CharacterWardrobe.equip(catalog, look, "chr_qm_swat_head").is_empty() and look.item_in("headwear").is_empty(),
			"a covering head takes the hat off")
	var odd := CharacterAppearance.new()
	odd.body = QU_MALE
	odd.items = {"hair": "chr_qm_swat_head", "eyebrows": "chr_unknown", "upper_body": "chr_qm_swat_body"}
	odd.colours = {"chr_unknown": {"x": "#ff0000"}}
	var notes := CharacterWardrobe.sanitize(catalog, odd)
	check(odd.items.is_empty() and odd.colours.is_empty() and notes.size() == 3, "sanitising removes misplaced, unknown and unfitting items %s" % [notes])
	var nobody := CharacterAppearance.new()
	nobody.body = "body_nobody"
	CharacterWardrobe.sanitize(catalog, nobody)
	check(catalog.is_available(nobody.body), "an unknown body becomes an installed one")
	var stable := true
	var bodies: Dictionary[String, int] = {}
	for seed_value: int in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var random := CharacterWardrobe.randomise(catalog, rng)
		bodies[random.body] = 1
		var again := random.duplicate_appearance()
		if not CharacterWardrobe.sanitize(catalog, again).is_empty() or not again.equals(random):
			stable = false
		for slot_id: String in catalog.body_slots(random.body):
			if catalog.is_required(random.body, slot_id) and random.item_in(slot_id).is_empty() \
					and CharacterWardrobe.covered_by(catalog, random, slot_id).is_empty():
				stable = false
	check(stable, "60 random looks are all wearable as made")
	check(bodies.size() >= 3, "randomising uses every installed base character (%d seen)" % bodies.size())
	var team := CharacterWardrobe.default_appearance(catalog, QM)
	CharacterWardrobe.apply_team_colours(catalog, team, Color.RED, Color.BLUE)
	var painted := 0
	for item_id: String in team.items.values():
		var channel := catalog.team_channel(item_id, "primary")
		if not channel.is_empty() and team.colour(item_id, channel).is_equal_approx(Color.RED):
			painted += 1
	check(painted > 0, "team colours paint the primary uniform channels")


func _test_appearance() -> void:
	section("Appearance format")
	var look := CharacterWardrobe.default_appearance(catalog, QU_FEMALE)
	look.set_colour("chr_qu_hair_long", "tint", Color("aa3355"))
	look.skin_tone = "8a5a3c"
	var data := look.to_dict()
	check(str(data["format"]) == CharacterAppearance.FORMAT and int(data["format_version"]) == 1, "appearances carry a format and version")
	var back := CharacterAppearance.from_dict(JSON.parse_string(JSON.stringify(data)) as Dictionary)
	check(back.equals(look), "an appearance survives a JSON round trip")
	var junk := CharacterAppearance.from_dict({"format": CharacterAppearance.FORMAT, "format_version": 1, "items": 5, "colours": [1]})
	check(junk.items.is_empty() and junk.colours.is_empty(), "malformed fields load as empty")


func _test_unlocks() -> void:
	section("Unlocks")
	var none: Array[String] = []
	check(CharacterUnlocks.is_unlocked(catalog, "chr_qu_hair_long", none, false), "starter items are unlocked")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CharacterCatalog.PATH))
	var first := (data["items"] as Array)[0] as Dictionary
	first["unlock"] = {"kind": "career", "note": "test"}
	var copy := CharacterCatalog.from_dict(data)
	var item_id := str(first["id"])
	check(not CharacterUnlocks.is_unlocked(copy, item_id, none, false), "a career item is locked until owned")
	check(not CharacterUnlocks.lock_reason(copy, item_id, none, false).is_empty(), "and says why")
	var owned: Array[String] = [item_id]
	check(CharacterUnlocks.is_unlocked(copy, item_id, owned, false), "an owned career item is unlocked")
	check(CharacterUnlocks.is_unlocked(copy, item_id, none, true), "developer mode shows every item regardless of unlock")


func _test_presets() -> void:
	section("Presets")
	check(CharacterPresets.directory.begins_with(TEST_DIR), "tests write presets to a scratch folder")
	var look := CharacterWardrobe.default_appearance(catalog, QM)
	check(not str(CharacterPresets.save("   ", look)["error"]).is_empty(), "a preset needs a name")
	var saved := CharacterPresets.save("Test soldier", look)
	check(str(saved["error"]).is_empty(), "a preset saves")
	var id := str(saved["id"])
	check(CharacterPresets.list().size() == 1 and CharacterPresets.preset_name(id) == "Test soldier", "and is listed with its name")
	var loaded := CharacterPresets.load_preset(id)
	check(loaded != null and loaded.equals(look), "and loads back the same look")
	var other := CharacterWardrobe.default_appearance(catalog, QU_MALE)
	CharacterPresets.save("Renamed", other, id)
	check(CharacterPresets.list().size() == 1 and CharacterPresets.load_preset(id).equals(other), "saving with an ID overwrites that preset")
	check(CharacterPresets.load_preset("../escape") == null, "unsafe preset IDs are refused")
	check(CharacterPresets.delete(id) == OK and CharacterPresets.list().is_empty(), "a preset deletes")


# --- rig -----------------------------------------------------------------------------------------

func _new_rig() -> CharacterRig:
	var rig := CharacterRig.new()
	tree.root.add_child(rig)
	return rig


func _test_rig() -> void:
	section("Character rig")
	var rig := _new_rig()
	for body_id: String in catalog.body_ids():
		if not catalog.is_available(body_id):
			continue
		var notes := rig.apply(CharacterWardrobe.default_appearance(catalog, body_id))
		await wait_frames(1)
		check(notes.is_empty() and rig.skeleton != null, "%s builds on its own skeleton" % catalog.display_name(body_id))
		check(rig.retargeter != null and rig.retargeter.is_bound(), "  and is driven by the shared animations")
		var shown := 0
		for item_id: String in rig.appearance.items.values():
			shown += 1 if not rig.item_meshes(item_id).is_empty() else 0
		check(shown == rig.appearance.items.size(), "  every worn item has meshes (%d)" % shown)
		check(rig.top_height() > 1.4 and rig.top_height() < 2.3, "  stands a human height (%.2f m)" % rig.top_height())
	check(rig.clips().size() == 24, "24 animation clips (%d)" % rig.clips().size())
	for clip: StringName in [CharacterRig.ANIM_IDLE, CharacterRig.ANIM_WALK, CharacterRig.ANIM_RUN, CharacterRig.ANIM_RUN_BACK,
			CharacterRig.ANIM_RUN_LEFT, CharacterRig.ANIM_RUN_RIGHT, CharacterRig.ANIM_DEATH]:
		check(rig.clips().has(String(clip)), "clip %s exists" % clip)
	var look := CharacterWardrobe.default_appearance(catalog, QM)
	rig.apply(look)
	var hoodie_top := look.item_in("upper_body")
	CharacterWardrobe.equip(catalog, look, "chr_qm_swat_body")
	rig.apply(look)
	await wait_frames(1)
	check(rig.item_meshes(hoodie_top).is_empty() and not rig.item_meshes("chr_qm_swat_body").is_empty(), "swapping a top replaces its meshes")
	var channel := str(catalog.colour_channels("chr_qm_swat_body")[0]["id"])
	look.set_colour("chr_qm_swat_body", channel, Color("22aa44"))
	rig.apply(look)
	check(rig.channel_colour("chr_qm_swat_body", channel).is_equal_approx(Color("22aa44")), "an item channel takes its own colour")
	look.clear_colour("chr_qm_swat_body")
	rig.apply(look)
	check(rig.channel_colour("chr_qm_swat_body", channel).is_equal_approx(rig.factory_colour("chr_qm_swat_body", channel)),
		"and goes back to the model's colour")
	rig.play(CharacterRig.ANIM_RUN)
	await wait_frames(2)
	check(rig.animation_player.current_animation == "Run", "the rig plays a clip")
	rig.queue_free()
	await wait_frames(1)


func _test_every_item() -> void:
	section("Every item on every body it fits")
	var rig := _new_rig()
	var failures: Array[String] = []
	var tried := 0
	for body_id: String in catalog.body_ids():
		if not catalog.is_available(body_id):
			continue
		for slot_id: String in catalog.body_slots(body_id):
			for item_id: String in catalog.items_for(slot_id, body_id):
				if not catalog.is_available(item_id):
					continue
				var look := CharacterWardrobe.default_appearance(catalog, body_id)
				if not CharacterWardrobe.equip(catalog, look, item_id).is_empty():
					failures.append("%s on %s: refused" % [item_id, body_id])
					continue
				rig.apply(look)
				tried += 1
				if rig.item_meshes(item_id).is_empty():
					failures.append("%s on %s: no meshes" % [item_id, body_id])
	await wait_frames(1)
	check(tried >= 40, "%d item/body pairs built" % tried)
	check(failures.is_empty(), "every installed item shows on every body it fits %s" % [failures])
	rig.queue_free()
	await wait_frames(1)


# --- profile, options, bots -------------------------------------------------------------------------

func _test_profile() -> void:
	section("The player's look")
	var profile := CosmeticProfile.current()
	check(profile.path.begins_with(TEST_DIR), "tests use a scratch cosmetic profile")
	var look := CharacterWardrobe.default_appearance(catalog, QU_MALE)
	look.skin_tone = "6b4a33"
	profile.set_appearance(look)
	profile.owned_character_items = ["chr_qu_hair_buns"]
	check(profile.save() == OK, "the profile saves with a look")
	var reread := CosmeticProfile.new()
	reread.path = profile.path
	reread.load_file()
	check(reread.appearance.equals(look) and reread.owned_character_items == ["chr_qu_hair_buns"], "and loads it back")
	var old := FileAccess.open(TEST_DIR.path_join("old_cosmetics.json"), FileAccess.WRITE)
	old.store_string(JSON.stringify({"format": "f2f.cosmetics", "format_version": 1, "weapons": {}, "knife": ""}))
	old.close()
	var older := CosmeticProfile.new()
	older.path = TEST_DIR.path_join("old_cosmetics.json")
	older.load_file()
	check(older.appearance.body.is_empty() and not older.to_dict().has("appearance"), "a profile from before looks loads without one")


func _test_dev_options() -> void:
	section("Developer option")
	check(not DevOptions.bot_character_models(), "bots keep the box bodies by default")
	check(DevOptions.set_bot_character_models(true) == OK, "the option saves")
	DevOptions.reload()
	check(DevOptions.bot_character_models(), "and is read back")
	DevOptions.set_bot_character_models(false)


func _test_avatar_and_bots() -> void:
	section("Bots wearing character models")
	check(CharacterAvatar.movement_clip(Vector3.ZERO)[0] == CharacterRig.ANIM_IDLE, "standing still: idle")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, -2))[0] == CharacterRig.ANIM_WALK, "slow: walk")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, -5))[0] == CharacterRig.ANIM_RUN, "fast forward: run")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, 5))[0] == CharacterRig.ANIM_RUN_BACK, "fast backward: run back")
	check(CharacterAvatar.movement_clip(Vector3(-5, 0, 0))[0] == CharacterRig.ANIM_RUN_LEFT, "fast left: run left")
	var plain := BotController.new()
	plain.setup("chr_plain", "Plain", &"home", BotSkill.preset(&"normal"), Color("3c6a8a"))
	tree.root.add_child(plain)
	check(plain.avatar == null, "with the option off a bot has no character model")
	DevOptions.set_bot_character_models(true)
	var bot := BotController.new()
	bot.setup("chr_model", "Model", &"home", BotSkill.preset(&"normal"), Color("3c6a8a"))
	tree.root.add_child(bot)
	await wait_frames(2)
	check(bot.avatar != null and bot.avatar.rig.skeleton != null, "with it on the bot wears a character model")
	check(bot.hitboxes.size() == plain.hitboxes.size(), "with the same hitboxes")
	var box_meshes := 0
	for hitbox: Hitbox in bot.hitboxes:
		for child: Node in hitbox.get_children():
			box_meshes += 1 if child is MeshInstance3D else 0
	check(box_meshes == 0, "and no box body")
	var again := BotController.new()
	again.setup("chr_model", "Model", &"home", BotSkill.preset(&"normal"), Color("3c6a8a"))
	check(again.appearance != null and again.appearance.equals(bot.appearance), "a bot's look is the same every time (seeded by its ID)")
	again.free()
	bot.health.kill()
	await wait_frames(2)
	check(bot.avatar.is_dead() and bot.avatar.rig.current_clip() == CharacterRig.ANIM_DEATH, "a dying bot plays the death clip")
	bot.respawn_at(Vector3.ZERO, 0.0)
	await wait_frames(2)
	check(not bot.avatar.is_dead(), "and moves again after respawning")
	DevOptions.set_bot_character_models(false)
	bot.queue_free()
	plain.queue_free()
	await wait_frames(1)


# --- creator -----------------------------------------------------------------------------------

func _test_creator() -> void:
	section("Character Creator")
	check(App.SCENE_PATHS.has(App.SCENE_CHARACTER_CREATOR), "the creator is a registered scene")
	var creator := spawn_scene(CREATOR_SCENE) as CharacterCreator
	if creator == null:
		return
	await wait_frames(2)
	check(creator.body_list.item_count == catalog.body_ids().size(), "every base character is listed")
	check(creator.rig.skeleton != null and not creator.appearance.body.is_empty(), "a character is shown")
	check(creator.clip_picker.item_count == 24, "with the animation picker")
	check(creator.select_body(QM).is_empty() and creator.appearance.body == QM, "choosing the modular body")
	check(creator.slot_pickers.has("upper_body") and not creator.slot_pickers.has("hair"), "shows that body's slots")
	check(not creator.equip_item("chr_qu_hair_long").is_empty(), "an incompatible item is refused")
	var picker := creator.slot_pickers["upper_body"]
	var choices: Array = creator.slot_choices["upper_body"]
	var swat := choices.find("chr_qm_swat_body")
	check(swat > 0 and not picker.is_item_disabled(swat), "fitting items are enabled in the picker")
	check(creator.equip_item("chr_qm_swat_body").is_empty() and creator.appearance.item_in("upper_body") == "chr_qm_swat_body",
		"equipping an item")
	check(not creator.rig.item_meshes("chr_qm_swat_body").is_empty(), "shows it on the preview")
	check(not creator.clear_slot("upper_body").is_empty(), "a required slot stays filled")
	check(creator.select_body(QU_FEMALE).is_empty(), "choosing a Universal body")
	var hair_choices: Array = creator.slot_choices["hair"]
	var hair_picker := creator.slot_pickers["hair"]
	var mohawk := hair_choices.find("chr_ih_hairstyle_male_010")
	check(mohawk > 0, "adapted and other-pack items are listed")
	if not _ih_installed():
		check(hair_picker.is_item_disabled(mohawk) and not hair_picker.get_item_tooltip(mohawk).is_empty(),
			"a not-installed item is disabled and says why")
	var long_hair := hair_choices.find("chr_qu_hair_long")
	check(not hair_picker.is_item_disabled(long_hair), "native hair is enabled")
	check(creator.clear_slot("hair").is_empty() and creator.appearance.item_in("hair").is_empty(), "an optional slot empties")
	creator.equip_item("chr_qu_hair_long")
	creator.set_item_colour("chr_qu_hair_long", "tint", Color("3355aa"))
	check(creator.rig.channel_colour("chr_qu_hair_long", "tint").is_equal_approx(Color("3355aa")), "an item colour changes the preview")
	creator.set_skin_tone(Color("7a5236"))
	check(creator.appearance.skin_tone == "#7a5236", "the skin tone changes")
	check(creator.set_skin_texture("lighter").is_empty() and creator.appearance.skin_texture == "lighter", "a skin texture is chosen")
	var saved := creator.save_preset("Creator test")
	check(str(saved["error"]).is_empty() and creator.preset_list.item_count == 1, "saving a preset lists it")
	var kept := creator.appearance.duplicate_appearance()
	creator.randomise()
	await wait_frames(1)
	check(creator.rig.skeleton != null, "randomise shows a new character")
	check(creator.load_preset(str(saved["id"])).is_empty() and creator.appearance.equals(kept), "loading the preset brings the look back")
	check(creator.use_as_my_look() == OK and CosmeticProfile.current().appearance.equals(kept), "use as my look stores it in the profile")
	creator.set_developer_mode(false)
	check(not creator.developer_mode and creator.appearance.equals(kept), "developer mode off: starter items stay")
	creator.set_developer_mode(true)
	check(creator.set_bot_models(true) == OK and DevOptions.bot_character_models(), "the creator turns bot models on")
	creator.set_bot_models(false)
	check(creator.delete_preset(str(saved["id"])) == OK and creator.preset_list.item_count == 0, "deleting the preset")
	creator.play_clip(CharacterRig.ANIM_RUN)
	await wait_frames(2)
	check(creator.rig.animation_player.current_animation == "Run", "the animation picker plays a clip")
	await despawn(creator)
