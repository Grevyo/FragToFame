class_name SoundSuite
extends TestSuite
## Milestone 22: original generated sound effects, the library that plays them (or supplied
## replacements), volume settings and buses, and the game's sounds in the FPS runtime: shots,
## running footsteps (walking is silent), grenades and the bomb.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Sound (Milestone 22)"


func run() -> void:
	_test_generator()
	_test_library()
	_test_settings()
	await _test_in_game()


func _test_generator() -> void:
	section("Generated effects")
	var silent: Array[String] = []
	var loud: Array[String] = []
	for slot: StringName in SoundCatalog.slots():
		var samples := SoundSynth.render(SoundCatalog.recipe(slot), SoundCatalog.seed_for(slot))
		var peak := 0.0
		for sample: float in samples:
			peak = maxf(peak, absf(sample))
		if peak < 0.2:
			silent.append(String(slot))
		if peak > 0.91:
			loud.append(String(slot))
	check(SoundCatalog.slots().size() >= 40, "%d sound slots" % SoundCatalog.slots().size())
	check(silent.is_empty() and loud.is_empty(), "every slot makes a sound within its peak (silent: %s; clipping: %s)" % [
		", ".join(silent), ", ".join(loud)])
	var first := SoundSynth.render(SoundCatalog.recipe(&"shot_ak47"), SoundCatalog.seed_for(&"shot_ak47"))
	var again := SoundSynth.render(SoundCatalog.recipe(&"shot_ak47"), SoundCatalog.seed_for(&"shot_ak47"))
	check(first == again and first.size() == int(0.75 * SoundSynth.RATE), "the generator is repeatable (same recipe and seed, same samples)")
	var other := SoundSynth.render(SoundCatalog.recipe(&"shot_ak47"), 12345)
	check(other != first, "a different seed gives a different take")
	var stream := SoundSynth.to_stream(first)
	check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == SoundSynth.RATE and stream.data.size() == first.size() * 2,
		"16-bit mono at 44.1 kHz")
	var missing: Array[String] = []
	for id: StringName in WeaponCatalog.ids():
		var definition := WeaponCatalog.get_definition(id)
		if (definition.category == WeaponDefinition.CATEGORY_PRIMARY or definition.category == WeaponDefinition.CATEGORY_SECONDARY) \
				and not SoundCatalog.has(SoundCatalog.shot_for(id)):
			missing.append(String(id))
	check(missing.is_empty(), "every gun has its own shot (missing: %s)" % ", ".join(missing))
	var ak := SoundCatalog.recipe(&"shot_ak47")
	var sniper := SoundCatalog.recipe(&"shot_l118a1")
	var pistol := SoundCatalog.recipe(&"shot_g17")
	check(float(sniper["length"]) > float(ak["length"]) and float(ak["length"]) > float(pistol["length"]),
		"a sniper rifle rings longer than a rifle, a rifle longer than a pistol")


func _test_library() -> void:
	section("Library")
	var unplayable: Array[String] = []
	var not_generated: Array[String] = []
	for slot: StringName in SoundCatalog.slots():
		if SoundLibrary.stream(slot) == null:
			unplayable.append(String(slot))
		if SoundLibrary.path_for(slot).is_empty():
			not_generated.append(String(slot))
	check(unplayable.is_empty(), "every slot resolves to a stream (%s)" % ", ".join(unplayable))
	check(not_generated.is_empty(), "every slot has its generated file in assets/audio (run tools/generate_sounds.gd: %s)" % ", ".join(not_generated))
	check(SoundLibrary.path_for(&"shot_ak47") == "res://assets/audio/shot_ak47.wav" and not SoundLibrary.is_supplied(&"shot_ak47"),
		"without a supplied file the generated one plays")
	check(SoundLibrary.stream(&"no_such_sound") == null, "an unknown slot has no sound")
	check(SoundCatalog.footstep(&"wood", 4) == &"step_wood_2" and SoundCatalog.footstep(&"lava", 0) == &"step_stone_1",
		"footsteps cycle through their variants; an unknown surface sounds like stone")
	check(SoundCatalog.surface_of("planks") == &"wood" and SoundCatalog.surface_of("metal_rust") == &"metal"
		and SoundCatalog.surface_of("sand") == &"sand" and SoundCatalog.surface_of("adobe") == &"stone",
		"map materials map to footstep surfaces")


func _test_settings() -> void:
	section("Volume settings")
	var saved_path := AudioSettings.file_path
	AudioSettings.file_path = "user://tests/audio_settings.json"
	if FileAccess.file_exists(AudioSettings.file_path):
		DirAccess.remove_absolute(AudioSettings.file_path)
	AudioSettings.reread()
	AudioSettings.apply()
	check(AudioSettings.BUSES.all(func(bus: StringName) -> bool: return AudioServer.get_bus_index(bus) >= 0),
		"the Master, Effects, UI and Voice buses exist")
	check(is_equal_approx(AudioSettings.volume(&"Master"), 0.8), "defaults without a settings file")
	check(AudioSettings.set_volume(&"Effects", 0.25) == OK
		and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Effects"))), 0.25),
		"a volume change applies to its bus")
	AudioSettings.set_volume(&"UI", 0.0)
	AudioSettings.reread()
	check(is_equal_approx(AudioSettings.volume(&"Effects"), 0.25)
		and is_equal_approx(AudioSettings.volume(&"UI"), 0.0), "volumes are saved and read back")
	AudioSettings.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI")), "a volume of zero mutes its bus")
	check(AudioSettings.set_volume(&"Nonsense", 0.5) != OK, "an unknown bus is refused")
	var screen := ControlsScreen.new()
	tree.root.add_child(screen)
	check(screen.volume_sliders.size() == AudioSettings.BUSES.size()
		and is_equal_approx(screen.volume_sliders[&"Effects"].value, 25.0), "Controls & audio has a slider per bus, at the saved volume")
	screen.free()
	DirAccess.remove_absolute(AudioSettings.file_path)
	AudioSettings.file_path = saved_path
	AudioSettings.reread()
	AudioSettings.apply()


func _test_in_game() -> void:
	section("Sounds in the game")
	var app := tree.root.get_node("App")
	app.set("pending_match_setup", null)
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	SoundPlayer.reset_counts()
	var steps: Array[int] = [0]
	player.stepped.connect(func() -> void: steps[0] += 1)
	player.scripted_move = Vector2(0, -1)
	await wait_seconds(2.0)
	var running := steps[0]
	player.scripted_move = Vector2(0, 1)
	player.scripted_walk = true
	await wait_seconds(0.6)
	steps[0] = 0
	await wait_seconds(1.5)
	player.scripted_move = Vector2.ZERO
	player.scripted_walk = false
	check(running >= 3 and steps[0] == 0, "running makes footsteps (%d in 2 s), walking makes none (%d)" % [running, steps[0]])
	var step_sounds := 0
	for slot: StringName in SoundPlayer.played:
		if String(slot).begins_with("step_"):
			step_sounds += SoundPlayer.played[slot]
	check(step_sounds == running, "each footstep plays a footstep sound (%d)" % step_sounds)
	var shot := SoundCatalog.shot_for(player.weapons.current().definition.id)
	player.weapons.shot_fired.emit(player.global_position, player.global_position + Vector3.FORWARD, Hitscan.Result.new())
	check(not shot.is_empty() and int(SoundPlayer.played.get(shot, 0)) == 1, "a shot plays its weapon's sound (%s)" % shot)
	var level := sandbox.get_node("Level") as SandboxLevel
	level.utility.detonated.emit(EquipmentCatalog.FRAG, player.global_position + Vector3(5, 1, 0), "x")
	level.utility.grenade_bounced.emit(EquipmentCatalog.FLASH, player.global_position + Vector3(3, 1, 0), 8.0)
	check(int(SoundPlayer.played.get(&"frag_explode", 0)) == 1 and int(SoundPlayer.played.get(&"grenade_bounce", 0)) == 1,
		"grenades bounce and explode audibly")
	var players := sandbox.find_children("*", "AudioStreamPlayer3D", true, false)
	check(not players.is_empty() and players.all(func(node: Node) -> bool: return (node as AudioStreamPlayer3D).bus == &"Effects"),
		"world sounds are positional, on the Effects bus")
	var button := UIFactory.button("Test")
	button.pressed.emit()
	button.free()
	check(int(SoundPlayer.played.get(&"ui_click", 0)) == 1, "interface buttons click")
	await despawn(sandbox)
	await wait_frames(2)
