class_name SoundLibrary
extends RefCounted
## Finds the stream for a sound slot (Milestone 22). A supplied file replaces the generated one:
## for slot "shot_ak47" the library plays res://assets/audio/supplied/shot_ak47.ogg (or .wav)
## when it exists, else the generated res://assets/audio/shot_ak47.wav, else it synthesises the
## slot's recipe on the spot (so a missing file never means silence).

const GENERATED_DIR: String = "res://assets/audio"
const SUPPLIED_DIR: String = "res://assets/audio/supplied"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

static var _cache: Dictionary[StringName, AudioStream] = {}


## The stream for [param slot] (null for an unknown slot without a supplied file).
static func stream(slot: StringName) -> AudioStream:
	if _cache.has(slot):
		return _cache[slot]
	var found: AudioStream = null
	var path := path_for(slot)
	if not path.is_empty():
		found = load(path) as AudioStream
	if found == null and SoundCatalog.has(slot):
		found = SoundSynth.to_stream(SoundSynth.render(SoundCatalog.recipe(slot), SoundCatalog.seed_for(slot)))
	if found != null:
		_cache[slot] = found
	return found


## The file that plays for [param slot]: a supplied one first, then the generated one ("" when
## neither exists).
static func path_for(slot: StringName) -> String:
	for directory: String in [SUPPLIED_DIR, GENERATED_DIR]:
		for extension: String in EXTENSIONS:
			var path := "%s/%s.%s" % [directory, slot, extension]
			if ResourceLoader.exists(path):
				return path
	return ""


## Whether [param slot] plays a supplied file rather than the generated effect.
static func is_supplied(slot: StringName) -> bool:
	return path_for(slot).begins_with(SUPPLIED_DIR)


## Forgets loaded streams (after files change).
static func clear_cache() -> void:
	_cache.clear()
