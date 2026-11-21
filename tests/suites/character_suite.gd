extends TestSuite
## Character models and the Developer Character Creator: the catalog of bodies and items from
## the downloaded packs, availability (the ithappy pack is local-only), what fits which body,
## dressing rules, appearances, unlocks and career grants, presets, the animated rig (every item
## on every body it fits), crouching, held weapons, the player's stored look, the developer option,
## bots wearing models, team uniforms, other players' looks over the network and the creator.
##
## Works with or without the ithappy pack installed: checks that need it say so and are skipped.

const TEST_DIR: String = "user://tests/characters"
const CREATOR_SCENE: String = "res://scenes/character_creator/character_creator.tscn"
const QM: String = "body_qm_modular_male"
const QU_MALE: String = "body_qu_male"
const QU_FEMALE: String = "body_qu_female"
const IH: String = "body_ih_creative"
## Test-only loopback port (246xx), distinct from the match session suite's.
const MATCH_PORT: int = 24672

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
	DevOptions.file_path = TEST_DIR.path_join("dev_options.json")
	DevOptions.reread()
	_test_catalog()
	_test_availability()
	_test_fit()
	_test_wardrobe()
	_test_appearance()
	_test_unlocks()
	_test_career_grants()
	_test_presets()
	await _test_rig()
	await _test_every_item()
	await _test_crouch_and_weapon()
	_test_profile()
	_test_dev_options()
	await _test_avatar_and_bots()
	_test_team_kits()
	await _test_network_looks()
	await _test_creator()
	CosmeticProfile.use(real_profile)
	CharacterPresets.directory = CharacterPresets.DEFAULT_DIR
	DevOptions.file_path = DevOptions.DEFAULT_PATH
	DevOptions.reread()
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
	check(catalog.items.size() == 85, "85 items: only what is in the downloaded files (%d)" % catalog.items.size())
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


func _test_career_grants() -> void:
	section("Career unlocks")
	var none: Array[String] = []
	var career_items: Array[String] = []
	for item_id: String in catalog.items:
		if CharacterUnlocks.kind_of(catalog, item_id) == CharacterUnlocks.KIND_CAREER:
			career_items.append(item_id)
			if CharacterUnlocks.career_rule(catalog, item_id).is_empty():
				check(false, "%s has a career rule" % item_id)
	check(career_items.size() == 17, "four outfits (16 parts) and the crown are career rewards (%d)" % career_items.size())
	check(not CharacterUnlocks.is_unlocked(catalog, "chr_qm_swat_body", none, false), "the SWAT outfit is locked at the start")
	check(CharacterUnlocks.lock_reason(catalog, "chr_qm_swat_body", none, false).contains("10 career matches"),
		"and says what earns it")
	check(CharacterUnlocks.earned_items(catalog, {}).is_empty(), "no progress earns nothing")
	var progress := {CareerUnlockProgress.MATCHES: 12, CareerUnlockProgress.KILLS: 40, CareerUnlockProgress.CONTRACTS: 1,
		CareerUnlockProgress.PODIUMS: 0, CareerUnlockProgress.TITLES: 0}
	var owned: Array[String] = []
	var granted := CharacterUnlocks.grant_earned(catalog, owned, progress)
	check(granted.has("chr_qm_swat_head") and granted.has("chr_qm_suit_body") and not granted.has("chr_qm_spacesuit_body")
		and not granted.has("chr_qm_king_head"), "12 matches and a contract earn the SWAT and suit outfits, not the others")
	check(granted.size() == 8 and owned.size() == 8, "each part is granted once (%d)" % granted.size())
	check(CharacterUnlocks.grant_earned(catalog, owned, progress).is_empty(), "nothing is granted twice")
	check(CharacterUnlocks.is_unlocked(catalog, "chr_qm_swat_body", owned, false), "earned items can be worn")
	var hub_script := load("res://scenes/career_hub/career_hub.gd") as GDScript
	check(bool(hub_script.call("is_player_save", "user://careers/sav_x/career.db")), "careers in the save folder grant items")
	check(not bool(hub_script.call("is_player_save", "user://tests/careers/sav_x/career.db")),
		"test careers never grant items to the player's profile")


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
	await _test_headwear(rig)
	check(failures.is_empty(), "every installed item shows on every body it fits %s" % [failures])
	rig.queue_free()
	await wait_frames(1)


## Modular Male's hats: three split off the pack's heads, three adapted from another pack.
func _test_headwear(rig: CharacterRig) -> void:
	var hats := catalog.items_for("headwear", QM)
	check(hats.size() == 6, "Modular Male has six hats (%d)" % hats.size())
	for item_id: String in ["chr_qm_hat_hard_hat", "chr_qm_hat_straw_hat", "chr_qm_hat_crown"]:
		var look := CharacterWardrobe.default_appearance(catalog, QM)
		CharacterWardrobe.equip(catalog, look, item_id)
		rig.apply(look)
		var meshes := rig.item_meshes(item_id)
		check(not meshes.is_empty() and meshes[0].skin != null, "%s is split off its head and skinned to it" % item_id)
	var look := CharacterWardrobe.default_appearance(catalog, QM)
	CharacterWardrobe.equip(catalog, look, "chr_ih_hat_010")
	rig.apply(look)
	await wait_frames(2)
	var head_bone := rig.skeleton.find_bone(&"Head")
	var head := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(head_bone).origin
	var hat_meshes := rig.item_meshes("chr_ih_hat_010")
	var hat := hat_meshes[0].global_transform * hat_meshes[0].get_aabb().get_center() if not hat_meshes.is_empty() else Vector3.ZERO
	check(Vector2(hat.x - head.x, hat.z - head.z).length() < 0.12 and hat.y > head.y and hat.y - head.y < 0.4,
		"an adapted hat sits on top of the head (%.2f m above it)" % (hat.y - head.y))
	CharacterWardrobe.equip(catalog, look, "chr_qm_hat_hard_hat")
	rig.apply(look)
	check(rig.hair_hidden() and _visible_hair(rig) == 0, "a hat modelled for a bald head hides the hair under it")
	CharacterWardrobe.equip(catalog, look, "chr_qm_hat_crown")
	rig.apply(look)
	check(not rig.hair_hidden() and _visible_hair(rig) > 0, "and the hair comes back with a hat that fits over it")


static func _visible_hair(rig: CharacterRig) -> int:
	var count := 0
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface)
			count += 1 if mesh.visible and material != null and material.resource_name == "Hair" else 0
	return count


func _test_crouch_and_weapon() -> void:
	section("Crouching and held weapons")
	var avatar := CharacterAvatar.new()
	tree.root.add_child(avatar)
	avatar.apply(CharacterWardrobe.default_appearance(catalog, QU_MALE))
	var heights: Array[float] = []
	var head := avatar.rig.skeleton.find_bone(&"Head")
	var measure := func() -> void:
		heights.append((avatar.rig.skeleton.global_transform * avatar.rig.skeleton.get_bone_global_pose(head).origin).y)
	avatar.rig.skeleton.skeleton_updated.connect(measure)
	await wait_frames(3)
	var standing := heights[heights.size() - 1] if not heights.is_empty() else 0.0
	avatar.crouch = 1.0
	await wait_frames(3)
	var crouched := heights[heights.size() - 1] if not heights.is_empty() else 0.0
	avatar.rig.skeleton.skeleton_updated.disconnect(measure)
	check(standing > 1.4, "standing head height %.2f m" % standing)
	var hitbox_head := standing * CombatantMovementBody.CROUCH_HEIGHT / CombatantMovementBody.STAND_HEIGHT
	check(absf(crouched - hitbox_head) < 0.1, "a full crouch brings the head onto the crouched head hitbox (%.2f m to %.2f m, hitbox %.2f m)"
		% [standing, crouched, hitbox_head])
	check(avatar.rig.retargeter.crouch_angle() > 0.3, "by bending the knees (%.2f rad)" % avatar.rig.retargeter.crouch_angle())
	avatar.set_weapon(&"wpn_ak47")
	await wait_frames(3)
	check(avatar.weapon_visual != null and avatar.weapon_visual.weapon_id == &"wpn_ak47", "a weapon is held")
	var hand_height := avatar.held_at.y - avatar.global_position.y
	check(avatar.weapon_visual.global_position.distance_to(avatar.held_at) < avatar.weapon_visual.size.z * 0.5
		and hand_height > 0.5 and hand_height < 1.6, "in the right hand (%.2f m up)" % hand_height)
	var forward := -avatar.weapon_visual.global_transform.basis.z
	check(forward.dot(-avatar.global_transform.basis.z) > 0.9, "pointing where the character faces")
	check(CharacterAvatar.held_model(EquipmentCatalog.KNIFE) == WeaponModels.DEFAULT_KNIFE, "the knife shows the default knife look")
	check(CharacterAvatar.held_model(&"wpn_utility_unknown").is_empty(), "items without a model leave the hands empty")
	check(avatar.rig.upper_clip() == CharacterRig.ANIM_AIM, "a gun keeps the upper body in the gun-holding clip")
	var misses: Dictionary[StringName, float] = {}
	var measure_hands := func() -> void:
		for side: StringName in avatar.rig.retargeter.reach:
			misses[side] = avatar.rig.retargeter.grip_position(side).distance_to(avatar.rig.retargeter.reach[side])
	avatar.rig.skeleton.skeleton_updated.connect(measure_hands)
	await wait_frames(3)
	check(misses.has(&"Right") and misses.has(&"Left") and misses[&"Right"] < 0.02 and misses[&"Left"] < 0.05,
		"both hands are on the rifle's grips %s" % [misses])
	avatar.set_weapon(&"wpn_desert_eagle")
	await wait_frames(3)
	check(misses[&"Right"] < 0.02 and misses[&"Left"] < 0.05, "and on a pistol, two-handed %s" % [misses])
	avatar.rig.skeleton.skeleton_updated.disconnect(measure_hands)
	var still := avatar.weapon_visual.global_transform.basis.z
	avatar.rig.play(CharacterRig.ANIM_RUN)
	await wait_frames(4)
	check(avatar.rig.upper_clip() == CharacterRig.ANIM_AIM and avatar.weapon_visual.global_transform.basis.z.dot(still) > 0.98,
		"running keeps the gun raised and pointed ahead")
	avatar.set_weapon(WeaponModels.DEFAULT_KNIFE)
	check(avatar.rig.upper_clip().is_empty(), "a knife lets the free arm move with the legs")
	avatar.set_weapon(&"")
	check(avatar.weapon_visual == null and avatar.rig.upper_clip().is_empty(), "and a weapon can be put away")
	check(CharacterAvatar.movement_clip(Vector3.ZERO, true)[0] == CharacterRig.ANIM_AIM, "armed and still: weapon raised")
	avatar.queue_free()
	await wait_frames(1)
	for gun: StringName in WeaponModels.ids():
		var points := WeaponModels.hand_points(gun, Vector3(0.05, 0.2, 0.8))
		if not points.has(&"Right") or not points.has(&"Left") or WeaponModels.hand_frames(gun).size() != 2:
			check(false, "%s has grips for both hands" % gun)
	check(WeaponModels.hand_points(WeaponModels.DEFAULT_KNIFE, Vector3(0.01, 0.05, 0.3)).keys() == [&"Right"],
		"every gun has grips for both hands; a knife is held in one")
	await _test_first_person_arms()


func _test_first_person_arms() -> void:
	section("First-person arms")
	var camera := Camera3D.new()
	tree.root.add_child(camera)
	var arms := FirstPersonArms.new()
	camera.add_child(arms)
	check(not arms.apply(null) and not arms.visible, "no look: no arms")
	check(arms.apply(CharacterWardrobe.default_appearance(catalog, QM)), "the player's look gives arms")
	var gun := WeaponVisual.new()
	camera.add_child(gun)
	gun.setup(&"wpn_ak47")
	# Where the viewmodel holds a long gun (WeaponEffects): butt just behind the view.
	gun.position = Vector3(0.17, -0.17 - gun.size.y * 0.22, -0.3 + 0.36 - gun.size.z / 2.0)
	arms.hold(gun, gun.weapon_id, gun.size)
	check(arms.visible, "shown while something is held")
	var misses: Dictionary[StringName, float] = {}
	var head_scale := [1.0]
	var measure := func() -> void:
		var skeleton := arms.rig.skeleton
		for side: StringName in arms.rig.retargeter.reach:
			misses[side] = arms.rig.retargeter.grip_position(side).distance_to(arms.rig.retargeter.reach[side])
		head_scale[0] = skeleton.get_bone_global_pose(skeleton.find_bone(&"Head")).basis.get_scale().x
	arms.rig.skeleton.skeleton_updated.connect(measure)
	await wait_frames(3)
	check(misses.get(&"Right", 1.0) < 0.02 and misses.get(&"Left", 1.0) < 0.05, "the hands hold the viewmodel %s" % [misses])
	check(float(head_scale[0]) < 0.01, "the head is hidden from the eye")
	gun.position += Vector3(-0.06, 0.04, -0.04)
	gun.rotation_degrees = Vector3(8, -25, 10)
	await wait_frames(3)
	check(misses.get(&"Right", 1.0) < 0.03, "and follow it through an inspection %s" % [misses])
	arms.rig.skeleton.skeleton_updated.disconnect(measure)
	arms.hold(null, &"", Vector3.ZERO)
	check(not arms.visible, "empty hands hide the arms")
	camera.queue_free()
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
	check(DevOptions.bot_character_models(), "bots wear character models by default")
	check(DevOptions.set_bot_character_models(false) == OK, "the option saves")
	DevOptions.reread()
	check(not DevOptions.bot_character_models(), "and is read back")
	var old := FileAccess.open(DevOptions.file_path, FileAccess.WRITE)
	old.store_string(JSON.stringify({"format": DevOptions.FORMAT, "format_version": 1, "bot_character_models": false}))
	old.close()
	DevOptions.reread()
	check(DevOptions.bot_character_models(), "an old v1 \"off\" no longer keeps the box bodies")


func _test_avatar_and_bots() -> void:
	section("Bots wearing character models")
	check(CharacterAvatar.movement_clip(Vector3.ZERO)[0] == CharacterRig.ANIM_IDLE, "standing still: idle")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, -2))[0] == CharacterRig.ANIM_WALK, "slow: walk")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, -5))[0] == CharacterRig.ANIM_RUN, "fast forward: run")
	check(CharacterAvatar.movement_clip(Vector3(0, 0, 5))[0] == CharacterRig.ANIM_RUN_BACK, "fast backward: run back")
	check(CharacterAvatar.movement_clip(Vector3(-5, 0, 0))[0] == CharacterRig.ANIM_RUN_LEFT, "fast left: run left")
	DevOptions.set_bot_character_models(false)
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
	check(CharacterPresets.directory.begins_with(TEST_DIR) and DevOptions.file_path.begins_with(TEST_DIR),
		"bot tests use the scratch folder, never the player's presets")
	for entry: Dictionary in CharacterPresets.list():
		if CharacterPresets.directory.begins_with(TEST_DIR):
			CharacterPresets.delete(str(entry["id"]))
	var saved := CharacterWardrobe.default_appearance(catalog, QU_FEMALE)
	var saved_id := str(CharacterPresets.save("Bot test", saved)["id"])
	var worn := CharacterAvatar.bot_look(hash("chr_any"), Color("3c6a8a"))
	check(worn != null and worn.body == QU_FEMALE and worn.items == saved.items, "bots wear the player's saved presets")
	var dressed := BotController.new()
	dressed.setup("chr_dressed", "Dressed", &"home", BotSkill.preset(&"normal"), Color("3c6a8a"))
	check(dressed.appearance != null and dressed.appearance.body == QU_FEMALE, "every bot set up picks from them")
	dressed.free()
	var own := CosmeticProfile.current().appearance.duplicate_appearance()
	CosmeticProfile.current().set_appearance(null)
	check(CharacterAvatar.player_look() != null and CharacterAvatar.player_look().body == QU_FEMALE,
		"a player with no look of their own is seen in their newest preset")
	CosmeticProfile.current().set_appearance(own)
	CharacterPresets.delete(saved_id)
	var again := BotController.new()
	again.setup("chr_model", "Model", &"home", BotSkill.preset(&"normal"), Color("3c6a8a"))
	check(again.appearance != null and again.appearance.equals(bot.appearance), "a bot's look is the same every time (seeded by its ID)")
	again.free()
	check(bot.avatar.weapon_id == CharacterAvatar.held_model(bot.weapons.current().definition.id),
		"the bot holds its current weapon")
	bot.health.kill()
	await wait_frames(2)
	check(bot.avatar.is_dead() and bot.avatar.rig.current_clip() == CharacterRig.ANIM_DEATH, "a dying bot plays the death clip")
	bot.respawn_at(Vector3.ZERO, 0.0)
	await wait_frames(2)
	check(not bot.avatar.is_dead(), "and moves again after respawning")
	bot.queue_free()
	plain.queue_free()
	await wait_frames(1)


func _test_team_kits() -> void:
	section("Team uniforms")
	var setup := MatchSetup.new()
	check(setup.team_colour(0, Color.RED).is_equal_approx(Color.RED), "no team colour: the runtime's colour")
	setup.home_colour = "#2255aa"
	setup.away_colour = "#aa2222"
	var data := setup.to_dict()
	check(int(data["format_version"]) == 3 and str(data["home_colour"]) == "#2255aa", "match setups carry team colours (v3)")
	var back := MatchSetup.from_dict(data)
	check(back != null and back.team_colour(1, Color.WHITE).is_equal_approx(Color("aa2222")), "and they survive a round trip")
	data["format_version"] = 2
	data.erase("home_colour")
	data.erase("away_colour")
	var older := MatchSetup.from_dict(data)
	check(older != null and older.home_colour.is_empty(), "a v2 setup still loads, with the runtime's colours")
	check(CareerKits.away_kit("#2255aa", "#aa2222") == "#aa2222", "different kits are kept")
	var change := CareerKits.away_kit("#2255aa", "#2a58a8")
	check(not CareerKits.clashes(Color("2255aa"), Color(change)), "a clashing away kit changes to a contrasting one (%s)" % change)
	var look := CharacterAvatar.random_look(hash("chr_kit"), Color("2255aa"))
	var painted := false
	for item_id: String in look.items.values():
		var channel := catalog.team_channel(item_id, "primary")
		painted = painted or (not channel.is_empty() and look.colour(item_id, channel).is_equal_approx(Color("2255aa")))
	check(painted or look.body != QM, "a bot's uniform takes its team colour")


func _test_network_looks() -> void:
	section("Other players' looks over the network")
	var host_root := Node3D.new()
	host_root.name = "CharacterHostWorld"
	var client_root := Node3D.new()
	client_root.name = "CharacterClientWorld"
	tree.root.add_child(host_root)
	tree.root.add_child(client_root)
	var host_session := MatchSession.new()
	host_session.name = "MatchSession"
	var client_session := MatchSession.new()
	client_session.name = "MatchSession"
	host_root.add_child(host_session)
	client_root.add_child(client_session)
	var host_body := Node3D.new()
	host_root.add_child(host_body)
	var client_body := Node3D.new()
	client_root.add_child(client_body)
	var client_head := Node3D.new()
	client_head.name = "Head"
	client_body.add_child(client_head)
	var client_weapons := WeaponController.new()
	client_weapons.name = "Weapons"
	client_body.add_child(client_weapons)
	var ak: Array[StringName] = [&"wpn_ak47"]
	client_weapons.set_loadout(ak)
	host_session.local_body = host_body
	client_session.local_body = client_body
	var host_look := CharacterWardrobe.default_appearance(catalog, QU_FEMALE)
	var client_look := CharacterWardrobe.default_appearance(catalog, QM)
	host_session.local_appearance = host_look.to_dict()
	client_session.local_appearance = client_look.to_dict()
	client_head.rotation.x = 0.3
	check(host_session.host(MATCH_PORT, "127.0.0.1") == OK, "match host listens")
	client_session.join("127.0.0.1", MATCH_PORT)
	var shared := await wait_until(func() -> bool:
		var id := client_session.local_peer_id()
		var a := host_session.avatar_for(id)
		var b := client_session.avatar_for(1)
		return a != null and b != null and a.character != null and b.character != null, 6.0)
	check(shared, "both players see the other as a character model")
	var client_id := client_session.local_peer_id()
	var on_host := host_session.avatar_for(client_id)
	var on_client := client_session.avatar_for(1)
	if shared:
		check(on_host.character.rig.appearance.equals(client_look), "the host sees the client's own look")
		check(on_client.character.rig.appearance.equals(host_look), "the client sees the host's own look")
		check(not on_host.get_node("Body").visible, "the capsule is hidden behind a model")
		var armed := await wait_until(func() -> bool: return on_host.character.weapon_id == &"wpn_ak47", 3.0)
		check(armed, "the host sees the client's weapon in its hand")
		check(is_equal_approx(on_host.character.aim_pitch, 0.3), "and where it aims")
	on_host.apply_state(Vector3.ZERO, 0.0, 1.0, 0.0, &"")
	check(on_host.character == null or is_equal_approx(on_host.character.crouch, 1.0), "a crouching player is shown crouching")
	var junk := {"format": "f2f.character_appearance", "body": "body_nobody", "items": {"x": "y"}}
	check(on_host.apply_appearance(junk), "a foreign look is sanitised to something wearable")
	check(not on_host.apply_appearance({}), "no look: the capsule")
	var huge := {"filler": "x".repeat(MatchSession.MAX_APPEARANCE_BYTES + 10)}
	check(not host_session.call("_store_appearance", 99, huge), "oversized looks are refused")
	client_session.leave("test over")
	host_session.leave("test over")
	host_root.queue_free()
	client_root.queue_free()
	await wait_frames(2)


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
