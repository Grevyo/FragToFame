extends SceneTree
## Generates the game's original sound effects (Milestone 22): every slot in [SoundCatalog] is
## synthesised by [SoundSynth] from its recipe and saved as res://assets/audio/<slot>.wav.
## Deterministic (a fixed seed per slot), so re-running gives identical files. Re-run after
## changing a recipe, then import (the validation script's import step does).
##
## Supplied replacements go in res://assets/audio/supplied/<slot>.ogg|wav; they are never
## overwritten and play instead of the generated file.
##   <godot> --headless --path <project> --script res://tools/generate_sounds.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SoundLibrary.GENERATED_DIR))
	var failed := 0
	var total_seconds := 0.0
	for slot: StringName in SoundCatalog.slots():
		var samples := SoundSynth.render(SoundCatalog.recipe(slot), SoundCatalog.seed_for(slot))
		var path := "%s/%s.wav" % [SoundLibrary.GENERATED_DIR, slot]
		var error := SoundSynth.to_stream(samples).save_to_wav(ProjectSettings.globalize_path(path))
		if error != OK:
			print("%s: could not save (%s)" % [slot, error_string(error)])
			failed += 1
			continue
		total_seconds += float(samples.size()) / SoundSynth.RATE
	print("%d sounds generated (%.1f s of audio), %d failed" % [SoundCatalog.slots().size() - failed, total_seconds, failed])
	quit(1 if failed > 0 else 0)
