class_name SoundPlayer
extends RefCounted
## Plays sound slots (Milestone 22). World sounds are positional ([method play_at]): they fade
## with distance over the range of their kind ([constant SoundCatalog.RANGE]) and are muffled
## and quieter when the map's geometry stands between them and the listener. The player's own
## sounds and the interface play unspatialised ([method play_flat]). Each player frees itself
## when it finishes. Every sound played is also counted in [member played] (tests, debugging).

## How much a wall between the sound and the listener takes off, and the muffle it adds.
const OCCLUDED_DB: float = -9.0
const OCCLUDED_CUTOFF_HZ: float = 1400.0
## Slot -> times played since start (or the last [method reset_counts]).
static var played: Dictionary[StringName, int] = {}


## A positional sound of [param slot] at [param position], added under [param parent] (the
## level). [param kind] is a [constant SoundCatalog.RANGE] key.
static func play_at(parent: Node, slot: StringName, position: Vector3, kind: StringName,
		volume_db: float = 0.0, pitch_jitter: float = 0.04) -> AudioStreamPlayer3D:
	var stream := SoundLibrary.stream(slot)
	if parent == null or not parent.is_inside_tree() or stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"Effects"
	player.max_distance = float(SoundCatalog.RANGE.get(kind, 40.0))
	player.unit_size = player.max_distance / 8.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.attenuation_filter_cutoff_hz = 20500.0
	parent.add_child(player)
	player.global_position = position
	if _occluded(parent, position):
		player.volume_db += OCCLUDED_DB
		player.attenuation_filter_cutoff_hz = OCCLUDED_CUTOFF_HZ
	player.finished.connect(player.queue_free)
	player.play()
	_count(slot)
	return player


## An unspatialised sound of [param slot] on [param bus], added under [param parent].
static func play_flat(parent: Node, slot: StringName, bus: StringName = &"Effects", volume_db: float = 0.0,
		pitch_jitter: float = 0.0) -> AudioStreamPlayer:
	var stream := SoundLibrary.stream(slot)
	if parent == null or not parent.is_inside_tree() or stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	_count(slot)
	return player


## An interface sound, played from the scene tree's root.
static func play_ui(slot: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		play_flat(tree.root, slot, &"UI")


static func reset_counts() -> void:
	played.clear()


static func _count(slot: StringName) -> void:
	played[slot] = int(played.get(slot, 0)) + 1


## Whether map geometry stands between [param position] and the listener (the active camera).
static func _occluded(node: Node, position: Vector3) -> bool:
	var spatial := node as Node3D
	if spatial == null:
		return false
	var camera := node.get_viewport().get_camera_3d()
	if camera == null:
		return false
	var from := camera.global_position
	if from.distance_to(position) < 1.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, position, Hitscan.LAYER_WORLD)
	return not spatial.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
