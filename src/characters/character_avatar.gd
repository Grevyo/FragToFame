class_name CharacterAvatar
extends Node3D
## A [CharacterRig] worn by a moving combatant in the FPS runtime: bots (developer option) and
## other players in a networked match. It turns the rig to face forward (-Z), picks a movement
## clip from the velocity in its own frame, lays a crouch over it, holds the current weapon in
## the right hand pointed where the combatant aims, plays the death clip on [method die] and goes
## back to moving on [method revive]. Presentation only: hitboxes, collision, movement and aim
## belong to the combatant, never to this.
##
## Velocity, crouch and aim come from [member body] when it is a [CombatantMovementBody] (bots);
## otherwise the owner sets [member crouch] and [member aim_pitch] and velocity is measured from
## this node's own movement (remote players, whose position arrives over the network).

## Below this flat speed (m/s) the character stands.
const IDLE_SPEED: float = 0.4
## Below this flat speed (m/s) the character walks; above it, it runs.
const WALK_SPEED: float = 3.4
## The run clips are authored for about this speed (m/s); playback is scaled to match.
const RUN_CLIP_SPEED: float = 5.0
## Where the hand holds a weapon, from the weapon's centre in weapon space (fraction of length
## toward the stock, metres down).
const GRIP_BACK: float = 0.18
const GRIP_DOWN: float = 0.05
const HAND_BONE: StringName = &"RightHand"
## How far the hips drop at a full crouch (m). The hitboxes go from 1.8 m to 1.2 m tall; a
## knees-bent crouch with the upper body leaning brings the head down that far with this drop.
const CROUCH_HIP_DROP: float = 0.46

var rig: CharacterRig
## The combatant whose velocity, crouch and aim drive the character (defaults to the parent).
var body: Node3D = null
## 0 = standing, 1 = fully crouched (used when [member body] does not say).
var crouch: float = 0.0
## Aim pitch in radians, positive = up (used when [member body] does not say).
var aim_pitch: float = 0.0
## The weapon held in the hand ("" = empty hands).
var weapon_id: StringName = &""
var weapon_visual: WeaponVisual = null
## Where the right hand was in the last final (animated) pose, in world space.
var held_at: Vector3 = Vector3.ZERO

var _dead: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _measured_velocity: Vector3 = Vector3.ZERO


func _init() -> void:
	name = "Avatar"
	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.rotation.y = PI
	add_child(rig)


func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent() as Node3D


## Dresses the character. Returns what sanitising changed.
func apply(appearance: CharacterAppearance) -> PackedStringArray:
	var notes := rig.apply(appearance)
	rig.play(CharacterRig.ANIM_IDLE, 0.0)
	return notes


## Puts a weapon in the hand ("" or a weapon without a model = empty hands).
func set_weapon(id: StringName) -> void:
	if id == weapon_id:
		return
	weapon_id = id
	if not WeaponModels.has_model(id):
		if weapon_visual != null:
			weapon_visual.queue_free()
			weapon_visual = null
		return
	if weapon_visual == null:
		weapon_visual = WeaponVisual.new()
		weapon_visual.name = "HeldWeapon"
		add_child(weapon_visual)
	weapon_visual.setup(id)


func die() -> void:
	_dead = true
	rig.play(CharacterRig.ANIM_DEATH, 0.1)
	if weapon_visual != null:
		weapon_visual.visible = false


func revive() -> void:
	_dead = false
	_has_last = false
	rig.play(CharacterRig.ANIM_IDLE, 0.0)
	if weapon_visual != null:
		weapon_visual.visible = true


func is_dead() -> bool:
	return _dead


## Where the right hand is in world space (the avatar's origin when the body has no hand bone).
## Only the final animated pose while the skeleton reports [signal Skeleton3D.skeleton_updated];
## at other times the pose before animation modifiers (see [member held_at]).
func hand_position() -> Vector3:
	var skeleton := rig.skeleton
	var bone := skeleton.find_bone(HAND_BONE) if skeleton != null else -1
	if bone < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _process(delta: float) -> void:
	_measure_velocity(delta)
	_read_body()
	if rig.retargeter != null:
		rig.retargeter.crouch_drop = 0.0 if _dead else CROUCH_HIP_DROP * crouch
	if _dead:
		return
	var velocity := _measured_velocity
	if body is CharacterBody3D:
		velocity = (body as CharacterBody3D).velocity
	var clip_and_speed := movement_clip(global_transform.basis.inverse() * velocity, weapon_visual != null)
	rig.play(clip_and_speed[0] as StringName, 0.2, float(clip_and_speed[1]))
	_watch_skeleton()


func _read_body() -> void:
	var mover := body as CombatantMovementBody
	if mover == null:
		return
	crouch = mover.crouch_amount
	var head := mover.get_node_or_null(^"Head") as Node3D
	if head != null:
		aim_pitch = head.rotation.x
	var controller := mover.get_node_or_null(^"Weapons") as WeaponController
	if controller != null:
		var state := controller.current()
		set_weapon(held_model(state.definition.id if state != null else &""))


func _measure_velocity(delta: float) -> void:
	if delta <= 0.0:
		return
	if _has_last:
		var step := (global_position - _last_position) / delta
		_measured_velocity = _measured_velocity.lerp(step, clampf(delta * 12.0, 0.0, 1.0))
	_last_position = global_position
	_has_last = true


## The hand is read once the skeleton's final (animated) pose is known: modifier results are not
## visible to ordinary _process code.
func _watch_skeleton() -> void:
	var skeleton := rig.skeleton
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_hold_weapon):
		skeleton.skeleton_updated.connect(_hold_weapon)


## Points the held weapon where the combatant aims, its grip in the right hand.
func _hold_weapon() -> void:
	if weapon_visual == null or _dead:
		return
	var aim := global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, aim_pitch)
	var grip := Vector3(0.0, -GRIP_DOWN, weapon_visual.size.z * GRIP_BACK)
	held_at = hand_position()
	weapon_visual.global_transform = Transform3D(aim, held_at - aim * grip)


## The model shown in the hand for a carried weapon: the default knife look for the knife,
## nothing for utility, else the weapon's own model.
static func held_model(weapon_id: StringName) -> StringName:
	if weapon_id == EquipmentCatalog.KNIFE:
		return WeaponModels.DEFAULT_KNIFE
	return weapon_id if WeaponModels.has_model(weapon_id) else &""


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
## [clip: StringName, speed: float]. [param armed]: standing still the weapon is raised.
static func movement_clip(local_velocity: Vector3, armed: bool = false) -> Array:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var speed := flat.length()
	if speed < IDLE_SPEED:
		return [CharacterRig.ANIM_AIM if armed else CharacterRig.ANIM_IDLE, 1.0]
	if speed < WALK_SPEED:
		return [CharacterRig.ANIM_WALK, clampf(speed / 1.8, 0.6, 1.6)]
	var rate := clampf(speed / RUN_CLIP_SPEED, 0.7, 1.5)
	if absf(flat.x) > absf(flat.y):
		return [CharacterRig.ANIM_RUN_RIGHT if flat.x > 0.0 else CharacterRig.ANIM_RUN_LEFT, rate]
	return [CharacterRig.ANIM_RUN if flat.y < 0.0 else CharacterRig.ANIM_RUN_BACK, rate]
