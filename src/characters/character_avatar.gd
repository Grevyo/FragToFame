class_name CharacterAvatar
extends Node3D
## A [CharacterRig] worn by a moving body in the FPS runtime (developer preview on bots). It turns
## the rig to face the body's forward (-Z) and picks a movement clip from the body's velocity in
## its own frame; [method die] plays the death clip and [method revive] goes back to moving.
## Presentation only: hitboxes, collision, movement and aim belong to the body, not to this.

## Below this flat speed (m/s) the character stands.
const IDLE_SPEED: float = 0.4
## Below this flat speed (m/s) the character walks; above it, it runs.
const WALK_SPEED: float = 3.4
## The run clips are authored for about this speed (m/s); playback is scaled to match.
const RUN_CLIP_SPEED: float = 5.0

var rig: CharacterRig
## The body whose velocity drives the clips (defaults to the parent, when it is one).
var body: CharacterBody3D = null
var _dead: bool = false


func _init() -> void:
	name = "Avatar"
	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.rotation.y = PI
	add_child(rig)


func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent() as CharacterBody3D


## Dresses the character. Returns what sanitising changed.
func apply(appearance: CharacterAppearance) -> PackedStringArray:
	var notes := rig.apply(appearance)
	rig.play(CharacterRig.ANIM_IDLE, 0.0)
	return notes


func die() -> void:
	_dead = true
	rig.play(CharacterRig.ANIM_DEATH, 0.1)


func revive() -> void:
	_dead = false
	rig.play(CharacterRig.ANIM_IDLE, 0.0)


func is_dead() -> bool:
	return _dead


func _process(_delta: float) -> void:
	if _dead or body == null:
		return
	var clip_and_speed := movement_clip(body.global_transform.basis.inverse() * body.velocity)
	rig.play(clip_and_speed[0] as StringName, 0.2, float(clip_and_speed[1]))


## A seeded random look on an installed body, its team-colour channels in [param team_colour]
## (secondary: a lighter shade). Null when no body is installed.
static func random_look(seed_value: int, team_colour: Color) -> CharacterAppearance:
	var catalog := CharacterCatalog.shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var look := CharacterWardrobe.randomise(catalog, rng)
	if look.body.is_empty():
		return null
	CharacterWardrobe.apply_team_colours(catalog, look, team_colour, team_colour.lightened(0.45))
	return look


## The clip and playback speed for a velocity in the body's own frame (-Z forward):
## [clip: StringName, speed: float].
static func movement_clip(local_velocity: Vector3) -> Array:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var speed := flat.length()
	if speed < IDLE_SPEED:
		return [CharacterRig.ANIM_IDLE, 1.0]
	if speed < WALK_SPEED:
		return [CharacterRig.ANIM_WALK, clampf(speed / 1.8, 0.6, 1.6)]
	var rate := clampf(speed / RUN_CLIP_SPEED, 0.7, 1.5)
	if absf(flat.x) > absf(flat.y):
		return [CharacterRig.ANIM_RUN_RIGHT if flat.x > 0.0 else CharacterRig.ANIM_RUN_LEFT, rate]
	return [CharacterRig.ANIM_RUN if flat.y < 0.0 else CharacterRig.ANIM_RUN_BACK, rate]
